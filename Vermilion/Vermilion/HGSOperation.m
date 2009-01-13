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
#import "GTMObjectSingleton.h"
#import "GTMDebugSelectorValidation.h"
#import "GDataHTTPFetcher.h"
#import "HGSLog.h"

static const NSOperationQueuePriority kDiskQueuePriority = NSOperationQueuePriorityNormal;
static const NSOperationQueuePriority kNetworkQueuePriority = NSOperationQueuePriorityNormal;
static const NSOperationQueuePriority kNetworkFinishQueuePriority = NSOperationQueuePriorityNormal;
static const NSOperationQueuePriority kMemoryQueuePriority = NSOperationQueuePriorityLow;

static NSString * const kHGSInvocationOperationThreadKey = @"kHGSInvocationOperationThreadKey";
static NSString * const kCallbackTypeKey = @"kCallbackTypeKey";
static NSString * const kCallbackTypeData = @"kCallbackTypeData";
static NSString * const kCallbackTypeError = @"kCallbackTypeError";
static NSString * const kCallbackDataKey = @"kCallbackDataKey";
static NSString * const kCallbackErrorKey = @"kCallbackErrorKey";

static const CFTimeInterval kNetworkOperationTimeout = 60; // seconds


@interface HGSInvocationOperation(PrivateMethods)
- (id)initWithTarget:(id)target selector:(SEL)sel object:(id)arg;
- (id)initWithInvocation:(NSInvocation *)inv;
- (InvocationType)invocationType;
- (void)setInvocationType:(InvocationType)type;
- (id)target;
- (void)setTarget:(id)target;
- (SEL)selector;
- (void)setSelector:(SEL)selector;
@end


@interface HGSNetworkOperation : HGSInvocationOperation {
  NSDictionary      *callbackDict_;           // STRONG
  GDataHTTPFetcher  *fetcher_;                // STRONG
  id                fetcherTarget_;           // STRONG
  BOOL              isReady_;
  SEL               didFinishSel_;
  SEL               didFailSel_;
}
- (id)initWithTarget:(id)target
                 forFetcher:(GDataHTTPFetcher *)fetcher
          didFinishSelector:(SEL)didFinishSel
            didFailSelector:(SEL)didFailWithErrorSel;
- (void)beginFetch;
@end


@interface HGSFetcherThread : NSObject {
 @private
  CFRunLoopSourceRef rlSource_;
  NSMutableArray  *fetches_;   
  NSLock *fetchesLock_;
  CFRunLoopRef runLoop_;
}
+ (HGSFetcherThread *)sharedFetcherThread;
- (void)enqueue:(HGSNetworkOperation *)op;
- (void)beginOps;
@end


// HGSFetcherThread is a long lived thread that on which the NSURLConnections
// for all HGSNetworkOperations run. The order of operation is:
//   Application instantiates an HGSNetworkOperation
//   The HTTP fetch occurs on the HGSFetcherThread
//   The HGSNetworkOperation isReady method returns NO until the fetch completes
//   The fetch completes, isReady returns YES, and the GDataHTTPFetcher
//   callbacks run on the HGSNetworkOperation thread
// All HTTP fetches run on the same HGSFetcherThread, which is instantiated
// when the first HGSNetworkOperations is created.
@implementation HGSFetcherThread

GTMOBJECT_SINGLETON_BOILERPLATE(HGSFetcherThread, sharedFetcherThread);

static void HGSFetcherThreadPerformCallBack(void *info) {
  HGSFetcherThread *thread = (HGSFetcherThread *)info;
  [thread beginOps];
}

- (id)init {
  self = [super init];
  if (self) {
    CFRunLoopSourceContext context;
    bzero(&context, sizeof(context));
    context.info = self;
    context.perform = HGSFetcherThreadPerformCallBack;
    rlSource_ = CFRunLoopSourceCreate(NULL, 0, &context);
    fetchesLock_ = [[NSLock alloc] init];
    fetches_ = [[NSMutableArray alloc] init];
    NSCondition *runLoopCondition = [[NSCondition alloc] init];
    if (!rlSource_ || !fetchesLock_ || !runLoopCondition) {
      [self release];
      return nil;
    }
    [runLoopCondition lock];
    [NSThread detachNewThreadSelector:@selector(main:) 
                             toTarget:self 
                           withObject:runLoopCondition];
    while (!runLoop_) {
      [runLoopCondition wait];
    }
    [runLoopCondition unlock];
    [runLoopCondition release];
  }
  return self;
}

- (void)dealloc {
  [fetches_ release];
  [fetchesLock_ release];
  if (rlSource_) {
    if (runLoop_) {
      CFRunLoopRemoveSource(runLoop_, rlSource_, kCFRunLoopDefaultMode);
    }
    CFRelease(rlSource_);
  }
  [super dealloc];
}

