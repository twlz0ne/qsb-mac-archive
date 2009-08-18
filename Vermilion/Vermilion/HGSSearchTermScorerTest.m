//
//  HGSSearchTermScorerTest.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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


#import "GTMSenTestCase.h"
#import "HGSSearchTermScorer.h"
#import <OCMock/OCMock.h>

// We consider any score to be a successful match, but a 'reasonable' score
// is considered > 5.0, a 'good' score > 10, and an excellent score > 15.

static const CGFloat kHGSTestNotAMatchScore = 0.0;
static const CGFloat kHGSTestReasonableScore = 5.0;
static const CGFloat kHGSTestGoodScore = 10.0;
static const CGFloat kHGSTestExcellentScore = 15.0;
static const CGFloat kHGSTestPerfectScore = 100.0;

@interface HGSSearchTermScorerTest : GTMTestCase

// Insure that the scoring factors are set to the defaults.
// Keep this coordinated with the values given at the top of
// HGSSearchTermScorer.m.
- (void)ResetScoringFactors;

@end

@implementation HGSSearchTermScorerTest

- (void)ResetScoringFactors {
  CGFloat characterMatchFactor = 1.0;
  CGFloat firstCharacterInWordFactor = 3.0;
  CGFloat adjacencyFactor = 3.8;
  CGFloat startDistanceFactor = 0.8;
  CGFloat wordPortionFactor = 5.0;
  CGFloat itemPortionFactor = 0.8;
  NSUInteger maximumCharacterDistance = 22;
  NSUInteger maximumItemCharactersScanned = 250;
  
  HGSSetSearchTermScoringFactors(characterMatchFactor,
                                 firstCharacterInWordFactor,
                                 adjacencyFactor,
                                 startDistanceFactor,
                                 wordPortionFactor,
                                 itemPortionFactor,
                                 maximumCharacterDistance,
                                 maximumItemCharactersScanned);
}

#pragma mark Tests

- (void)testSetScoringFactors {
  CGFloat characterMatchFactor = 1.0;
  CGFloat firstCharacterInWordFactor = 3.0;
  CGFloat adjacencyFactor = 3.8;
  CGFloat startDistanceFactor = 0.8;
  CGFloat wordPortionFactor = 5.0;
  CGFloat itemPortionFactor = 0.8;
  NSUInteger maximumCharacterDistance = 22;
  NSUInteger maximumItemCharactersScanned = 250;
  
  HGSSetSearchTermScoringFactors(characterMatchFactor,
                                 firstCharacterInWordFactor,
                                 adjacencyFactor,
                                 startDistanceFactor,
                                 wordPortionFactor,
                                 itemPortionFactor,
                                 maximumCharacterDistance,
                                 maximumItemCharactersScanned);
}

- (void)testBasicTermScoring {
  [self ResetScoringFactors];
  CGFloat score = HGSScoreTermForItem(@"abc", @"abc", nil);
  STAssertEquals(score, kHGSTestPerfectScore, @"%f != %f",
                 score, kHGSTestPerfectScore);
  score = HGSScoreTermForItem(@"abc", @"def", nil);
  STAssertEquals(score, kHGSTestNotAMatchScore, @"%f != %f",
                 score, kHGSTestNotAMatchScore);
  
  // Test a few of what we'd consider excellent scores.
  // Runs-of-characters matches
  score = HGSScoreTermForItem(@"abc", @"abcdef", nil);
  STAssertTrue(score > kHGSTestExcellentScore, @"%f !> %f",
               score, kHGSTestExcellentScore);
  score = HGSScoreTermForItem(@"abcdef", @"xabcxdefx", nil);
  STAssertTrue(score > kHGSTestExcellentScore, @"%f !> %f",
               score, kHGSTestExcellentScore);

  // Abbreviations
  score = HGSScoreTermForItem(@"abc", @"a b c", nil);
  STAssertTrue(score > kHGSTestExcellentScore, @"%f !> %f",
               score, kHGSTestExcellentScore);
  score = HGSScoreTermForItem(@"abc", @"american bandstand of canada", nil);
  STAssertTrue(score > kHGSTestExcellentScore, @"%f !> %f",
               score, kHGSTestExcellentScore);
  
  // Test a few of what we'd consider good scores.
  // Complete words
  score = HGSScoreTermForItem(@"abc", @"here is the abc of the matter", nil);
  STAssertTrue(score > kHGSTestGoodScore, @"%f !> %f",
               score, kHGSTestGoodScore);
}

- (void)testRelativeTermScoring {
  [self ResetScoringFactors];
  CGFloat scoreA = HGSScoreTermForItem(@"abc", @"abcd", nil);
  CGFloat scoreB = HGSScoreTermForItem(@"abc", @"abcde", nil);
  STAssertTrue(scoreA > scoreB,  @"%f !> %f", scoreA, scoreB);
  scoreA = HGSScoreTermForItem(@"abc", @"xxabcxx", nil);
  scoreB = HGSScoreTermForItem(@"abc", @"xxxabcx", nil);
  STAssertTrue(scoreA > scoreB, @"%f !> %f", scoreA, scoreB);
  scoreA = HGSScoreTermForItem(@"abc", @"american bandstand of canada",
                               nil);
  scoreB = HGSScoreTermForItem(@"abc", @"american candy bandstand of canada",
                               nil);
  STAssertTrue(scoreA > scoreB, @"%f !> %f", scoreA, scoreB);
  scoreA = HGSScoreTermForItem(@"canada", @"american bandstand of canada", nil);
  scoreB = HGSScoreTermForItem(@"canada", @"american candy bandstand of canada",
                               nil);
  STAssertTrue(scoreA > scoreB, @"%f !> %f", scoreA, scoreB);
  scoreA = HGSScoreTermForItem(@"can", @"american candy bandstand of canada",
                               nil);
  scoreB = HGSScoreTermForItem(@"can", @"american bandstand of canada", nil);
  STAssertTrue(scoreA > scoreB, @"%f !> %f", scoreA, scoreB);
}

@end
