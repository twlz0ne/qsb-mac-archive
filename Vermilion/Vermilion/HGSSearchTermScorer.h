//
//  HGSSearchTermScorer.h
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

/*!
 @header HGSSearchTermScorer
 @discussion HGSSearchTermScorer provides several functions for scoring
      the presence of a string (search term) within another string (the
      search item).  The scoring algorithm takes into consideration
      several factors, including how complete of a match the term is
      when compared to the item, how much of a word is matched, if the
      term represents an abbreviation of the item, and so forth.

      Functions are provided for those applications that wish to collect
      metrics about the candidate matches for the term within each item.
      In order to have access to those function it is necessary to
      define HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS.
*/

#import <Foundation/Foundation.h>

/*!
 @typedef HGSItemWordRange
 @abstract Metrics about a word in a search item string.
 @discussion This structure is a component of the HGSItemWordMetrics
             structure and provides word location information for
             a word in a string being search for occurrences of
             a search term.
*/
@interface HGSItemWordRange : NSObject {
 @private
  NSUInteger wordStart_;
  NSUInteger wordLength_;
}

@property (nonatomic, readonly, assign) NSUInteger wordStart;
@property (nonatomic, readonly, assign) NSUInteger wordLength;

@end

#ifdef __cplusplus
extern "C" {
#endif

/*!
 Sets how each component comprising the matching algorithm influences
 the overall score acheived by a match.
 @param characterMatchFactor This is the basic value a character gets
        in a search term for matching a character in the search item.  Default
        value: 1.0.
 @param firstCharacterInWordFactor This is how much value a character in the
        search term gets if it happens to match the first character in a
        word of the search item.  Default value: 3.0.
 @param adjacencyFactor This is the factor applied to a character's adjacency
        value.  The value is calculated by summing the adjacency values (not
        factors) for all preceeding adjacent characters.  The character's
        score is then calculated by multiplying its adjacency value by this
        factor.  Default value: 3.8.
 @param startDistanceFactor This is the minimum percentage allowed when
        calculating the start distance score, which is multiplied to the
        accumulated term score.  100% is awarded for terms which begin
        at the first character of the search item.  It goes down from
        there.  Default value: 0.8.
 @param wordPortionFactor The multiplier applied to the word portion value to
        get the word portion score, which is accumulated into the overall term
        score.  The word portion value is calculated based on the longest
        word portion matched within the search item.  Default value: 5.0.
 @param itemPortionFactor This is the minimum percentage allowed when
        calculating the item portion score, which is multiplied to the
        accumulated term score.  100% is awarded for terms which are the
        same length as the search item.  It goes down from there.
        Default value: 0.8.
 @param matchSpreadFactor The multiplier applied to the final score based on
        the 'spread' of the matching characters within the item being tested
        (i.e. distance from first matching character to the last matching
        character) in relation to the length of the term.
 @param maximumCharacterDistance The maximum distance between occurrences of
        search term characters within the search item before the search term
        iteration is abandoned.  Default value: 22.
 @param maximumItemCharactersScanned The maximum number of characters of the
        search item which will be scanned.  All characters in the search
        item beyond this limit are ignored.  Note that there is an absolute
        maximum at 250.  Default value: 250.
 @param enableBestWordScoring When NO, this turns off the best word match
        portion of the scoring algorithm.  The effect is to prevent the
        calculation of the word boundaries within the search item and,
        potentially, improve performance.  Default value: YES.
 @param otherTermMultiplier The weight of the score of an otherItem when
        considering if the other item has scored enough to be significant.
        The score of the other item will be multiplied by this amount and
        this score will be compared against the main item score and, if
        greater, used instead of the main item score.
*/
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
                                    CGFloat otherTermMultiplier);

/*!
 Scores how well a given term comprised of a singe word matches to a
 string.  (Release version.)
 @param term The search term against which the candidate item will be
        searched.  This should be a single word.
 @param item The string against which to match the search term.
 @param pWordRanges A pointer to an NSArray containing HGSItemWordRanges
        of metrics delimiting the words in the search item.  When this pointer
        points to a NULL the word metrics will be calculated and an
        HGSItemWordRange created and populated with the start position and
        length of each word in the search item.  This is then added to the
        resulting array (in reverse order for internal optimization reasons).
        This array should be cached and provided in subsequent calls
        to the scoring function.  If this pointer is nil then no word
        metric information will be returned.
 @result an unbounded float representing the matching score of the best match.
*/
CGFloat HGSScoreTermForItem(NSString *term,
                            NSString *item,
                            NSArray **pWordRanges);

