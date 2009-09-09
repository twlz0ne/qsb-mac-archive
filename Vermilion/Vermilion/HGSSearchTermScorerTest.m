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
#import <Vermilion/HGSBundle.h>
#import <OCMock/OCMock.h>

// There is an accompanying test data file with the name 
// HGSSearchTermScorerTestData.plist which is used by the
// testRelativeTermScoring test case below.  The construct of the test data
// file is an array of test cases.  Each test case is a dictionary
// with two items.  One item has a key of 'search terms' and is a string
// containing one or more words which will be used to score 'search items'.
// The other item in the dictionary has a key of 'search items' and is
// an array of strings, each of which will be scored against the 'search
// terms'.  The array of 'search items' should be in the order in which
// you expect them to score from highest to lowest.

#define kHGSMaximumRelativeTermScoringTests 100

// We consider any score to be a successful match, but a 'reasonable' score
// is considered > 5.0, a 'good' score > 10, and an excellent score > 15.

static const CGFloat kHGSTestNotAMatchScore = 0.0;
static const CGFloat kHGSTestReasonableScore = 5.0;
static const CGFloat kHGSTestGoodScore = 10.0;
static const CGFloat kHGSTestExcellentScore = 15.0;
static const CGFloat kHGSTestPerfectScore = 1000.0;

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
  BOOL enableBestWordScoring = YES;
  CGFloat otherTermMultiplier = 0.5;
  
  HGSSetSearchTermScoringFactors(characterMatchFactor,
                                 firstCharacterInWordFactor,
                                 adjacencyFactor,
                                 startDistanceFactor,
                                 wordPortionFactor,
                                 itemPortionFactor,
                                 maximumCharacterDistance,
                                 maximumItemCharactersScanned,
                                 enableBestWordScoring,
                                 otherTermMultiplier);
}

#pragma mark Tests

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
  
  // Perfect score.
  CGFloat perfectScore = HGSPerfectMatchScore();
  STAssertEquals(perfectScore, (CGFloat)1000.0, nil);
}

- (void)testBasicRelativeTermScoring {
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

- (void)testRelativeTermScoring {
  [self ResetScoringFactors];
  // Pull in the test data.
  NSBundle *bundle = HGSGetPluginBundle();
  STAssertNotNil(bundle, nil);
  NSString *plistPath = [bundle pathForResource:@"HGSSearchTermScorerTestData"
                                         ofType:@"plist"];
  STAssertNotNil(plistPath, nil);
  NSArray *testList = [NSArray arrayWithContentsOfFile:plistPath];
  STAssertNotNil(testList, nil);
  STAssertTrue([testList count] > 0, nil);
  STAssertTrue([testList count] <= kHGSMaximumRelativeTermScoringTests, nil);
  
  // Allow a maximum of kHGSMaximumRelativeTermScoringTests possible
  // search items.  The scores will be in one-to-one correspondence with the
  // input testItems and the resulting scores should following a descending
  // pattern even though the items will be scored randomly.
  CGFloat itemScores[kHGSMaximumRelativeTermScoringTests];
  NSUInteger itemIndex[kHGSMaximumRelativeTermScoringTests];  // Used to randomize the items.
  srandom((float)[NSDate timeIntervalSinceReferenceDate]);
  
  for (NSDictionary *test in testList) {
    for (NSUInteger i = 0; i < kHGSMaximumRelativeTermScoringTests; ++i) {
      itemScores[i] = 0.0;
      itemIndex[i] = i;
    }
    NSString *testTermsString = [test objectForKey:@"query"];
    NSArray *testTerms = [testTermsString componentsSeparatedByString:@" "];
    NSArray *testItems = [test objectForKey:@"results"];
    NSUInteger itemsCount = [testItems count];
    for (NSUInteger j = itemsCount; j > 0; --j) {
      // Pick a random item index then compress the index choices.
      NSUInteger indexChoice = random() / (LONG_MAX / j);
      NSUInteger randomIndex = itemIndex[indexChoice];
      for (NSUInteger k = indexChoice + 1; k < 50; ++k) {
        itemIndex[k - 1] = itemIndex[k];
      }
      id testItem = [testItems objectAtIndex:randomIndex];
      NSString *primaryItem = nil;
      NSArray *secondaryItems = nil;
      if ([testItem isKindOfClass:[NSString class]]) {
        primaryItem = testItem;
      } else if ([testItem isKindOfClass:[NSArray class]]) {
        secondaryItems = testItem;
        NSUInteger itemCount = [secondaryItems count];
        if (itemCount > 0) {
          primaryItem = [secondaryItems objectAtIndex:0];
          secondaryItems = (itemCount > 1)
            ? [secondaryItems subarrayWithRange:NSMakeRange(1, itemCount - 1)]
            : nil;
        }
      }
      if (primaryItem) {
        // This replicates the score formula used in HGSMemorySearchSource
        // when secondaryItems are taken into consideration.
        NSArray *wordRanges = nil;
        CGFloat itemScore = 0.0;
        for (NSString *queryTerm in testTerms) {
          CGFloat termScore
            = HGSScoreTermForItem(queryTerm, primaryItem, &wordRanges);
          // Only consider secondaryItem that have better scores than the main
          // search item.
          for (NSString *secondaryItem in secondaryItems) {
            termScore = MAX(termScore,
                            HGSScoreTermForItem(queryTerm, secondaryItem, nil)
                            / 2.0);
          }
          if (termScore < 0.01) {
            // Short-circuit this item since at least one search term
            // was not adequately matched.
            itemScore = 0.0;
            break;
          }
          itemScore += termScore;
        }
        itemScores[randomIndex] = itemScore;
      }
    }
    // Verify that we got ascending scores.
    for (NSUInteger l = 1; l < itemsCount; ++l) {
      STAssertTrue(itemScores[l - 1] >= itemScores[l], 
                   @"Score failure for '%@'[%d]: %0.2f !>= '%@'[%d]: %0.2f "
                   @"for term '%@'", 
                   [testItems objectAtIndex:l - 1], l - 1, itemScores[l - 1],
                   [testItems objectAtIndex:l], l, itemScores[l],
                   testTermsString);
    }
  }
}

@end
