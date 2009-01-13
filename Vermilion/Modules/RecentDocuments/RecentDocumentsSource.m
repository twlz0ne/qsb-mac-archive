//
//  RecentDocumentsSource.m
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

#import <Vermilion/Vermilion.h>
#import "GTMNSFileManager+Carbon.h"
#import "GTMGarbageCollection.h"
#import "GTMMethodCheck.h"
#import "GTMNSEnumerator+Filter.h"

// The RecentDocumentsSource provides results containing
// the recent documents opened for the application being pivoted.
//
@interface RecentDocumentsSource : HGSCallbackSearchSource
// These methods, given a set of words a1,a2,...,an, creates a clause
// of the form (a1 AND a2 AND a3 AND a4) or (a1 or a2 or a3 or a4).
//
// The point being that we want to order documents that match all the
// terms first, then find documents that match just one of the terms.
// The "correct" way to do this is to order by the number of terms the
// documents match, but I think that's an NP complete problem :-)
- (NSString *)createAndSearchStringFromWordSet:(NSSet *)queryWords;
- (NSString *)createOrSearchStringFromWordSet:(NSSet *)queryWords;
@end

@implementation RecentDocumentsSource
GTM_METHOD_CHECK(NSFileManager, gtm_pathFromAliasData:);
GTM_METHOD_CHECK(NSEnumerator, gtm_enumeratorByTarget:performOnEachSelector:);

- (NSString *)createAndSearchStringFromWordSet:(NSSet *)queryWords {
  NSString *andClause = [[queryWords allObjects]
                          componentsJoinedByString:@"' AND SELF CONTAINS[cd] '"];
  NSMutableString *andString = [NSMutableString stringWithString:andClause];
  [andString insertString:@"(SELF CONTAINS[cd] '" atIndex:0];
  [andString appendString:@"')"];

  return andString;
}

- (NSString *)createOrSearchStringFromWordSet:(NSSet *)queryWords {
  NSString *orClause = [[queryWords allObjects]
                         componentsJoinedByString:@"' OR SELF CONTAINS[cd] '"];
  NSMutableString *orString = [NSMutableString stringWithString:orClause];

  [orString insertString:@"(SELF CONTAINS[cd] '" atIndex:0];
  [orString appendString:@"')"];

  return orString;
}

- (BOOL)isSearchConcurrent {
  // NSFilemanager isn't listed as thread safe
  // http://developer.apple.com/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/chapter_950_section_2.html
  return YES;
}

