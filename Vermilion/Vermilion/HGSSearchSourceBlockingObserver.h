//
//  HGSSearchSourceBlockingObserver.h
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

#import <Foundation/Foundation.h>
#import "HGSSearchSourceObserver.h"

@class HGSSearchOperation;

// An empty search source observer which can simply records whether a
// search operation is finished and/or results returned.
//
// It can also block until searchOperationFinish: or
// searchOperationUpdated: is called.
@interface HGSSearchSourceBlockingObserver : NSObject <HGSSearchSourceObserver> {
  NSUInteger updateCount_;
  BOOL finished_;
}

// Blocks while waiting for searchOperationFinished: is called. Gives up
// after |timeout| seconds.
- (void)runUntilSearchOperationFinishedCalled:(NSTimeInterval)timeout;
// Blocks while waiting for searchOperationUpdated: is called. Gives up after
// |timeout| seconds.
- (void)runUntilSearchOperationUpdatedCalled:(NSTimeInterval)timeout;

// Is the operation finished?
- (BOOL)finished;
// How many times did searchOperationUpdated: get called?
- (NSUInteger)updateCount;
@end
