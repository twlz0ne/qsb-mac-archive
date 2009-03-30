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

static NSString* const kHGSMemorySourceResultKey = @"HGSMSResultObject";
static NSString* const kHGSMemorySourceNameTermsKey = @"HGSMSNameTerms";
static NSString* const kHGSMemorySourceOtherTermsKey = @"HGSMSOtherTerms";

// Done as a C func so it can be inlined below to make matching as fast/simple
// as possible.
static inline BOOL WordSetContainsPrefixMatchForTerm(NSSet *wordSet, NSString *term) {
  // Since we normalized all the strings up front, we can do hasPrefix for the
  // matches.
  NSUInteger termLen = [term length];
  for (NSString *aWord in wordSet) {
    if (([aWord length] >= termLen) && [aWord hasPrefix:term]) {
      return YES;
    }
  }
  return NO;
}

// HGSMemorySearchSourceObject is our internal storage for caching
// results with the terms that match for them. We used to use an
// NSDictionary (80 bytes each). These are only 16 bytes each.
@interface HGSMemorySearchSourceObject : NSObject {
 @private
  HGSResult *result_;
  NSSet *nameTerms_;
  NSSet *otherTerms_;
}
@property (nonatomic, retain, readonly) HGSResult *result;
@property (nonatomic, retain, readonly) NSSet *nameTerms;
@property (nonatomic, retain, readonly) NSSet *otherTerms;

- (id)initWithResult:(HGSResult *)result 
           nameTerms:(NSSet *)nameTerms 
          otherTerms:(NSSet *)otherTerms;

@end

@implementation HGSMemorySearchSourceObject
@synthesize result = result_;
@synthesize nameTerms = nameTerms_;
@synthesize otherTerms = otherTerms_;

- (id)initWithResult:(HGSResult *)result 
           nameTerms:(NSSet *)nameTerms 
          otherTerms:(NSSet *)otherTerms {
  if ((self = [super init])) {
    result_ = [result retain];
    nameTerms_ = [nameTerms retain];
    otherTerms_ = [otherTerms retain];
  }
  return self;
}

- (void)dealloc {
  [result_ release];
  [nameTerms_ release];
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
  NSSet* queryWords = [query uniqueWords];
  NSUInteger queryWordsCount = [queryWords count];
  
  @synchronized(resultsArray_) {

    if ((queryWordsCount == 0) && ([query pivotObject] != nil)) {
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
        HGSResult *resultCopy = [[result copy] autorelease];
        [results addObject:resultCopy];
      }
        
    } else if (queryWordsCount > 0) {

      // Match the terms
      NSEnumerator* indexEnumerator = [resultsArray_ objectEnumerator];
      HGSMemorySearchSourceObject* indexObject;
      while (((indexObject = [indexEnumerator nextObject])) 
             && ![operation isCancelled]) {
        HGSResult* result = [indexObject result];
        NSSet* titleTermsSet = [indexObject nameTerms];
        NSSet* otherTermsSet = [indexObject otherTerms];

        BOOL matchedAllTerms = YES;
        BOOL hasNameMatch = NO;
        for (NSString *queryTerm in queryWords) {
          BOOL hasMatch
            = WordSetContainsPrefixMatchForTerm(titleTermsSet, queryTerm);
          if (hasMatch) {
            hasNameMatch = YES;
          } else {
            hasMatch = WordSetContainsPrefixMatchForTerm(otherTermsSet, 
                                                         queryTerm);
          }
          if (!hasMatch) {
            matchedAllTerms = NO;
            break;
          }
        }
        if (matchedAllTerms) {
          // Copy the result so any attributes looked up and cached don't stick.
          // Also take care of any dup folding not leaving set attirubtes on 
          // other objects.
          HGSMutableResult *resultCopy = [[result mutableCopy] autorelease];
          if (hasNameMatch) {
            [resultCopy addRankFlags:eHGSNameMatchRankFlag];
          } else {
            [resultCopy removeRankFlags:eHGSNameMatchRankFlag];
            // TODO(alcor): handle ranking correctly
            // For now, halve the rank of anything that isn't a name match
            // This prevents uppity contacts from matching on domains and other
            // things.
            [resultCopy setRank:[resultCopy rank] / 2];
          }
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

- (void)indexResult:(HGSResult*)hgsResult
         nameString:(NSString*)nameString
        otherString:(NSString*)otherString {
  // must have result and name string
  if (hgsResult) {
    NSSet *nameTermsSet = [self normalizedTokenSetForString:nameString];
    NSSet *otherTermsSet = [self normalizedTokenSetForString:otherString];
    if (nameTermsSet || otherTermsSet) {
      HGSMemorySearchSourceObject *resultsArrayObject 
        = [[HGSMemorySearchSourceObject alloc] initWithResult:hgsResult
                                                    nameTerms:nameTermsSet
                                                   otherTerms:otherTermsSet];
      if (resultsArrayObject) {
        @synchronized(resultsArray_) {
          // Into the list
          [resultsArray_ addObject:resultsArrayObject];
        }
        [resultsArrayObject release];
      }
    }
  }
}

- (void)indexResult:(HGSResult*)hgsResult
         nameString:(NSString*)nameString
  otherStringsArray:(NSArray*)otherStrings {
  // do a simple join of the otherStrings
  return [self indexResult:hgsResult
                nameString:nameString
               otherString:[otherStrings componentsJoinedByString:@"\n"]];
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
          NSString *nameTerms = [[[resultObject nameTerms] allObjects] 
                                 componentsJoinedByString: @" "];
          NSString *otherTerms = [[[resultObject otherTerms] allObjects] 
                                  componentsJoinedByString: @" "];
          NSDictionary *cacheObject
            = [NSDictionary dictionaryWithObjectsAndKeys:
                                  archivedRep, kHGSMemorySourceResultKey,
                                  nameTerms, kHGSMemorySourceNameTermsKey,
                                  otherTerms, kHGSMemorySourceOtherTermsKey,
                                  nil];
          [archiveObjects addObject:cacheObject];
        }
      }
      
      NSData *data = [NSKeyedArchiver archivedDataWithRootObject:archiveObjects];
      [data writeToFile:cachePath_ atomically:YES];
      cacheHash_ = hash;
    }
  }
}

- (void)loadResultsCache {
  cacheHash_ = 0;
  // This routine can allocate a lot of temporary objects, so we wrap it
  // in an autorelease pool to keep our memory usage down.
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSData *data = [NSData dataWithContentsOfFile:cachePath_];
  if (data) {
    NSArray *archiveObjects = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    for (NSDictionary *cacheObject in archiveObjects) {
      HGSResult *result = [self resultWithArchivedRepresentation:
                           [cacheObject
                            objectForKey:kHGSMemorySourceResultKey]];
      if (result) {
        NSString *nameTerms =
          [cacheObject objectForKey:kHGSMemorySourceNameTermsKey];
        NSString *otherTerms =
          [cacheObject objectForKey:kHGSMemorySourceOtherTermsKey];
        [self indexResult:result
               nameString:nameTerms
              otherString:otherTerms];
        cacheHash_ ^= [result hash];
      }
    }
  }
  [pool release];
}

@end

@implementation HGSMemorySearchSource (ProtectedMethods)

- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query {
  // Do nothing; subclasses may override.
}

@end
