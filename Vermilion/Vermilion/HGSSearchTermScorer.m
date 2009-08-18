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
#import "HGSLog.h"


static CGFloat gCharacterMatchFactor_ = 1.0;  // Basic char match factor.
static CGFloat gFirstCharacterInWordFactor_ = 3.0;  // First-char-in-word factor.
static CGFloat gAdjacencyFactor_ = 3.8;  // Adjacency factor.
// Start distance factor representing the minimum percentage allowed when
// applying the start distance score.  This should be > 0 and <= 1.00.
static CGFloat gStartDistanceFactor_ = 0.8;
static CGFloat gWordPortionFactor_ = 5.0; // Portion of complete word factor.
// Item portion of complete item factor representing the minimum percentage
// allowed when applying the start distance score.  This should be > 0 and
// <= 1.00.
static CGFloat gItemPortionFactor_ = 0.8;
static NSUInteger gMaximumCharacterDistance_ = 22;  // Maximum adjacency distance.
// Maximum distance we will scan into the search item for matches.
static NSUInteger gMaximumItemCharactersScanned_ = 250;

// Keys to search term detail dictionary items.
NSString *const kHGSScoreTermWordKey = @"searchTerm";
NSString *const kHGSScoreTermBestScoreKey = @"bestScore";
NSString *const kHGSScoreTermMatchCountKey = @"matchCount";
NSString *const kHGSScoreTermMatchDetailKey = @"matchDetail";

// Keys to match detail dictionary items.
NSString *const kHGSScoreMatchScoreKey = @"score";
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


// Structure containing information on each search term
// character matching and scoring results.
typedef struct {
  // Postition within search item that character was found.
  NSUInteger charMatchIndex_;
  // Value for being first character in a search item word.
  NSUInteger firstCharacterValue_;
  NSUInteger adjacencyValue_;  // Character adjacency value.
} HGSTermCharStat;

// Utility function to clear a charStat.
void ResetCharStat(HGSTermCharStat *pCharStat);


@interface HGSItemWordRange ()

+ (id)wordRangeWithStart:(NSUInteger)wordStart
                  length:(NSUInteger)wordLength;

- (id)initWithStart:(NSUInteger)wordStart
             length:(NSUInteger)wordLength;

@end


void HGSSetSearchTermScoringFactors(CGFloat characterMatchFactor,
                                    CGFloat firstCharacterInWordFactor,
                                    CGFloat adjacencyFactor,
                                    CGFloat startDistanceFactor,
                                    CGFloat wordPortionFactor,
                                    CGFloat itemPortionFactor,
                                    NSUInteger maximumCharacterDistance,
                                    NSUInteger maximumItemCharactersScanned) {
  gCharacterMatchFactor_ = characterMatchFactor;
  gFirstCharacterInWordFactor_ = firstCharacterInWordFactor;
  gAdjacencyFactor_ = adjacencyFactor;
  gStartDistanceFactor_ = startDistanceFactor;
  gWordPortionFactor_ = wordPortionFactor;
  gItemPortionFactor_ = itemPortionFactor;
  gMaximumCharacterDistance_ = maximumCharacterDistance;
  gMaximumItemCharactersScanned_ = maximumItemCharactersScanned;
}

NSArray *BuildWordRanges(NSString *wordString) {
  NSArray *revWordRanges = nil;
  NSArray *wordList = [wordString componentsSeparatedByString:@" "];
  require([wordList count], BuildWordRangesFailed);
  NSUInteger wordCount = [wordList count];
  NSMutableArray *forWordRanges = [NSMutableArray arrayWithCapacity:wordCount];
  NSUInteger wordStart = 0;
  for (NSString *word in wordList) {
    NSUInteger wordLength = [word length];
    HGSItemWordRange *wordRange
      = [HGSItemWordRange wordRangeWithStart:wordStart
                                      length:wordLength];
    [forWordRanges addObject:wordRange];
    wordStart += (wordLength + 1);
  }
  // Reverse the results
  NSEnumerator *revRangeEnum = [forWordRanges reverseObjectEnumerator];
  revWordRanges = [revRangeEnum allObjects];
BuildWordRangesFailed:
  return revWordRanges;
}

