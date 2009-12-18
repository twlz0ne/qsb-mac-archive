//
//  HGSSearchTermScorer.m
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

#import "HGSSearchTermScorer.h"
#import "HGSBundle.h"
#import "HGSLog.h"

// Use 'define' because compiler complains about stack protection.
#define kHGSMaximumItemCharactersScanned 250

static CGFloat gHGSPerfectMatchScore = 1000.0;  // Score for a perfect match.
static CGFloat gHGSCharacterMatchFactor = 1.0;  // Basic char match factor.
static CGFloat gHGSFirstCharacterInWordFactor = 3.0;  // First-char-in-word factor.
static CGFloat gHGSAdjacencyFactor = 2.8;  // Adjacency factor.
// Start distance factor representing the minimum percentage allowed when
// applying the start distance score.  This should be > 0 and <= 1.00.
static CGFloat gHGSStartDistanceFactor = 0.5;
static CGFloat gHGSWordPortionFactor = 3.0; // Portion of complete word factor.
// Item portion of complete item factor representing the minimum percentage
// allowed when applying the start distance score.  This should be > 0 and
// <= 1.00.
static CGFloat gHGSItemPortionFactor = 0.8;
// The minimum match distance factor applied to the score calculated by
// taking the length of the term and dividing by the spread of the match.
static CGFloat gHGSMatchSpreadFactor = 0.8;
// Maximum distance between matching characters before abandoning the match.
static NSUInteger gHGSMaximumCharacterDistance = 22;
// Maximum distance we will scan into the search item for matches.
static NSUInteger gHGSMaximumItemCharactersScanned
  = kHGSMaximumItemCharactersScanned;
static BOOL gHGSEnableBestWordScoring = YES;  // Perform best word match scoring.
// The amount by which an other item score is multiplied in order to determine
// its final score.
static CGFloat gHGSOtherItemMultiplier = 0.5;

// Any score less than this is considered as a zero score.
static CGFloat const gHGSMinimumSignificantScore = 0.1;

#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

// Keys to search term detail dictionary items.
NSString *const kHGSScoreTermWordKey = @"searchTerm";
NSString *const kHGSScoreTermBestScoreKey = @"bestScore";
NSString *const kHGSScoreTermNormScoreKey = @"normScore";
NSString *const kHGSScoreTermMatchCountKey = @"matchCount";
NSString *const kHGSScoreTermMatchDetailKey = @"matchDetail";

// Keys to match detail dictionary items.
NSString *const kHGSScoreMatchScoreKey = @"score";
NSString *const kHGSScoreMatchNormScoreKey = @"norm";
NSString *const kHGSScoreMatchSDSKey = @"sds";
NSString *const kHGSScoreMatchABSKey = @"abs";
NSString *const kHGSScoreMatchBMLKey = @"bml";
NSString *const kHGSScoreMatchBWLKey = @"bwl";
NSString *const kHGSScoreMatchBMLVKey = @"bmlv";
NSString *const kHGSScoreMatchBMLSKey = @"bmls";
NSString *const kHGSScoreMatchPOIMFKey = @"poimf";
NSString *const kHGSScoreMatchCharDetailKey = @"charDetail";

// Keys to character detail dictionary items.
NSString *const kHGSScoreCharPosKey = @"pos";
NSString *const kHGSScoreCharPSKey = @"ps";
NSString *const kHGSScoreCharFCVKey = @"fcv";
NSString *const kHGSScoreCharADVKey = @"adv";
NSString *const kHGSScoreCharADSKey = @"ads";

#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

// Structure containing information on each search term
// character matching and scoring results.
typedef struct {
  // Postition within search item that character was found.
  CFIndex charMatchIndex_;
  // Value for being first character in a search item word.
  NSUInteger firstCharacterValue_;
  NSUInteger adjacencyValue_;  // Character adjacency value.
} HGSTermCharStat;

// Utility function to clear a charStat.
static void HGSResetCharStat(HGSTermCharStat *pCharStat);

#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

// Utility function to grab the best scoring detail from term details.
static NSMutableDictionary *HGSBestDetailsFromCandidateDetails(NSDictionary *
                                                               candidateDetails);

#else  // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

// Main scoring function called by non-detailed functions.
static CGFloat HGSScoreTermAndDetailsForItem(NSString *term,
                                             HGSScoreString *item,
                                             NSDictionary **pSearchTermDetails);

