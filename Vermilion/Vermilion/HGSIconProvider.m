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
      NSURL *newURL = nil;
      if (thumbnailURL) {
        thumbnailURL
          = [NSString stringWithFormat:thumbnailURL,[url absoluteString]];
        newURL = [NSURL URLWithString:thumbnailURL];
      } else {
        newURL = [NSURL URLWithString:@"/favicon.ico" relativeToURL:url];
      }
      if (newURL) {
        url = newURL;
      }
    }
  }
  return url;
}

static NSImage *FileSystemImageForURL(NSURL *url) {
  NSImage *icon;
  NSString *scheme = [url scheme];
  typedef struct {
    NSString *scheme;
    OSType icon;
  } SchemeMap;
  SchemeMap map[] = {
    { @"http", 'tSts' },
    { @"https", 'tSts' },
    { @"ftp", kInternetLocationFTPIcon },
    { @"sftp", kInternetLocationFTPIcon },
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
  return icon;
}

@class HGSIconOperation;

@interface HGSIconProvider()
// Remove an operation from our list of pending icon fetch operations.
- (void)removeOperation:(HGSIconOperation *)operation;
- (void)setValueOnMainThread:(NSDictionary *)args;

@end


@interface HGSIconOperation : NSObject {
 @protected
  HGSInvocationOperation *basicOperation_; // WEAK
  HGSInvocationOperation *advancedOperation_; // WEAK
  HGSResult *result_;    // WEAK
  BOOL skipBasic_;
}
+ (HGSIconOperation *)iconOperationForResult:(HGSResult*)result;
- (id)initWithResult:(HGSResult*)result;
- (void)beginLoading;
- (void)cancel;
- (NSImage *)basicDiskLoad:(HGSResult *)result;
- (NSImage *)advancedDiskLoad:(HGSResult *)result;
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

- (NSUInteger)hash {
  NSUInteger hash = [result_ hash];
  return hash;
}

- (BOOL)isEqual:(id)otherObj {
  BOOL isEqual = NO;
  // We call them equal if they reference the same two HGSObjects
  if ([otherObj isKindOfClass:[self class]]) {
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
  if (!advancedOperation_) {
    NSURL *url = IconURLForResult(result_);
    if ([url isFileURL]) {
      if (!skipBasic_) {
        basicOperation_ 
          = [HGSInvocationOperation diskInvocationOperationWithTarget:self
                                                             selector:@selector(basicDiskLoad:)
                                                               object:result_];
      }
      advancedOperation_
        = [HGSInvocationOperation diskInvocationOperationWithTarget:self
                                                           selector:@selector(advancedDiskLoad:)
                                                             object:result_];
    } else {
      if (!skipBasic_) {
        basicOperation_ 
        = [HGSInvocationOperation diskInvocationOperationWithTarget:self
                                                           selector:@selector(basicDiskLoad:)
                                                             object:result_];
        [basicOperation_ setQueuePriority:NSOperationQueuePriorityHigh];
      }
      NSString *scheme = [url scheme];
      if ([scheme hasPrefix:@"http"]) {
        NSURLRequest *request = [NSURLRequest requestWithURL:url];
        GDataHTTPFetcher *fetcher = [GDataHTTPFetcher httpFetcherWithRequest:request];
        advancedOperation_ 
          = [HGSInvocationOperation networkInvocationOperationWithTarget:self
                                                              forFetcher:fetcher
                                                       didFinishSelector:@selector(httpFetcher:finishedWithData:)
                                                         didFailSelector:@selector(httpFetcher:failedWithError:)];
        [advancedOperation_ setQueuePriority:NSOperationQueuePriorityLow];
      }
    }
    if (basicOperation_ && advancedOperation_) {
      [advancedOperation_ addDependency:basicOperation_];
    }
    HGSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
    if (basicOperation_) {
      [queue addOperation:basicOperation_];
    }
    if (advancedOperation_) {
      [queue addOperation:advancedOperation_];
    }
  }
}

- (void)cancel {
  @synchronized(self) {
    [basicOperation_ cancel];
    basicOperation_ = nil;
    [advancedOperation_ cancel];
    advancedOperation_ = nil;
  }
}

- (NSImage *)basicDiskLoad:(HGSResult *)result {
  @synchronized(self) {
    basicOperation_ = nil;
  }
  skipBasic_ = YES;
  NSURL *url = IconURLForResult(result);
  if (!url) return nil;
  NSImage *icon = nil;
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  if ([url isFileURL]) {
    icon = [ws iconForFile:[url path]];
  } else {
    icon = FileSystemImageForURL(url);
  }
  if (icon) {
    HGSIconProvider *sharedIconProvider = [HGSIconProvider sharedIconProvider];
    [sharedIconProvider setIcon:icon 
                      forResult:result];
  }
  return icon;
}

- (NSImage *)advancedDiskLoad:(HGSResult *)result {
  @synchronized(self) {
    advancedOperation_ = nil;
  }
  HGSIconProvider *sharedIconProvider = [HGSIconProvider sharedIconProvider];
  NSURL *url = IconURLForResult(result);
  NSImage *icon = nil;
  if (url) {
    NSString *extension = [[[url path] pathExtension] lowercaseString];
    NSArray *ignoreArray 
      = [NSArray arrayWithObjects:@"prefpane", @"app", @"framework", nil];
    BOOL ignoreQuickLook = [ignoreArray containsObject:extension];
    
    if (!ignoreQuickLook) {
      NSDictionary *dict 
        = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] 
                                      forKey:(NSString *)kQLThumbnailOptionIconModeKey];
      CGImageRef ref = QLThumbnailImageCreate(kCFAllocatorDefault, 
                                              (CFURLRef)url, 
                                              CGSizeMake(96, 96),
                                              (CFDictionaryRef)dict);
      if (ref) {
        NSBitmapImageRep *bitmapImageRep 
          = [[NSBitmapImageRep alloc] initWithCGImage:ref];
        if (bitmapImageRep) {
          NSSize bitmapSize = [bitmapImageRep size];
          icon = [[[NSImage alloc] initWithSize:bitmapSize] autorelease];
          [icon addRepresentation:bitmapImageRep];
          [bitmapImageRep release];
        }
        CFRelease(ref);
      }
    }
    if (icon) {
      [sharedIconProvider setIcon:icon 
                        forResult:result];
    }
  }
  [sharedIconProvider removeOperation:self];
  return icon;
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  @synchronized(self) {
    advancedOperation_ = nil;
  }  
  HGSIconProvider *sharedIconProvider = [HGSIconProvider sharedIconProvider];
  NSImage *favicon = [[[NSImage alloc] initWithData:retrievedData] autorelease];
  NSURL *url = [[fetcher request] URL];
  NSImage *baseImage = FileSystemImageForURL(url);
  NSSize iconSize = [sharedIconProvider preferredIconSize];
  NSSize baseImageSize = NSMakeSize(32, 32);
  NSSize faviconSize = NSMakeSize(16, 16);
  [baseImage setSize:baseImageSize];
  [favicon setSize:faviconSize];
  NSImage *icon = [[[NSImage alloc] initWithSize:iconSize] autorelease];
  NSBitmapImageRep *imageRep 
    = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL 
                                               pixelsWide:baseImageSize.width
                                               pixelsHigh:baseImageSize.height 
                                            bitsPerSample:8 
                                          samplesPerPixel:4 
                                                 hasAlpha:YES 
                                                 isPlanar:NO 
                                           colorSpaceName:NSCalibratedRGBColorSpace 
                                             bitmapFormat:0 
                                              bytesPerRow:0
                                             bitsPerPixel:0] autorelease];
  NSGraphicsContext *gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:gc];
  [baseImage drawInRect:GTMNSRectOfSize(baseImageSize)
               fromRect:GTMNSRectOfSize(baseImageSize)
              operation:NSCompositeCopy fraction:1.0];
  [favicon drawInRect:NSMakeRect(baseImageSize.width / 2, 
                                 0, 
                                 baseImageSize.height / 2, 
                                 baseImageSize.width / 2) 
             fromRect:GTMNSRectOfSize(faviconSize) 
            operation:NSCompositeSourceOver 
             fraction:1.0];
  [NSGraphicsContext restoreGraphicsState];
  [icon addRepresentation:imageRep];
  
  baseImageSize = iconSize;
  faviconSize = NSMakeSize(32, 32);
  [baseImage setSize:baseImageSize];
  [favicon setScalesWhenResized:YES];
  [favicon setSize:faviconSize];
  imageRep 
    = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL 
                                               pixelsWide:baseImageSize.width
                                               pixelsHigh:baseImageSize.height
                                            bitsPerSample:8 
                                          samplesPerPixel:4 
                                                 hasAlpha:YES 
                                                 isPlanar:NO 
                                           colorSpaceName:NSCalibratedRGBColorSpace 
                                             bitmapFormat:0 
                                              bytesPerRow:0 
                                             bitsPerPixel:0] autorelease];
  gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:gc];
  [baseImage drawInRect:GTMNSRectOfSize(baseImageSize)
               fromRect:GTMNSRectOfSize(baseImageSize)
              operation:NSCompositeCopy 
               fraction:1.0];
  [favicon drawInRect:NSMakeRect(56,8,32,32) 
             fromRect:GTMNSRectOfSize(faviconSize)
            operation:NSCompositeSourceOver 
             fraction:1.0];
  [NSGraphicsContext restoreGraphicsState];
  [icon addRepresentation:imageRep];
  if (icon) {
    [sharedIconProvider setIcon:icon forResult:result_];
  }
  [sharedIconProvider removeOperation:self];
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  @synchronized(self) {
    advancedOperation_ = nil;
  }  
  // Failed fetches are not unexpected.
  HGSIconProvider *sharedIconProvider = [HGSIconProvider sharedIconProvider];
  [sharedIconProvider removeOperation:self];
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