CGFloat HGSScoreTermForItem(NSString *term,
                            NSString *item, 
                            NSArray **pWordRanges) {
  return HGSScoreTermAndDetailsForItem(term, item, pWordRanges, NULL);
}

NSArray *HGSScoreTermsForItem(NSArray *searchTerms,
                              NSString *item, 
                              NSArray **pWordRanges) {
  return HGSScoreTermsAndDetailsForItem(searchTerms, item, pWordRanges, NULL);
}

NSArray *HGSScoreTermsAndDetailsForItem(NSArray *searchTerms,
                                        NSString *item, 
                                        NSArray **pWordRanges, 
                                        NSArray **pSearchTermsDetails) {
  NSUInteger searchTermCount = [searchTerms count];
  NSMutableArray *searchTermScores
    = [NSMutableArray arrayWithCapacity:searchTermCount];
  // If the caller has not provided a wordRanges then we create and return
  // a new one.
  NSArray **pTempWordRanges = pWordRanges;
  NSArray *tempWordRanges = nil;
  if (!pWordRanges) {
    pTempWordRanges = &tempWordRanges;
  }
  NSMutableArray *searchTermsDetails = nil;
  NSDictionary *matchDetails = nil;
  NSDictionary **pMatchDetails = (pSearchTermsDetails) ? &matchDetails : NULL;
  for (NSString *searchTerm in searchTerms) {
    CGFloat searchTermScore = HGSScoreTermAndDetailsForItem(searchTerm,
                                                            item,
                                                            pTempWordRanges,
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

CGFloat HGSScoreTermAndDetailsForItem(NSString *term,
                                      NSString *item, 
                                      NSArray **pWordRanges, 
                                      NSDictionary **pSearchTermDetails) {
  // TODO(mrossetti): Instead of calculating the wordRanges herein, consider
  // having the search source pre-calculate the word ranges.
  NSMutableArray *matchDetailsArray = nil;
  if (pSearchTermDetails) {
    *pSearchTermDetails = nil;
  }
  CGFloat bestScore = 0.0;
  NSUInteger termLength = [term length];
  NSUInteger itemLength = [item length];
  if (termLength < gMaximumItemCharactersScanned_) {
    if (termLength < itemLength) {
      CGFloat termMatchScore = 0.0;  // Score of term match.
      HGSTermCharStat *charStat = calloc(sizeof(HGSTermCharStat), termLength);
      HGSAssert(charStat, NULL);
      NSArray *wordRanges = (pWordRanges) ? *pWordRanges : nil;
      NSUInteger termCharIndex = 0;  // Current term character being processed.
      BOOL done = NO;
      do {
        NSUInteger itemCharIndex = 0;  // Position of term char in item.
        if (termCharIndex < termLength) {
          itemCharIndex = (termCharIndex)
                          ? charStat[termCharIndex - 1].charMatchIndex_ + 1
                          : 0;
        } else {
          // Done with a match.  Calculate the term's total score.
          termMatchScore = 0.0;
          // Determine if all are first characters because we don't count
          // a first character value unless they're _all_ first characters.
          BOOL allFirstCharacter = YES;
          for (NSUInteger cj = 0; cj < termLength; ++cj) {
            if (charStat[cj].firstCharacterValue_ == 0) {
              allFirstCharacter = NO;
              break;
            }
          }
          // Calculate the individual charScores and accumulate term scores.
          NSMutableArray *charDetailsArray
            = (pSearchTermDetails)
              ? [NSMutableArray arrayWithCapacity:termLength]
              : nil;
          CGFloat abbrevationScore = 0.0;
          for (NSUInteger ci = 0; ci < termLength; ++ci) {
            CGFloat charScore = gCharacterMatchFactor_;
            NSUInteger firstCharacterValue = charStat[ci].firstCharacterValue_;
            CGFloat firstCharacterScore
              = (allFirstCharacter && firstCharacterValue != 0)
                ? (CGFloat)(firstCharacterValue) * gFirstCharacterInWordFactor_
                : 0.0;
            abbrevationScore += firstCharacterScore;
            CGFloat adjacencyScore
              = (CGFloat)(charStat[ci].adjacencyValue_) * gAdjacencyFactor_;
            charScore += adjacencyScore;
            termMatchScore += charScore;
            // Collect statistics.
            if (pSearchTermDetails) {
              NSMutableDictionary *charDict
                = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithUnsignedInt:charStat[ci].charMatchIndex_],
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
          }

          termMatchScore += abbrevationScore;  // Add in the abbreviation score.
          
          // Determine the best complete word match length score.
          NSUInteger bestTermMatchLength = 0;  // Best word match length
          NSUInteger bestMatchedWordLength = 0;  // Best word length
          CGFloat bestMatchLengthValue = 0.0;  // Best word match length value
          CGFloat bestMatchLengthScore = 0.0;  // Best word match length score
          // Scan charStats in reverse to determine best match.
          NSInteger charStatCount = termLength;
          while (charStatCount > 0) {
            NSUInteger charStatItem = charStatCount - 1;
            NSUInteger adjacencyValue = charStat[charStatItem].adjacencyValue_;
            if (adjacencyValue > 0) {
              if (!wordRanges) {
                wordRanges = BuildWordRanges(item);
                if (pWordRanges) {
                  *pWordRanges = wordRanges;
                }
              }
              for (HGSItemWordRange *wordRange in wordRanges) {
                if (charStat[charStatItem].charMatchIndex_
                    >= [wordRange wordStart]) {
                  NSUInteger wordLength = [wordRange wordLength];
                  CGFloat matchValue = (CGFloat)(adjacencyValue + 1)
                                       / (CGFloat)wordLength;
                  CGFloat matchScore = gWordPortionFactor_ * matchValue;
                  if (matchScore > bestMatchLengthScore) {
                    bestTermMatchLength = adjacencyValue + 1;
                    bestMatchedWordLength = [wordRange wordLength];
                    bestMatchLengthValue = matchValue;
                    bestMatchLengthScore = matchScore;
                    break;
                  }
                }
              }
            }
            charStatCount -= (adjacencyValue + 1);
          }
          termMatchScore += bestMatchLengthScore;
          
          // The complete term matching score and the start distance
          // scores modify the total term match score by multiplying
          // as a percentage.  For instance, a match that starts at the
          // beginning of the search item gets 100%, declining from there.
          // The factor in each case is the minimum percentage possible.
          
          // Calculate the complete term matching score.
          CGFloat itemPortionScore
            = gItemPortionFactor_
              + ((1.0 - gItemPortionFactor_)
                 * ((CGFloat)termLength / (CGFloat)itemLength));
          termMatchScore *= itemPortionScore;
          
          // Calculate the start distance score.
          NSUInteger potentialPortion = itemLength - termLength;
          NSUInteger portionPosition = potentialPortion - charStat[0].charMatchIndex_;
          CGFloat startDistanceScore
            = gStartDistanceFactor_
              + ((CGFloat)portionPosition / (CGFloat)potentialPortion
                 * (1.0 - gStartDistanceFactor_));
          termMatchScore *= startDistanceScore;
          if (termMatchScore > bestScore) {
            bestScore = termMatchScore;
          }
          
          if (pSearchTermDetails) {
            if (!matchDetailsArray) {
              matchDetailsArray = [NSMutableArray array];
            }
            if (matchDetailsArray) {
              // Collect statistics.
              NSMutableDictionary *matchDict
                = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                   [NSNumber numberWithFloat:termMatchScore],
                   kHGSScoreMatchScoreKey,
                   [NSNumber numberWithFloat:startDistanceScore],
                   kHGSScoreMatchSDSKey,
                   [NSNumber numberWithFloat:abbrevationScore],
                   kHGSScoreMatchABSKey,
                   [NSNumber numberWithUnsignedInt:bestTermMatchLength],
                   kHGSScoreMatchBMLKey,
                   [NSNumber numberWithUnsignedInt:bestMatchedWordLength],
                   kHGSScoreMatchBWLKey,
                   [NSNumber numberWithUnsignedInt:bestMatchLengthValue],
                   kHGSScoreMatchBMLVKey,
                   [NSNumber numberWithFloat:bestMatchLengthScore],
                   kHGSScoreMatchBMLSKey,
                   [NSNumber numberWithFloat:itemPortionScore],
                   kHGSScoreMatchPOIMFKey,
                   charDetailsArray, kHGSScoreMatchCharDetailKey,
                   nil];
              [matchDetailsArray addObject:matchDict];
            }
          }
          // Scan forward for the next occurrence of this character.
          --termCharIndex;
          ResetCharStat(&charStat[termCharIndex]);
          ++charStat[termCharIndex].charMatchIndex_;
          itemCharIndex = charStat[termCharIndex].charMatchIndex_;
        }
        
        BOOL charDone = NO;
        do {
          if (itemCharIndex < (itemLength - termLength + termCharIndex + 1)) {
            unichar termChar = [term characterAtIndex:termCharIndex];
            unichar itemChar = [item characterAtIndex:itemCharIndex];
            if (termChar == itemChar) {
              // Score this character and (optionally) collect statistics.
              charStat[termCharIndex].charMatchIndex_ = itemCharIndex;
              NSUInteger firstCharacterValue = 0;
              NSUInteger adjacencyValue = 0;
              
              // First character in word score or camelCase/adjacency score.
              unichar prevChar = (itemCharIndex)
                                 ? [item characterAtIndex:(itemCharIndex - 1)]
                                 : 0;
              if (itemCharIndex == 0 || prevChar == ' ') {
                // First character in word value
                firstCharacterValue = 1;
                if (termCharIndex && itemCharIndex > 0) {
                  firstCharacterValue
                    += charStat[termCharIndex - 1].firstCharacterValue_;
                }
                charStat[termCharIndex].firstCharacterValue_ = firstCharacterValue;
              } else {
                // Adjacency value (a word break resets adjacency chain)
                if (termCharIndex
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
              if (termCharIndex
                  && (itemCharIndex - charStat[termCharIndex - 1].charMatchIndex_)
                      > gMaximumCharacterDistance_) {
                // Characters are too far apart.  Give up on this character
                // and back up to the previous character.
                --termCharIndex;
                ResetCharStat(&charStat[termCharIndex]);
                ++charStat[termCharIndex].charMatchIndex_;
                itemCharIndex = charStat[termCharIndex].charMatchIndex_;
              }
            }
          } else {
            // No more of the character at term[cc] in item so either
            // step back one character in the term or else we're done.
            if (termCharIndex) {
              --termCharIndex;
              ResetCharStat(&charStat[termCharIndex]);
              ++charStat[termCharIndex].charMatchIndex_;
              itemCharIndex = charStat[termCharIndex].charMatchIndex_;
            } else {
              done = YES;
            }
          }
        } while (!charDone && !done);
      } while (!done);
      // Encapsulate the matchDetails in a dictionary.
      if (pSearchTermDetails) {
        NSNumber *termMatchCount
          = [NSNumber numberWithUnsignedInt:[matchDetailsArray count]];
        NSNumber *bestScoreNumber = [NSNumber numberWithFloat:bestScore];
        NSDictionary *searchTermDetails
          = [NSDictionary dictionaryWithObjectsAndKeys:
             term, kHGSScoreTermWordKey,
             bestScoreNumber, kHGSScoreTermBestScoreKey,
             termMatchCount, kHGSScoreTermMatchCountKey,
             matchDetailsArray, kHGSScoreTermMatchDetailKey,
             nil];
        *pSearchTermDetails = searchTermDetails;
      }
    } else if ([term isEqualToString:item]) {
      bestScore = 10000.0;
    }
  }
  return bestScore;
}

void ResetCharStat(HGSTermCharStat *pCharStat) {
  pCharStat->firstCharacterValue_ = 0;
  pCharStat->adjacencyValue_ = 0;
}


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
    wordStart_ = wordStart;
    wordLength_ = wordLength;
  }
  return self;
}

- (NSString *)description {
  NSString *description
    = [NSString stringWithFormat:@"<%@:%p> start: %d, length: %d",
       [self class], self, [self wordStart], [self wordLength]];
  return description;
}

@end

