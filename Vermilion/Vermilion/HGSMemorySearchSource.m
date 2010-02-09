//
//  HGSMemorySearchSource.m
//
//  Copyright (c) 2008 Google Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are
//  met:
//
//    * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//    * Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following disclaimer
//  in the documentation and/or other materials provided with the
//  distribution.
//    * Neither the name of Google Inc. nor the names of its
//  contributors may be used to endorse or promote products derived from
//  this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
//  A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
//  OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
//  DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
//  THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "HGSMemorySearchSource.h"
#import "HGSResult.h"
#import "HGSQuery.h"
#import "HGSTokenizer.h"
#import "HGSSearchOperation.h"
#import "HGSDelegate.h"
#import "HGSPluginLoader.h"
#import "HGSLog.h"
#import "HGSSearchTermScorer.h"

static NSString* const kHGSMemorySourceResultKey = @"HGSMSResultObject";
static NSString* const kHGSMemorySourceNameKey = @"HGSMSName";
static NSString* const kHGSMemorySourceOtherTermsKey = @"HGSMSOtherTerms";
static NSString* const kHGSMemorySourceVersionKey = @"HGSMSVersion";
static NSString* const kHGSMemorySourceEntriesKey = @"HGSMSEntries";
static NSString* const kHGSMemorySourceVersion = @"1";

// HGSMemorySearchSourceObject is our internal storage for caching
// results with the terms that match for them. We used to use an
// NSDictionary (80 bytes each). These are only 16 bytes each.
@interface HGSMemorySearchSourceObject : NSObject {
 @private
  HGSResult *result_;
  HGSTokenizedString *name_;
  NSArray *otherTerms_;
}
@property (nonatomic, retain, readonly) HGSResult *result;
@property (nonatomic, copy, readonly) HGSTokenizedString *name;
@property (nonatomic, retain, readonly) NSArray *otherTerms;

- (id)initWithResult:(HGSResult *)result 
                name:(HGSTokenizedString *)name 
          otherTerms:(NSArray *)otherTerms;

@end

@implementation HGSMemorySearchSourceObject
@synthesize result = result_;
@synthesize name = name_;
@synthesize otherTerms = otherTerms_;

- (id)initWithResult:(HGSResult *)result 
                name:(HGSTokenizedString *)name 
          otherTerms:(NSArray *)otherTerms {
  if ((self = [super init])) {
    result_ = [result retain];
    name_ = [name retain];
    otherTerms_ = [otherTerms retain];
  }
  return self;
}

- (void)dealloc {
  [result_ release];
  [name_ release];
  [otherTerms_ release];
  [super dealloc];
}
@end

@implementation HGSMemorySearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    resultsArray_ = [[NSMutableArray alloc] init];
    id<HGSDelegate> delegate = [[HGSPluginLoader sharedPluginLoader] delegate];
    NSString *appSupportPath = [delegate userCacheFolderForApp];
    NSString *filename =
      [NSString stringWithFormat:@"%@.cache.db", [self identifier]];
    cachePath_ =
      [[appSupportPath stringByAppendingPathComponent:filename] retain];
  }
  return self;
}

- (void)dealloc {
  [resultsArray_ release];
  [cachePath_ release];
  [super dealloc];
}

- (void)performSearchOperation:(HGSCallbackSearchOperation *)operation {
  NSArray *rankedResults = nil;
  @synchronized(resultsArray_) {
  rankedResults = [self rankedResultsFromArray:resultsArray_ 
                                  forOperation:operation];
  }
  [operation setRankedResults:rankedResults];
}