- (void)enqueue:(HGSNetworkOperation *)op {
  [fetchesLock_ lock];
  // Wrap this in a try catch block so we don't unintentionally deadlock.
  // should never happen with a simple add.
  @try {
    [fetches_ addObject:op];
  }
  @catch(NSException *e) {
    HGSLog(@"Unexpected exception in enqueue: %@", e);
  }
  [fetchesLock_ unlock];
  CFRunLoopSourceSignal(rlSource_);
  CFRunLoopWakeUp(runLoop_);
}

- (void)beginOps {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [fetchesLock_ lock];
 
  for (HGSNetworkOperation *op in fetches_) {
    // Wrap this in a try catch block so we don't unintentionally deadlock.
    @try {
      [op beginFetch];
    }
    @catch(NSException *e) {
      HGSLog(@"Unexpected exception in beginOps: %@", e);
    }
  }  
  [fetches_ removeAllObjects];
  [fetchesLock_ unlock];
  [pool release];
}

- (void)main:(NSCondition *)runLoopCondition {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  // init our run loop
  [runLoopCondition lock];
  runLoop_ = CFRunLoopGetCurrent();
  CFRunLoopAddSource(runLoop_, rlSource_, kCFRunLoopDefaultMode);
  [runLoopCondition signal];
  [runLoopCondition unlock];
  
  [pool release];
  CFRunLoopRun();
}

@end


@implementation HGSNetworkOperation

- (id)initWithTarget:(id)target
          forFetcher:(GDataHTTPFetcher *)fetcher
   didFinishSelector:(SEL)didFinishSel
     didFailSelector:(SEL)didFailSel {
  self = [super init];
  if (self) {
    fetcherTarget_ = [target retain];
    fetcher_ = [fetcher retain];
    didFinishSel_ = didFinishSel;
    didFailSel_ = didFailSel;
    [self setInvocationType:NETWORK_INVOCATION];
    [self setQueuePriority:kNetworkQueuePriority];

    GTMAssertSelectorNilOrImplementedWithArguments(target,
                                                   didFinishSel_,
                                                   @encode(GDataHTTPFetcher *),
                                                   @encode(NSData *),
                                                   NULL);
    GTMAssertSelectorNilOrImplementedWithArguments(target,
                                                   didFailSel_,
                                                   @encode(GDataHTTPFetcher *),
                                                   @encode(NSError *),
                                                   NULL);
  }
  return self;
}

- (void)dealloc {
  [callbackDict_ release];
  [fetcher_ release];
  [fetcherTarget_ release];
  [super dealloc];
}

- (void)beginFetch {
  [fetcher_ beginFetchWithDelegate:self
                 didFinishSelector:@selector(httpFetcher:finishedWithData:)
                   didFailSelector:@selector(httpFetcher:failedWithError:)];
}

- (BOOL)isReady {
  if ([super isReady]) {
    return isReady_;
  }
  return NO;
}

- (void)setIsReady:(BOOL)isReady {
  [self willChangeValueForKey:@"isReady"];
  isReady_ = isReady;
  [self didChangeValueForKey:@"isReady"];
}

- (void)main {
  [[[NSThread currentThread] threadDictionary] setObject:self
                                                  forKey:kHGSInvocationOperationThreadKey];
  NSInvocation *invocation = nil;
  NSString *callbackType = [callbackDict_ objectForKey:kCallbackTypeKey];
  if ([callbackType isEqual:kCallbackTypeData]) {
    NSData *data = [callbackDict_ objectForKey:kCallbackDataKey];
    NSMethodSignature *signature = [fetcherTarget_ methodSignatureForSelector:didFinishSel_];
    invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:didFinishSel_];
    [invocation setTarget:fetcherTarget_];
    [invocation setArgument:&fetcher_ atIndex:2];
    [invocation setArgument:&data atIndex:3];
  } else if ([callbackType isEqual:kCallbackTypeError]) {
    NSError *error = [callbackDict_ objectForKey:kCallbackErrorKey];
    NSMethodSignature *signature = [fetcherTarget_ methodSignatureForSelector:didFailSel_];
    invocation = [NSInvocation invocationWithMethodSignature:signature];
    [invocation setSelector:didFailSel_];
    [invocation setTarget:fetcherTarget_];
    [invocation setArgument:&fetcher_ atIndex:2];
    [invocation setArgument:&error atIndex:3];
  }
  [invocation invoke];
  [[[NSThread currentThread] threadDictionary] removeObjectForKey:kHGSInvocationOperationThreadKey];
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  if (callbackDict_) {
    HGSLogDebug(@"httpFetcher:finishedWithData: called after another callback");
  }
  callbackDict_ = [[NSDictionary dictionaryWithObjectsAndKeys:
                   kCallbackTypeData, kCallbackTypeKey,
                   [NSData dataWithData:retrievedData], kCallbackDataKey,
                   nil] retain];
  [self setIsReady:YES];
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  if (callbackDict_) {
    HGSLogDebug(@"httpFetcher:failedWithError: called after another callback");
  }
  callbackDict_ = [[NSDictionary dictionaryWithObjectsAndKeys:
                   kCallbackTypeError, kCallbackTypeKey,
                   [[error copy] autorelease], kCallbackErrorKey,
                   nil] retain];
  [self setIsReady:YES];
}

