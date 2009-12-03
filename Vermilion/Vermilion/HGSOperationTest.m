//
//  HGSOperationTest.m
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

#import <Foundation/Foundation.h>
#import "GTMSenTestCase.h"
#import "HGSOperation.h"
#import <GData/GDataHTTPFetcher.h>

static const useconds_t kDiskOperationLength = 500000; // microseconds
static const useconds_t kNetworkOperationLength = 500000; // microseconds
static const NSInteger kMemoryOperationCount = 10;
static const NSInteger kNormalOperationCount = 5;
static NSString * const kGoogleUrl = @"http://www.google.com/";
static NSString * const kGoogle404Url = @"http://www.google.com/dfhasjhdfkhdgkshg";
static NSString * const kGoogleNonExistentUrl = @"http://sgdfgsdfsewfgsd.corp.google.com/";

@interface HGSOperationTest : GTMTestCase {
  BOOL          finishedWithDataIsRunning_;
  BOOL          finishedWithData_;
  BOOL          failedWithStatus_;
  BOOL          failedWithError_;
  NSInteger     memoryOperations_;
  NSInteger     normalOperations_;
}
- (void)diskCounterOperation:(id)obj;
@end

@implementation HGSOperationTest

- (void)diskCounterOperation:(id)obj {
  static NSInteger expectOpNum;
  static NSInteger counter;
  
  STAssertNotNil([HGSInvocationOperation currentOperation],
                 @"currentOperation not present");
  STAssertTrue([obj isKindOfClass:[NSNumber class]],
               @"incorrect argument passed to disk operation");
  
  @synchronized(self) {
    // Ensure that we are running sequentially
    STAssertEquals(expectOpNum, [obj integerValue],
                   @"disk operation ran out of order");
    if (expectOpNum == 3) {
      // Op 4 is cancelled
      expectOpNum = 5;
    } else {
      expectOpNum++;
    }
    // Ensure that we are not running simultaneously
    STAssertEquals(counter, (NSInteger)0, @"disk operation is already running");
    counter++;
  }
  
  // Sleep long enough to allow the operation queue to do some more work (that
  // is, give us some confidence that our test results are accurate because
  // the class is correctly implemented, not because the operation ran so
  // quickly that the next queued-up operation didn't have time to start)
  usleep(kDiskOperationLength);
  
  @synchronized(self) {
    // Ensure that we are still not running simultaneously
    STAssertEquals(counter, (NSInteger)1, @"disk operation started while one was running");
    counter--;
  }
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  finishedWithData_ = YES;
  STAssertNotNil(fetcher, @"finishedWithData got a nil GDataHTTPFetcher");
  STAssertNotNil(fetcher, @"finishedWithData got a nil retrievedData");
  STAssertTrue([retrievedData length] != 0,
               @"finishedWithData got an empty retrievedData");
  STAssertTrue([[[[fetcher request] URL] absoluteString] isEqual:kGoogleUrl],
               @"finishedWithData URL incorrect");

  // Simulate a long-running operation that gets cancelled. This operation will
  // start off non-cancelled. Signal the condition variable
  // to let testNetworkOperations know we're running, which will give it a
  // chance cancel us. Then, sleep for a couple of seconds after signalling
  // the condition to give testNetworkOperations a chance to cancel.
  NSCondition *condition = [fetcher userData];
  STAssertFalse([[HGSInvocationOperation currentOperation] isCancelled],
                @"finishedWithData operation was cancelled");
  [condition lock];
  finishedWithDataIsRunning_ = YES;
  [condition signal];
  [condition unlock];
  usleep(kNetworkOperationLength); // testNetworkOperations is now cancelling...
  STAssertTrue([[HGSInvocationOperation currentOperation] isCancelled],
               @"finishedWithData operation was not cancelled");
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  // Just confirm that both GDataHTTPFetcher's status errors and network errors
  // come to this callback.
  if ([[error domain] isEqual:kGDataHTTPFetcherStatusDomain]) {
    failedWithStatus_ = YES;

    NSInteger status = [error code];
    NSString *urlString = [[[fetcher request] URL] absoluteString];
    if ([urlString isEqual:kGoogle404Url]) {
      STAssertEquals(status, (NSInteger)404, @"failedWithStatus expected a 404 response");
    } else if ([urlString isEqual:kGoogleUrl]) {
      STFail(@"Google home page request failed");
      NSCondition *condition = [fetcher userData];
      [condition lock];
      finishedWithDataIsRunning_ = YES;
      [condition signal];
      [condition unlock];
    } else if ([urlString isEqual:kGoogleNonExistentUrl]) {
      // Depending on how DNS is done, we could get a 503 or a non 
      // kGDataHTTPFetcherStatusDomain error. So we set failedWithError_ in
      // both cases.
      failedWithError_ = YES;
    }
  } else {
    failedWithError_ = YES;

    NSCondition *condition = [fetcher userData];
    [condition lock];
    finishedWithDataIsRunning_ = YES;
    [condition signal];
    [condition unlock];
  }
}

