//
//  HGSSuggestSource.h
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
// TODO(altse): Invalidate cache periodically

#import <Foundation/Foundation.h>
#import <Vermilion/Vermilion.h>

@class HGSSQLiteBackedCache;

@interface HGSSuggestSource : HGSCallbackSearchSource {
 @protected
  NSMutableDictionary *cache_;
 @private
  NSString *suggestBaseUrl_;
  // Stores the last full result returned by the source. Does not get set
  // for partial results such as those derived from a previous query.
  NSArray *lastResult_;  // Array of HGSResult's
  // Operation queue
  BOOL isReady_;
  BOOL continueRunning_;
  NSMutableArray *operationQueue_;
}

// Designated Initializer
- (id)initWithConfiguration:(NSDictionary *)configuration
                    baseURL:(NSString*)baseURL;

- (void)stopFetching;
// Used in subclasses (HGSNavSuggestSource)
// TODO(altse): Take the caching private headers out into a separate file
//              so HGSNavSuggestSource can use it.
//@protected
// Cache a value by a key. It is expected that the key is not nil and
// the key is the query submitted.
- (void)cacheObject:(id)cacheValue forKey:(id)key;
- (void)setLastResult:(NSArray *)lastResult;
- (void)resetHistoryAndCache;

@end