/*!
 Scores how well a one or more words match a string.  (Release version.)
 @param searchTerms An NSArray of search terms against which the candidate
        item will be searched.  This may contain one or more strings.
 @param mainItem The string against which to score the search term.
 @param otherItems An NSArray of alternative items against which the
        searchTerms will be scored.  If the score for any of the other items
        is high enough then its score will be used instead of the score
        for the main item.
 @param pWordRanges A pointer to an NSArray containing HGSItemWordRanges
        of metrics delimiting the words in the search item.  When this pointer
        points to a NULL the word metrics will be calculated and an
        HGSItemWordRange created and populated with the start position and
        length of each word in the search item.  This is then added to the
        resulting array (in reverse order for internal optimization reasons).
        This array should be cached and provided in subsequent calls
        to the scoring function.  If this pointer is nil then no word
        metric information will be returned.
 @result an NSArray of float NSNumbers representing the matching scores
        of the best match for each search term.
*/
CGFloat HGSScoreTermsForMainAndOtherItems(NSArray *searchTerms,
                                          NSString *mainItem,
                                          NSArray *otherItems,
                                          NSArray **pWordRanges);

#ifdef HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

/*!
 Scores how well a one or more words match a string.  (Release version.)
 @param searchTerms An NSArray of search terms against which the candidate
        item will be searched.  This may contain one or more strings.
 @param mainItem The string against which to score the search term.
 @param otherItems An NSArray of alternative items against which the
        searchTerms will be scored.  If the score for any of the other items
        is high enough then its score will be used instead of the score
        for the main item.
 @param pWordRanges A pointer to an NSArray containing HGSItemWordRanges
        of metrics delimiting the words in the search item.  When this pointer
        points to a NULL the word metrics will be calculated and an
        HGSItemWordRange created and populated with the start position and
        length of each word in the search item.  This is then added to the
        resulting array (in reverse order for internal optimization reasons).
        This array should be cached and provided in subsequent calls
        to the scoring function.  If this pointer is nil then no word
        metric information will be returned.
 @param pScoringDetails An NSArray containing a dictionary for each term
        in searchTerms.  Each dictionary will contain details describing the
        highest scoring match of the search term against the  main item
        and the other items.  Each dictionary provides: 1) the score of the
        best match, 2) the character details,  3) sds, 4) abs, 5) bmls,
        6) poimf, and 7) the index of the item within which the match
        with 0 being the main item.
        If the caller provides a nil pointer then no details are collected
        and returned.  If this pointer is not nil, anything to which it
        points is ignored (and the caller must insure any old NSDictionary is
        properly disposed) and the address of the newly created dictionary
        is placed therein.  If a search term exactly matches the search item
        this pointer will be set to NSNull.
 @result an NSArray of float NSNumbers representing the matching scores
        of the best match for each search term.
 */
CGFloat HGSScoreTermsForMainAndOtherItemsWithDetails(NSArray *searchTerms,
                                                     NSString *mainItem,
                                                     NSArray *otherItems,
                                                     NSArray **pWordRanges,
                                                     NSArray **pScoringDetails);

/*!
 Scores how well a given term comprised of a singe word matches to a
 string.  (Debug version.)
 @param term the string to match against.
 @param item the string against which to match the search term.
 @param pWordRanges A pointer to an NSArray containing HGSItemWordRanges
        of metrics delimiting the words in the search item.  When this pointer
        points to a NULL the word metrics will be calculated and an
        HGSItemWordRange created and populated with the start position and
        length of each word in the search item.  This is then added to the
        resulting array (in reverse order for internal optimization reasons).
        This array should be cached and provided in subsequent calls
        to the scoring function.  If this pointer is nil then no word
        metric information will be returned.
 @param pSearchTermDetails An NSDictionary containing the details describing
        the candidate matches of the search term against the search item.  The
        dictionary provides: 1) the score of the best match, 2) the
        count of matches,  3) the search term, and 4) an NSArray of
        NSDictionaries giving details about each candidate match ('match
        details').  The match detail dictionary provides the various
        values and scores which contributed to the overall match's score as
        was as detail about how each character in the search term matched.
        If the caller provides a nil pointer then no details are collected
        and returned.  If this pointer is not nil, anything to which it
        points is ignored (and the caller must insure any old NSDictionary is
        properly disposed) and the address of the newly created dictionary
        is placed therein.  If a search term exactly matches the search item
        this pointer will be set to NULL.
 @result an unbounded float representing the matching score of the best match.
*/
CGFloat HGSScoreTermAndDetailsForItem(NSString *term,
                                      NSString *item,
                                      NSArray **pWordRanges,
                                      NSDictionary **pSearchTermDetails);

