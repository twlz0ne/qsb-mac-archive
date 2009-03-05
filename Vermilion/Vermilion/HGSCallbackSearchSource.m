//
//  HGSCallbackSearchSource.m
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

#import "HGSCallbackSearchSource.h"
#import "HGSLog.h"
#import "HGSSearchOperation.h"
#import "HGSStringUtil.h"
#import "HGSTokenizer.h"

@interface HGSCallbackSearchOperation : HGSSearchOperation {
 @private
  HGSCallbackSearchSource *callbackSource_;
}
- (id)initWithSource:(HGSCallbackSearchSource *)callbackSource
               query:(HGSQuery*)query;
@end

@implementation HGSCallbackSearchSource

- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query {
  HGSCallbackSearchOperation* searchOp
    = [[[HGSCallbackSearchOperation alloc] initWithSource:self
                                                    query:query] autorelease];
  return searchOp;
}

@end

@implementation HGSCallbackSearchSource (ProtectedMethods)

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  // Must be overridden
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey]) {
    HGSLog(@"ERROR: CallbackSource %@ forgot to override performSearchOperation:.",
           [self class]);
  }
  [self doesNotRecognizeSelector:_cmd];
}

- (BOOL)isSearchConcurrent {
  return NO;
}

- (NSSet *)normalizedTokenSetForString:(NSString*)string {
  NSSet *set = nil;
  if ([string length]) {
    // do our normalization...
    NSString *preppedString
      = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:string];
    
    // now split them into terms and use sets to keep each just once...
    NSArray *terms = [HGSTokenizer tokenizeString:preppedString
                                        wordsOnly:YES];
    set = [NSSet setWithArray:terms];
  }
  return set;
}  

@end

@implementation HGSCallbackSearchOperation

- (id)initWithSource:(HGSCallbackSearchSource *)callbackSource
               query:(HGSQuery*)query {
  if ((self = [super initWithQuery:query])) {
    callbackSource_ = [callbackSource retain];
    if (!callbackSource_) {
      HGSLogDebug(@"Tried to create a CallbackSearchSource's operation w/o the "
                  @"search source.");
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [callbackSource_ release];
  [super dealloc];
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@ callbackSource:%@",
          [super description], callbackSource_];
}

- (BOOL)isConcurrent {
  return [callbackSource_ isSearchConcurrent];
}

- (void)main {
  [callbackSource_ performSearchOperation:self];
}

- (NSString *)displayName {
  return [callbackSource_ displayName];
}

@end
