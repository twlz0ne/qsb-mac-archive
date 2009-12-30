//
//  FilesystemDirectorySearchSource.m
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
#import "NSString+CaseInsensitive.h"
#import "HGSLog.h"
#import "GTMMethodCheck.h"
#import "GTMNSFileManager+Carbon.h"
#import "GTMNSNumber+64Bit.h"

// This source provides results for directory restricted searches:
// If a pivot object is a folder, it will find direct children with a prefix
// match.
// Additionally, it provides synthetic results for / and ~

@interface FilesystemDirectorySearchSource : HGSCallbackSearchSource
@end

@implementation FilesystemDirectorySearchSource
GTM_METHOD_CHECK(NSString, qsb_hasPrefix:options:);
GTM_METHOD_CHECK(NSNumber, gtm_numberWithCGFloat:);

- (BOOL)isSearchConcurrent {
  return YES;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // We accept file: urls as queries, and raw paths starting with '/' or '~'.
  // (So we force yes since default is a word check)
  // We do NOT call [super isValidForQuery:] because it will fail the / and ~
  // check.
  BOOL isValid = YES;
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    isValid = [pivotObject isFileResult];
  } 
  return isValid;
}

- (void)performSearchOperation:(HGSCallbackSearchOperation *)operation {
  NSFileManager *fm = [NSFileManager defaultManager];
  HGSQuery *query = [operation query];
  // use the raw query since we're trying to match paths to specific folders.
  HGSResult *pivotObject = [query pivotObject];
  BOOL isApplication = [pivotObject conformsToType:kHGSTypeFileApplication];
  if (pivotObject) {
    NSString *normalizedQueryString = [query normalizedQueryString];
    NSURL *url = [pivotObject url];
    NSString *path = [url path];
    NSMutableArray *results = [NSMutableArray array];
    
    LSItemInfoRecord infoRec;
    OSStatus err = LSCopyItemInfoForURL((CFURLRef)url, 
                                        kLSRequestBasicFlagsOnly, &infoRec);
    
    // If the path is an alias, we resolve before continuing
    if (err == noErr && (infoRec.flags & kLSItemInfoIsAliasFile)) {
      FSRef aliasRef;
        
      if (CFURLGetFSRef((CFURLRef)url, &aliasRef)) {
        Boolean targetIsFolder;
        Boolean wasAliased;
        err = FSResolveAliasFileWithMountFlags(&aliasRef, 
                                               true, 
                                               &targetIsFolder,
                                               &wasAliased,
                                               0);
        if (err == noErr) {
          path = [fm gtm_pathFromFSRef:&aliasRef];
        }
      }
    }
    
    BOOL emptyQuery = [normalizedQueryString length] == 0;
    NSArray *contents = [fm directoryContentsAtPath:path];
    BOOL showInvisibles = ([query flags] & eHGSQueryShowAlternatesFlag) != 0;
    // Only construct these one time, rather than each time through the loop.
    NSNumber *belowFoldRankFlag 
      = [NSNumber numberWithUnsignedInteger:eHGSBelowFoldRankFlag];
    CGFloat strongScore = HGSCalibratedScore(kHGSCalibratedStrongScore);
    NSNumber *nsStrongScore = [NSNumber gtm_numberWithCGFloat:strongScore];
    for (NSString *subpath in contents) {
      NSString *fullPath = [path stringByAppendingPathComponent:subpath];
      if (!showInvisibles) {
        if ([subpath hasPrefix:@"."]) continue;
        NSURL *subURL = [NSURL fileURLWithPath:fullPath];
        LSItemInfoRecord subInfoRec;
        err = LSCopyItemInfoForURL((CFURLRef)subURL, 
                                   kLSRequestBasicFlagsOnly, &subInfoRec);
        if (err == noErr) {
          if (subInfoRec.flags & kLSItemInfoIsInvisible) continue;
        } else {
          HGSLogDebug(@"Error %d fetching directory content info for '%@'.",
                      err, fullPath);
        }
      }
      // Filter further based on the query string, or, if there is no
      // query string then boost the score of the folder's contents.
      NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
      if (emptyQuery) {
        // TODO(mrossetti): Fix the following once issue 850 is addressed.
        // http://code.google.com/p/qsb-mac/issues/detail?id=850
        [attributes setObject:nsStrongScore forKey:kHGSObjectAttributeRankKey];
        if (isApplication) {
          [attributes setObject:belowFoldRankFlag
                         forKey:kHGSObjectAttributeRankFlagsKey];
        }
      } else {
        NSString *tokenizedSubpath = [HGSTokenizer tokenizeString:subpath];
        CGFloat score
          = HGSScoreTermForString(normalizedQueryString, tokenizedSubpath);
        if (score < FLT_EPSILON) continue;
        [attributes setObject:[NSNumber gtm_numberWithCGFloat:score] 
                       forKey:kHGSObjectAttributeRankKey];
      }

      NSError *error = nil;               
      NSDictionary *itemAttributes = [fm attributesOfItemAtPath:fullPath
                                                          error:&error];
      if (!error) {
        NSDate *modDate = [itemAttributes fileModificationDate];
        [attributes setObject:modDate
                       forKey:kHGSObjectAttributeLastUsedDateKey];
      } else {
        HGSLogDebug(@"Error fetching mod date for '%@': %@.",
                    fullPath, error);
      }
      
      HGSResult *result = [HGSResult resultWithFilePath:fullPath 
                                                 source:self 
                                             attributes:attributes];
      [results addObject:result];
    }

    [operation setResults:results];
  } else {
    // use the raw query since we're trying to match paths to specific folders.
    // we treat the input as a raw path, so no tokenizing, etc.
    NSString *path = [query rawQueryString];
    
    // Convert file urls
    if ([path hasPrefix:@"file:"]) {
      path = [[NSURL URLWithString:path] path];
    }
    
    // As a convenince, interpret ` as ~
    if ([path isEqualToString:@"`"]) path = @"~";
    
    if ([path hasPrefix:@"/"] || [path hasPrefix:@"~"]) {
      path = [path stringByStandardizingPath];
      if ([fm fileExistsAtPath:path]) {
        NSDictionary *attributes
          = [NSDictionary dictionaryWithObjectsAndKeys:
             [NSNumber numberWithFloat:1000], kHGSObjectAttributeRankKey, nil];
        HGSResult *result = [HGSResult resultWithFilePath:path 
                                                   source:self
                                               attributes:attributes];
        [operation setResults:[NSArray arrayWithObject:result]]; 
      } else {
        NSString *container = [path stringByDeletingLastPathComponent];
        NSString *partialPath = [path lastPathComponent];
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:container isDirectory:&isDirectory]
            && isDirectory) {
          NSArray *dirContents = [fm directoryContentsAtPath:container];
          NSUInteger count = [dirContents count];
          NSMutableArray *contents = [NSMutableArray arrayWithCapacity:count];
          for (path in [fm directoryContentsAtPath:container]) {
            if ([path qsb_hasPrefix:partialPath 
                            options:(NSWidthInsensitiveSearch 
                                   | NSCaseInsensitiveSearch
                                   | NSDiacriticInsensitiveSearch)]) {
              LSItemInfoRecord infoRec;
              NSURL *fileURL = [NSURL fileURLWithPath:path];
              if (noErr == LSCopyItemInfoForURL((CFURLRef)fileURL,
                                                kLSRequestBasicFlagsOnly,
                                                &infoRec)) {
                if (infoRec.flags & kLSItemInfoIsInvisible) {
                  continue;
                }
              }
              path = [container stringByAppendingPathComponent:path];
              HGSResult *result = [HGSResult resultWithFilePath:path
                                                         source:self
                                                     attributes:nil];
              [contents addObject:result];
            }
          }
          [operation setResults:contents]; 
        }
      }
    }
  }
  [operation finishQuery];
}

@end