#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

@interface HGSItemWordRange ()

+ (id)wordRangeWithStart:(NSUInteger)wordStart
                  length:(NSUInteger)wordLength;

- (id)initWithStart:(NSUInteger)wordStart
             length:(NSUInteger)wordLength;

@end

@interface HGSScoreString ()

@property (copy, readwrite) NSString *string;
@property (retain) NSArray *wordRanges;

- (NSArray *)buildWordRangesForString:(NSString *)wordString;
- (NSUInteger)length;

@end

void HGSSetSearchTermScoringFactors(CGFloat characterMatchFactor,
                                    CGFloat firstCharacterInWordFactor,
                                    CGFloat adjacencyFactor,
                                    CGFloat startDistanceFactor,
                                    CGFloat wordPortionFactor,
                                    CGFloat itemPortionFactor,
                                    CGFloat matchSpreadFactor,
                                    NSUInteger maximumCharacterDistance,
                                    NSUInteger maximumItemCharactersScanned,
                                    BOOL enableBestWordScoring,
                                    CGFloat otherItemMultiplier) {
  gHGSCharacterMatchFactor = characterMatchFactor;
  gHGSFirstCharacterInWordFactor = firstCharacterInWordFactor;
  gHGSAdjacencyFactor = adjacencyFactor;
  gHGSStartDistanceFactor = startDistanceFactor;
  gHGSWordPortionFactor = wordPortionFactor;
  gHGSItemPortionFactor = itemPortionFactor;
  gHGSMatchSpreadFactor = matchSpreadFactor;
  gHGSMaximumCharacterDistance = maximumCharacterDistance;
  gHGSMaximumItemCharactersScanned
    = MIN(maximumItemCharactersScanned, kHGSMaximumItemCharactersScanned);
  gHGSEnableBestWordScoring = enableBestWordScoring;
  gHGSOtherItemMultiplier = otherItemMultiplier;
}

CGFloat HGSCalibratedScore(HGSCalibratedScoreType scoreType) {
  CGFloat calibratedScore = 0.0;
  if (scoreType < kHGSCalibratedLastScore) {
    static BOOL scoresCalibrated = NO;
    static CGFloat calibratedScores[kHGSCalibratedLastScore];
    if (!scoresCalibrated) {
      NSBundle *bundle = HGSGetPluginBundle();
      HGSAssert(bundle, nil);
      NSString *plistPath = [bundle pathForResource:@"ScoreCalibration"
                                             ofType:@"plist"];
      HGSAssert(plistPath, nil);
      NSArray *calibrations = [NSArray arrayWithContentsOfFile:plistPath];
      HGSAssert(calibrations, nil);
      NSUInteger i = 0;
      for (NSDictionary *calibration in calibrations) {
        NSString *term = [calibration objectForKey:@"term"];
        HGSAssert(term, nil);
        NSString *itemString = [calibration objectForKey:@"item"];
        HGSAssert(itemString, nil);
        HGSScoreString *item = [HGSScoreString scoreStringWithString:itemString];
        calibratedScores[i] = HGSScoreTermForItem(term, item);
        ++i;
      }
      scoresCalibrated = YES;
    }
    calibratedScore = calibratedScores[scoreType];
  }
  return calibratedScore;
}

#pragma mark Internal Scoring Functions