- (void)memoryOperationCounter:(id)obj {
  STAssertNotNil([HGSInvocationOperation currentOperation],
                 @"currentOperation not present");
  @synchronized(self) {
    memoryOperations_++;
  }
}

- (void)normalOperationCounter:(id)obj {
  STAssertNil([HGSInvocationOperation currentOperation],
              @"currentOperation is present");
  @synchronized(self) {
    normalOperations_++;
  }
}

- (void)testDiskOperations {
  NSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  
  // Queue up a bunch of long disk operations
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:0]]];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:1]]];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:2]]];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:3]]];
  NSInvocationOperation *op4 = [HGSInvocationOperation
    diskInvocationOperationWithTarget:self
                             selector:@selector(diskCounterOperation:)
                               object:[NSNumber numberWithInt:4]];
  [queue addOperation:op4];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:5]]];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:6]]];
  [queue addOperation:[HGSInvocationOperation
   diskInvocationOperationWithTarget:self
                            selector:@selector(diskCounterOperation:)
                              object:[NSNumber numberWithInt:7]]];
  // Cancel one in the middle to make sure 1) it doesn't run; 2) we
  // continue to run in order; and 3) we continue to run non-
  // simultaneously
  [op4 cancel];
  STAssertTrue([op4 isCancelled],
               @"cancelled disk operation didn't end up that way");
  [queue waitUntilAllOperationsAreFinished];
}

- (void)testNetworkOperations {
  NSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  NSCondition *condition = [[[NSCondition alloc] init] autorelease];
  
  // Request Google's home page
  NSURL *url = [NSURL URLWithString:kGoogleUrl];
  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  GDataHTTPFetcher *fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];
  [fetcher setUserData:condition];
  NSOperation *networkOp = [HGSInvocationOperation
     networkInvocationOperationWithTarget:self
                               forFetcher:fetcher
                        didFinishSelector:@selector(httpFetcher:finishedWithData:)
                          didFailSelector:@selector(httpFetcher:failedWithError:)];
  STAssertNotNil(networkOp, @"failed to create network op for %@", kGoogleUrl);
  [queue addOperation:networkOp];
  [condition lock];
  while (!finishedWithDataIsRunning_) {
    [condition wait];
  }
  [networkOp cancel];
  [condition unlock];
  
  // Request a non-existent Google page
  url = [NSURL URLWithString:kGoogle404Url];
  request = [NSURLRequest requestWithURL:url];
  fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];
  networkOp = [HGSInvocationOperation
     networkInvocationOperationWithTarget:self
                               forFetcher:fetcher
                        didFinishSelector:@selector(httpFetcher:finishedWithData:)
                          didFailSelector:@selector(httpFetcher:failedWithError:)];
  STAssertNotNil(networkOp, @"failed to create network op for %@", kGoogle404Url);
  [queue addOperation:networkOp];
  
  // Request a non-existent web site
  url = [NSURL URLWithString:kGoogleNonExistentUrl];
  request = [NSURLRequest requestWithURL:url];
  fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];
  networkOp = [HGSInvocationOperation
     networkInvocationOperationWithTarget:self
                               forFetcher:fetcher
                        didFinishSelector:@selector(httpFetcher:finishedWithData:)
                          didFailSelector:@selector(httpFetcher:failedWithError:)];
  STAssertNotNil(networkOp, @"failed to create network op for %@", kGoogleNonExistentUrl);
  [queue addOperation:networkOp];
  
  [queue waitUntilAllOperationsAreFinished];
  
  STAssertTrue(finishedWithData_,
               @"finishedWithData: not called by network operation");
  STAssertTrue(failedWithStatus_,
               @"failedWithError: not called for status by network operation");
  STAssertTrue(failedWithError_,
               @"failedWithError: not called for network error by network operation");
}

- (void)testMemoryOperations {
  NSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  for (NSInteger i = 0; i < kMemoryOperationCount; i++) {
    NSOperation *memoryOp = [HGSInvocationOperation
                             memoryInvocationOperationWithTarget:self
                                                        selector:@selector(memoryOperationCounter:)
                                                          object:self];
    STAssertNotNil(memoryOp, @"failed to create memory op");
    [queue addOperation:memoryOp];
  }
  
  [queue waitUntilAllOperationsAreFinished];
  
  STAssertEquals(memoryOperations_, kMemoryOperationCount,
                 @"incorrect number of memory operations completed");
}

- (void)testNSInvocationOperations {
  // Make sure that plain NSInvocationOperations work OK with our
  // NSOperationQueue subclass
  NSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  for (int i = 0; i < kNormalOperationCount; i++) {
    NSOperation *normalOp = [[NSInvocationOperation alloc]
                             initWithTarget:self
                                   selector:@selector(normalOperationCounter:)
                                     object:self];
    STAssertNotNil(normalOp, @"failed to create memory op");
    [queue addOperation:normalOp];
  }
  
  [queue waitUntilAllOperationsAreFinished];
  
  STAssertEquals(normalOperations_, kNormalOperationCount,
                 @"incorrect number of memory operations completed");
}

@end
