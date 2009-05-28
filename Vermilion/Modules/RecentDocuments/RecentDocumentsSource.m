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
#import "HGSTokenizer.h"

// The RecentDocumentsSource provides results containing
// the recent documents opened for the application being pivoted.
//
@interface RecentDocumentsSource : HGSCallbackSearchSource
@end

@implementation RecentDocumentsSource
GTM_METHOD_CHECK(NSFileManager, gtm_pathFromAliasData:);


- (BOOL)isSearchConcurrent {
  // NSFilemanager isn't listed as thread safe
  // http://developer.apple.com/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/chapter_950_section_2.html
  return YES;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = NO;
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    isValid = [super isValidSourceForQuery:query];
  }
  return isValid;
}

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  HGSQuery *query = [operation query];
  HGSResult *pivotObject = [query pivotObject];
  NSString *normalizedQuery = [query normalizedQueryString];
  if (pivotObject) {
    NSURL *url = [pivotObject url];
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

        NSFileManager *manager = [NSFileManager defaultManager];

        for (id recentDocumentItem in recentDocuments) {
          NSData *aliasData = [[recentDocumentItem objectForKey:@"_NSLocator"]
                                objectForKey:@"_NSAlias"];
          NSString *recentPath = [manager gtm_pathFromAliasData:aliasData];

          if (recentPath && [manager fileExistsAtPath:recentPath]) {
            NSString *basename = [recentPath lastPathComponent];
            NSString *tokenizedName = [HGSTokenizer tokenizeString:basename];
            CGFloat rank = HGSScoreForAbbreviation(tokenizedName,
                                                   normalizedQuery, 
                                                   NULL);
            if (rank > 0) {
              NSNumber *nsRank = [NSNumber numberWithFloat:rank];
              NSDictionary *attributes 
                = [NSDictionary dictionaryWithObjectsAndKeys:
                   nsRank, kHGSObjectAttributeRankKey, nil];
              HGSResult *result = [HGSResult resultWithFilePath:recentPath
                                                         source:self
                                                     attributes:attributes];
              [finalResults addObject:result];
            }
          }
        }
        [operation setResults:finalResults];
      }
    }
  }

  [operation finishQuery];
}

@end