- (BOOL)doesActionApplyTo:(HGSObject *)result {
  return [result conformsToType:kHGSTypeFileApplication];
}

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  HGSQuery *query = [operation query];
  HGSObject *pivotObject = [query pivotObject];
  if (pivotObject) {
    NSURL *url = [pivotObject identifier];
    NSString *appPath = [url path];
    if (appPath) {
      NSBundle *appBundle = [[[NSBundle alloc]
                               initWithPath:appPath] autorelease];
      NSString *appIdentifier = [appBundle bundleIdentifier];

      if (appIdentifier) {
        NSArray *recentDocuments
          = GTMCFAutorelease(
              CFPreferencesCopyValue(CFSTR("NSRecentDocumentRecords"),
                                     (CFStringRef)appIdentifier,
                                     kCFPreferencesCurrentUser,
                                     kCFPreferencesAnyHost));

        // Xcode 3.1 also has a recent projects pref key and we'd like
        // to include that as well.  But Xcode 2.5 stores recent files
        // using NSRecentDocumentRecords
        if ([appIdentifier isEqualToString:@"com.apple.Xcode"]) {
          NSArray *recentXCodeProjects
            = GTMCFAutorelease(
                CFPreferencesCopyValue(CFSTR("NSRecentXCProjectDocuments"),
                                       (CFStringRef)appIdentifier,
                                       kCFPreferencesCurrentUser,
                                       kCFPreferencesAnyHost));

          NSArray *recentXCFiles
            = GTMCFAutorelease(CFPreferencesCopyValue(
                CFSTR("NSRecentXCFileDocuments"),
                (CFStringRef)appIdentifier,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost));

          // If recentXCodeProjects is not nil, recentDocuments should
          // be nil since XCode switched from using
          // NSRecentDocumentRecords to the two different keys above
          // for files/projects between 2.5 & 3.1.
          if (recentXCodeProjects) {
            HGSAssert(!recentDocuments,
                      @"found XCode files in both NSRecentDocumentRecords"
                      @" and NSRecentXCProjectDocuments");
            recentDocuments = recentXCodeProjects;
          }

          if (recentXCFiles) {
            recentDocuments = [recentDocuments
                                arrayByAddingObjectsFromArray:recentXCFiles];
          }
        }

        NSMutableArray *finalResults = [NSMutableArray
                                         arrayWithCapacity:
                                           [recentDocuments count]];

        // Whether the user has entered more than 1 word after
        // pivoting on the app.  Use this later on to create the
        // results list as soon as possible, rather than going through
        // the predicate logic
        BOOL filterUsingPredicates = ([[query uniqueWords] count] > 1);

        NSFileManager *manager = [NSFileManager defaultManager];
        NSMutableArray *documentsArray = [NSMutableArray
                                           arrayWithCapacity:
                                             [recentDocuments count]];
        for (id recentDocumentItem in recentDocuments) {
          NSData *aliasData = [[recentDocumentItem objectForKey:@"_NSLocator"]
                                objectForKey:@"_NSAlias"];
          NSString *recentPath = [manager gtm_pathFromAliasData:aliasData];

          if (recentPath && [manager fileExistsAtPath:recentPath]) {
            if (filterUsingPredicates) {
              // If the user has entered keywords, we need to filter it down
              // by those keywords
              [documentsArray addObject:recentPath];
            } else {
              // If the user hasn't entered keywords, add to the final results list.
              // If the user has only entered 1,  do a simple containment test
              // and add to results list
              HGSAssert(([[query uniqueWords] count] < 2),
                        @"Query word count >= 2 in non-predicate path");
              if ([[query uniqueWords] count] == 1) {
                NSString *queryWord =
                  [[[query uniqueWords] anyObject] lowercaseString];

                if ([[recentPath lowercaseString]
                      rangeOfString:queryWord].length > 0) {
                  HGSObject *result = [HGSObject objectWithFilePath:recentPath
                                                 source:self
                                                 attributes:nil];
                  [finalResults addObject:result];
                }
              } else {
                HGSObject *result = [HGSObject objectWithFilePath:recentPath
                                               source:self
                                               attributes:nil];
                [finalResults addObject:result];
              }
            }
          }
        }

        if (filterUsingPredicates) {
          NSString *predicateStringMatchingAllWords =
            [self createAndSearchStringFromWordSet:[query uniqueWords]];

          NSPredicate *andSearchPredicate =
            [NSPredicate predicateWithFormat:predicateStringMatchingAllWords];

          NSArray *filteredDocsMatchingAllWords =
            [documentsArray filteredArrayUsingPredicate:andSearchPredicate];

          NSEnumerator *finalResultsEnum;

          NSMutableArray *docsMatchingAllWords =
            [NSMutableArray arrayWithArray:filteredDocsMatchingAllWords];

          NSString *predicateStringMatchingOneWord =
            [self createOrSearchStringFromWordSet:[query uniqueWords]];

          NSPredicate *orSearchPredicate =
            [NSPredicate predicateWithFormat:predicateStringMatchingOneWord];

          NSArray *filteredDocsMatchingOneWord =
            [documentsArray filteredArrayUsingPredicate: orSearchPredicate];

          NSMutableArray *docsMatchingOneWord =
            [NSMutableArray arrayWithArray:filteredDocsMatchingOneWord];

          // Now remove duplicates by removing docs that matched ALL
          // words from the docs that matched any of the words
          [docsMatchingOneWord removeObjectsInArray:docsMatchingAllWords];

          // And append the docs matching one word to the docs
          // matching all words
          [docsMatchingAllWords addObjectsFromArray:docsMatchingOneWord];

          finalResultsEnum = [[docsMatchingAllWords objectEnumerator]
                               gtm_enumeratorByTarget:self
                               performOnEachSelector:@selector(HGSObjectFromFilePath:)];

          [finalResults addObjectsFromArray:[finalResultsEnum allObjects]];
        }
        [operation setResults:finalResults];
      }
    }
  }

  [operation finishQuery];
}

- (HGSObject *)HGSObjectFromFilePath:(NSString *)docPath {
  return [HGSObject objectWithFilePath:docPath
                                source:self
                            attributes:nil];
}
@end