CGFloat ScoreTerm(CFIndex termLength, HGSScoreString *itemString,
                  HGSTermCharStat *charStat
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
                  , NSMutableArray **pMatchDetailsArray
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
                  ) {
  CGFloat termScore = 0.0;
  // Calculate the individual charScores and accumulate term scores.
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  NSMutableArray *charDetailsArray
    = (pMatchDetailsArray)
      ? [NSMutableArray arrayWithCapacity:termLength]
      : nil;
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  BOOL abbreviation = YES;
  CGFloat abbreviationScore = 0.0;
  for (CFIndex ci = 0; ci < termLength; ++ci) {
    CGFloat charScore = gHGSCharacterMatchFactor;
    NSUInteger firstCharacterValue = charStat[ci].firstCharacterValue_;
    if (!firstCharacterValue) {
      abbreviation = NO;
    }
    CGFloat firstCharacterScore
      = (CGFloat)(firstCharacterValue) * gHGSFirstCharacterInWordFactor;
    charScore += firstCharacterScore;
    CGFloat adjacencyScore
      = (CGFloat)(charStat[ci].adjacencyValue_) * gHGSAdjacencyFactor;
    charScore += adjacencyScore;
    termScore += charScore;
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
    // Collect statistics.
    if (pMatchDetailsArray) {
      NSMutableDictionary *charDict
        = [NSMutableDictionary dictionaryWithObjectsAndKeys:
           [NSNumber numberWithLong:charStat[ci].charMatchIndex_],
           kHGSScoreCharPosKey,
           [NSNumber numberWithFloat:charScore], kHGSScoreCharPSKey,
           [NSNumber numberWithUnsignedInt:firstCharacterValue],
           kHGSScoreCharFCVKey,
           [NSNumber numberWithUnsignedInt:charStat[ci].adjacencyValue_],
           kHGSScoreCharADVKey,
           [NSNumber numberWithFloat:adjacencyScore],
           kHGSScoreCharADSKey,
           nil];
      [charDetailsArray addObject:charDict];
    }
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  }

  // Determine the best complete word match length score.
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  NSUInteger bestTermMatchLength = 0;  // Best word match length
  NSUInteger bestMatchedWordLength = 0;  // Best word length
  CGFloat bestMatchLengthValue = 0.0;  // Best word match length value
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  CGFloat bestMatchLengthScore = 0.0;  // Best word match length score
  // Scan charStats in reverse to determine best match.
  CFIndex charStatCount = termLength;
  while (charStatCount > 0 && gHGSEnableBestWordScoring) {
    CFIndex charStatItem = charStatCount - 1;
    NSUInteger adjacencyValue = charStat[charStatItem].adjacencyValue_;
    NSArray *wordRanges = [itemString wordRanges];
    for (HGSItemWordRange *wordRange in wordRanges) {
      if (charStat[charStatItem].charMatchIndex_
          >= [wordRange wordStart]) {
        NSUInteger wordLength = [wordRange wordLength];
        CGFloat matchValue
          = (CGFloat)(adjacencyValue + 1) / (CGFloat)wordLength;
        CGFloat matchScore = gHGSWordPortionFactor * matchValue;
        if (matchScore > bestMatchLengthScore) {
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
          bestTermMatchLength = adjacencyValue + 1;
          bestMatchedWordLength = [wordRange wordLength];
          bestMatchLengthValue = matchValue;
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
          bestMatchLengthScore = matchScore;
          break;
        }
      }
    }
    charStatCount -= (adjacencyValue + 1);
  }
  termScore += bestMatchLengthScore;

  // The complete term matching score, the start distance
  // score, and the match spread distance modify the total term match
  // score by multiplying as a percentage.  For instance, a match that
  // starts at the beginning of the search item gets 100%, declining
  // from there. The factor in each case is the minimum percentage possible.

  // Calculate the complete term matching score.
  NSUInteger itemLength = [itemString length];
  CGFloat itemPortionScore
    = gHGSItemPortionFactor + ((1.0 - gHGSItemPortionFactor)
                               * ((CGFloat)termLength / (CGFloat)itemLength));
  termScore *= itemPortionScore;

  // Calculate the start distance score.
  CGFloat portion = (CGFloat)(itemLength - termLength);
  CGFloat charPos = (CGFloat)(charStat[0].charMatchIndex_);
  CGFloat startDistancePortion
    = (portion - charPos) / portion * (1.0 - gHGSStartDistanceFactor);
  CGFloat startDistanceScore = gHGSStartDistanceFactor + startDistancePortion;
  termScore *= startDistanceScore;

  // Calculate the match spread factor.
  if (termLength > 1) {
    CGFloat matchSpread = (CGFloat)(charStat[termLength - 1].charMatchIndex_
                                    - charStat[0].charMatchIndex_ - 1);
    CGFloat maxSpread
      = (CGFloat)(termLength - 1) * gHGSMaximumCharacterDistance - 1.0;
    CGFloat matchSpreadFactor = 1.0 - ((1.0 - gHGSMatchSpreadFactor)
                                       * (matchSpread - 1)
                                       / maxSpread);
    termScore *= matchSpreadFactor;
    
    // If there is an abbreviation match, see if that scores higher.
    if (abbreviation) {

      NSUInteger wordCount = [[itemString wordRanges] count];
      abbreviationScore
        = ((((CGFloat)termLength / (CGFloat)wordCount)
            * ((CGFloat)termLength / (CGFloat)itemLength))
           * HGSCalibratedScore(kHGSCalibratedModerateScore)
           * gHGSItemPortionFactor);
      termScore = MAX(termScore, abbreviationScore);
    }
  }
  
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  if (pMatchDetailsArray) {
    // Collect statistics.
    NSMutableArray *matchDetailsArray = *pMatchDetailsArray;
    if (!matchDetailsArray) {
      matchDetailsArray = [NSMutableArray array];
      *pMatchDetailsArray = matchDetailsArray;
    }
    CGFloat strongScore = HGSCalibratedScore(kHGSCalibratedStrongScore);
    CGFloat weakScore = HGSCalibratedScore(kHGSCalibratedInsignificantScore);
    CGFloat normScore = MAX(0.0, MIN(1.0,
                                     ((termScore - weakScore)
                                      / (strongScore - weakScore))));
    NSMutableDictionary *matchDict
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         [NSNumber numberWithFloat:termScore], kHGSScoreMatchScoreKey,
         [NSNumber numberWithFloat:normScore], kHGSScoreMatchNormScoreKey,
         [NSNumber numberWithFloat:startDistanceScore], kHGSScoreMatchSDSKey,
         [NSNumber numberWithFloat:abbreviationScore], kHGSScoreMatchABSKey,
         [NSNumber numberWithUnsignedInt:bestTermMatchLength],
         kHGSScoreMatchBMLKey,
         [NSNumber numberWithUnsignedInt:bestMatchedWordLength],
         kHGSScoreMatchBWLKey,
         [NSNumber numberWithUnsignedInt:bestMatchLengthValue],
         kHGSScoreMatchBMLVKey,
         [NSNumber numberWithFloat:bestMatchLengthScore],
         kHGSScoreMatchBMLSKey,
         [NSNumber numberWithFloat:itemPortionScore], kHGSScoreMatchPOIMFKey,
         charDetailsArray, kHGSScoreMatchCharDetailKey,
         nil];
    [matchDetailsArray addObject:matchDict];
  }
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  return termScore;
}

