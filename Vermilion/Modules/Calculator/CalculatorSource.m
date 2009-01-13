//
//  CalculatorSource.m
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

#import <Vermilion/Vermilion.h>
#import "CalculatePrivate.h"

@interface CalculatorSource : HGSCallbackSearchSource {
 @private
  NSCharacterSet *mathSet_;
  NSCharacterSet *nonAlphanumericSet_;
  NSURL *calculatorAppURL_;
}
@end

@implementation CalculatorSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSCharacterSet *mathSet
      = [NSCharacterSet characterSetWithCharactersInString:@"1234567890+-*/() "];
    mathSet_ = [mathSet retain];
    NSCharacterSet *nonAlphanumericSet = 
      [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    nonAlphanumericSet_ = [nonAlphanumericSet retain];
    
    NSString *calcPath
      = [[NSWorkspace sharedWorkspace]
         absolutePathForAppBundleWithIdentifier:@"com.apple.calculator"];
    if ([calcPath length]) {
      calculatorAppURL_ = [[NSURL fileURLWithPath:calcPath] retain];
    }
    if (!mathSet_ || !nonAlphanumericSet_ || !calculatorAppURL_) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [mathSet_ release];
  [nonAlphanumericSet_ release];
  [calculatorAppURL_ release];
  [super dealloc];
}

#pragma mark -

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  NSString *rawQuery = [query rawQueryString];

  // It takes atleast 3 chars to make an expression ie- 1+1
  if ([rawQuery length] < 3) {
    return NO;
  }

  // As long as any of the math characters are in the string, let it through
  NSRange range = [rawQuery rangeOfCharacterFromSet:mathSet_];
  if (range.location == NSNotFound) return NO;
  // Also require at least one math character that isn't alphanumeric
  range = [rawQuery rangeOfCharacterFromSet:nonAlphanumericSet_];
  return (range.location != NSNotFound);
}

- (BOOL)isSearchConcurrent {
  // Not sure if the framework we call is thread safe, so play it safe
  return YES;
}

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  NSArray *resultsArray = nil;
  
  NSString *rawQuery = [[operation query] rawQueryString];

  char answer[1024];
  int success
    = CalculatePerformExpression((char *)[rawQuery UTF8String], 10, 1, answer);
  if (success) {
    NSString *resultString
      = [NSString stringWithFormat:@"%@ = %@", rawQuery,
                                   [NSString stringWithUTF8String:answer]];
    // Cheat, force this result high in the list.
    // TODO(dmaclach): figure out a cleaner way to get results like this high
    // in the results.
    NSDictionary *attributes
     = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithFloat:2.0f], kHGSObjectAttributeRankKey, nil];
    HGSObject *hgsObject
      = [HGSObject objectWithIdentifier:calculatorAppURL_
                                   name:resultString
                                   type:HGS_SUBTYPE(kHGSTypeOnebox, @"calculator")
                                 source:self
                             attributes:attributes];
    resultsArray = [NSArray arrayWithObject:hgsObject];
    [operation setResults:resultsArray];
  }
  // Since we are concurent, finish the query ourselves.
  [operation finishQuery];
}

@end
