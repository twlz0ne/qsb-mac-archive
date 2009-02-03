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
#import "HGSLog.h"

@interface HGSQuery (PrivateMethods)
- (BOOL)parseQuery;
@end

static NSString * const kEmptyQuery = @"";

@implementation HGSQuery

- (id)initWithString:(NSString*)query 
         pivotObject:(HGSObject *)pivotObject
          queryFlags:(HGSQueryFlags)flags{
  if ((self = [super init])) {
    rawQuery_ = [query copy];
    pivotObject_ = [pivotObject retain];
    maxDesiredResults_ = -1;
    flags_ = flags;

    // If we got nil for a query, but had a pivot, turn it into an empty query.
    if (!rawQuery_ && pivotObject_) {
      rawQuery_ = [kEmptyQuery copy];
    }

    if (!rawQuery_ || ![self parseQuery]) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [rawQuery_ release];
  [uniqueWords_ release];
  [pivotObject_ release];
  [parent_ release];
  [super dealloc];
}

- (NSSet *)uniqueWords {
  // make sure it ends up in any local pool so the caller is safe threading wise
  return [[uniqueWords_ retain] autorelease];
}

- (NSString *)rawQueryString {
  // make sure it ends up in any local pool so the caller is safe threading wise
  return [[rawQuery_ retain] autorelease];
}

- (HGSObject*)pivotObject {
  // make sure it ends up in any local pool so the caller is safe threading wise
  return [[pivotObject_ retain] autorelease];
}

- (HGSQuery*)parent {
  // make sure it ends up in any local pool so the caller is safe threading wise
  return [[parent_ retain] autorelease];
}

- (void)setParent:(HGSQuery*)parent {
  HGSAssert(parent != self, @"um, we can't be our own parent");
  [parent_ autorelease];
  parent_ = [parent retain];
}

- (NSInteger)maxDesiredResults {
  return maxDesiredResults_;
}

- (void)setMaxDesiredResults:(NSInteger)maxResults {
  maxDesiredResults_ = maxResults;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@ - Q='%@' PO=%@ P=<%@>]",
          [self class], rawQuery_, pivotObject_, parent_];
}

- (HGSQueryFlags)flags {
  return flags_;
}

@end

@implementation HGSQuery (PrivateMethods)

- (BOOL)parseQuery {
  // start out by lowercasing and folding diacriticals
  NSString *prepedQuery
    = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:rawQuery_];
  
  // first, just collect all the words
  NSArray *wordsArray
    = [[HGSTokenizer wordEnumeratorForString:prepedQuery] allObjects];
  if (!wordsArray) {
    return NO; // COV_NF_LINE
  }
  
  // now unique them
  uniqueWords_ = [[NSSet alloc] initWithArray:wordsArray];
  if (!uniqueWords_) {
    return NO; // COV_NF_LINE
  }
  
  // If we want phrases, etc. there is more work to do here, see
  // googlemac/Vermilion/Query for that version.
  
  return YES;
}

@end
