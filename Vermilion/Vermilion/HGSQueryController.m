//
//  HGSQueryController.m
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

#import "HGSQueryController.h"
#import "HGSQuery.h"
#import "HGSResult.h"
#import "HGSAction.h"
#import "HGSSearchSource.h"
#import "HGSSearchOperation.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSMixer.h"
#import "HGSLog.h"
#import "HGSBundle.h"
#import "GTMDebugThreadValidation.h"

NSString *kHGSQueryControllerWillStartNotification 
  = @"HGSQueryControllerWillStartNotification";
NSString *kHGSQueryControllerDidFinishNotification 
  = @"HGSQueryControllerDidFinishNotification";
NSString *kHGSQueryControllerDidUpdateResultsNotification 
  = @"HGSQueryControllerDidUpdateResultsNotification";

NSString* const kQuerySlowSourceTimeoutSecondsPrefKey = @"slowSourceTimeout";

// Key callbacks for our really simple pointer to id based dictionary
// The keys we pass in don't support "copy" but all we are interested in
// is that their pointers don't clash.
static const void *ResultsDictionaryRetainCallBack(CFAllocatorRef allocator, 
                                                   const void *value);
static void ResultsDictionaryReleaseCallBack(CFAllocatorRef allocator, 
                                             const void *value);
static CFStringRef ResultsDictionaryCopyDescriptionCallBack(const void *value);
static Boolean ResultsDictionaryEqualCallBack(const void *value1, 
                                       const void *value2);
static CFHashCode ResultsDictionaryHashCallBack(const void *value);

@interface HGSQueryController()
- (void)annotateResults:(NSMutableArray*)results;
+ (NSString *)categoryForType:(NSString *)type;
- (void)cancelPendingSearchOperations:(NSTimer*)timer;
@end

@implementation HGSQueryController

+ (void)initialize {
  if (self == [HGSQueryController class]) {
    NSDictionary *defaultsDict
      = [NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:60.0]
                                    forKey:kQuerySlowSourceTimeoutSecondsPrefKey];
    NSUserDefaults *sd = [NSUserDefaults standardUserDefaults];
    [sd registerDefaults:defaultsDict];
  }
}

- (id)initWithQuery:(HGSQuery*)query
              mixer:(HGSMixer*)mixer {
  if ((self = [super init])) {
    queryOperations_ = [[NSMutableArray alloc] init];
    pendingQueryOperations_ = [[NSMutableArray alloc] init];
    parsedQuery_ = [query retain];
    mixer_ = [mixer retain];
    CFDictionaryKeyCallBacks keyCallBacks = {
      0,
      ResultsDictionaryRetainCallBack,
      ResultsDictionaryReleaseCallBack,
      ResultsDictionaryCopyDescriptionCallBack,
      ResultsDictionaryEqualCallBack,
      ResultsDictionaryHashCallBack
    };
    sourceResults_ = CFDictionaryCreateMutable(NULL,
                                               0, 
                                               &keyCallBacks, 
                                               &kCFTypeDictionaryValueCallBacks);
  }
  return self;
}

- (void)dealloc {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [self cancel];
  [rankedResults_ release];
  [slowSourceTimer_ invalidate];
  [slowSourceTimer_ release];
  [queryOperations_ release];
  [parsedQuery_ release];
  [pendingQueryOperations_ release];
  [mixer_ release];
  if (sourceResults_) {
    CFRelease(sourceResults_);
  }
  [super dealloc];
}

- (void)startQuery {
  // Spin through the Sources checking to see if they are valid for the source
  // and kick off the SearchOperations.  
  HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSQueryControllerWillStartNotification object:self];
  for (id<HGSSearchSource> source in [sourcesPoint extensions]) {
    // Check if the source likes the query string
    if ([source isValidSourceForQuery:parsedQuery_]) {
      HGSSearchOperation* operation;
      operation = [source searchOperationForQuery:parsedQuery_];
      if (operation) {
        [nc addObserver:self 
               selector:@selector(searchOperationDidFinish:) 
                   name:kHGSSearchOperationDidFinishNotification 
                 object:operation];
        [nc addObserver:self 
               selector:@selector(searchOperationDidUpdateResults:) 
                   name:kHGSSearchOperationDidUpdateResultsNotification 
                 object:operation];
        [queryOperations_ addObject:operation];
        [pendingQueryOperations_ addObject:operation];
        
        [operation startQuery];
      }
    }
  }

  // Normally we inform the observer that we are done when the last source
  // reports in; if we don't have any sources that will never happen, so just
  // call the query done immediately.
  if ([queryOperations_ count] == 0) {
    [nc postNotificationName:kHGSQueryControllerDidFinishNotification 
                      object:self];
  } else {
    // we kick off a timer to pull the plug on any really slow sources.
    NSUserDefaults *sd = [NSUserDefaults standardUserDefaults];
    NSTimeInterval slowSourceTimeout
      = [sd doubleForKey:kQuerySlowSourceTimeoutSecondsPrefKey];
    slowSourceTimer_
      = [[NSTimer scheduledTimerWithTimeInterval:slowSourceTimeout
                                          target:self
                                        selector:@selector(cancelPendingSearchOperations:)
                                        userInfo:nil
                                         repeats:NO] retain];
  }
}