- (NSArray *)rankedResultsFromArray:(NSArray *)results 
                      forOperation:(HGSCallbackSearchOperation *)operation {
  HGSQuery* query = [operation query];
  NSMutableArray* rankedResults = [NSMutableArray array];
  HGSTokenizedString *tokenizedQuery = [query tokenizedQueryString];
  NSUInteger queryLength = [tokenizedQuery originalLength];
  HGSResult *pivotObject = [query pivotObject];
    
  if ((queryLength == 0) && pivotObject) {
    // Per the note above this class in the header, if we get a pivot w/o
    // any query terms, we match everything so the subclass can filter it
    // w/in pre/postFilterResult:matchesForQuery:pivotObject
    
    for (HGSMemorySearchSourceObject *indexObject in resultsArray_) {
      if ([operation isCancelled]) break;
      HGSResult* result = [self preFilterResult:[indexObject result] 
                                matchesForQuery:query 
                                    pivotObject:pivotObject];
      if (!result) continue;
      HGSScoredResult *scoredResult 
        = [HGSScoredResult resultWithResult:result
                                      score:HGSCalibratedScore(kHGSCalibratedModerateScore) 
                                matchedTerm:tokenizedQuery 
                             matchedIndexes:nil];
      scoredResult = [self postFilterScoredResult:scoredResult 
                                  matchesForQuery:query 
                                      pivotObject:pivotObject];
      if (scoredResult) {
        [rankedResults addObject:scoredResult];
      }
    }
  } else if (queryLength > 0) {
    for (HGSMemorySearchSourceObject *indexObject in resultsArray_) {
      if ([operation isCancelled]) break;
      HGSResult* result = [self preFilterResult:[indexObject result] 
                                matchesForQuery:query 
                                    pivotObject:pivotObject];
      if (!result) continue;
      HGSTokenizedString* name = [indexObject name];
      NSArray* otherItems = [indexObject otherTerms];
      HGSTokenizedString *matchedTerm = nil;
      NSIndexSet *matchedIndexes = nil;
      CGFloat score = HGSScoreTermForMainAndOtherItems(tokenizedQuery,
                                                      name,
                                                      otherItems,
                                                      &matchedTerm,
                                                      &matchedIndexes);        
      if (score > 0.0) {
        HGSRankFlags flagsToSet 
          = [matchedTerm isEqual:name] ? eHGSNameMatchRankFlag : 0;
        HGSScoredResult *scoredResult
          = [HGSScoredResult resultWithResult:result 
                                        score:score 
                                   flagsToSet:flagsToSet 
                                 flagsToClear:0 
                                  matchedTerm:matchedTerm
                               matchedIndexes:matchedIndexes];
        scoredResult = [self postFilterScoredResult:scoredResult 
                                    matchesForQuery:query 
                                        pivotObject:pivotObject];
        if (scoredResult) {
          [rankedResults addObject:scoredResult];
        }
      }
    }
  }
  return rankedResults;
}

- (void)clearResultIndex {
  @synchronized(resultsArray_) {
    [resultsArray_ removeAllObjects];
  }
}

- (void)indexResult:(HGSResult *)hgsResult
      tokenizedName:(HGSTokenizedString *)name
         otherTerms:(NSArray *)otherTerms {
  if ([name tokenizedLength] || otherTerms) {
    HGSMemorySearchSourceObject *resultsArrayObject 
      = [[HGSMemorySearchSourceObject alloc] initWithResult:hgsResult
                                                       name:name
                                                 otherTerms:otherTerms];
    if (resultsArrayObject) {
      @synchronized(resultsArray_) {
        // Into the list
        [resultsArray_ addObject:resultsArrayObject];
      }
      [resultsArrayObject release];
    }
  }
}

- (void)indexResult:(HGSResult *)hgsResult
               name:(NSString *)name
         otherTerms:(NSArray *)otherTerms {
  // must have result and name string
  if (hgsResult) {
    HGSTokenizedString *tokenizedName = [HGSTokenizer tokenizeString:name];
    NSArray *array = [HGSTokenizer tokenizeStrings:otherTerms];
    [self indexResult:hgsResult 
        tokenizedName:tokenizedName 
           otherTerms:array];
  }
}

- (void)indexResult:(HGSResult *)hgsResult
               name:(NSString *)name
          otherTerm:(NSString *)otherTerm {
  NSArray *otherTerms = otherTerm ? [NSArray arrayWithObject:otherTerm] : nil;
  [self indexResult:hgsResult
               name:name
         otherTerms:otherTerms];
}

- (void)indexResult:(HGSResult *)hgsResult {
  [self indexResult:hgsResult 
               name:[hgsResult displayName] 
         otherTerms:nil];
}