#pragma mark Public Scoring Functions

CGFloat HGSScoreTermForItem(NSString *term,
                            HGSScoreString *item) {
  return HGSScoreTermAndDetailsForItem(term, item, NULL);
}

CGFloat HGSScoreTermForString(NSString *term, NSString *string) {
  HGSScoreString *scoreString = [HGSScoreString scoreStringWithString:string];
  return HGSScoreTermForItem(term, scoreString);
}

CGFloat HGSScoreTermsForMainAndOtherItems(NSArray *searchTerms,
                                          HGSScoreString *mainString,
                                          NSArray *otherStrings) {
  // If the caller has not provided a wordRanges then we create and return
  // a new one.
  CGFloat score = 0.0;
  for (NSString *searchTerm in searchTerms) {
    CGFloat itemScore
      = HGSScoreTermForItem(searchTerm, mainString);
    // Check |otherItems| only for better matches than the main
    // search item.
    for (HGSScoreString *otherString in otherStrings) {
      itemScore = MAX(itemScore,
                      HGSScoreTermForItem(searchTerm, otherString)
                      * gHGSOtherItemMultiplier);
    }
    if (itemScore < gHGSMinimumSignificantScore) {
      // Short-circuit this item since at least one search term
      // was not adequately matched.
      score = 0.0;
      break;
    }
    score += itemScore;
  }
  return score;
}

#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