- (void)cancelPendingSearchOperations:(NSTimer*)timer {
  if ([self queriesFinished]) return;

  NSUserDefaults *sd = [NSUserDefaults standardUserDefaults];
  BOOL doLog = [sd boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey];
  
  // Loop back to front so we can remove things as we go
  for (NSUInteger idx = [pendingQueryOperations_ count]; idx > 0; --idx) {
    HGSSearchOperation *operation
      = [pendingQueryOperations_ objectAtIndex:(idx - 1)];

    // If it thinks it's finished, but in our pending list, it means we have yet
    // to get our notification, so we won't cancel it since we should get that
    // shortly on the next spin of the main run loop.
    if (![operation isFinished]) {
      if (doLog) {
        HGSLog(@"Took too much time, canceling SearchOperation %@", operation);
      }
      [operation cancel];
    }
  }
}

- (HGSQuery *)query {
  return parsedQuery_;
}

- (NSArray*)results {
  NSMutableArray* results = [NSMutableArray array];
  NSDictionary *nsSourceResults = (NSDictionary *)sourceResults_;
  for (NSArray *opResult in [nsSourceResults allValues]) {
    [results addObjectsFromArray:opResult];
  }
  return results;
}

- (NSDictionary *)rankedResultsByCategory {
  // Return a dictionary of results organized by category.  If there
  // were no acceptable results then return nil.
  NSArray *results = [self rankedResults];
  NSMutableDictionary *dictionary = nil;
  NSEnumerator *resultEnumerator = [results objectEnumerator];
  HGSResult *result = nil;
  while ((result = [resultEnumerator nextObject])) {
    NSString *type = [result type];
    if (type &&
        ![result conformsToType:kHGSTypeSuggest]) {
      if (!dictionary) {
        dictionary = [NSMutableDictionary dictionary];
      }
      // Translate |type| into a category.
      NSString *category = [[self class] categoryForType:type];
      // Fallback to type if necessary.
      if (!category) {
        category = type;
      }
      NSMutableArray *array = [dictionary objectForKey:category];
      if (!array) {
        array = [NSMutableArray array];
        [dictionary setObject:array
                       forKey:category];
      }
      [array addObject:result];
    }
  }
  return dictionary;
}

- (BOOL)hasAnyRealResults {
  return hasRealResults_;
}

// Each source has a list of results, ranked by relevance internally within
// that source. This method:
// - ranks them in global order
// - removes/merges duplicates
// - removes objects that don't match the type of a pending action
// - annotates results across all sources
// TODO(pinkerton) - we can decide whether this should rank everything or just
//      the top M from each source to get the top N later.
// TODO(pinkerton) - should annotations re-rank?
- (NSArray*)rankedResults {
  if (!rankedResults_) {
    
    // gather all the results at the current time
    NSDictionary *nsSourceResults = (NSDictionary *)sourceResults_;
    NSArray* operationResultArrays = [nsSourceResults allValues];
    // mix and de-dupe
    NSMutableArray* results = [mixer_ mix:operationResultArrays
                                    query:parsedQuery_];

  #if !TARGET_OS_IPHONE
    [self annotateResults:results];
  #endif
    rankedResults_ = [results retain];
  }
  return rankedResults_;
}

