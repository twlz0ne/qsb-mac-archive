//
//  HGSMixer.h
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

/*!
 @header
 @discussion HGSMixer
*/

#import <Foundation/Foundation.h>
#import "GTMDefines.h"

@class HGSQueryController;
@class HGSScoredResult;

/*!
 The mixer takes N arrays that are assumed to be internally sorted
 and mixes them all together into a single array whose ranking is based
 on global (cross-provider) heuristics. The mixer also handles merging
 duplicate results together (lower ranked into higher ranked).
*/
@interface HGSMixer : NSObject {
 @private
  NSArray *ops_;
  NSMutableArray *results_;
  NSMutableDictionary *resultsByCategory_;
  uint64_t mainThreadTime_;
  NSInteger *opsIndices_;
  NSInteger *opsMaxIndices_;
  NSUInteger currentIndex_;
  NSOperation *operation_;
  NSOperationQueue *opQueue_;
  volatile BOOL isFinished_;
  volatile BOOL isCancelled_;
}

/*!
 Designated initializer.
 @param ops - the ops that supply the results that the mixer mixes
 @param mainThreadTime - the amount of time that the mixer should run on the 
                         main thread (to optimize speed) before moving to a
                         background thread (to optimize user responsiveness)
*/
- (id)initWithSearchOperations:(NSArray *)ops
                mainThreadTime:(NSTimeInterval)mainThreadTime;
        
/*!
  A snapshot of the results. Safe to call from any thread. Calling this too
  often will slow down the mixing.
*/
- (NSArray *)rankedResults;

/*!
  A snapshot of the results sorted by categories. Safe to call from any thread. 
  Calling this too often will slow down the mixing.
*/
- (NSDictionary *)rankedResultsByCategory;

/*!
  Start the mixing operation.
*/
- (void)start;

- (BOOL)isCancelled;
- (void)cancel;
- (BOOL)isFinished;
@end


/*! 
 The standard HGS sort. Suitable for use with
 -[NSArray sortedArrayUsingFunction:context:].
 @param resultA a HGSScoredResult*
 @param resultB a HGSScoredResult*
 @param context is ignored.
*/
NSInteger HGSMixerScoredResultSort(HGSScoredResult *resultA, 
                                   HGSScoredResult *resultB, 
                                   void* context);

/*!
 Called when the mixer will start.  Object is the mixer.
*/
GTM_EXTERN NSString *const kHGSMixerWillStartNotification;

/*!
 Called when the mixer has completed or was cancelled. Object is the mixer.
*/
GTM_EXTERN NSString *const kHGSMixerDidFinishNotification;
