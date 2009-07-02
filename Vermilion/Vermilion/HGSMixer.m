//
//  HGSMixer.m
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

#import "HGSMixer.h"
#import "HGSQueryController.h"
#import "HGSResult.h"
#import "HGSLog.h"

static NSInteger RelevanceCompare(id ptr1, id ptr2, void *context);

@interface HGSMixer()
// these methods can be overridden to customize the behavior of the ranking
// and de-duping.
- (void)sortObjectsInSitu:(NSMutableArray*)objects
          queryController:(HGSQueryController*)controller;
- (NSMutableArray *)mergeDuplicates:(NSArray*)objects
                    queryController:(HGSQueryController*)controller;
@end

@implementation HGSMixer

- (NSMutableArray*)mix:(NSArray*)providerArrays 
       queryController:(HGSQueryController*)controller {
  // join all arrays into one big one. If we can normalize the rankings
  // somehow beforehand we can try to just pick off elements from the front
  // of each pre-sorted list, but until then, we just punt and work in one big
  // array.
  NSMutableArray* results = [NSMutableArray array];
  for (NSArray *curr in providerArrays) {
    [results addObjectsFromArray:curr];
  }
  
  // sort in global order
  [self sortObjectsInSitu:results queryController:controller];
  
  // merge/remove duplicates
  //
  results = [self mergeDuplicates:results queryController:controller];
  
  return results;
}

//
// -sortObjectsInSitu:
//
// Sort the objects in-place in the array. Currently does only our standard
// relevance sort, but can be overridden to apply multiple sorts or tweak
// results to taste.
//
- (void)sortObjectsInSitu:(NSMutableArray*)objects 
          queryController:(HGSQueryController*)controller {
  [objects sortUsingFunction:RelevanceCompare context:NULL];
#if 0
  if ([controller cancelled]) return;
  // TODO(pinkerton): move this into the regular compare when the name match
  //    bit is set.
  [results sortUsingFunction:NameCompare context:parsedQuery_];
#endif
}

//
// -mergeDuplicates:
//
// merges/removes duplicate results
//
- (NSMutableArray *)mergeDuplicates:(NSArray*)results 
                    queryController:(HGSQueryController*)controller {
  NSUInteger resultsCount = [results count];
  id *singulars = malloc(sizeof(id) * resultsCount);
  NSUInteger singularIndex = 0;
  id *resultObjects = malloc(sizeof(id) * resultsCount);
  if (!singulars || !resultObjects) {
    free(singulars);
    free(resultObjects);
    HGSLogDebug(@"Out of memory at mergeDuplicates");
    return nil;
  }
  [results getObjects:resultObjects];
  for (NSUInteger i = 0; i < resultsCount; ++i) {
    // Check to see if it's a duplicate of any of the confirmed results
    HGSResult *currentResult = resultObjects[i];
    NSUInteger currentHash = currentResult->idHash_;
    NSUInteger j;
    for (j = 0; j < singularIndex; ++j) {
      HGSResult *singular = singulars[j];
      if (currentHash == singular->idHash_) {
        if ([currentResult isDuplicate:singular]) {
          // We've got a match; merge this into the existing result and replace
          singular = [singular mergeWith:currentResult];
          singulars[j] = singular;
          break;
        }
      }
    }
    if ([controller cancelled]) {
      return nil;
    }
    if (j == singularIndex) {
      singulars[singularIndex] = currentResult;
      ++singularIndex;
    }
  }
  NSMutableArray *outArray = [NSMutableArray arrayWithObjects:singulars 
                                                        count:singularIndex];
  free(singulars);
  free(resultObjects);
  return outArray;
}

#pragma mark -

#if 0
static int NameCompare(id r1, id r2, void *context) {
  NSString *query = [[(HGSQuery *)context query] lowercaseString];
  NSString *n1 = [[r1 valueForKey:kHGSObjectAttributeNameKey] lowercaseString];
  NSString *n2 = [[r2 valueForKey:kHGSObjectAttributeNameKey] lowercaseString];
  NSEnumerator *n1Substrings = [[n1 componentsSeparatedByString:@" "] objectEnumerator];
  NSEnumerator *n2Substrings = [[n2 componentsSeparatedByString:@" "] objectEnumerator];
  NSString *subString1 = nil;
  NSString *subString2 = nil;
  int count1 = 0, count2 = 0;
  while ((subString1 = [n1Substrings nextObject])) {
    ++count1;
    if ([subString1 hasPrefix:query]) {
      break;
    }
  }
  while ((subString2 = [n2Substrings nextObject])) {
    ++count2;
    if ([subString2 hasPrefix:query]) {
      break;
    }
  }
  int sub1Len = [subString1 length];
  int sub2Len = [subString2 length];
  if (sub1Len < sub2Len) {
    return NSOrderedAscending;
  } else if (sub1Len > sub2Len) {
    return NSOrderedDescending;
  } else {
    if (count1 < count2) {
      return NSOrderedAscending;
    } else if (count2 < count1) {
      return NSOrderedDescending;
    } else {
      sub1Len = [n1 length];
      sub2Len = [n2 length];
      if (sub1Len < sub2Len) {
        return NSOrderedAscending;
      } else {
        return NSOrderedDescending;
      }
    }
  }
}
#endif

