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
#import "HGSTokenizer.h"
#import "GTMSenTestCase.h"

@interface HGSAbbreviationRankerTest : GTMTestCase 
@end

@implementation HGSAbbreviationRankerTest

- (void)assertAbbreviation:(NSString *)abbreviation
               isBetterFor:(NSString *)title1
                   thanFor:(NSString*)title2 {
  NSString *tokenizedTitle1 = [HGSTokenizer tokenizeString:title1];
  NSString *tokenizedTitle2 = [HGSTokenizer tokenizeString:title2];
  CGFloat score1 = HGSScoreForAbbreviation(tokenizedTitle1, abbreviation, NULL);
  CGFloat score2 = HGSScoreForAbbreviation(tokenizedTitle2, abbreviation, NULL);
  STAssertGreaterThan(score1, score2,
                      @"%@ should be a better abbreviation for "
                      @"%@ (%.03f - %@) than for %@ (%.03f - %@)",
                      abbreviation,  
                      title1, score1, tokenizedTitle1,
                      title2, score2, tokenizedTitle2);
}

- (void)assertRankFor:(NSString *)abbreviation1
         isBetterThan:(NSString *)abbreviation2
             forTitle:(NSString*)title {
  NSString *tokenizedTitle = [HGSTokenizer tokenizeString:title];
  CGFloat score1 = HGSScoreForAbbreviation(tokenizedTitle, abbreviation1, NULL);
  CGFloat score2 = HGSScoreForAbbreviation(tokenizedTitle, abbreviation2, NULL);
  STAssertGreaterThan(score1, score2,
                      @"%@ (%.03f) should be a better abbreviation than "
                      @"%@ (%.03f) for %@ (%@)",
                      abbreviation1,  score1,
                      abbreviation2, score2,
                      title, tokenizedTitle);
}

- (void)testCompareAbbreviations {
  struct {
    NSString *name;
    NSString *abbreviation1;
    NSString *abbreviation2;
  } tests[] = {
    { @"Adobe Photoshop CS3", @"ph", @"p" },
    { @"Adobe Photoshop CS3", @"pshop", @"shop" },
    { @"Adobe Photoshop CS3", @"ap3", @"pho" },
    { @"Adobe Photoshop CS3", @"beph", @"ep" },
    { @"Vincent Newbury", @"vn", @"vc" },
    { @"Vincent Newbury", @"iy", @"dm" },
  };
  
  for (size_t i = 0; i < sizeof(tests) / sizeof (tests[0]); ++i) {
    [self assertRankFor:tests[i].abbreviation1
           isBetterThan:tests[i].abbreviation2 
               forTitle:tests[i].name];
  }
}

- (void)testCompareTitles {
  struct {
    NSString *abbreviation;
    NSString *title1;
    NSString *title2;
  } tests[] = {
    { @"vnc", @"JollyVNC", @"Interactive measurements calculator, weights and measures /metric conversion" },
    { @"ap3", @"Adobe Photoshop CS3", @"Adobe Photoshop CS4.app" },
    { @"earth", @"Google Earth", @"Where are the Google Engineers?" },
    { @"earth", @"Google Earth", @"sequence grabber determining the capture resolution of an iidc device" },
    { @"ear", @"Google Earth", @"gsearch" },
    { @"mai", @"Mail", @"GMail" },
  };
  
  for (size_t i = 0; i < sizeof(tests) / sizeof (tests[0]); ++i) {
    [self assertAbbreviation:tests[i].abbreviation
                 isBetterFor:tests[i].title1 
                     thanFor:tests[i].title2];
  }
}
  
@end