CGFloat HGSScoreTermsForMainAndOtherItemsWithDetails(NSArray *searchTerms,
                                                     HGSScoreString *mainItem,
                                                     NSArray *otherItems,
                                                     NSArray **pScoringDetails) {
  CGFloat score = 0.0;
  NSMutableArray *scoringDetails
    = [NSMutableArray arrayWithCapacity:[otherItems count] + 1];

  for (NSString *searchTerm in searchTerms) {
    NSDictionary *candidateDetails = nil;
    NSUInteger bestItemIndex = 0;
    CGFloat itemScore
      = HGSScoreTermAndDetailsForItem(searchTerm, mainItem, &candidateDetails);
    NSMutableDictionary *scoringDetail
      = HGSBestDetailsFromCandidateDetails(candidateDetails);
    // Check |otherItems| only for better matches than the main
    // search item.
    NSUInteger otherItemIndex = 0;
    for (HGSScoreString *otherItem in otherItems) {
      ++otherItemIndex;
      CGFloat otherScore
        = HGSScoreTermAndDetailsForItem(searchTerm, 
                                        otherItem, 
                                        &candidateDetails)
          * gHGSOtherItemMultiplier;
      if (otherScore > itemScore) {
        itemScore = otherScore;
        bestItemIndex = otherItemIndex;
        scoringDetail = HGSBestDetailsFromCandidateDetails(candidateDetails);
     }
    }
    if (itemScore < gHGSMinimumSignificantScore) {
      // Short-circuit this item since at least one search term
      // was not adequately matched.
      score = 0.0;
      [scoringDetails removeAllObjects];
      break;
    }
    if (scoringDetail) {
      [scoringDetail setObject:[NSNumber numberWithUnsignedInt:bestItemIndex]
                        forKey:@"itemIndex"];
      [scoringDetail setObject:[NSNumber numberWithFloat:itemScore]
                        forKey:@"itemScore"];
      [scoringDetails addObject:scoringDetail];
    } else {
      [scoringDetails addObject:[NSNull null]];
    }
    score += itemScore;
  }
  *pScoringDetails = scoringDetails;
  return score;
}

NSArray *HGSScoreTermsAndDetailsForItem(NSArray *searchTerms,
                                        HGSScoreString *item,
                                        NSArray **pSearchTermsDetails) {
  NSUInteger searchTermCount = [searchTerms count];
  NSMutableArray *searchTermScores
    = [NSMutableArray arrayWithCapacity:searchTermCount];
  NSMutableArray *searchTermsDetails = nil;
  NSDictionary *matchDetails = nil;
  NSDictionary **pMatchDetails = (pSearchTermsDetails) ? &matchDetails : NULL;
  for (NSString *searchTerm in searchTerms) {
    CGFloat searchTermScore = HGSScoreTermAndDetailsForItem(searchTerm,
                                                            item,
                                                            pMatchDetails);
    NSNumber *bestScoreNumber = [NSNumber numberWithFloat:searchTermScore];
    [searchTermScores addObject:bestScoreNumber];
    if (pSearchTermsDetails) {
      if (!searchTermsDetails) {
        searchTermsDetails = [NSMutableArray arrayWithCapacity:searchTermCount];
        *pSearchTermsDetails = searchTermsDetails;
      }
      if (matchDetails) {
        [searchTermsDetails addObject:matchDetails];
      } else {
        [searchTermsDetails addObject:[NSNull null]];
      }
    }
  }
  return searchTermScores;
}

#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS



BOOL HGSValidateTokenizedString(NSString *tokenizedString) {
  static NSMutableCharacterSet *antiNumberCharacterSet = nil;
  static NSMutableCharacterSet *antiWordCharacterSet = nil;
  @synchronized (@"HGSValidateTokenizedString") {
    if (!antiNumberCharacterSet) {
      antiNumberCharacterSet = [NSMutableCharacterSet decimalDigitCharacterSet];
      [antiNumberCharacterSet addCharactersInString:@",."];
      [antiNumberCharacterSet invert];
      [antiNumberCharacterSet retain];  // Leak
    }
    
    if (!antiWordCharacterSet) {
      antiWordCharacterSet 
        = [NSMutableCharacterSet capitalizedLetterCharacterSet];
      NSCharacterSet *puncSet = [NSCharacterSet punctuationCharacterSet];
      [antiWordCharacterSet formUnionWithCharacterSet:puncSet];
      [antiWordCharacterSet removeCharactersInString:@"'‚Äô"];
      [antiWordCharacterSet retain];  // Leak
    }
  }
  BOOL isNormalized = YES;
  NSArray *strings = [tokenizedString componentsSeparatedByString:@" "];
  for (NSString *string in strings) {
    // See if it's a valid number, which can have digits, commas and periods.
    NSCharacterSet *decDigitSet = [NSCharacterSet decimalDigitCharacterSet];
    NSRange testRange
      = [string rangeOfCharacterFromSet:decDigitSet];
    if (testRange.location != NSNotFound) {
      // A potential number was found but insure that it does not contain
      // any other types of characters.
      testRange = [string rangeOfCharacterFromSet:antiNumberCharacterSet];
      isNormalized = (testRange.location == NSNotFound);
    } else {
      // Should be some kind of word with no punctuation or caps but
      // interstiched apostrophe's are okay, just not by themselves.
      isNormalized = (![string isEqualToString:@"'"]
                      && ![string isEqualToString:@"’"]);
      if (isNormalized) {
        testRange = [string rangeOfCharacterFromSet:antiWordCharacterSet];
        isNormalized = (testRange.location == NSNotFound);
      }
    }
    if (!isNormalized) {
      break;
    }
  }
  return isNormalized;
}

