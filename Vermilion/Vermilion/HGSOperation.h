//
//  HGSOperation.h
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
 @header NSInvocationOperation and NSOperationQueue Specializations
 HGSInvocationOperation and HGSOperationQueue provide serialization and
 threading control.
*/

#import <Foundation/Foundation.h>

@class GDataHTTPFetcher;

@interface NSOperation(HGSInvocationOperation)
- (BOOL)isDiskOperation;
@end

/*! 
 @enum InvocationType Internal use only.
 @constant NORMAL_INVOCATION Standard NSInvocationOperation invocation.
 @constant DISK_INVOCATION Serialize with other disk invocations.
 @constant NETWORK_INVOCATION Invoke with multiple finish selectors.
 @constant MEMORY_INVOCATION Invoke with low priority.
 */
typedef enum {
  NORMAL_INVOCATION = 0,
  DISK_INVOCATION,
  NETWORK_INVOCATION,
  MEMORY_INVOCATION
} InvocationType;

/*!
 Add invocations specialized for serialization, priority and dispatching
 of multiple finishers.
*/
@interface HGSInvocationOperation : NSInvocationOperation {
 @private
  InvocationType invocationType_;
  id target_;
  SEL selector_;
}

/*!
  Create an HGSInvocationOperation that behaves like a standard
  non-concurrent (in the NSOperation sense of "concurrent")
  NSInvocationOperation with one exception: when added to an
  HGSOperationQueue, disk invocations are run sequentially, without
  the possibility of running coincident to other disk invocations. This
  ensures that only one thread is hitting the disk at any time.
*/
+ (HGSInvocationOperation *)diskInvocationOperationWithTarget:(id)target
                                                     selector:(SEL)sel
                                                       object:(id)arg;

/*!
  Helper for GDataHTTPFetcher which calls the finish selectors using
  NSOperations rather than running them on the same thread that made
  the initial async request. This call replaces GDataHTTPFetcher's
  beginFetchWithDelegate method. For instance:
 
@textblock
  GDataHTTPFetcher *fetcher = [GDataHTTPFetcher httpFetcherWithRequest:req];
  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(httpFetcher:finishedWithData:)
                  didFailSelector:@selector(httpFetcher:failedWithError:)];
@/textblock

  Becomes:

@textblock
  GDataHTTPFetcher *fetcher = [GDataHTTPFetcher httpFetcherWithRequest:req];
  HGSInvocationOperation *op = [HGSInvocationOperation
    networkInvocationOperationWithTarget:self
                              forFetcher:fetcher
                       didFinishSelector:@selector(httpFetcher:finishedWithData:)
                         didFailSelector:@selector(httpFetcher:failedWithError:)];
  [[HGSOperationQueue sharedOperationQueue] addOperation:op];
@/textblock
*/
+ (HGSInvocationOperation *)networkInvocationOperationWithTarget:(id)target
                                                      forFetcher:(GDataHTTPFetcher *)fetcher
                                               didFinishSelector:(SEL)didFinishSel
                                                 didFailSelector:(SEL)failedSEL;

/*!
  Creates a NSInvocationOperation that runs at a low priority relative
  to disk and network operations.
*/
+ (HGSInvocationOperation *)memoryInvocationOperationWithTarget:(id)target
                                                       selector:(SEL)sel
                                                         object:(id)arg;

/*!
  Returns a pointer to the currently executing operation, or nil
  if the current thread is not operating within the context of a
  non-concurrent HGSInvocationOperation.
*/
+ (HGSInvocationOperation *)currentOperation;
@end

/*!
  Singleton class that manages the shared NSOperationQueue and implements
  HGSInvocationOperation semantics (e.g., keeping disk operations from
  running simultaneously). Like NSOperationQueue, you may instantiate
  multiple HGSOperationQueues, but each one will maintain its own separate
  set of book keeping. That means if you want to keep all of your disk
  operations sequential, you need to use a single (preferably the singleton)
  HGSOperationQueue.

  This class performs some extra work for HGSInvocationOperations, but
  any NSOperation can be added to it (the NSOperation just won't get any
  special behavior applied to it).
*/
@interface HGSOperationQueue : NSOperationQueue
+ (HGSOperationQueue *)sharedOperationQueue;
@end
