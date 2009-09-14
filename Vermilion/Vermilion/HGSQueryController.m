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
#import "HGSDTrace.h"
#import "GTMDebugThreadValidation.h"
#import "HGSOperation.h"
#import "HGSMemorySearchSource.h"
#import "GTMObjectSingleton.h"
#import <mach/mach_time.h>

NSString *const kHGSQueryControllerWillStartNotification 
  = @"HGSQueryControllerWillStartNotification";
NSString *const kHGSQueryControllerDidFinishNotification 
  = @"HGSQueryControllerDidFinishNotification";
NSString *const kHGSQueryControllerDidUpdateResultsNotification 
  = @"HGSQueryControllerDidUpdateResultsNotification";
NSString *const kHGSQueryControllerDidFinishOperationNotification
  = @"kHGSQueryControllerDidFinishOperationNotification";
NSString *const kHGSQueryControllerOperationsKey
  = @"HGSQueryControllerOperationsKey";
NSString *const kHGSShortcutsSourceIdentifier
  = @"com.google.qsb.shortcuts.source";

NSString *const kQuerySlowSourceTimeoutSecondsPrefKey = @"slowSourceTimeout";

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

@interface HGSSourceRanker : NSObject {
 @private
  NSMutableDictionary *rankDictionary_;
}
+ (HGSSourceRanker *)sharedSourceRanker;
- (void)addTimeDataPoint:(UInt64)machTime 
               forSource:(HGSSearchSource *)source;
- (NSArray *)orderedSources;
@end

@interface HGSQueryController()
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
    operationStartTimes_ = [[NSMutableDictionary alloc] init];
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
  [operationStartTimes_ release];
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
  HGSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSQueryControllerWillStartNotification object:self];
  HGSSourceRanker *sourceRanker = [HGSSourceRanker sharedSourceRanker];
  for (HGSSearchSource *source in [sourceRanker orderedSources]) {
    // Check if the source likes the query string
    if ([source isValidSourceForQuery:parsedQuery_]) {
      HGSSearchOperation* operation;
      operation = [source searchOperationForQuery:parsedQuery_];
      if (operation) {
        [nc addObserver:self 
               selector:@selector(searchOperationWillStart:)
                   name:kHGSSearchOperationWillStartNotification
                 object:operation];
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
        
        NSOperation *nsOp = [operation searchOperation];
        [nsOp setQueuePriority:NSOperationQueuePriorityVeryHigh];
        [queue addOperation:nsOp];
        [nc postNotificationName:kHGSSearchOperationDidQueueNotification 
                          object:operation];
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
    HGSAssert(!slowSourceTimer_, 
              @"We shouldn't start a timer without it having been invalidated");
    slowSourceTimer_
      = [NSTimer scheduledTimerWithTimeInterval:slowSourceTimeout
                                         target:self
                                       selector:@selector(cancelPendingSearchOperations:)
                                       userInfo:nil
                                        repeats:NO];
  }
}

- (void)cancelPendingSearchOperations:(NSTimer*)timer {
  [slowSourceTimer_ invalidate];
  slowSourceTimer_ = nil;
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
                                queryController:self];

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
      category = @"^Others";
      HGSLogDebug(@"No category found for type '%@'.  Using 'Others'.", type);
    }
  }
  
  if (addNewMapping && category) {
    [sTypeCategoryDict setObject:category forKey:type];
  }
  return category;
}

// stops the query
- (void)cancel {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  for (HGSSearchOperation* operation in queryOperations_) {
    [nc removeObserver:self name:nil object:operation];
    [operation cancel];
  }
  [slowSourceTimer_ invalidate];
  slowSourceTimer_ = nil;
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

- (void)searchOperationWillStart:(NSNotification *)notification {
  HGSSearchOperation *operation = [notification object];
  UInt64 startTime = mach_absolute_time();
  NSNumber *nsStartTime = [NSNumber numberWithUnsignedLongLong:startTime];
  [operationStartTimes_ setObject:nsStartTime
                           forKey:[[operation source] identifier]];
  if (VERMILION_SEARCH_START_ENABLED()) {
    HGSSearchSource *source = [operation source];
    HGSQuery *query = [operation query];
    NSString *ptr = [NSString stringWithFormat:@"%p", operation];
    VERMILION_SEARCH_START((char *)[[source identifier] UTF8String],
                           (char *)[[query rawQueryString] UTF8String],
                           (char *)[ptr UTF8String]);
  }
}

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
  HGSSearchSource *source = [operation source];
  NSString *sourceID = [source identifier];
  UInt64 deltaTime = 0;
  // We always want the shortcut source up front, so it's time will
  // always be zero.
  if (![sourceID isEqualToString:kHGSShortcutsSourceIdentifier]) {
    NSNumber *startTime = [operationStartTimes_ objectForKey:sourceID];
    deltaTime = mach_absolute_time() - [startTime unsignedLongLongValue];
  }
  [[HGSSourceRanker sharedSourceRanker] addTimeDataPoint:deltaTime
                                               forSource:source];
  NSDictionary *userInfo 
     = [NSDictionary dictionaryWithObject:[NSArray arrayWithObject:operation]
                                   forKey:kHGSQueryControllerOperationsKey];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSQueryControllerDidFinishOperationNotification
                    object:self
                  userInfo:userInfo];
  // If this is the last query operation to complete then report as overall
  // query completion and cancel our timer.
  if ([self queriesFinished]) {
    [slowSourceTimer_ invalidate];
    slowSourceTimer_ = nil;

    [nc postNotificationName:kHGSQueryControllerDidFinishNotification 
                      object:self];
  }
  if (VERMILION_SEARCH_FINISH_ENABLED()) {
    HGSQuery *query = [operation query];
    NSString *ptr = [NSString stringWithFormat:@"%p", operation];
    VERMILION_SEARCH_FINISH((char *)[[source identifier] UTF8String],
                            (char *)[[query rawQueryString] UTF8String],
                            (char *)[ptr UTF8String]);
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
  HGSSearchOperation *operation = [notification object];
  CFDictionarySetValue(sourceResults_, operation, operationResults);
  [rankedResults_ release];
  rankedResults_ = nil;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSDictionary *newUserInfo 
    = [NSDictionary dictionaryWithObject:[NSArray arrayWithObject:operation]
                                  forKey:kHGSQueryControllerOperationsKey];
  [nc postNotificationName:kHGSQueryControllerDidUpdateResultsNotification 
                    object:self
                  userInfo:newUserInfo];
}

