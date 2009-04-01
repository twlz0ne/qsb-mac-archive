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
#import "HGSResult.h"
#import "HGSSearchSource.h"
#import "HGSOperation.h"
#import "GTMObjectSingleton.h"
#import "GTMGeometryUtils.h"
#import "GTMNSImage+Scaling.h"
#import "GTMNSBezierPath+CGPath.h"
#import <GData/GDataHTTPFetcher.h>
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
static NSString *const kHGSIconProviderAttrKey = @"HGSIconProviderAttrKey";
static NSString *const kHGSIconProviderURIKey = @"HGSIconProviderURIKey";
static NSString *const kHGSIconProviderThumbnailURLFormat = @"HGSIconProviderThumbnailURLFormat";

static NSURL* IconURLForResult(HGSResult *result) {
  NSURL *url = [result valueForKey:kHGSObjectAttributeIconPreviewFileKey];
  if (!url) {
    url = [result url];
    
    // For urls, we can specify a thumbnail provider for web sites.
    // HTTPS sites are usually locked down, so ignore it for those
    if ([[url scheme] isEqualToString:@"http"]) {
      NSString *thumbnailURL = [[NSUserDefaults standardUserDefaults]
                               stringForKey:kHGSIconProviderThumbnailURLFormat]; 
      if (thumbnailURL) {
        thumbnailURL
          = [NSString stringWithFormat:thumbnailURL,[url absoluteString]];
        url = [NSURL URLWithString:thumbnailURL];
      }
    }
  }
  return url;
}

@class HGSIconOperation;

@interface HGSIconProvider()
- (void)beginLazyLoadForResult:(HGSResult*)result;

// Remove an operation from our list of pending icon fetch operations.
- (void)removeOperation:(HGSIconOperation *)operation;
- (void)setValueOnMainThread:(NSDictionary *)args;

@end


@interface HGSIconOperation : NSObject {
 @protected
  HGSInvocationOperation *operation_; // STRONG
  GDataHTTPFetcher *fetcher_;   // STRONG
  HGSResult *result_;    // WEAK
}
+ (HGSIconOperation *)iconOperationForResult:(HGSResult*)result;
- (id)initWithResult:(HGSResult*)result;
- (void)beginLoading;
- (void)cancel;
@end


@implementation HGSIconOperation

+ (HGSIconOperation *)iconOperationForResult:(HGSResult*)result {
  return [[[HGSIconOperation alloc] initWithResult:result] autorelease];
}

- (id)initWithResult:(HGSResult*)result {
  self = [super init];
  if (self) {
    result_ = result;
  }
  return self;
}

- (void)dealloc {
  [fetcher_ release];
  [operation_ release];
  [super dealloc];
}

- (NSUInteger)hash {
  NSUInteger hash = [result_ hash];
  return hash;
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
    HGSResult *otherResult = ((HGSIconOperation*)otherObj)->result_;
    isEqual = (result_ == otherResult) ? YES : NO;
  }
  return isEqual;
}