/*!
 Scores how well a one or more words match a string.  (Debug version.)
 @param searchTerms An NSArray of search terms against which the candidate
        item will be searched.  This may contain one or more strings.
 @param item the string against which to match the search term.
 @param pWordRanges A pointer to an NSArray containing HGSItemWordRanges
        of metrics delimiting the words in the search item.  When this pointer
        points to a NULL the word metrics will be calculated and an
        HGSItemWordRange created and populated with the start position and
        length of each word in the search item.  This is then added to the
        resulting array (in reverse order for internal optimization reasons).
        This array should be cached and provided in subsequent calls
        to the scoring function.  If this pointer is nil then no word
        metric information will be returned.
 @param pSearchTermsDetails A pointer to an NSArray of NSDictionaries per
        search term of search term matching details.  See the description
        of HGSScoreTermAndDetailsForItem for a full explanation of the
        contents of these dicationaries.
 @result an NSArray of float NSNumbers representing the matching scores
        of the best match for each search term.
*/
NSArray *HGSScoreTermsAndDetailsForItem(NSArray *searchTerms,
                                        NSString *item,
                                        NSArray **pWordRanges,
                                        NSArray **pSearchTermsDetails);

#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

/*!
 Function for verifying that a string has been properly tokenized.
 Used in debug builds.
*/
BOOL HGSValidateTokenizedString(NSString *tokenizedString);  
  
/*!
 @enum Calibrated Score Categories
 @abstract Used to specify the minimum score required to achieve the
           desired category.
 @constant kHGSCalibratedPerfectScore The score assigned for a perfect math.
 @constant kHGSCalibratedStrongScore A strong match score.
 @constant kHGSCalibratedModerateScore A moderately match score.
 @constant kHGSCalibratedWeakScore A moderate match score.
 @constant kHGSCalibratedInsignificantScore An insignificant match score.
 @constant kHGSCalibratedLastScore Can be used as a count of possible values.
*/  
typedef enum {
  kHGSCalibratedPerfectScore = 0,
  kHGSCalibratedStrongScore,
  kHGSCalibratedModerateScore,
  kHGSCalibratedWeakScore,
  kHGSCalibratedInsignificantScore,
  kHGSCalibratedLastScore
} HGSCalibratedScoreType;

  
/*!
 Returns a calibrated score based on the desired category strengh.
 @param scoreType The strength category for which the minimum match score
        is to be returned.
 @result A CGFloat containing the minimum match score for the given
         strength category.
*/
CGFloat HGSCalibratedScore(HGSCalibratedScoreType scoreType);

#ifdef __cplusplus
}
#endif

#ifdef HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS

// Keys to search term detail dictionary items.
extern NSString *const kHGSScoreTermWordKey;         // NSString: The search term word.
extern NSString *const kHGSScoreTermBestScoreKey;    // CGFloat: Best score of all matches.
extern NSString *const kHGSScoreTermMatchCountKey;   // NSUInteger: Number of matches.
extern NSString *const kHGSScoreTermMatchDetailKey;  // NSArray: Match detail dicts

// Keys to match detail dictionary items.
extern NSString *const kHGSScoreMatchScoreKey;  // CGFloat: Score of term match.
extern NSString *const kHGSScoreMatchSDVKey;    // NSUInteger: Start distance value
extern NSString *const kHGSScoreMatchSDSKey;    // CGFloat: Start distance score
extern NSString *const kHGSScoreMatchBMLKey;    // NSUInteger: Best word match length
extern NSString *const kHGSScoreMatchBWLKey;    // NSUInteger: Best word length
extern NSString *const kHGSScoreMatchBMLVKey;   // CGFloat: Best word match length value
extern NSString *const kHGSScoreMatchBMLSKey;   // CGFloat: Best word match length score
extern NSString *const kHGSScoreMatchPOIMFKey;  // CGFloat: Portion-of-item multiplier factor.
extern NSString *const kHGSScoreMatchCharDetailKey;  // NSArray: Char detail dicts.

// Keys to character detail dictionary items.
extern NSString *const kHGSScoreCharPosKey;  // NSUInteger: Position of term char in item.
extern NSString *const kHGSScoreCharPSKey;   // CGFloat: Partial score of term char.
extern NSString *const kHGSScoreCharFCVKey;  // NSUInteger: First char in word value of term char.
extern NSString *const kHGSScoreCharADVKey;  // NSUInteger: Adjacency value of term char.
extern NSString *const kHGSScoreCharFCSKey;  // CGFloat: First-char-in-word score.
extern NSString *const kHGSScoreCharADSKey;  // CGFloat: Adjacency score.

#endif // HGS_ENABLE_TERM_SCORING_METRICS_FUNCTIONS
