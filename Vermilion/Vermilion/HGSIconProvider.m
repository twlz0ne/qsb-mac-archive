//
//  HGSIconProvider.m
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

#import <QuickLook/QuickLook.h> 
#import "HGSIconProvider.h"
#import "HGSLRUCache.h"
#import "HGSObject.h"
#import "HGSSearchSource.h"
#import "HGSOperation.h"
#import "GTMObjectSingleton.h"
#import "GTMGeometryUtils.h"
#import "GTMNSImage+Scaling.h"
#import "GTMNSBezierPath+CGPath.h"
#import "GTMHTTPFetcher.h"
#import "HGSLog.h"
#import "GTMDebugThreadValidation.h"

static const void *LRURetain(CFAllocatorRef allocator, const void *value);
static void LRURelease(CFAllocatorRef allocator, const void *value);
static Boolean LRUEqual(const void *value1, const void *value2);
static CFHashCode LRUHash(const void *value);

const size_t kIconCacheSize = 5 * 1024 * 1024; // bytes
static HGSLRUCacheCallBacks kLRUCacheCallbacks = {
  0,           // version
  LRURetain,   // keyRetain
  LRURelease,  // keyRelease
  LRUEqual,    // keyEqual
  LRUHash,     // keyHash
  LRURetain,   // valueRetain
  LRURelease,  // valueRelease
  nil          // evict
};

static NSString *const kHGSIconProviderResultKey = @"HGSIconProviderResultKey";
static NSString *const kHGSIconProviderValueKey = @"HGSIconProviderValueKey";
static NSString *const kHGSIconProviderAttrKey = @"kHGSIconProviderAttrKey";

@interface HGSIconProvider()
- (void)beginLazyLoadForResult:(HGSObject*)result useCache:(BOOL)useCache;
@end


@interface HGSIconOperation : NSObject {
 @protected
  HGSInvocationOperation *operation_; // STRONG
  GTMHTTPFetcher *fetcher_;   // STRONG
  HGSObject *result_;    // WEAK
  BOOL useCache_;
}
+ (HGSIconOperation *)iconOperationForResult:(HGSObject*)result
                                    useCache:(BOOL)useCache;
- (id)initWithResult:(HGSObject*)result useCache:(BOOL)useCache;
- (void)beginLoading;
- (void)cancel;
- (void)setValueOnMainThread:(NSDictionary *)args;
@end


@implementation HGSIconOperation

+ (HGSIconOperation *)iconOperationForResult:(HGSObject*)result
                                    useCache:(BOOL)useCache {
  return [[[HGSIconOperation alloc] initWithResult:result
                                          useCache:useCache] autorelease];
}

- (id)initWithResult:(HGSObject*)result useCache:(BOOL)useCache {
  self = [super init];
  if (self) {
    result_ = result;
    useCache_ = useCache;
  }
  return self;
}

- (void)dealloc {
  [fetcher_ release];
  [operation_ release];
  [super dealloc];
}

- (BOOL)isEqual:(id)otherObj {
  BOOL isEqual = NO;
  // We call them equal if they reference the same two HGSObjects
  if ([otherObj isMemberOfClass:[self class]]) {
    // NOTE: ideally we'd like to @sync to both objects here, but then we could
    // hit deadlock if two threads happen to compare both in reverse order.  If
    // we add an accessor for the result from the other object, then we would
    // have to push it to the callers auto release pool, which could be bad
    // since we could end up here as a result of the result being dealloced.
    isEqual = (result_ == ((HGSIconOperation*)otherObj)->result_) ? YES : NO;
  }
  return isEqual;
}

- (void)beginLoading {
  if (!operation_) {
    NSURL *url = [result_ valueForKey:kHGSObjectAttributeIconPreviewFileKey];
    if (!url) {
      url = [result_ valueForKey:kHGSObjectAttributeURIKey];
    }
    if ([url isFileURL]) {
      operation_ = [[HGSInvocationOperation
                     diskInvocationOperationWithTarget:self
                                              selector:@selector(performDiskLoad:)
                                                object:result_] retain];
    } else {
      NSString *scheme = [url scheme];
      if ([scheme hasPrefix:@"http"]) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        fetcher_ = [GTMHTTPFetcher httpFetcherWithRequest:request];
        operation_ = [[HGSInvocationOperation
                       networkInvocationOperationWithTarget:self
                                                 forFetcher:fetcher_
                                          didFinishSelector:@selector(httpFetcher:finishedWithData:)
                                            didFailSelector:@selector(httpFetcher:failedWithError:)]
                      retain];
      }
    }
    if (operation_) {
      [[HGSOperationQueue sharedOperationQueue] addOperation:operation_];
    }
  }
}

