//
//  HGSOperation.m
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

#import "HGSOperation.h"
#import <GTM/GTMDebugSelectorValidation.h>
#import <GTM/GTMObjectSingleton.h>
#import <GData/GDataHTTPFetcher.h>

@interface HGSFetcherOperation ()
- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData;

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error;
@end


@implementation HGSFetcherOperation

- (id)initWithTarget:(id)target
          forFetcher:(GDataHTTPFetcher *)fetcher
   didFinishSelector:(SEL)didFinishSel
     didFailSelector:(SEL)failedSel {
  GTMAssertSelectorNilOrImplementedWithArguments(target,
                                                 didFinishSel,
                                                 @encode(GDataHTTPFetcher *),
                                                 @encode(NSData *),
                                                 @encode(NSOperation *),
                                                 NULL);
  GTMAssertSelectorNilOrImplementedWithArguments(target,
                                                 failedSel,
                                                 @encode(GDataHTTPFetcher *),
                                                 @encode(NSError *),
                                                 @encode(NSOperation *),
                                                 NULL);
  if ((self = [super init])) {
    fetcher_ = [fetcher retain];
    target_ = [target retain];
    didFinishSel_ = didFinishSel;
    didFailSel_ = failedSel;
  }
  return self;
}

- (void)dealloc {
  [fetcher_ release];
  [target_ release];
  [super dealloc];
}

- (GDataHTTPFetcher *)fetcher {
  return [[fetcher_ retain] autorelease];
}

- (void)main {
  didFinish_ = NO;
  [fetcher_ beginFetchWithDelegate:self
                 didFinishSelector:@selector(httpFetcher:finishedWithData:)
                   didFailSelector:@selector(httpFetcher:failedWithError:)];
  CFRunLoopSourceContext context;
  bzero(&context, sizeof(context));
  CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
  CFRunLoopRef runloop = CFRunLoopGetCurrent();
  CFRunLoopAddSource(runloop, source, kCFRunLoopDefaultMode);
  while (!didFinish_) {
    CFRunLoopRun();
  }
  CFRunLoopRemoveSource(runloop, source, kCFRunLoopDefaultMode);
  CFRelease(source);
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  NSMethodSignature *sig = [target_ methodSignatureForSelector:didFinishSel_];
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
  [invocation setTarget:target_];
  [invocation setSelector:didFinishSel_];
  [invocation setArgument:&fetcher_ atIndex:2];
  [invocation setArgument:&retrievedData atIndex:3];
  [invocation setArgument:&self atIndex:4];
  [invocation invoke];
  didFinish_ = YES;
  CFRunLoopRef rl = CFRunLoopGetCurrent();
  CFRunLoopStop(rl);
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  NSMethodSignature *sig = [target_ methodSignatureForSelector:didFailSel_];
  NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:sig];
  [invocation setTarget:target_];
  [invocation setSelector:didFailSel_];
  [invocation setArgument:&fetcher_ atIndex:2];
  [invocation setArgument:&error atIndex:3];
  [invocation setArgument:&self atIndex:4];
  [invocation invoke];
  didFinish_ = YES;
  CFRunLoopRef rl = CFRunLoopGetCurrent();
  CFRunLoopStop(rl);
}

@end

@implementation HGSOperationQueue

GTMOBJECT_SINGLETON_BOILERPLATE(HGSOperationQueue, sharedOperationQueue);

@end