CGFloat HGSScoreTermAndDetailsForItem(NSString *termString,
                                      HGSScoreString *itemString,
                                      NSDictionary **pSearchTermDetails) {
#if DEBUG
  // Verify that the term we are receiving is normalized, i.e.
  // do not contain any caps, punctuation, etc.  Numbers are allowed
  // to contain commas and periods.
  if (!HGSValidateTokenizedString(termString)) {
    HGSLog(@"Term string not properly tokenized: '%@'", termString);
  }
  // TODO(mrossetti): This occurs frequently and the sources should be changed
  // so throttle it back for now otherwise it pollutes the console.
  static NSUInteger singleWordWarningCount = 0;
  if ([[termString componentsSeparatedByString:@" "] count] > 1
      && singleWordWarningCount++ < 50) {
    HGSLog(@"Term string is not single word: '%@'", termString);
  }
#endif // DEBUG
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  NSMutableArray *matchDetailsArray = nil;
  if (pSearchTermDetails) {
    *pSearchTermDetails = nil;
  }
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
  CGFloat bestScore = 0.0;
  CFStringRef termRef = (CFStringRef)termString;
  CFStringRef itemRef = (CFStringRef)[itemString string];
  CFIndex termLength = CFStringGetLength(termRef);
  CFIndex itemLength = CFStringGetLength(itemRef);
  if (termLength > 0 && termLength < kHGSMaximumItemCharactersScanned) {
    if (termLength < itemLength) {
      // Max out itemLength to desired maximum.
      itemLength = MIN(itemLength, gHGSMaximumItemCharactersScanned);
      UniChar termChars[kHGSMaximumItemCharactersScanned];
      const UniChar *term = CFStringGetCharactersPtr(termRef);
      if (!term) {
        term = termChars;
        CFStringGetCharacters(termRef, CFRangeMake(0, termLength),
                              (UniChar *)term);
      }
      UniChar itemChars[kHGSMaximumItemCharactersScanned];
      const UniChar *item = CFStringGetCharactersPtr(itemRef);
      if (!item) {
        item = itemChars;
        CFStringGetCharacters(itemRef, CFRangeMake(0, itemLength),
                              (UniChar *)item);
      }

      CGFloat termScore = 0.0;  // Score of term match.
      HGSTermCharStat charStats[kHGSMaximumItemCharactersScanned];
      HGSTermCharStat *charStat = charStats;
      CFIndex termCharIndex = 0;  // Current term character being processed.
      BOOL done = NO;
      do {
        CFIndex itemCharIndex = 0;  // Position of term char in item.
        if (termCharIndex < termLength) {
          itemCharIndex = (termCharIndex > 0)
                          ? charStat[termCharIndex - 1].charMatchIndex_ + 1
                          : 0;
        } else {
          // Done with a match.  Calculate the term's total score.
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
          NSMutableArray **pMatchDetailsArray
            = (pSearchTermDetails) ? &matchDetailsArray : nil;
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
          termScore = ScoreTerm(termLength, itemString, charStat
#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
                                , pMatchDetailsArray
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
                                );
          if (termScore > bestScore) {
            bestScore = termScore;
          }

          // Scan forward for the next occurrence of this character.
          --termCharIndex;
          HGSResetCharStat(&charStat[termCharIndex]);
          ++charStat[termCharIndex].charMatchIndex_;
          itemCharIndex = charStat[termCharIndex].charMatchIndex_;
        }

        BOOL charDone = NO;
        do {
          if (itemCharIndex < (itemLength - termLength + termCharIndex + 1)) {
            UniChar termChar = term[termCharIndex];
            UniChar itemChar = item[itemCharIndex];
            if (termChar == itemChar) {
              // Score this character and (optionally) collect statistics.
              HGSResetCharStat(&charStat[termCharIndex]);
              charStat[termCharIndex].charMatchIndex_ = itemCharIndex;
              NSUInteger firstCharacterValue = 0;
              NSUInteger adjacencyValue = 0;

              // First character in word score or camelCase/adjacency score.
              UniChar prevChar = (itemCharIndex > 0)
                                 ? item[itemCharIndex - 1]
                                 : 0;
              if (itemCharIndex == 0 || prevChar == ' ') {
                // First character in word value
                firstCharacterValue = 1;
                if (termCharIndex > 0 && itemCharIndex > 0) {
                  firstCharacterValue
                    += charStat[termCharIndex - 1].firstCharacterValue_;
                  // Adjacency value (for word break adjacency)
                  if (itemCharIndex
                       == (charStat[termCharIndex - 1].charMatchIndex_ + 2)) {
                    adjacencyValue
                      = charStat[termCharIndex - 1].adjacencyValue_ + 1;
                    charStat[termCharIndex].adjacencyValue_ = adjacencyValue;
                  }
                }
                charStat[termCharIndex].firstCharacterValue_ = firstCharacterValue;
              } else {
                // Adjacency value (for non-word break adjacency)
                if (termCharIndex > 0
                    && itemCharIndex > 0
                    && itemCharIndex
                       == (charStat[termCharIndex - 1].charMatchIndex_ + 1)) {
                  adjacencyValue
                    = charStat[termCharIndex - 1].adjacencyValue_ + 1;
                  charStat[termCharIndex].adjacencyValue_ = adjacencyValue;
                }
              }
              ++termCharIndex;  // Move to next term character.
              charDone = YES;
            } else {
              ++itemCharIndex;  // Move to the next item character.
              if (termCharIndex > 0
                  && (itemCharIndex - charStat[termCharIndex - 1].charMatchIndex_)
                      > gHGSMaximumCharacterDistance) {
                // Characters are too far apart.  Give up on this character
                // and back up to the previous character.
                --termCharIndex;
                HGSResetCharStat(&charStat[termCharIndex]);
                ++charStat[termCharIndex].charMatchIndex_;
                itemCharIndex = charStat[termCharIndex].charMatchIndex_;
              }
            }
          } else {
            // No more of the character at term[cc] in item so either
            // step back one character in the term or else we're done.
            if (termCharIndex > 0) {
              --termCharIndex;
              HGSResetCharStat(&charStat[termCharIndex]);
              ++charStat[termCharIndex].charMatchIndex_;
              itemCharIndex = charStat[termCharIndex].charMatchIndex_;
            } else {
              done = YES;
            }
          }
        } while (!charDone && !done);
      } while (!done);

#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
      // Encapsulate the matchDetails in a dictionary.
      if (pSearchTermDetails) {
        NSNumber *termMatchCount
          = [NSNumber numberWithUnsignedInt:[matchDetailsArray count]];
        NSNumber *bestScoreNumber = [NSNumber numberWithFloat:bestScore];
        CGFloat strongScore = HGSCalibratedScore(kHGSCalibratedStrongScore);
        CGFloat weakScore = HGSCalibratedScore(kHGSCalibratedInsignificantScore);
        CGFloat normScore = MAX(0.0, MIN(1.0,
                                         ((bestScore - weakScore)
                                          / (strongScore - weakScore))));
        NSNumber *normScoreNumber = [NSNumber numberWithFloat:normScore];
        NSDictionary *searchTermDetails
          = [NSDictionary dictionaryWithObjectsAndKeys:
             termString, kHGSScoreTermWordKey,
             bestScoreNumber, kHGSScoreTermBestScoreKey,
             normScoreNumber, kHGSScoreTermNormScoreKey,
             termMatchCount, kHGSScoreTermMatchCountKey,
             matchDetailsArray, kHGSScoreTermMatchDetailKey,
             nil];
        *pSearchTermDetails = searchTermDetails;
      }
#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
    } else if ([termString isEqualToString:[itemString string]]) {
      bestScore = gHGSPerfectMatchScore;
    }
  }
  return bestScore;
}