- (void)cancel {
  @synchronized(self) {
    [operation_ cancel];
  }
}

- (void)performDiskLoad:(id)obj {
  NSURL *url = nil;
  @synchronized(self) {
    if (![operation_ isCancelled]) {
      url = [result_ valueForKey:kHGSObjectAttributeIconPreviewFileKey];
      if (!url) {
        url = [result_ valueForKey:kHGSObjectAttributeURIKey];
      }
    }
  }
  
  NSImage *icon = nil;
  if (url) {
    NSSize size = NSMakeSize(128.0, 128.0);
    BOOL ignoreQuickLook = 
      [[[url path] pathExtension] caseInsensitiveCompare:@"prefpane"]
        == NSOrderedSame;
    
    
    if (!ignoreQuickLook) {
      NSDictionary *dict = [NSDictionary
                            dictionaryWithObject:[NSNumber numberWithBool:YES] 
                                          forKey:(NSString *)kQLThumbnailOptionIconModeKey];
      
      CGImageRef ref = QLThumbnailImageCreate(kCFAllocatorDefault, 
                                              (CFURLRef)url, 
                                              CGSizeMake(size.width, size.height),
                                              (CFDictionaryRef)dict);
      
      if (ref) {
        NSBitmapImageRep *bitmapImageRep = [[NSBitmapImageRep alloc] initWithCGImage:ref];
        if (bitmapImageRep) {
          icon = [[[NSImage alloc] initWithSize:[bitmapImageRep size]] autorelease];
          [icon addRepresentation:bitmapImageRep];
          [bitmapImageRep release];
        }
        CFRelease(ref);
      }
    }
    if (!icon) {
      icon = [[NSWorkspace sharedWorkspace] iconForFile:[url path]];
      [icon setSize:size];
    }
  }
  
  if (icon && useCache_) {
    [[HGSIconProvider sharedIconProvider] cacheIcon:icon
                                             forKey:[url absoluteString]];
  }
  
  @synchronized(self) {
    if (icon && ![operation_ isCancelled]) {
      NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                            result_, kHGSIconProviderResultKey,
                            icon, kHGSIconProviderValueKey,
                            kHGSObjectAttributeIconKey, kHGSIconProviderAttrKey,
                            nil];
      [self performSelectorOnMainThread:@selector(setValueOnMainThread:)
                             withObject:args
                          waitUntilDone:NO];
    }
  }
}

- (void)setValueOnMainThread:(NSDictionary *)args {
  GTMAssertRunningOnMainThread();
  HGSObject *result = [args objectForKey:kHGSIconProviderResultKey];
  id value = [args objectForKey:kHGSIconProviderValueKey];
  NSString *key = [args objectForKey:kHGSIconProviderAttrKey];
  [result setValue:value forKey:key];
}

- (void)httpFetcher:(GTMHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  @synchronized(self) {
    if ([operation_ isCancelled]) {
      return;
    }
  }
  
  NSImage *icon = [[[NSImage alloc] initWithData:retrievedData] autorelease];
  
  if (icon && useCache_) {
    [[HGSIconProvider sharedIconProvider] cacheIcon:icon
                               forKey:[[[fetcher request] URL] absoluteString]];
  }
  
  @synchronized(self) {
    if (icon && ![operation_ isCancelled]) {
      NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                            result_, kHGSIconProviderResultKey,
                            icon, kHGSIconProviderValueKey,
                            kHGSObjectAttributeIconKey, kHGSIconProviderAttrKey,
                            nil];
      [self performSelectorOnMainThread:@selector(setValueOnMainThread:)
                             withObject:args
                          waitUntilDone:NO];
    }
  }
}

- (void)httpFetcher:(GTMHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  HGSLogDebug(@"http icon fetch failed for %@ with error %@",
              [[[fetcher request] URL] absoluteString], error);
}
@end


@implementation HGSIconProvider

GTMOBJECT_SINGLETON_BOILERPLATE(HGSIconProvider, sharedIconProvider);

- (id)init {
  self = [super init];
  if (self) {
    iconOperations_ = [[NSMutableSet alloc] init];
    cache_ = [[HGSLRUCache alloc] initWithCacheSize:kIconCacheSize
                                          callBacks:&kLRUCacheCallbacks
                                       evictContext:self];
    placeHolderIcon_ = [[NSImage imageNamed:@"blue-placeholder"] retain];
  }
  return self;
}

