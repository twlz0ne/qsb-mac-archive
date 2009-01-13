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
#import "HGSObject.h"
#import "HGSQuery.h"
#import "HGSStringUtil.h"
#import "HGSTokenizer.h"
#import "HGSSearchOperation.h"
#import "HGSDelegate.h"
#import "HGSModuleLoader.h"
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

@implementation HGSMemorySearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    resultsArray_ = [[NSMutableArray alloc] init];
    if (!resultsArray_) {
      [self release];
      self = nil;
    }
    id<HGSDelegate> delegate = [[HGSModuleLoader sharedModuleLoader] delegate];
    NSString *appSupportPath = [delegate userApplicationSupportFolderForApp];
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
      NSDictionary* indexObject;
      while (((indexObject = [indexEnumerator nextObject])) && ![operation isCancelled]) {
        HGSObject* result = [indexObject objectForKey:kHGSMemorySourceResultKey];

        // Copy the result so any attributes looked up and cached don't stick.
        // Also take care of any dup folding not leaving set attributes on other
        // objects.
        HGSObject *resultCopy = [[result copy] autorelease];
        [results addObject:resultCopy];
      }
        
    } else if (queryWordsCount > 0) {

      // Match the terms
      NSEnumerator* indexEnumerator = [resultsArray_ objectEnumerator];
      NSDictionary* indexObject;
      while (((indexObject = [indexEnumerator nextObject])) && ![operation isCancelled]) {
        HGSObject* result = [indexObject objectForKey:kHGSMemorySourceResultKey];
        NSSet* titleTermsSet = [indexObject valueForKey:kHGSMemorySourceNameTermsKey];
        NSSet* otherTermsSet = [indexObject valueForKey:kHGSMemorySourceOtherTermsKey];

        BOOL matchedAllTerms = YES;
        BOOL hasNameMatch = NO;
        for (NSString *queryTerm in queryWords) {
          BOOL hasMatch
            = WordSetContainsPrefixMatchForTerm(titleTermsSet, queryTerm);
          if (hasMatch) {
            hasNameMatch = YES;
          } else {
            hasMatch = WordSetContainsPrefixMatchForTerm(otherTermsSet, queryTerm);
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
          HGSMutableObject *resultCopy = [[result mutableCopy] autorelease];
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

- (void)indexResult:(HGSObject*)hgsResult
         nameString:(NSString*)nameString
        otherString:(NSString*)otherString {
  // must have result and name string
  if (hgsResult && ([nameString length] > 0)) {

    // do our normalization...
    NSString *prepedNameString
      = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:nameString];
    NSString *prepedOtherString
      = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:otherString];
    
    // now split them into terms and use sets to keep each just once...
    NSArray *nameTerms
      = [[HGSTokenizer wordEnumeratorForString:prepedNameString] allObjects];
    NSSet *nameTermsSet = [NSSet setWithArray:nameTerms];
    NSSet *otherTermsSet = nil;
    if ([prepedOtherString length] > 0) {
      NSArray *otherTerms
        = [[HGSTokenizer wordEnumeratorForString:prepedOtherString] allObjects];
      otherTermsSet = [NSSet setWithArray:otherTerms];
    }

    // add it to the result array for searching
    NSDictionary *resultsArrayObject
      = [NSDictionary dictionaryWithObjectsAndKeys:
                            hgsResult, kHGSMemorySourceResultKey,
                            nameTermsSet, kHGSMemorySourceNameTermsKey,
                            otherTermsSet, kHGSMemorySourceOtherTermsKey,
                            nil];

    if (resultsArrayObject) {
      @synchronized(resultsArray_) {
        // Into the list
        [resultsArray_ addObject:resultsArrayObject];
      }
    }
  }
}

- (void)indexResult:(HGSObject*)hgsResult
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
    for (NSDictionary *result in resultsArray_) {
      hash ^= [[result objectForKey:kHGSMemorySourceResultKey] hash];
    }
    
    if (hash != cacheHash_) {
      NSMutableArray *archiveObjects =
        [NSMutableArray arrayWithCapacity:[resultsArray_ count]];
      for (NSDictionary *result in resultsArray_) {
        // Generate a cache object suitable for a later call to
        // indexResult:nameString:otherString: when unarchving the
        // object from the cache
        HGSObject *obj = [result objectForKey:kHGSMemorySourceResultKey];
        NSDictionary *archivedRep = [self archiveRepresentationForObject:obj];
        if (archivedRep) {
          NSString *nameTerms =
            [[[result objectForKey:kHGSMemorySourceNameTermsKey]
              allObjects] componentsJoinedByString: @" "];
          NSString *otherTerms =
            [[[result objectForKey:kHGSMemorySourceOtherTermsKey]
              allObjects] componentsJoinedByString: @" "];
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
  NSData *data = [NSData dataWithContentsOfFile:cachePath_];
  if (data) {
    NSArray *archiveObjects = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    for (NSDictionary *cacheObject in archiveObjects) {
      HGSObject *result = [self objectWithArchivedRepresentation:
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
}

@end

@implementation HGSMemorySearchSource (ProtectedMethods)

- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query {
  // Do nothing; subclasses may override.
}

@end