- (NSImage *)cachedIconForResult:(HGSResult *)result {
  NSImage *icon = nil;
  NSURL *url = IconURLForResult(result);
  if (url) {
    NSString *urlString = [url absoluteString];
    icon = [self cachedIconForKey:urlString];
  }
  return icon;
}

- (NSImage *)provideIconForResult:(HGSResult*)result
                  skipPlaceholder:(BOOL)skipPlaceholder {
  NSImage *icon = [self cachedIconForResult:result];
  if (!icon) { 
    HGSIconOperation *operation 
      = [HGSIconOperation iconOperationForResult:result];
    if (skipPlaceholder) {
      icon = [operation basicDiskLoad:result];
    } else {
      icon = [self placeHolderIcon];
    }
    @synchronized(self) {
      // Don't add if we're already doing a load for this object
      if (![iconOperations_ member:operation]) {
        [iconOperations_ addObject:operation];
        [operation beginLoading];
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
      // * 4 because we have 4 samples for pixel
      // / 8 because we have 8 pixels in a byte
      size_t repSize = ([rep pixelsHigh] 
                        * [rep pixelsWide] 
                        * [rep bitsPerSample] * 4 / 8);
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
  NSRect bestRepRect = GTMNSRectOfSize([bestRep size]);
  NSRect drawRect = GTMNSScaleRectToRect(bestRepRect, 
                                         borderRect,
                                         GTMScaleProportionally,
                                         GTMRectAlignCenter);
  drawRect = NSIntegralRect(drawRect);
  NSBitmapImageRep *imageRep 
    = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL 
                                               pixelsWide:preferredSize.width 
                                               pixelsHigh:preferredSize.height 
                                            bitsPerSample:8 
                                          samplesPerPixel:4 
                                                 hasAlpha:YES 
                                                 isPlanar:NO 
                                           colorSpaceName:NSCalibratedRGBColorSpace 
                                             bitmapFormat:0 
                                              bytesPerRow:preferredSize.width * 4 
                                             bitsPerPixel:32] autorelease];
  [formattedImage setSize:[imageRep size]];
  [formattedImage addRepresentation:imageRep];
  [formattedImage lockFocusOnRepresentation:imageRep];
  NSGraphicsContext *nsContext = [NSGraphicsContext currentContext];
  NSShadow *aShadow = [[[NSShadow alloc] init] autorelease];
  [aShadow setShadowOffset:NSMakeSize(0, -1)];
  [aShadow setShadowBlurRadius:2];
  [aShadow set];
  [nsContext setImageInterpolation:NSImageInterpolationHigh];
  CGContextRef cgContext = [nsContext graphicsPort];
  CGContextBeginTransparencyLayer(cgContext, NULL);
  NSRect insetRect = NSInsetRect(drawRect, 0.5, 0.5);
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:insetRect
                                                           xRadius:2.0
                                                           yRadius:2.0];
  [nsContext saveGraphicsState];
  [path setClip];
  [bestRep drawInRect:drawRect];
  [nsContext restoreGraphicsState];
  [path setLineWidth:1.0];
  [[NSColor colorWithCalibratedRed:0 green:0 blue:0 alpha:0.25] setStroke];
  [path stroke];
  CGContextEndTransparencyLayer(cgContext);
  [formattedImage unlockFocus];
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
      forResult:(HGSResult *)result {
  NSURL *url = IconURLForResult(result);
  NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                        result, kHGSIconProviderResultKey,
                        icon, kHGSIconProviderValueKey,
                        kHGSObjectAttributeIconKey, kHGSIconProviderAttrKey,
                        [url absoluteString], kHGSIconProviderURIKey,
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
  // We want to autorelease (as opposed to release) because we want the 
  // actual dealloc of the item to occur outside the "cache" lock.
  // We had a bug where dealloc'ing an image caused us to deadlock
  // because we had the NSAppKitLock in thread 1 and were waiting 
  // on the HGSIconProvider cache_ lock, and in thread 2 we had the 
  // HGSIconProvider cache_ lock and were waiting on NSAppKitLock.
  // By switching the release to an autorelease, we should get out of the
  // cache lock on thread 2, before attempting to release the image which
  // acquires the NSAppKitLock.
  
  //  Thread 1...
  //  928 -[NSTableView _drawContentsAtRow:column:withCellFrame:]
  //    928 -[QSBViewTableViewCell drawWithFrame:inView:]
  //      928 -[NSView addSubview:]
  //        928 -[NSView _setWindow:]
  //          928 CFArrayApplyFunction
  //            928 __NSViewRecursionHelper
  //              928 -[NSControl _setWindow:]
  //                928 -[NSView _setWindow:]
  //                  928 -[QSBResultIconView viewDidMoveToWindow]
  //                    928 -[NSView displayIfNeeded]
  //                      928 -[NSView _sendViewWillDrawInRect:]
  //                        928 -[NSView viewWillDraw]
  //                          928 -[NSTableView viewWillDraw]
  //                            928 -[NSView viewWillDraw]
  //                              928 -[NSView viewWillDraw]
  //                                928 -[QSBResultIconView viewWillDraw]
  //                                  928 -[HGSResult valueForKey:]
  //                                    928 -[HGSResult provideValueForKey:result:]
  //                                      928 -[HGSIconProvider provideIconForResult:loadLazily:useCache:]
  //                                        928 -[HGSIconProvider cachedIconForKey:]
  //                                          928 pthread_mutex_lock
  //                                            928 semaphore_wait_signal_trap
  //                                              928 semaphore_wait_signal_trap
  //  Thread 2...
  //  928 -[HGSInvocationOperation intermediateInvocation:]
  //    928 -[HGSIconOperation performDiskLoad:]
  //      928 -[HGSIconProvider cacheIcon:forKey:]
  //        928 -[HGSLRUCache setValue:forKey:size:]
  //          928 -[HGSLRUCache removeValueForKey:]
  //            928 CFDictionaryRemoveValue
  //              928 HGSLRUCacheEntryRelease
  //                928 LRURelease
  //                  928 -[NSImage dealloc]
  //                    928 -[NSImage _setRepresentationListCache:]
  //                      928 _CFRelease
  //                        928 __CFArrayReleaseValues
  //                          928 CFRelease
  //                            928 -[NSIconRefBitmapImageRep dealloc]
  //                              928 -[NSBitmapImageRep dealloc]
  //                                928 SetCustomCGColorSpace
  //                                  928 _NSAppKitLock
  //                                    928 -[NSRecursiveLock lock]
  //                                      928 pthread_mutex_lock
  //                                        928 semaphore_wait_signal_trap
  //                                          928 semaphore_wait_signal_trap
  [(id)value autorelease];
}

static Boolean LRUEqual(const void *value1, const void *value2) {
  return [(id)value1 isEqual:(id)value2];
}

static CFHashCode LRUHash(const void *value) {
  return [(id)value hash];
}