+ (NSString *)categoryForType:(NSString *)type {
  // If this is being accessed from multiple threads you will
  // have to make typeCategoryDict threadsafe somehow. Right now it is only
  // being used off of the main thread, so we assert to make sure it stays
  // that way.
  GTMAssertRunningOnMainThread();
  
  if (!type) return nil;
  
  static NSMutableDictionary *sTypeCategoryDict = nil;
  if (!sTypeCategoryDict) {
    NSBundle *bundle = HGSGetPluginBundle();
    // Pull in our type->category dictionary.
    NSString *plistPath = [bundle pathForResource:@"TypeCategories"
                                           ofType:@"plist"];
    if (plistPath) {
      sTypeCategoryDict 
      = [[NSMutableDictionary alloc] initWithContentsOfFile:plistPath];
    }
    if (!sTypeCategoryDict) {
      HGSLogDebug(@"TypeCategories.plist cannot be found in the app bundle.");
    }
  }
  NSString *category = nil;
  NSString *searchType = type;
  BOOL addNewMapping = NO;
  while ([searchType length]
         && !(category = [sTypeCategoryDict objectForKey:searchType])) {
    addNewMapping = YES;  // Signal that we should cache a new mapping.
    NSRange dotRange = [searchType rangeOfString:@"." options:NSBackwardsSearch];
    if (dotRange.location != NSNotFound) {
      searchType = [searchType substringToIndex:dotRange.location];
    } else {
      searchType = nil;  // Not found.
      category = HGSLocalizedString(@"Other", nil);
      HGSLogDebug(@"No category found for type '%@'.  Using 'Other'.", type);
    }
  }
  
  if (addNewMapping && category) {
    [sTypeCategoryDict setObject:category forKey:type];
  }
  return category;
}

// allow each source a chance to add more information to a result that could
// come from another source. This is O(N*M) where N = #results and M=#sources
- (void)annotateResults:(NSMutableArray*)results {
  NSEnumerator* resultIt = [results objectEnumerator];
  HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
  HGSResult* currentResult = nil;
  NSInteger resultCount = 0;
  NSInteger maxCount = [parsedQuery_ maxDesiredResults];
  while ((currentResult = [resultIt nextObject])
         && ++resultCount <= maxCount) {
    for (id<HGSSearchSource> source in [sourcesPoint extensions]) {
      [source annotateResult:currentResult withQuery:parsedQuery_];
    }
  }
}

// stops the query
- (void)cancel {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  for (HGSSearchOperation* operation in queryOperations_) {
    [nc removeObserver:self name:nil object:operation];
    [operation cancel];
  }
  cancelled_ = YES;
}

- (BOOL)queriesFinished {
  return ([pendingQueryOperations_ count] == 0) ? YES : NO;
}

- (BOOL)cancelled {
  return cancelled_;
}  

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ - Predicate:%@ Operations:%@", 
          [super description], parsedQuery_, queryOperations_];
}
          
#pragma mark Notifications

//
// -searchOperationDidFinish:
//
// Called when a single operation has completed (or been cancelled). There may
// be other sources still working. We send a "first tier completed" notification
// when we count that we've gotten enough "operation finished" notices to match
// the number of first-tier operations (after de-bouncing).
//
- (void)searchOperationDidFinish:(NSNotification *)notification {
  HGSSearchOperation *operation = [notification object];
  HGSAssert([pendingQueryOperations_ containsObject:operation],
            @"ERROR: Received duplicate finished notifications from operation %@", 
            [operation description]);

  [pendingQueryOperations_ removeObject:operation];
  
  // If this is the last query operation to complete then report as overall
  // query completion and cancel our timer.
  if ([self queriesFinished]) {
    [slowSourceTimer_ invalidate];
    [slowSourceTimer_ release];
    slowSourceTimer_ = nil;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:kHGSQueryControllerDidFinishNotification 
                      object:self];
  }
}

//
// -searchOperationDidUpdateResults:
//
// Called when a source has added more results. 
//
- (void)searchOperationDidUpdateResults:(NSNotification *)notification {
  NSDictionary *userInfo = [notification userInfo];
  NSArray *operationResults 
    = [userInfo objectForKey:kHGSSearchOperationNotificationResultsKey];
  if (!hasRealResults_) {
    for (HGSResult *result in operationResults) {
      hasRealResults_ = ![result conformsToType:kHGSTypeGoogleSuggest];
      if (hasRealResults_) break;
    }
  }
  CFDictionarySetValue(sourceResults_, [notification object], operationResults);
  [rankedResults_ release];
  rankedResults_ = nil;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSQueryControllerDidUpdateResultsNotification 
                    object:self];
}

- (NSString *)pendingQueryNames {
  return [[pendingQueryOperations_ valueForKey:@"displayName"]
           componentsJoinedByString:@", "];
}
@end

// Callbacks for our really simple pointer to id based dictionary
const void *ResultsDictionaryRetainCallBack(CFAllocatorRef allocator, 
                                            const void *value) {
  return [(id)value retain];
}

void ResultsDictionaryReleaseCallBack(CFAllocatorRef allocator,
                                      const void *value) {
  [(id)value release];
}

CFStringRef ResultsDictionaryCopyDescriptionCallBack(const void *value) {
  return (CFStringRef)[(id)value description];
}

Boolean ResultsDictionaryEqualCallBack(const void *value1, 
                                       const void *value2) {
  return value1 == value2;
}

CFHashCode ResultsDictionaryHashCallBack(const void *value) {
  return (CFHashCode)value;
}

