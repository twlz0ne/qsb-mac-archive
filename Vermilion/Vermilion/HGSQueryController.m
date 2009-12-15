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
#import "HGSDTrace.h"
#import "HGSOperation.h"
#import "HGSMemorySearchSource.h"
#import "GTMObjectSingleton.h"
#import <mach/mach_time.h>

NSString *const kHGSQueryControllerWillStartNotification 
  = @"HGSQueryControllerWillStartNotification";
NSString *const kHGSQueryControllerDidFinishNotification 
  = @"HGSQueryControllerDidFinishNotification";

NSString *const kQuerySlowSourceTimeoutSecondsPrefKey = @"slowSourceTimeout";

@interface HGSSourceRanker : NSObject {
 @private
  NSMutableDictionary *rankDictionary_;
}
+ (HGSSourceRanker *)sharedSourceRanker;
- (void)addTimeDataPoint:(UInt64)machTime 
               forSource:(HGSSearchSource *)source;
- (NSArray *)orderedSources;
- (UInt64)averageTimeForSource:(HGSSearchSource *)source;
@end

@interface HGSQueryController()
- (void)cancelPendingSearchOperations:(NSTimer*)timer;
@end

@implementation HGSQueryController
@synthesize mixer = mixer_;

+ (void)initialize {
  if (self == [HGSQueryController class]) {
    NSDictionary *defaultsDict
      = [NSDictionary dictionaryWithObject:[NSNumber numberWithDouble:60.0]
                                    forKey:kQuerySlowSourceTimeoutSecondsPrefKey];
    NSUserDefaults *sd = [NSUserDefaults standardUserDefaults];
    [sd registerDefaults:defaultsDict];
  }
}

- (id)initWithQuery:(HGSQuery*)query {
  if ((self = [super init])) {
    queryOperations_ = [[NSMutableArray alloc] init];
    pendingQueryOperations_ = [[NSMutableArray alloc] init];
    queryOperationsWithResults_ = [[NSMutableSet alloc] init];
    parsedQuery_ = [query retain];
  }
  return self;
}

- (void)dealloc {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [self cancel];
  [rankedResults_ release];
  [queryOperations_ release];
  [parsedQuery_ release];
  [pendingQueryOperations_ release];
  [queryOperationsWithResults_ release];
  [mixer_ cancel];
  [mixer_ release];
  [super dealloc];
}

- (void)startQuery {
  // Spin through the Sources checking to see if they are valid for the source
  // and kick off the SearchOperations.  
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
      }
    }
  }
  
  UInt64 startUpTime = 0;
  // We will run up to 50 ms of queries on the main thread. This cuts
  // down on the overhead of thread creation, and gives us really fast
  // first results for quick sources.
  AbsoluteTime absoluteWaitTime = DurationToAbsolute(durationMillisecond * 50);
  UInt64 waitTime = UnsignedWideToUInt64(absoluteWaitTime);
  for (HGSSearchOperation *operation in queryOperations_) {
    HGSSearchSource *source = [operation source];
    startUpTime += [sourceRanker averageTimeForSource:source];
    [operation run:((startUpTime > 0) && (startUpTime < waitTime))];
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

- (void)startMixingCurrentResults:(id<HGSMixerDelegate>)delegate {
  NSArray *currentOps = nil;
  @synchronized (queryOperationsWithResults_) {
    currentOps = [queryOperationsWithResults_ allObjects];
  }
  [mixer_ cancel];
  [mixer_ release];
  mixer_ = [[HGSMixer alloc] initWithDelegate:delegate
                             searchOperations:currentOps
                               mainThreadTime:0.05];
  [mixer_ start];
}

- (NSArray *)rankedResults {
  return [mixer_ rankedResults];
}

- (NSDictionary *)rankedResultsByCategory {
  return [mixer_ rankedResultsByCategory];
}

- (NSUInteger)totalResultsCount {
  NSUInteger count = 0;
  @synchronized (queryOperationsWithResults_) {
    for (HGSSearchOperation *op in queryOperationsWithResults_) {
      count += [op resultCount];
    }
  }
  return count;
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

- (BOOL)isCancelled {
  return cancelled_;
}  

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ - Predicate:%@ Operations:%@", 
          [super description], parsedQuery_, queryOperations_];
}
          
#pragma mark Notifications

- (void)searchOperationWillStart:(NSNotification *)notification {
  HGSSearchOperation *operation = [notification object];
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
  UInt64 runTime = [operation runTime];
  [[HGSSourceRanker sharedSourceRanker] addTimeDataPoint:runTime
                                               forSource:source];
  
  // If this is the last query operation to complete then report as overall
  // query completion and cancel our timer.
  if ([self queriesFinished]) {
    [slowSourceTimer_ invalidate];
    slowSourceTimer_ = nil;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
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
  HGSSearchOperation *operation = [notification object];
  @synchronized (self) {
    [queryOperationsWithResults_ addObject:operation];
  }
}

- (NSArray *)pendingQueries {
  return [[pendingQueryOperations_ copy] autorelease];
}
@end

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
  } else if (time1 < time2) {
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

- (UInt64)averageTimeForSource:(HGSSearchSource *)source {
  UInt64 avgTime = 0;
  NSString *sourceID = [source identifier];
  @synchronized (self) {
    HGSSourceRankerDataPoint *dp = [rankDictionary_ objectForKey:sourceID];
    if (dp) {
      avgTime = [dp averageTime];
    }
  }
  return avgTime;
}

- (NSArray *)orderedSources {
  HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
  NSMutableArray *sources = [[[sourcesPoint extensions] mutableCopy] autorelease];
  @synchronized (self) {
    [sources sortUsingFunction:HGSSourceRankerSort context:rankDictionary_];
  }
  return sources;
}

- (NSString *)description {
  NSArray *orderedSources = [self orderedSources];
  NSMutableString *string = [NSMutableString stringWithString:[super description]];
  for(HGSSearchSource *source in orderedSources) {
    NSString *identifier = [source identifier];
    HGSSourceRankerDataPoint *dp = [rankDictionary_ objectForKey:identifier];
    [string appendFormat:@"  %15lld %@\n", [dp averageTime], [source displayName]];
  }
  return string;
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
