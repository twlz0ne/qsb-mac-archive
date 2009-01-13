//
//  HGSSearchSourceBlockingObserver.m
//  GoogleMobile
//
//  Created by Alastair Tse on 2008/05/17.
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

#import "HGSSearchSourceBlockingObserver.h"
// We use an alternative SenTesting framework for iPhone.
#if TARGET_OS_IPHONE
#import "GTMSenTestCase.h"
#else
#import <SenTestingKit/SenTestingKit.h>
#endif


@implementation HGSSearchSourceBlockingObserver

- (void)runUntilSearchOperationFinishedCalled:(NSTimeInterval)timeout {
  NSDate* startDate = [NSDate date];
  while (!finished_) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (-1 * [startDate timeIntervalSinceNow] > timeout) {
      // Timeout exceeded.
      STAssertFalse(YES,
                    @"Timed out waiting for request to complete: %f",
                    -1 * [startDate timeIntervalSinceNow]);
      break;
    }
  }
}

- (void)runUntilSearchOperationUpdatedCalled:(NSTimeInterval)timeout {
  NSDate* startDate = [NSDate date];
  while (updateCount_ < 1) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (-1 * [startDate timeIntervalSinceNow] > timeout) {
      // Timeout exceeded.
      STAssertFalse(YES,
                    @"Timed out waiting for request to complete: %f",
                    -1 * [startDate timeIntervalSinceNow]);
      break;
    }
  }
}
- (void)searchOperationFinished:(HGSSearchOperation *)operation {
  STAssertFalse(finished_, @"Already finished");
  finished_ = YES;
}

- (void)searchOperationUpdated:(HGSSearchOperation *)operation {
  STAssertFalse(finished_, @"Already finished");
  ++updateCount_;
}

- (BOOL)finished {
  return finished_;
}

- (NSUInteger)updateCount {
  return updateCount_;
}

@end
