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
#import "HGSAbbreviationRanker.h"

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
  NSString *name_;
  NSArray *otherTerms_;
}
@property (nonatomic, retain, readonly) HGSResult *result;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, retain, readonly) NSArray *otherTerms;

- (id)initWithResult:(HGSResult *)result 
                name:(NSString *)name 
          otherTerms:(NSArray *)otherTerms;

@end

@implementation HGSMemorySearchSourceObject
@synthesize result = result_;
@synthesize name = name_;
@synthesize otherTerms = otherTerms_;

- (id)initWithResult:(HGSResult *)result 
                name:(NSString *)nameTerms 
          otherTerms:(NSArray *)otherTerms {
  if ((self = [super init])) {
    result_ = [result retain];
    name_ = [nameTerms copy];
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
    if (!resultsArray_) {
      [self release];
      self = nil;
    }
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

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  HGSQuery* query = [operation query];
  NSMutableArray* results = [NSMutableArray array];
  NSString *normalizedQuery = [query normalizedQueryString];
  NSUInteger normalizedLength = [normalizedQuery length];
  @synchronized(resultsArray_) {

    if ((normalizedLength == 0) && ([query pivotObject])) {
      // Per the note above this class in the header, if we get a pivot w/o
      // any query terms, we match everything so the subclass can filter it
      // w/in |processMatchingResults:forQuery:|.

      NSEnumerator* indexEnumerator = [resultsArray_ objectEnumerator];
      HGSMemorySearchSourceObject* indexObject;
      while (((indexObject = [indexEnumerator nextObject])) 
             && ![operation isCancelled]) {
        HGSResult* result = [indexObject result];

        // Copy the result so any attributes looked up and cached don't stick.
        // Also take care of any dup folding not leaving set attributes on other
        // objects.
        HGSMutableResult *resultCopy = [[result mutableCopy] autorelease];
        [results addObject:resultCopy];
      }
        
    } else if (normalizedLength > 0) {

      // Match the terms
      for (HGSMemorySearchSourceObject *indexObject in resultsArray_) {
        if ([operation isCancelled]) break;
        HGSResult* result = [indexObject result];
        NSString* name = [indexObject name];
        

        CGFloat rank = HGSScoreForAbbreviation(name,
                                               normalizedQuery, 
                                               NULL);
        BOOL hasNameMatch = rank > 0;
        if (!(rank > 0)) {
          NSArray* otherTerms = [indexObject otherTerms];
          for (NSString *otherTerm in otherTerms) {
            CGFloat otherRank = HGSScoreForAbbreviation(otherTerm,
                                                        normalizedQuery, 
                                                        NULL);
            if (otherRank > rank) {
              // TODO(dmaclach): do we want to blend these somehow instead
              // of a strict replacement policy?
              rank = otherRank;
            }
            if (rank > 0.9) {
              break;
            }
          }
        } 
          
        if (rank > 0) {
          // Copy the result so we can apply rank to it
          HGSMutableResult *resultCopy = [[result mutableCopy] autorelease];
          if (hasNameMatch) {
            [resultCopy addRankFlags:eHGSNameMatchRankFlag];
          } else {
            rank *= 0.5;
            [resultCopy removeRankFlags:eHGSNameMatchRankFlag];
          }
          [resultCopy setRank:rank];
          [results addObject:resultCopy];
        }
      }
    }
  }

  if ([results count]) {
    // Give subclasses a chance to modify the result list.
    [self processMatchingResults:results forQuery:query];

    // And into the operation.
    [operation setResults:results];
  }
}

- (void)clearResultIndex {
  @synchronized(resultsArray_) {
    [resultsArray_ removeAllObjects];
  }
}

- (void)indexResult:(HGSResult *)hgsResult
      tokenizedName:(NSString *)name
         otherTerms:(NSArray *)otherTerms {
  if ([name length] || otherTerms) {
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
    name = [HGSTokenizer tokenizeString:name];
    NSUInteger count = [otherTerms count];
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:count];
    for (NSString *term in otherTerms) {
      term = [HGSTokenizer tokenizeString:term];
      [array addObject:term];
    }
    [self indexResult:hgsResult 
        tokenizedName:name 
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
          NSString *name = [resultObject name];
          NSArray *otherTerms = [resultObject otherTerms];
          NSDictionary *cacheObject
            = [NSDictionary dictionaryWithObjectsAndKeys:
                                  archivedRep, kHGSMemorySourceResultKey,
                                  name, kHGSMemorySourceNameKey,
                                  otherTerms, kHGSMemorySourceOtherTermsKey,
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
            NSArray *otherTerms =
              [cacheObject objectForKey:kHGSMemorySourceOtherTermsKey];
            [self indexResult:result
                tokenizedName:name
                   otherTerms:otherTerms];
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

- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query {
  // Do nothing; subclasses may override.
}

@end