//
// RelevanceCompare
//
// Compares two objects based on a series of strong and weak boosts, outlined
// in . Returns NSOrderedAscending if |ptr1| is "smaller" (higher relevance) 
// than |ptr2|.
//
static NSInteger RelevanceCompare(id ptr1, id ptr2, void *context) {
  // Sanity
  if (!(ptr1 && ptr2)) return kCFCompareEqualTo;  // Nothing sane to do
  
  // Save some typing and cast
  HGSResult *item1 = (HGSResult *)ptr1;
  HGSResult *item2 = (HGSResult *)ptr2;
  NSDate *dateOne = nil;
  NSDate *dateTwo = nil;
  
  // Final result
  CFComparisonResult compareResult = kCFCompareEqualTo;
  
  ////////////////////////////////////////////////////////////
  //  Value rank above all else
  ////////////////////////////////////////////////////////////
  
  CGFloat rank1 = [item1 rank];
  CGFloat rank2 = [item2 rank];
  if (rank1 < rank2) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  } else if (rank1 > rank2) {
    compareResult = kCFCompareLessThan;
    goto RelevanceCompareComplete;
  }
  
  HGSRankFlags flags1 = [item1 rankFlags];
  HGSRankFlags flags2 = [item2 rankFlags];
  
  ////////////////////////////////////////////////////////////
  //  Penalize spam
  ////////////////////////////////////////////////////////////
  
  if (flags1 & eHGSSpamRankFlag) {
    if (!flags2 & eHGSSpamRankFlag) {
      compareResult = kCFCompareGreaterThan;
      goto RelevanceCompareComplete;
    }
    // Fall through
  } else if (flags2 & eHGSSpamRankFlag) {
    compareResult = kCFCompareLessThan;
    goto RelevanceCompareComplete;
  }
    
  ////////////////////////////////////////////////////////////
  //  "Launchable" (Applications, Pref panes, etc.)
  ////////////////////////////////////////////////////////////
  
  if (flags1 & eHGSLaunchableRankFlag && flags1 & eHGSNameMatchRankFlag) {
    if (!(flags2 & eHGSLaunchableRankFlag && flags2 & eHGSNameMatchRankFlag)) {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
    // Fall through
  } else if (flags2 & eHGSLaunchableRankFlag && flags2 & eHGSNameMatchRankFlag) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Contacts
  ////////////////////////////////////////////////////////////
  
  BOOL item1IsContact = [item1 conformsToType:kHGSTypeContact];
  BOOL item2IsContact = [item2 conformsToType:kHGSTypeContact];
  if (item1IsContact) {
    if (item2IsContact) {
      // Between contacts just sort on last used
      goto RelevanceCompareLastUsed;
    } else {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
  } else if (item2IsContact) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  "Persistent" items (Dock, Finder sidebar, etc.)
  ////////////////////////////////////////////////////////////
  
  if (flags1 & eHGSUserPersistentPathRankFlag) {
    if (!flags2 & eHGSUserPersistentPathRankFlag) {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
    // Fall through to further comparisons
  } else if (flags2 & eHGSUserPersistentPathRankFlag) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Special UI objects
  ////////////////////////////////////////////////////////////
  
  if (flags1 & eHGSSpecialUIRankFlag) {
    if (!flags2 & eHGSSpecialUIRankFlag) {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
    // Fall through to further comparisons
  } else if (flags2 & eHGSSpecialUIRankFlag) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Home folder check
  ////////////////////////////////////////////////////////////
  
  // Special home folder places
  if (flags1 & eHGSUnderHomeRankFlag 
      || flags1 & eHGSUnderDownloadsRankFlag
      || flags1 & eHGSUnderDesktopRankFlag) {
    if (!(flags2 & eHGSUnderHomeRankFlag 
          || flags2 & eHGSUnderDownloadsRankFlag
          || flags2 & eHGSUnderDesktopRankFlag)) {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
    // Fall through
  } else if (flags2 & eHGSUnderHomeRankFlag 
             || flags2 & eHGSUnderDownloadsRankFlag
             || flags2 & eHGSUnderDesktopRankFlag) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  // Just under home in general is more relevant
  if (flags1 & eHGSUnderHomeRankFlag) {
    if (!flags2 & eHGSUnderHomeRankFlag) {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
    // Fall through
  } else if (flags2 & eHGSUnderHomeRankFlag) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Name matches are preferred even over recent usage
  ////////////////////////////////////////////////////////////
  if (flags1 & eHGSNameMatchRankFlag) {
    if (!flags2 & eHGSNameMatchRankFlag) {
      compareResult = kCFCompareLessThan;
      goto RelevanceCompareComplete;
    }
    // Fall through
  } else if (flags2 & eHGSNameMatchRankFlag) {
    compareResult = kCFCompareGreaterThan;
    goto RelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Last used date
  ////////////////////////////////////////////////////////////
RelevanceCompareLastUsed:
  // Set sort so that more recent wins, we can do this in one step by inverting
  // the comparison order (we want newer things to be less than)
  
  dateOne = [item2 lastUsedDate]; 
  dateTwo = [item1 lastUsedDate];
  
  compareResult = (CFComparisonResult)[dateOne compare:dateTwo];

  // Barring any better information, sort by name
  if (compareResult == kCFCompareEqualTo) {
    NSString *name1 = [item1 displayName];
    NSString *name2 = [item2 displayName];
    compareResult = (CFComparisonResult)[name1 caseInsensitiveCompare:name2]; 
  }
  
  
  // Finished, all comparisons done
RelevanceCompareComplete:
  // Return the final result
  return compareResult;
}

@end
