//
//  HGSIconProvider.h
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

#import <Cocoa/Cocoa.h>

@class HGSLRUCache;
@class HGSResult;

@interface HGSIconProvider : NSObject {
 @private
  NSMutableSet *iconOperations_;
  HGSLRUCache *cache_;
  NSImage *placeHolderIcon_;
  NSImage *compoundPlaceHolderIcon_;
}

// Returns the singleton instance of HGSIconProvider
+ (HGSIconProvider *)sharedIconProvider;

// Returns our default placeHolderIcon. Do not change this icon. Make a copy
// and change it.
- (NSImage *)placeHolderIcon;

// Returns our default compound placeHolderIcon. Do not change this icon. 
// Make a copy and change it.
- (NSImage *)compoundPlaceHolderIcon;

// Returns an NSImage value for a HGSResult.
// Returns the image if the was immediately set (if the cache was able to 
// provide the icon), or the placeHolder image if it wasn't in the cache.
//
// If loadLazily is YES, an asynchronous load of the icon will be started.
//
// The result argument is not retained; it's very important that for lazy icon
// retrievals cancelOperationsForResult be called whenever a result is going
// away.
- (NSImage *)provideIconForResult:(HGSResult *)result
                       loadLazily:(BOOL)loadLazily;

// If provideIconForResult has been called with loadLazily:YES, then the
// the call to provideIconForResult may be followed by a subsequent call
// to cancelOperationsForResult if the icon is no longer needed. Calling
// this method on a result that does not have a pending lazy load is
// harmless.
- (void)cancelOperationsForResult:(HGSResult*)result;

// Anyone can request that an icon be cached and then retrieve it later
- (NSImage *)cachedIconForKey:(NSString *)key;
- (void)cacheIcon:(NSImage *)icon forKey:(NSString *)key;

// Updates the icon for a given result and caches the image for the future.
// This can be called from any thread. The actual setting happens on the main
// thread.
- (void)setIcon:(NSImage *)icon
      forResult:(HGSResult *)result 
        withURI:(NSString *)uri;

- (NSImage *)imageWithRoundRectAndDropShadow:(NSImage *)image;
- (NSSize)preferredIconSize; // Size of the largest icon used in the UI

@end
