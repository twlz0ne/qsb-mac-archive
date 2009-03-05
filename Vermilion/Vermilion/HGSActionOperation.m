//
//  HGSActionOperation.m
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

#import "HGSActionOperation.h"
#import "HGSAction.h"
#import "HGSLog.h"

NSString *const kHGSActionWillPerformNotification = @"HSGActionWillPerformNotification";
NSString *const kHGSActionDidPerformNotification = @"HSGActionDidPerformNotification";
NSString* const kHGSActionCompletedSuccessfully = @"HGSActionCompletedSuccessfully";

@implementation HGSActionOperation
- (id)initWithAction:(id<HGSAction>)action 
       directObjects:(HGSResultArray *)directObjects {
  return [self initWithAction:action
                directObjects:directObjects
              indirectObjects:nil];
}

- (id)initWithAction:(id<HGSAction>)action 
       directObjects:(HGSResultArray *)directObjects
     indirectObjects:(HGSResultArray *)indirectObjects {
  if ((self = [super init])) {
    action_ = [action retain];
    args_
      = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
           directObjects, kHGSActionDirectObjectsKey,
           indirectObjects, kHGSActionIndirectObjectsKey,
           nil];
    if (!action_ || !directObjects || !args_) {
      [self release];
      return nil;
    }
  }
  return self;
}
  
- (void)dealloc {
  [action_ release];
  [args_ release];
  [super dealloc];
}

- (NSDictionary*)performAction {
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  NSNotification *notification
    = [NSNotification notificationWithName:kHGSActionWillPerformNotification
                                    object:action_
                                  userInfo:args_];
  [center postNotification:notification];
  // TODO(dmaclach): when we want to revisit results on actions, no only do we
  // need a result vs. success, we also need to figure out how we want to manage
  // actions that take a while.  this currently works synchronous to the main
  // event loop, so we'll need some way to mark actions as "long" so we know to
  // spawn them in a thread, or pass some context object/observer so the action
  // can then call back w/ the result when it's done.
  BOOL result = NO;
  @try {
    // Adding exception handler as we are potentially calling out
    // to third party code here that could be nasty to us.
    result =[action_ performWithInfo:args_];
  } 
  @catch (NSException *e) {
    result = NO;
    HGSLog(@"Exception thrown performing action: %@ (%@)", action_, e);
  }
  NSNumber *success = [NSNumber numberWithBool:result ? YES : NO];
  [args_ setObject:success forKey:kHGSActionCompletedSuccessfully];
  notification 
    = [NSNotification notificationWithName:kHGSActionDidPerformNotification
                                    object:action_
                                  userInfo:args_];
  [center postNotification:notification];
  return args_;
}

@end