@end


@implementation HGSInvocationOperation

+ (HGSInvocationOperation *)diskInvocationOperationWithTarget:(id)target
                                                     selector:(SEL)selector
                                                       object:(id)object {
  HGSInvocationOperation *result = [[[HGSInvocationOperation alloc]
                                    initWithTarget:target
                                          selector:selector
                                            object:object] autorelease];
  [result setInvocationType:DISK_INVOCATION];
  [result setQueuePriority:kDiskQueuePriority];
  return result;
}

+ (HGSInvocationOperation *)
   networkInvocationOperationWithTarget:(id)target
                             forFetcher:(GDataHTTPFetcher *)fetcher
                      didFinishSelector:(SEL)didFinishSel
                        didFailSelector:(SEL)didFailSel {
  HGSNetworkOperation *networkOp = [[[HGSNetworkOperation alloc]
                                    initWithTarget:target
                                        forFetcher:fetcher
                                 didFinishSelector:didFinishSel
                                     didFailSelector:didFailSel] autorelease];
  [[HGSFetcherThread sharedFetcherThread] enqueue:networkOp];
  return networkOp;
}

+ (HGSInvocationOperation *)memoryInvocationOperationWithTarget:(id)target
                                                       selector:(SEL)sel
                                                         object:(id)arg {
  HGSInvocationOperation *result = [[[HGSInvocationOperation alloc]
                                    initWithTarget:target
                                          selector:sel
                                            object:arg] autorelease];
  [result setInvocationType:MEMORY_INVOCATION];
  [result setQueuePriority:kMemoryQueuePriority];
  return result;
}

- (id)initWithTarget:(id)target selector:(SEL)sel object:(id)arg {
  self = [super initWithTarget:self
                      selector:@selector(intermediateInvocation:)
                        object:arg];
  if (self) {
    [self setInvocationType:NORMAL_INVOCATION];
    [self setTarget:target];
    [self setSelector:sel];
  }
  return self;
}

- (void)dealloc {
  [target_ release];
  [super dealloc];
}

- (id)initWithInvocation:(NSInvocation *)inv {
  self = [super initWithInvocation:inv];
  if (self) {
    [self setInvocationType:NORMAL_INVOCATION];
  }
  return self;
}

- (InvocationType)invocationType {
  return invocationType_;
}

- (void)setInvocationType:(InvocationType)type {
  invocationType_ = type;
}

- (id)target {
  return target_;
}

- (void)setTarget:(id)target {
  if (target_ != target) {
    [target_ release];
    target_ = [target retain];
  }
}

- (SEL)selector {
  return selector_;
}

- (void)setSelector:(SEL)selector {
  selector_ = selector;
}

- (void)intermediateInvocation:(id)obj {
   if (![self isConcurrent]) {
    [[[NSThread currentThread] threadDictionary] setObject:self
                                                    forKey:kHGSInvocationOperationThreadKey];
  }
  NSMethodSignature *signature = [target_ methodSignatureForSelector:selector_];
  if ([signature numberOfArguments] == 4) {
    [target_ performSelector:selector_ withObject:obj withObject:self];
  } else {
    [target_ performSelector:selector_ withObject:obj];
  }
  [[[NSThread currentThread] threadDictionary] removeObjectForKey:kHGSInvocationOperationThreadKey];
}

+ (HGSInvocationOperation *)currentOperation {
  return [[[NSThread currentThread] threadDictionary] objectForKey:kHGSInvocationOperationThreadKey];
}

@end


@implementation NSOperation(HGSInvocationOperation)

- (BOOL)isDiskOperation {
 return ([self isKindOfClass:[HGSInvocationOperation class]] &&
         [(HGSInvocationOperation *)self invocationType] == DISK_INVOCATION);
}

@end

@implementation HGSOperationQueue

GTMOBJECT_SINGLETON_BOILERPLATE(HGSOperationQueue, sharedOperationQueue);

- (void)addOperation:(NSOperation *)operation {
  @synchronized(self) {
    // Make disk operations sequential by making the added disk
    // operation a dependency of the last disk operation in the current
    // queue
    if ([operation isDiskOperation]) {
      NSArray *operations = [self operations];
      NSEnumerator *enumerator = [operations reverseObjectEnumerator];
      id op;
      while ((op = [enumerator nextObject])) {
        if ([op isDiskOperation]) {
          [operation addDependency:op];
          break;
        }
      }
    }
    
    [super addOperation:operation];
  }
}

@end