- (NSArray *)pendingQueries {
  return [[pendingQueryOperations_ copy] autorelease];
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
  return (CFStringRef)[[(id)value description] copy];
}

Boolean ResultsDictionaryEqualCallBack(const void *value1, 
                                       const void *value2) {
  return value1 == value2;
}

CFHashCode ResultsDictionaryHashCallBack(const void *value) {
  return (CFHashCode)value;
}

// Keep track of the average running time for a given source.
// These are stored by HGSSourceRanker in it's rankDictionary keyed
// by source identifier. In the future we may use other criteria to determine
// the order in which to run sources (such as rank relevancy).
@interface HGSSourceRankerDataPoint : NSObject {
 @private
  UInt64 runTime_;
  NSUInteger entries_;
}
- (void)addTimeDataPoint:(UInt64)machTime;
- (UInt64)averageTime;
@end

NSInteger HGSSourceRankerSort(id src1, id src2, void *rankDict) {
  HGSSearchSource *source1 = (HGSSearchSource *)src1;
  HGSSearchSource *source2 = (HGSSearchSource *)src2;
  NSDictionary *rankDictionary = (NSDictionary *)rankDict;
  NSString *id1 = [source1 identifier];
  NSString *id2 = [source2 identifier];
  HGSSourceRankerDataPoint *dp1 = [rankDictionary objectForKey:id1];
  HGSSourceRankerDataPoint *dp2 = [rankDictionary objectForKey:id2];
  UInt64 time1 = [dp1 averageTime];
  UInt64 time2 = [dp2 averageTime];
  NSInteger order = NSOrderedSame;
  if (time1 > time2) {
    order = NSOrderedDescending;
  } else if (time2 < time1) {
    order = NSOrderedAscending;
  } else if (time1 == 0 && time2 == 0) {
    // If we have no data on either of them, run memory search sources first.
    // This will mainly apply for our first searches we run.
    Class memSourceClass = [HGSMemorySearchSource class]; 
    BOOL src1IsMemorySource = [source1 isKindOfClass:memSourceClass];
    BOOL src2IsMemorySource = [source2 isKindOfClass:memSourceClass];
    if (src1IsMemorySource && !src2IsMemorySource) {
      order = NSOrderedAscending;
    } else if (!src1IsMemorySource && src2IsMemorySource) {
      order = NSOrderedDescending;
    }
  }
  return order;
}
    
@implementation HGSSourceRanker
GTMOBJECT_SINGLETON_BOILERPLATE(HGSSourceRanker, sharedSourceRanker);

- (id)init {
  if ((self = [super init])) {
    rankDictionary_ = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)dealloc {
  [rankDictionary_ release];
  [super dealloc];
}

- (void)addTimeDataPoint:(UInt64)machTime 
               forSource:(HGSSearchSource *)source {
  NSString *sourceID = [source identifier];
  @synchronized (self) {
    HGSSourceRankerDataPoint *dp = [rankDictionary_ objectForKey:sourceID];
    if (!dp) {
      dp = [[[HGSSourceRankerDataPoint alloc] init] autorelease];
      [rankDictionary_ setObject:dp forKey:sourceID];
    }
    [dp addTimeDataPoint:machTime];
  }
}

- (NSArray *)orderedSources {
  HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
  NSMutableArray *sources = [[[sourcesPoint extensions] mutableCopy] autorelease];
  @synchronized (self) {
    [sources sortUsingFunction:HGSSourceRankerSort context:rankDictionary_];
  }
  return sources;
}
@end

@implementation HGSSourceRankerDataPoint
- (void)addTimeDataPoint:(UInt64)machTime {
  runTime_ += machTime;
  entries_ += 1;
}

- (UInt64)averageTime {
  return runTime_ / entries_;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"averageTime: %llu (runTime: %llu entries "
          @"%lu)", [self averageTime], runTime_, entries_];
}
@end