- (void)dealloc {
  @synchronized(self) {
    for (NSOperation *op in iconOperations_) {
      [op cancel];
    }
  }
  [iconOperations_ release];
  [placeHolderIcon_ release];
  [super dealloc];
}

- (NSImage *)placeHolderIcon {
  return placeHolderIcon_;
}

- (NSImage *)provideIconForResult:(HGSObject*)result
                       loadLazily:(BOOL)loadLazily
                         useCache:(BOOL)useCache {
  NSImage *icon = nil;
  
  NSURL *url = [result valueForKey:kHGSObjectAttributeIconPreviewFileKey];
  if (!url) {
    url = [result valueForKey:kHGSObjectAttributeURIKey];
  }
  if (url) {
    if (useCache) {
      icon = [self cachedIconForKey:[url absoluteString]];
    }
    if (!icon) {
      if (loadLazily) {
        [self beginLazyLoadForResult:result useCache:useCache];
        icon = [[result source] defaultIconForObject:result];
        if (!icon) {
          icon = [self placeHolderIcon];
        }
      } else {
        if ([url isFileURL]) {
          HGSIconOperation *op 
            = [HGSIconOperation iconOperationForResult:result
                                              useCache:useCache];
          [op performDiskLoad:nil];
        }
      }
    }
  }
  return icon;
}

- (void)cancelOperationsForResult:(HGSObject*)result {
  HGSIconOperation *operation = 
    [HGSIconOperation iconOperationForResult:result
                                    useCache:NO];
  @synchronized(self) {
    HGSIconOperation *original = [iconOperations_ member:operation];
    if (original) {
      [original cancel];
      [iconOperations_ removeObject:original];
    }
  }
}

- (void)beginLazyLoadForResult:(HGSObject*)result useCache:(BOOL)useCache {
  HGSIconOperation *operation = 
    [HGSIconOperation iconOperationForResult:result
                                    useCache:useCache];
  @synchronized(self) {
    // Don't add if we're already doing a load for this object
    if (![iconOperations_ member:operation]) {
      [iconOperations_ addObject:operation];
      [operation beginLoading];
    }
  }
}

- (NSImage *)cachedIconForKey:(NSString *)key {
  NSImage *icon = nil;
  @synchronized(self) {
    icon = (NSImage *)[cache_ valueForKey:key];
  }
  return [[icon retain] autorelease];
}

- (void)cacheIcon:(NSImage *)icon forKey:(NSString *)key {
  if (icon) {
    // Figure out rough size of image
    size_t size = 0;
    for (NSBitmapImageRep *rep in [icon representations]) {
      size_t repSize = ([rep pixelsHigh] 
                        * [rep pixelsWide] 
                        * [rep bitsPerPixel] / 8);
      size += repSize;
    }
    [cache_ setValue:icon forKey:key size:size];
  }
}

