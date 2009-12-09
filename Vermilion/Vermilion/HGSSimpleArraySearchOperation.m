//
//  HGSSimpleArraySearchOperation.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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

#import "HGSSimpleArraySearchOperation.h"
#import "HGSLog.h"
#import "NSNotificationCenter+MainThread.h"
#import "GTMMethodCheck.h"

@implementation HGSSimpleArraySearchOperation
GTM_METHOD_CHECK(NSNotificationCenter, hgs_postOnMainThreadNotificationName:object:userInfo:);

- (void)dealloc {
  [results_ release];
  [super dealloc];
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
  @synchronized (self) {
    [results_ autorelease];
    results_ = [results copy];
  }
  [nc hgs_postOnMainThreadNotificationName:kHGSSearchOperationDidUpdateResultsNotification
                                    object:self
                                  userInfo:nil];
}

- (NSArray *)sortedResultsInRange:(NSRange)range {
  NSArray *sortedResults = nil;
  @synchronized (self) {
    NSRange fullRange = NSMakeRange(0, [results_ count]);
    NSRange newRange = NSIntersectionRange(fullRange, range);
    if (newRange.length) {
      sortedResults = [results_ subarrayWithRange:newRange];
    }
  }
  return sortedResults;
}

- (HGSResult *)sortedResultAtIndex:(NSUInteger)idx {
  HGSResult *result = nil;
  @synchronized (self) {
    result = [results_ objectAtIndex:idx];
  }
  return result;
}
  
- (NSUInteger)resultCount {
  NSUInteger count = 0;
  @synchronized (self) {
    count = [results_ count];
  }
  return count;
}

@end
