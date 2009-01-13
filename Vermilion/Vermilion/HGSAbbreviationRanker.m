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


const float kIgnoredCharactersScore = 0.9f;
const float kMinorSkippedCharactersPenalty = 0.15f;
const float kMajorSkippedCharactersPenalty = 1.0f;
const float kNoMatchScore = 0.0f;

CGFloat HGSScoreForAbbreviationWithRanges(CFStringRef str, 
                                          CFStringRef abbr, 
                                          NSMutableIndexSet* mask, 
                                          CFRange strRange, 
                                          CFRange abbrRange);

CGFloat HGSScoreForAbbreviation(CFStringRef str,
                                CFStringRef abbr, 
                                NSMutableIndexSet* mask) {
  if (!str) return 0.0;
  return HGSScoreForAbbreviationWithRanges(str, abbr, mask,
                                           CFRangeMake(0, CFStringGetLength(str)),
                                           CFRangeMake(0, CFStringGetLength(abbr)));
}


// This function is called recursively with gradually smaller ranges
// for example:
// 1: "APHO", "Adobe Photoshop" = 1.0 + (2) / strlen
// 2: "PHO", "dobe Photoshop" = (3)
// 3: "", "toshop" = 0.9
// 
// Generally each character is worth 0.0 to 1.0
// Skipped characters are worth 0.0, but sometimes are worth more if 
// they are skipped on the way to a space
// All incomplete letters are given a score of 0.9
//
// Example: Adobe Photoshop with abbreviation APHO
//
// * Match           (1.0)
// - Minor deduction (0.85)
// = Major deduction (0.0)
// . End of string   (0.9)
//
// Adobe Photoshop
// *----=***...... 
// Map Show
// =**==**.

CGFloat HGSScoreForAbbreviationWithRanges(CFStringRef str, // The string
                                          CFStringRef abbr, // The abbreviation
                                          NSMutableIndexSet* mask, // The hitmask
                                          CFRange strRange, // string range
                                          CFRange abbrRange) { // abbreviation range
  NSInteger i, j;
  CGFloat score = 0.0;
  
  CFRange matchedRange, remainingStrRange, adjustedStrRange = strRange;
  
  // If we have exhausted the abbreviation, deduct some points for all remaining letters
  if (!abbrRange.length)
    return kIgnoredCharactersScore;
  
  // Return 0 if the abbreviation is longer than the string
  if (abbrRange.length > strRange.length) 
    return kNoMatchScore;
  
  // Optimization: search for the first character of the abbreviation to make
  // sure it exists in the string
  UniChar u = CFStringGetCharacterAtIndex(abbr,abbrRange.location);
  UniChar uc = toupper(u);
  UniChar *chars = (UniChar*)malloc(strRange.length * sizeof(UniChar));
  if (!chars) return kNoMatchScore;
  Boolean found = NO;
  CFStringGetCharacters(str, strRange, chars);
  for (i = 0; i < strRange.length; ++i) {
    if (chars[i] == u || chars[i] == uc) {
      found = YES;
      break;
    }
  }
  free(chars);

  // If the character is not found, return 0
  if (!found)
    return kNoMatchScore;
  
  adjustedStrRange.length -= i;
  adjustedStrRange.location += i;

  // Search for steadily smaller portions of the abbreviation
  for (i = abbrRange.length; i > 0; --i) {
    CFStringRef curAbbr = CFStringCreateWithSubstring(NULL,
                                                      abbr, 
                                                      CFRangeMake(abbrRange.location, i));
    
    BOOL foundShorterAbbr = CFStringFindWithOptions(
      str, 
      curAbbr, 
      CFRangeMake(adjustedStrRange.location, 
                  adjustedStrRange.length - abbrRange.length + i),
      kCFCompareCaseInsensitive,
      &matchedRange);
    CFRelease(curAbbr);
    
    // ABBREVIATION was not found, try ABBREVIATIO
    if (!foundShorterAbbr) continue; 
    
     // If a mask was set, add the matched indexes
    if (mask)
      [mask addIndexesInRange:NSMakeRange(matchedRange.location,
                                          matchedRange.length)];
    
    // update the remaining ranges
    remainingStrRange.location = matchedRange.location + matchedRange.length;
    remainingStrRange.length = strRange.location
                               + strRange.length
                               - remainingStrRange.location;
    
    // Search what is left of the string with the rest of the abbreviation
    CFRange abbrRange = CFRangeMake(abbrRange.location + i, 
                                    abbrRange.length - i);
    CGFloat remainingScore = HGSScoreForAbbreviationWithRanges(str, 
                                                               abbr,
                                                               mask,
                                                               remainingStrRange,
                                                               abbrRange);
    
    // If there was a match from the remaining letters, then score ourselves
    if (remainingScore > kNoMatchScore) {
      // Score starts out as the number of characters covered
      score = remainingStrRange.location - strRange.location;
      
      // ignore skipped characters if is first letter of a word
      if (matchedRange.location > strRange.location) {
        //if some letters were skipped
        
        static CFCharacterSetRef whitespaceSet = NULL;
        if (!whitespaceSet)
          whitespaceSet = CFCharacterSetGetPredefined(kCFCharacterSetWhitespace);
        
        static CFCharacterSetRef uppercaseSet = NULL;
        if (!uppercaseSet)
          uppercaseSet = CFCharacterSetGetPredefined(kCFCharacterSetUppercaseLetter);
       
        if (CFCharacterSetIsCharacterMember(whitespaceSet,
                 CFStringGetCharacterAtIndex(str, matchedRange.location - 1))) {
          // If there is a space before the match, reduce score for all
          // skipped spaces, but be nicer about other characters
          
          for (j = matchedRange.location - 2; j >= strRange.location; --j) {
            if (CFCharacterSetIsCharacterMember(whitespaceSet,
                                         CFStringGetCharacterAtIndex(str, j))) {
              score -= kMajorSkippedCharactersPenalty;
            } else {
              score -= kMinorSkippedCharactersPenalty;
            }
          }
          
        } else if (CFCharacterSetIsCharacterMember(uppercaseSet, 
                     CFStringGetCharacterAtIndex(str, matchedRange.location))) {
          // If the match starts with a cap, reduce score for all
          // skipped caps, but be nicer about other characters
          
          for (j = matchedRange.location - 1; j >= strRange.location; --j) {
            if (CFCharacterSetIsCharacterMember(uppercaseSet,
                                         CFStringGetCharacterAtIndex(str, j))) {
              score -= kMajorSkippedCharactersPenalty;
            } else {
              score -= kMinorSkippedCharactersPenalty;
            }
          }
        } else {
          // heavily penalize all characters skipped
          score -= (matchedRange.location - strRange.location)
                   * kMajorSkippedCharactersPenalty;
        }
      }
      
      // add score from the rest of the string
      score += remainingScore * remainingStrRange.length;
      
      // divide total score by the string length
      score /= strRange.length;
      break;
    }
  }
  return score;
}