- (void)saveResultsCache {
  @synchronized(resultsArray_) {
    // Quick way to determine if resultsArray_ has changed since the
    // last cache action.
    NSUInteger hash = 0;
    for (HGSMemorySearchSourceObject *resultObject in resultsArray_) {
      hash ^= [[resultObject result] hash];
    }
    
    if (hash != cacheHash_) {
      NSMutableArray *archiveObjects =
        [NSMutableArray arrayWithCapacity:[resultsArray_ count]];
      for (HGSMemorySearchSourceObject *resultObject in resultsArray_) {
        // Generate a cache object suitable for a later call to
        // indexResult:nameString:otherString: when unarchiving the
        // object from the cache
        HGSResult *result = [resultObject result];
        NSDictionary *archivedRep = [self archiveRepresentationForResult:result];
        if (archivedRep) {
          HGSTokenizedString *name = [resultObject name];
          NSArray *otherTerms = [resultObject otherTerms];
          NSMutableArray *otherTermStrings
            = [NSMutableArray arrayWithCapacity:[otherTerms count]];
          for (HGSTokenizedString *otherTerm in otherTerms) {
            [otherTermStrings addObject:[otherTerm originalString]];
          }
          NSDictionary *cacheObject
            = [NSDictionary dictionaryWithObjectsAndKeys:
                                  archivedRep, kHGSMemorySourceResultKey,
                                  [name originalString], kHGSMemorySourceNameKey,
                                  otherTermStrings, kHGSMemorySourceOtherTermsKey,
                                  nil];
          [archiveObjects addObject:cacheObject];
        }
      }
      NSMutableDictionary *cache = [NSMutableDictionary dictionary];
      [cache setObject:archiveObjects forKey:kHGSMemorySourceEntriesKey];
      [cache setObject:kHGSMemorySourceVersion 
                forKey:kHGSMemorySourceVersionKey];
      if ([cache writeToFile:cachePath_ atomically:YES]) {
        cacheHash_ = hash;
      } else {
        HGSLogDebug(@"Unable to saveResultsCache for %@", cachePath_);
      }
    }
  }
}

- (BOOL)loadResultsCache {
  cacheHash_ = 0;
  // This routine can allocate a lot of temporary objects, so we wrap it
  // in an autorelease pool to keep our memory usage down.
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @try {
    NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:cachePath_];
    if (cache) {
      NSString *version = [cache objectForKey:kHGSMemorySourceVersionKey];
      if ([version isEqualToString:kHGSMemorySourceVersion]) {
        NSArray *entries = [cache objectForKey:kHGSMemorySourceEntriesKey];
        for (NSDictionary *cacheObject in entries) {
          NSDictionary *entry 
            = [cacheObject objectForKey:kHGSMemorySourceResultKey];
          HGSResult *result = [self resultWithArchivedRepresentation:entry];
          if (result) {
            NSString *name =
             [cacheObject objectForKey:kHGSMemorySourceNameKey];
            HGSTokenizedString *tokenizedName 
              = [HGSTokenizer tokenizeString:name];
            NSArray *otherTerms =
              [cacheObject objectForKey:kHGSMemorySourceOtherTermsKey];
            NSMutableArray *tokenizedOtherTerms 
              = [NSMutableArray arrayWithCapacity:[otherTerms count]];
            for (NSString *term in otherTerms) {
              HGSTokenizedString *tokenizedTerm 
                = [HGSTokenizer tokenizeString:term];
              [tokenizedOtherTerms addObject:tokenizedTerm];
            }
            [self indexResult:result
                tokenizedName:tokenizedName
                   otherTerms:tokenizedOtherTerms];
            cacheHash_ ^= [result hash];
          }
        }
      }
    }
  }
  @catch(NSException *e) {
    HGSLog(@"Unable to load results cache for %@ (%@)", self, e);
    cacheHash_ = 0;
    [self clearResultIndex];
  }
  [pool release];
  return cacheHash_ != 0;
}

@end

@implementation HGSMemorySearchSource (ProtectedMethods)

- (HGSResult *)preFilterResult:(HGSResult *)result 
               matchesForQuery:(HGSQuery*)query
                   pivotObject:(HGSResult *)pivotObject {
  // Do nothing. Subclasses can override.
  return result;
}

- (HGSScoredResult *)postFilterScoredResult:(HGSScoredResult *)result 
                            matchesForQuery:(HGSQuery *)query
                                pivotObject:(HGSResult *)pivotObject {
  // Do nothing. Subclasses can override.
  return result;
}

@end