- (void)beginLoading {
  if (!operation_) {
    NSURL *url = IconURLForResult(result_);
    if ([url isFileURL]) {
      operation_ = [[HGSInvocationOperation
                     diskInvocationOperationWithTarget:self
                                              selector:@selector(performDiskLoad:)
                                                object:result_] retain];
    } else {
      NSString *scheme = [url scheme];
      if ([scheme hasPrefix:@"http"]) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        fetcher_ = [GDataHTTPFetcher httpFetcherWithRequest:request];
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

- (NSImage *)performDiskLoad:(HGSResult *)result {
  NSURL *url = nil;
  @synchronized(self) {
    if (![operation_ isCancelled]) {
      url = IconURLForResult(result);
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
  
  HGSIconProvider *sharedIconProvider = [HGSIconProvider sharedIconProvider];

  if (icon && ![operation_ isCancelled]) {
    [sharedIconProvider setIcon:icon 
                      forResult:result 
                        withURI:[url absoluteString]];
  }
  [sharedIconProvider removeOperation:self];
  return icon;
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  BOOL cancelled = NO;
  @synchronized(self) {
    cancelled = ([operation_ isCancelled]);
  }
  HGSIconProvider *sharedIconProvider = [HGSIconProvider sharedIconProvider];
  if (!cancelled) {
    NSImage *icon = [[[NSImage alloc] initWithData:retrievedData] autorelease];
    icon = [sharedIconProvider imageWithRoundRectAndDropShadow:icon];
    if (icon && ![operation_ isCancelled]) {
      NSString *uri = [[[fetcher request] URL] absoluteString];
      [sharedIconProvider setIcon:icon forResult:result_ withURI:uri];
    }
  }
  [sharedIconProvider removeOperation:self];
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  HGSLogDebug(@"http icon fetch failed for %@ with error %@",
              [[[fetcher request] URL] absoluteString], error);
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@:%p> result: %@>", 
          [self class], self, result_];
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
    compoundPlaceHolderIcon_ 
      = [[NSImage imageNamed:NSImageNameMultipleDocuments] retain];
  }
  return self;
}

// COV_NF_START
// Singleton, so this is never called.
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
// COV_NF_END

- (NSImage *)placeHolderIcon {
  return placeHolderIcon_;
}

- (NSImage *)compoundPlaceHolderIcon {
  return compoundPlaceHolderIcon_;
}

- (NSImage *)provideIconForResult:(HGSResult*)result
                       loadLazily:(BOOL)loadLazily {
  NSImage *icon = nil;
  
  NSURL *url = IconURLForResult(result);
  if (url) {
    icon = [self cachedIconForKey:[url absoluteString]];
    if (!icon) {
      if (loadLazily) {
        [self beginLazyLoadForResult:result];
        icon = [[result source] provideValueForKey:kHGSObjectAttributeIconKey
                                            result:result];
        if (!icon) {
          icon = [self placeHolderIcon];
        }
      } else {
        HGSSearchSource *source = [result source];
        icon = [source provideValueForKey:kHGSObjectAttributeImmediateIconKey 
                                   result:result];
        if (icon) {
          [self cacheIcon:icon forKey:[url absoluteString]];
        } else {
          if ([url isFileURL]) {
            HGSIconOperation *op 
              = [HGSIconOperation iconOperationForResult:result];
            icon = [op performDiskLoad:result];
          } else {
            NSString *scheme = [url scheme];
            typedef struct {
              NSString *scheme;
              OSType icon;
            } SchemeMap;
            SchemeMap map[] = {
              { @"http", 'tSts' },
              { @"https", 'tSts' },
              { @"ftp", kInternetLocationFTPIcon },
              { @"afp", kInternetLocationAppleShareIcon },
              { @"mailto", kInternetLocationMailIcon },
              { @"news", kInternetLocationNewsIcon }
            };
            OSType iconType = kInternetLocationGenericIcon;
            for (size_t i = 0; i < sizeof(map) / sizeof(SchemeMap); ++i) {
              if ([scheme caseInsensitiveCompare:map[i].scheme] == NSOrderedSame) {
                iconType = map[i].icon;
                break;
              }
            }
            NSWorkspace *ws = [NSWorkspace sharedWorkspace];
            icon = [ws iconForFileType:NSFileTypeForHFSTypeCode(iconType)];
            [self beginLazyLoadForResult:result];
          }
        }
      }
    }
  }
  return icon;
}

- (void)cancelOperationsForResult:(HGSResult*)result {
  HGSIconOperation *operation
    = [HGSIconOperation iconOperationForResult:result];
  @synchronized(self) {
    HGSIconOperation *original = [iconOperations_ member:operation];
    if (original) {
      [original cancel];
      [iconOperations_ removeObject:original];
    } 
  }
}

- (void)removeOperation:(HGSIconOperation *)operation {
  @synchronized(self) {
    [iconOperations_ removeObject:operation];
  }
}

- (void)beginLazyLoadForResult:(HGSResult*)result {
  HGSIconOperation *operation
    = [HGSIconOperation iconOperationForResult:result];
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
  @synchronized(cache_) {
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
    @synchronized(cache_) {
      [cache_ setValue:icon forKey:key size:size];
    }
  }
}

// Return an image that has a round rectangle frame and a drop shadow
- (NSImage *)imageWithRoundRectAndDropShadow:(NSImage *)image {
  if (!image) return nil;
  NSImage *formattedImage = [[[NSImage alloc] init] autorelease];
  
  NSSize preferredSize = [self preferredIconSize];
  
  NSRect borderRect = GTMNSRectOfSize(preferredSize);
  borderRect = NSInsetRect(borderRect, 8.0, 8.0);
  
  NSImageRep *bestRep = [image gtm_bestRepresentationForSize:borderRect.size];  
  NSRect drawRect = GTMNSScaleRectToRect(GTMNSRectOfSize([bestRep size]), 
                                         borderRect,
                                         GTMScaleProportionally,
                                         GTMRectAlignCenter);
  drawRect = NSIntegralRect(drawRect);
  
  CGColorSpaceRef cspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);   
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
                                     yRadius:2.0] gtm_CGPath];
    CGContextBeginTransparencyLayer(largeContext, NULL);
    if (path) {
      CGContextAddPath(largeContext, path);
    }
    CGContextSaveGState(largeContext);
    CGContextClip(largeContext);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context 
      = [NSGraphicsContext graphicsContextWithGraphicsPort:largeContext 
                                                   flipped:YES];
    [NSGraphicsContext setCurrentContext:context];
    [bestRep drawInRect:drawRect];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(largeContext);
    CGContextSetLineWidth(largeContext, 1.0);
    if (path) {
      CGContextAddPath(largeContext, path);  
    }
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
                                         yRadius:2.0] gtm_CGPath];
    CGContextBeginTransparencyLayer(smallContext, NULL);
    if (path) {
      CGContextAddPath(smallContext, path);
    }
    CGContextSaveGState(smallContext);
    CGContextClip(smallContext);
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *context 
      = [NSGraphicsContext graphicsContextWithGraphicsPort:smallContext 
                                                   flipped:YES];
    [NSGraphicsContext setCurrentContext:context];
    [bestRep drawInRect:drawRect];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRestoreGState(smallContext);
    
    CGContextSetLineWidth(smallContext, 1.0);
    NSRect insetRect =  NSInsetRect(smallDrawRect, 0.5, 0.5);
    path = [[NSBezierPath bezierPathWithRoundedRect:insetRect
                                            xRadius:2.0
                                            yRadius:2.0] gtm_CGPath];
    if (path) {
      CGContextAddPath(smallContext, path);
    }
    CGContextSetRGBStrokeColor(smallContext, 0.0, 0.0, 0.0, 0.10);
    CGContextStrokePath(smallContext);
    CGContextEndTransparencyLayer(smallContext);
    
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


- (NSSize)preferredIconSize {
  return NSMakeSize(96.0, 96.0);
}

- (void)setValueOnMainThread:(NSDictionary *)args {
  GTMAssertRunningOnMainThread();
  HGSResult *result = [args objectForKey:kHGSIconProviderResultKey];
  NSString *key = [args objectForKey:kHGSIconProviderAttrKey];
  NSImage *icon = [args objectForKey:kHGSIconProviderValueKey];
  NSString *uri = [args objectForKey:kHGSIconProviderURIKey];
  HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
  [result willChangeValueForKey:key];
  [provider cacheIcon:icon forKey:uri];
  [result didChangeValueForKey:key];
}

- (void)setIcon:(NSImage *)icon 
      forResult:(HGSResult *)result 
        withURI:(NSString *)uri {
  NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                        result, kHGSIconProviderResultKey,
                        icon, kHGSIconProviderValueKey,
                        kHGSObjectAttributeIconKey, kHGSIconProviderAttrKey,
                        uri, kHGSIconProviderURIKey,
                        nil];
  [self performSelectorOnMainThread:@selector(setValueOnMainThread:)
                         withObject:args
                      waitUntilDone:NO];
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
