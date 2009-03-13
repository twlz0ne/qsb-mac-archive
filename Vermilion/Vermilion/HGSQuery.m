//
//  HGSQuery.m
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

#import "HGSQuery.h"
#import "HGSTokenizer.h"
#import "HGSStringUtil.h"

@implementation HGSQuery

@synthesize uniqueWords = uniqueWords_;
@synthesize rawQueryString = rawQueryString_;
@synthesize results = results_;
@synthesize parent = parent_;
@synthesize maxDesiredResults = maxDesiredResults_;
@synthesize flags = flags_;
@dynamic pivotObject;

- (id)initWithString:(NSString*)query 
             results:(HGSResultArray *)results
          queryFlags:(HGSQueryFlags)flags {
  if ((self = [super init])) {
    rawQueryString_ = [query copy];
    results_ = [results retain];
    maxDesiredResults_ = -1;
    flags_ = flags;

    // If we got nil for a query, but had a pivot, turn it into an empty query.
    if (!rawQueryString_ && results_) {
      rawQueryString_ = @"";
    }
    NSString *prepedQuery
      = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:rawQueryString_];
    
    // first, just collect all the words
    NSArray *wordsArray = [HGSTokenizer tokenizeString:prepedQuery wordsOnly:YES];
    if (wordsArray) {
      // now unique them
      uniqueWords_ = [[NSSet alloc] initWithArray:wordsArray];
    }
    if (!uniqueWords_) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [rawQueryString_ release];
  [uniqueWords_ release];
  [results_ release];
  [parent_ release];
  [super dealloc];
}

- (HGSResult *)pivotObject {
  HGSResult *result = nil;
  @synchronized(self) {
    result = [[self results] lastObject];
    // make sure it ends up in any local pool so the caller is safe threading wise
    [[result retain] autorelease];
  }
  return result;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@ - Q='%@' Rs=%@ P=<%@>]",
          [self class], rawQueryString_, results_, parent_];
}

@end
