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
#import "HGSAbbreviationRanker.h"

// This source provides results for directory restricted searches:
// If a pivot object is a folder, it will find direct children with a prefix
// match.
// Additionally, it provides synthetic results for / and ~

@interface FilesystemDirectorySearchSource : HGSCallbackSearchSource
@end

@implementation FilesystemDirectorySearchSource

- (BOOL)isSearchConcurrent {
  return YES;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // We accept file: urls as queries, and raw paths starting with '/' or '~'.
  // (So we force yes since default is a word check)
  BOOL isValid = YES;
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    NSURL *url = [pivotObject url];
    isValid = [url isFileURL];
  } 
  return isValid;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSFileManager *fm = [NSFileManager defaultManager];
  HGSQuery *query = [operation query];
  // use the raw query since we're trying to match paths to specific folders.
  NSString *queryString = [query rawQueryString];
  HGSResult *pivotObject = [query pivotObject];
  BOOL isApplication = [pivotObject conformsToType:kHGSTypeFileApplication];
  if (pivotObject) {
    NSURL *url = [pivotObject url];
    NSString *path = [url path];
    
    NSMutableArray *results = [NSMutableArray array];
    
    NSArray *contents = [fm directoryContentsAtPath:path];
    NSEnumerator *enumerator = [contents objectEnumerator];
    NSString *subpath;
    BOOL showInvisibles = ([query flags] & eHGSQueryShowAlternatesFlag) != 0;
    while ((subpath = [enumerator nextObject])) {
      if (!showInvisibles && [subpath hasPrefix:@"."]) continue;
      
      float score = HGSScoreForAbbreviation(subpath, queryString, nil);
      
      // if we have a query string, we exact prefix match (no tokenize, etc.)
      //if ([queryString length] && ![subpath hasCaseInsensitivePrefix:queryString]) continue;
      if (score <= 0.0) continue;
      
      subpath = [path stringByAppendingPathComponent:subpath];
      
      NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
      if (isApplication && ![queryString length]) {
        [attributes setObject:[NSNumber numberWithInt:eHGSBelowFoldRankFlag] 
                       forKey:kHGSObjectAttributeRankFlagsKey];
      }
      [attributes setObject:[NSNumber numberWithFloat:score] 
                     forKey:kHGSObjectAttributeRankKey];

      HGSResult *result = [HGSResult resultWithFilePath:subpath 
                                                 source:self 
                                             attributes:attributes];
  
      [results addObject:result];
    }

    [operation setResults:results];
  } else {
    // we treat the input as a raw path, so no tokenizing, etc.
    NSString *path = queryString;
    
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
          NSMutableArray *contents = [NSMutableArray array];
          NSEnumerator *e
            = [[fm directoryContentsAtPath:container] objectEnumerator];
          while ((path = [e nextObject])) {
            if ([path hasCaseInsensitivePrefix:partialPath]) {
              LSItemInfoRecord infoRec;
              if (noErr == LSCopyItemInfoForURL((CFURLRef)[NSURL fileURLWithPath:path],
                                                kLSRequestBasicFlagsOnly,
                                                &infoRec)) {
                if (infoRec.flags & kLSItemInfoIsInvisible) continue;
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
