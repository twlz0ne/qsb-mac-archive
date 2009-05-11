//
//  HGSSearchOperation.m
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

#import "HGSSearchOperation.h"
#import "HGSSearchSource.h"
#import "HGSOperation.h"
#import "HGSLog.h"

NSString *const kHGSSearchOperationDidQueueNotification
  = @"HGSSearchOperationDidQueueNotification";
NSString *const kHGSSearchOperationWillStartNotification 
  = @"HGSSearchOperationWillStartNotification";
NSString *const kHGSSearchOperationDidFinishNotification 
  = @"HGSSearchOperationDidFinishNotification";
NSString *const kHGSSearchOperationDidUpdateResultsNotification 
  = @"HGSSearchOperationDidUpdateResultsNotification";
NSString *const kHGSSearchOperationWasCancelledNotification
  = @"HGSSearchOperationWasCancelledNotification";
NSString *const kHGSSearchOperationNotificationResultsKey
   = @"HGSSearchOperationNotificationResultsKey";

@interface NSNotificationCenter (HGSSearchOperation)
- (void)hgs_postOnMainThreadNotificationName:(NSString *)name object:(id)object;
- (void)hgs_postOnMainThreadNotificationName:(NSString *)name 
                                      object:(id)object
                                    userInfo:(NSDictionary *)info;
@end

@interface HGSSearchOperation ()
@property (assign, getter=isFinished) BOOL finished;
@end

@implementation HGSSearchOperation

@synthesize source = source_;
@synthesize query = query_;
@synthesize finished = finished_;
@dynamic concurrent;
@dynamic cancelled;

- (id)initWithQuery:(HGSQuery*)query source:(HGSSearchSource *)source {
  if ((self = [super init])) {
    source_ = [source retain];
    query_ = [query retain]; 
  }
  return self;
}

- (void)dealloc {
  [source_ release];
  [operation_ release];
  [query_ release];
  [super dealloc];
}

- (BOOL)isConcurrent {
  return NO;
}

- (void)cancel {
  // Even though we clear the operation here, we don't need to
  // do anything from a threading pov.  If |operation_| were in a queue to run,
  // the queue would have a retain on it, so it won't get freed from under it.
  queryCancelled_ = YES;
  [operation_ cancel];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc hgs_postOnMainThreadNotificationName:kHGSSearchOperationWasCancelledNotification
                                    object:self];  
  [operation_ release];
  operation_ = nil;
}

- (BOOL)isCancelled {
  // NOTE: this is thread safe because the NSOperationQueue has to retain the
  // operation while it runs.  So the fact that -cancel releases it is ok.
  return queryCancelled_ || [operation_ isCancelled];
}

// call to replace the results of the operation with something more up to date.
// Threadsafe, can be called from any thread. Tells observers about the
// presence of new results on the main thread.
- (void)setResults:(NSArray*)results {
  if ([self isCancelled]) return;
  HGSAssert(![self isFinished], @"setting results after the query is done?");
  // No point in telling the observers there weren't results.  The source
  // should be calling finishQuery shortly to let it know it's done.
  if ([results count] == 0) return;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  // We do a copy here in case sources pass us a mutable object
  // and then go and mutate it underneath us.
  NSArray *cachedResults = [[results copy] autorelease];
  NSDictionary *userInfo 
    = [NSDictionary dictionaryWithObject:cachedResults 
                                  forKey:kHGSSearchOperationNotificationResultsKey];
  [nc hgs_postOnMainThreadNotificationName:kHGSSearchOperationDidUpdateResultsNotification
                                    object:self
                                  userInfo:userInfo];
}

- (void)wrappedMain {
  // Wrap main so we can log any exceptions and make sure we finish the search
  // operation if it threw.
  @try {
    [self main];
  }
  @catch (NSException * e) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey]) {
      HGSLog(@"ERROR: exception (%@) from SearchOperation %@", e, self);
    }
    // Make sure it's been marked as finished since it probably won't do that on
    // it's own now.
    if (![self isFinished]) {
      [self finishQuery];
    }
  }
}
  
- (void)queryOperation:(id)ignored {
  if (![self isCancelled]) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc hgs_postOnMainThreadNotificationName:kHGSSearchOperationWillStartNotification
                                      object:self];
    if ([self isConcurrent]) {
      // Concurrents were queued just to get things started, we bounce to the
      // main loop to actually run them (and they have to call finished when
      // done).
      [self performSelectorOnMainThread:@selector(wrappedMain)
                             withObject:nil
                          waitUntilDone:NO];
      // Drop the NSOperation, it was just here to get use into the queue.
      [operation_ release];
      operation_ = nil;
    } else {
      // Fire it
      @try {
        [self main];
      }
      @catch (NSException * e) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey]) {
          HGSLog(@"ERROR: exception (%@) from SearchOperation %@", e, self);
        }
      }
      // Non concurrent ones are done when their main finishes
      [self finishQuery];
    }
  }
}

- (void)finishQuery {
  if ([self isFinished]) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey]) {
      HGSLog(@"ERROR: finishedQuery called more than once for SearchOperation"
             @" %@ (if search operation is concurrent, you do NOT need to call"
             @" finishQuery).",
             self);
    }
    // Never send the notification twice
    return;
  }
  [self setFinished:YES];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc hgs_postOnMainThreadNotificationName:kHGSSearchOperationDidFinishNotification
                                    object:self];
}

- (void)main {
  // Since SearchSources are the only thing that needs to create these, we use
  // their pref for enabling extra logging to help developers out.
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey]) {
    HGSLog(@"ERROR: SearchOperation %@ forgot to override main.",
           [self class]);
  }
  [self doesNotRecognizeSelector:_cmd];
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ %@ - query: %@", 
          [super description],  
          [self isFinished] ? @"finished" : @"", query_];
}

- (NSString *)displayName {
  return NSStringFromClass([self class]);
}

- (NSOperation *)searchOperation {
  return [[NSInvocationOperation alloc] initWithTarget:self
                                              selector:@selector(queryOperation:)
                                                object:nil];
}

@end

@implementation NSNotificationCenter (HGSSearchOperation)

- (void)hgs_postOnMainThreadNotificationName:(NSString *)name 
                                      object:(id)object {
  [self hgs_postOnMainThreadNotificationName:name object:object userInfo:nil];
}

- (void)hgs_postOnMainThreadNotificationName:(NSString *)name 
                                      object:(id)object
                                    userInfo:(NSDictionary *)info {
  NSNotification *notification = [NSNotification notificationWithName:name 
                                                               object:object
                                                             userInfo:info];
  [self performSelectorOnMainThread:@selector(postNotification:)
                         withObject:notification
                      waitUntilDone:NO];
}

@end