void HGSResetCharStat(HGSTermCharStat *pCharStat) {
  pCharStat->firstCharacterValue_ = 0;
  pCharStat->adjacencyValue_ = 0;
}

#if HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

NSMutableDictionary *HGSBestDetailsFromCandidateDetails(NSDictionary *
                                                        candidateDetails) {
  NSMutableDictionary *details = nil;
  // Find the highest scoring candidate.
  NSDictionary *bestCandidate = nil;
  CGFloat bestScore = 0.0;

  NSArray *candidates
    = [candidateDetails objectForKey:kHGSScoreTermMatchDetailKey];

  for (NSDictionary *candidate in candidates) {
    NSNumber *scoreNumber = [candidate objectForKey:kHGSScoreMatchScoreKey];
    CGFloat score = [scoreNumber floatValue];
    if (score > bestScore) {
      bestCandidate = candidate;
      bestScore = score;
    }
  }
  if (bestCandidate) {
    // Extract the desired keys.
    NSSet *detailKeys = [NSSet setWithObjects: kHGSScoreMatchSDSKey,
                         kHGSScoreMatchABSKey,
                         kHGSScoreMatchBMLSKey,
                         kHGSScoreMatchPOIMFKey,
                         kHGSScoreMatchCharDetailKey,
                         nil];
    details = [NSMutableDictionary dictionaryWithCapacity:[detailKeys count]];
    for (NSString *key in detailKeys) {
      id detail = [bestCandidate objectForKey:key];
      [details setObject:detail forKey:key];
    }
  }
  return details;
}