// Return an image that has a round rectangle frame and a drop shadow
+ (NSImage *)imageWithRoundRectAndDropShadow:(NSImage *)image {
  NSImage *formattedImage = [[[NSImage alloc] init] autorelease];
  
  NSSize preferredSize = [self preferredIconSize];
  
  NSRect borderRect = GTMNSRectOfSize(preferredSize);
  borderRect = NSInsetRect(borderRect, 8.0, 8.0);
  
  NSBitmapImageRep *bestRep
    = (NSBitmapImageRep *)[image gtm_bestRepresentationForSize:borderRect.size];  
  NSRect drawRect = GTMNSScaleRectToRect(GTMNSRectOfSize([bestRep size]), 
                                         borderRect,
                                         GTMScaleProportionally,
                                         GTMRectAlignCenter);
  drawRect = NSIntegralRect(drawRect);

  CGImageRef imageRef = [bestRep CGImage]; // this is autoreleased
  
  CGColorSpaceRef cspace = CGColorSpaceCreateDeviceRGB();   
  if (!cspace) return image;
  
  CGSize largeSize = NSSizeToCGSize(preferredSize);
  CGContextRef largeContext
    =  CGBitmapContextCreate(NULL,
                             largeSize.width,
                             largeSize.height,
                             8,            // bits per component
                             largeSize.width * 4, // bytes per pixel
                             cspace,
                             kCGBitmapByteOrder32Host
                             | kCGImageAlphaPremultipliedLast);
  
  if (largeContext) {
    // Draw large icon
    CGContextSetShadow(largeContext, CGSizeMake(0.0, -1.0), 2.0);
    CGContextSetInterpolationQuality(largeContext, kCGInterpolationHigh);
    CGPathRef path
      = [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(drawRect, 0.5, 0.5)
                                     xRadius:2.0
                                     yRadius:2.0] gtm_createCGPath];
    CGContextBeginTransparencyLayer(largeContext, NULL);
    CGContextAddPath(largeContext, path);
    CGContextSaveGState(largeContext);
    CGContextClip(largeContext);
    CGContextDrawImage(largeContext, GTMNSRectToCGRect(drawRect), imageRef);
    CGContextRestoreGState(largeContext);
    CGContextSetLineWidth(largeContext, 1.0);
    CGContextAddPath(largeContext, path);  
    CGContextSetRGBStrokeColor(largeContext, 0.0, 0.0, 0.0, 0.25);
    CGContextStrokePath(largeContext);
    CGContextEndTransparencyLayer(largeContext);
    
    CGImageRef largeImage = CGBitmapContextCreateImage(largeContext);
    if (largeImage) {
      NSBitmapImageRep *cgRep
      = [[[NSBitmapImageRep alloc] initWithCGImage:largeImage] autorelease];
      [formattedImage addRepresentation:cgRep];   
      [formattedImage setSize:[cgRep size]];
      CGImageRelease(largeImage);
    }
  
    CGContextRelease(largeContext);
  }
  
  // Draw small icon
  NSSize smallSize = NSMakeSize(32, 32);
  NSRect smallDrawRect = GTMNSScaleRectToRect(GTMNSRectOfSize([bestRep size]), 
                                              GTMNSRectOfSize(smallSize),
                                              GTMScaleProportionally,
                                              GTMRectAlignCenter);
  smallDrawRect = NSIntegralRect(smallDrawRect);
  CGContextRef smallContext
    = CGBitmapContextCreate(NULL,
                            smallSize.width,
                            smallSize.height,
                            8,            // bits per component
                            smallSize.width * 4, // bytes per pixel
                            cspace,
                            kCGBitmapByteOrder32Host
                            | kCGImageAlphaPremultipliedLast);
  CFRelease(cspace);
  
  if (smallContext) {
    CGContextSetInterpolationQuality(smallContext, kCGInterpolationHigh);
    CGPathRef path
      = [[NSBezierPath bezierPathWithRoundedRect:smallDrawRect
                                         xRadius:2.0
                                         yRadius:2.0] gtm_createCGPath];
    CGContextBeginTransparencyLayer(smallContext, NULL);
    if (path) CGContextAddPath(smallContext, path);
    CGContextSaveGState(smallContext);
    CGContextClip(smallContext);
    CGContextDrawImage(smallContext, GTMNSRectToCGRect(smallDrawRect), imageRef);
    CGContextRestoreGState(smallContext);
    CFRelease(path);
    
    CGContextSetLineWidth(smallContext, 1.0);
    NSRect insetRect =  NSInsetRect(smallDrawRect, 0.5, 0.5);
    path = [[NSBezierPath bezierPathWithRoundedRect:insetRect
                                            xRadius:2.0
                                            yRadius:2.0] gtm_createCGPath];
    if (path) CGContextAddPath(smallContext, path);  
    CGContextSetRGBStrokeColor(smallContext, 0.0, 0.0, 0.0, 0.10);
    CGContextStrokePath(smallContext);
    CGContextEndTransparencyLayer(smallContext);
    CFRelease(path);
    
    CGImageRef smallImage = CGBitmapContextCreateImage(smallContext);
    
    if (smallImage) {
      NSBitmapImageRep *cgRep 
        = [[[NSBitmapImageRep alloc] initWithCGImage:smallImage] autorelease];
      [formattedImage addRepresentation:cgRep];   
      CGImageRelease(smallImage);
    } 
    CGContextRelease(smallContext);
  }
  
  return formattedImage;
}


+ (NSSize)preferredIconSize {
  return NSMakeSize(96.0, 96.0);
}
@end

static const void *LRURetain(CFAllocatorRef allocator, const void *value) {
  return [(id)value retain];
}

static void LRURelease(CFAllocatorRef allocator, const void *value) {
  [(id)value release];
}

static Boolean LRUEqual(const void *value1, const void *value2) {
  return [(id)value1 isEqual:(id)value2];
}

static CFHashCode LRUHash(const void *value) {
  return [(id)value hash];
}
