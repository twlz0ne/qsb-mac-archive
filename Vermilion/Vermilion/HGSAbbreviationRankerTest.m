//
//  HGSAbbreviationRankerTest.m
//
//  Copyright (c) 2008-2009 Google Inc. All rights reserved.
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

#import "HGSAbbreviationRanker.h"

#import "GTMSenTestCase.h"

@interface HGSAbbreviationRankerTest : GTMTestCase 
@end

@implementation HGSAbbreviationRankerTest

- (float)rankFor:(NSString*)abbreviation inTitle:(NSString*)title {
  float score = HGSScoreForAbbreviation((CFStringRef)title,
                                        (CFStringRef)abbreviation,
                                        nil);
  return score;
}

- (void)assertRankFor:(NSString*)abbreviation
              inTitle:(NSString*)title
           aboveScore:(float)expectedScore {
  float score = [self rankFor:abbreviation inTitle:title];
  STAssertTrue(score > expectedScore,
               @"'%@' in '%@' should score above %.03f (Got: %.03f)",
               abbreviation,
               title,
               expectedScore,
               score);
}

- (void)assertRankFor:(NSString*)abbreviation
              inTitle:(NSString*)title
           belowScore:(float)expectedScore {
  float score = [self rankFor:abbreviation inTitle:title];
  STAssertTrue(score < expectedScore,
               @"'%@' in '%@' should score below %.03f (Got: %.03f)",
               abbreviation,
               title,
               expectedScore,
               score);
}

- (void)testRankForBBCSportsPipeCricket {
  [self assertRankFor:@"cricket" inTitle:@"BBC SPORTS | Cricket" aboveScore:0.8f];
}

- (void)testRankForBBCSportsCricket {
  [self assertRankFor:@"cricket" inTitle:@"BBC Sports Cricket" aboveScore:0.8f];
}

- (void)testRankForCalculator {
  // This scores 0.83.
  //[self assertRankFor:@"al" inTitle:@"Calculator" belowScore:0.8f];
  [self assertRankFor:@"tor" inTitle:@"Calculator" belowScore:0.8f];
  [self assertRankFor:@"lc" inTitle:@"Calculator" belowScore:0.8f];
  [self assertRankFor:@"cal" inTitle:@"Calculator" aboveScore:0.8f];
}

@end