#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS


@implementation HGSItemWordRange

@synthesize wordStart = wordStart_;
@synthesize wordLength = wordLength_;

+ (id)wordRangeWithStart:(NSUInteger)wordStart
                  length:(NSUInteger)wordLength {
  HGSItemWordRange *wordRange
    = [[[[self class] alloc] initWithStart:wordStart length:wordLength]
       autorelease];
  return wordRange;
}

- (id)initWithStart:(NSUInteger)wordStart
             length:(NSUInteger)wordLength {
  if ((self = [super init])) {
    if (wordLength > 0) {
      wordStart_ = wordStart;
      wordLength_ = wordLength;
    } else {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)init {
  self = [self initWithStart:0 length:0];
  return self;
}

// COV_NF_START
- (NSString *)description {
  NSString *description
    = [NSString stringWithFormat:@"<%@:%p> start: %d, length: %d",
       [self class], self, [self wordStart], [self wordLength]];
  return description;
}
// COV_NF_END

@end

@implementation HGSScoreString
@synthesize string = string_;
@synthesize wordRanges = wordRanges_;

+ (id)scoreStringWithString:(NSString *)string {
  return [[[[self class] alloc] initWithString:string] autorelease];
}

+ (id)scoreStringArrayWithStringArray:(NSArray *)strings {
  NSMutableArray *array = [NSMutableArray arrayWithCapacity:[strings count]];
  for (NSString *string in strings) {
    [array addObject:[HGSScoreString scoreStringWithString:string]];
  }
  return array;
}

- (id)initWithString:(NSString *)string {
  if ((self = [super init])) {
    string_ = [string copy];
    wordRanges_ = [[self buildWordRangesForString:string_] retain];
#if DEBUG
    if (!HGSValidateTokenizedString(string_)) {
      HGSLog(@"Item string not properly tokenized: '%@'", string_);
    }
#endif
  }
  return self;
}

- (void)dealloc {
  [string_ release];
  [wordRanges_ release];
  [super dealloc];
}

- (NSArray *)buildWordRangesForString:(NSString *)wordString {
  NSArray *revWordRanges = nil;
  NSArray *wordList = [wordString componentsSeparatedByString:@" "];
  require([wordList count], BuildWordRangesFailed);
  NSUInteger wordCount = [wordList count];
  NSMutableArray *forWordRanges = [NSMutableArray arrayWithCapacity:wordCount];
  NSUInteger wordStart = 0;
  for (NSString *word in wordList) {
    NSUInteger wordLength = [word length];
    if (wordLength) {
      HGSItemWordRange *wordRange
        = [HGSItemWordRange wordRangeWithStart:wordStart
                                        length:wordLength];
      [forWordRanges addObject:wordRange];
    }
    wordStart += (wordLength + 1);
  }
  // Reverse the results
  NSEnumerator *revRangeEnum = [forWordRanges reverseObjectEnumerator];
  revWordRanges = [revRangeEnum allObjects];
BuildWordRangesFailed:
  return revWordRanges;
}

- (NSUInteger)length {
  return [string_ length];
}
@end


