//
//  HGSAbbreviationRanker.m
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

#import "HGSAbbreviationRanker.h"
#import <AssertMacros.h>

// TODO(dmaclach): possibly make these variables we can adjust?
//                 If we do so, make sure that they don't affect performance
//                 too badly.
static const CGFloat kHGSIsPrefixMultiplier = 1.0;
static const CGFloat kHGSIsFrontOfWordMultiplier = 0.8;
static const CGFloat kHGSIsWeakHitMultipier = 0.6;
static const CGFloat kHGSIsStrongMissMultiplier = 0.5;
static const CGFloat kHGSNoMatchScore = 0.0;

CGFloat HGSScoreForAbbreviation(NSString *nsStr,
                                NSString *nsAbbr, 
                                NSMutableIndexSet** outHitMask) {
  // TODO(dmaclach) add support for higher plane UTF16
  CGFloat score = kHGSNoMatchScore;
  require_quiet(nsStr && nsAbbr, BadParams);
  CFStringRef str = (CFStringRef)nsStr;
  CFStringRef abbr = (CFStringRef)nsAbbr;
  CFIndex strLength = CFStringGetLength(str);
  CFIndex abbrLength = CFStringGetLength(abbr);
  CFCharacterSetRef whiteSpaceSet 
    = CFCharacterSetGetPredefined(kCFCharacterSetWhitespace);
  Boolean ownStrChars = false;
  Boolean ownAbbrChars = false;
  
  const UniChar *strChars = CFStringGetCharactersPtr(str);
  if (!strChars) {
    strChars = malloc(sizeof(unichar) * strLength);
    require(strChars, CouldNotAllocateStrChars);
    ownStrChars = true;
    CFStringGetCharacters(str, CFRangeMake(0, strLength), (UniChar *)strChars);
  }
  const UniChar *abbrChars = CFStringGetCharactersPtr(abbr);
  if (!abbrChars) {
    abbrChars = malloc(sizeof(unichar) * abbrLength);
    require(abbrChars, CouldNotAllocateAbbrChars);
    ownAbbrChars = true;
    CFStringGetCharacters(abbr, 
                          CFRangeMake(0, abbrLength), 
                          (UniChar *)abbrChars);
  }
  CFRange *matchRanges = calloc(sizeof(CFRange), abbrLength);
  require(matchRanges, CouldNotAllocateRanges);
  BOOL *matchRangeDecent = calloc(1, abbrLength);
  require(matchRangeDecent, CouldNotAllocateRangesDecent);
  
  CFIndex stringIndex = 0;
  CFIndex abbrIndex = 0;
  CFIndex currMatchRange = 0;
  for (; stringIndex < strLength && abbrIndex < abbrLength; ++stringIndex) {
    UniChar abbrChar = abbrChars[abbrIndex];
    UniChar strChar = strChars[stringIndex];
    if (abbrChar == strChar) {
      if (matchRanges[currMatchRange].length == 0) {
        matchRanges[currMatchRange].location = stringIndex;
      }
      matchRanges[currMatchRange].length += 1;
      abbrIndex += 1;
    } else {
      // We missed a character
      if (matchRanges[currMatchRange].length > 0) {
        currMatchRange += 1;
      }
      // Let's scan forward and see if our missing character hits the 
      // first letter of an upcoming word
      for (CFIndex nextHitIndex = stringIndex; 
           nextHitIndex < strLength; 
           ++nextHitIndex) {
        UniChar nextStrChar = strChars[nextHitIndex];
        if (CFCharacterSetIsCharacterMember(whiteSpaceSet, nextStrChar)) {
          if (nextHitIndex < strLength - 1) {
            nextStrChar = strChars[nextHitIndex + 1];
            if (nextStrChar == abbrChar) {
              // We've got a front of word match. Let's use it instead.
              stringIndex = nextHitIndex;
            }
          }
          break;
        }
      }
    }
  }
  currMatchRange += 1;
  if (abbrIndex != abbrLength) {
    score = 0;
  } else {
    // Time to compare our ranges
    if (outHitMask) {
      *outHitMask = [NSMutableIndexSet indexSet];
    }
    for (CFIndex i = 0; i < currMatchRange; ++i) {
      if (outHitMask) {
        [*outHitMask addIndexesInRange:((NSRange*)matchRanges)[i]];
      }
      CFIndex location = matchRanges[i].location;
      if (location == 0) {
        // We have a prefix match
        score = matchRanges[i].length * kHGSIsPrefixMultiplier;
        matchRangeDecent[0] = YES;
      } else {
        if (CFCharacterSetIsCharacterMember(whiteSpaceSet, 
                                            strChars[location - 1])) {
          score += matchRanges[i].length * kHGSIsFrontOfWordMultiplier;
          matchRangeDecent[i] = YES;
        } else {
          matchRangeDecent[i] = matchRanges[i].length >= 3;
          score += matchRanges[i].length * kHGSIsWeakHitMultipier;
        }
        // Now match for the missed characters
        if (matchRangeDecent[i]) {
          if (i == 0) {
            score += matchRanges[i].location * kHGSIsStrongMissMultiplier;
          } else if (matchRangeDecent[i - 1]) {
            score += ((matchRanges[i].location - 
                      (matchRanges[i - 1].location + matchRanges[i-1].length))
                      * kHGSIsStrongMissMultiplier);
          }
        }
      }
    }
    score += ((strLength - 
               (matchRanges[currMatchRange - 1].location 
                + matchRanges[currMatchRange - 1].length)) 
              * kHGSIsStrongMissMultiplier);
    score /= strLength;
    if (score < 0.3) {
      score = 0;
    }
  }
  
  free(matchRangeDecent);
CouldNotAllocateRangesDecent:
  free(matchRanges);
CouldNotAllocateRanges:
  if (ownAbbrChars) {
    free((UniChar *)abbrChars);
  }
CouldNotAllocateAbbrChars:
  if (ownStrChars) {
    free((UniChar *)strChars);
  }
CouldNotAllocateStrChars:
BadParams:
  return score;
}
