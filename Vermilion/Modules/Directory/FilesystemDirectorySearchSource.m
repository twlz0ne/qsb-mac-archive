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
  return YES;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSFileManager *fm = [NSFileManager defaultManager];
  HGSQuery *query = [operation query];
  // use the raw query since we're trying to match paths to specific folders.
  NSString *queryString = [query rawQueryString];
  HGSObject *pivotObject = [query pivotObject];
  
  if (pivotObject) {
    NSURL *url = [pivotObject identifier];
    NSString *path = [url path];
    
    NSMutableArray *results = [NSMutableArray array];
    
    NSArray *contents = [fm directoryContentsAtPath:path];
    NSEnumerator *enumerator = [contents objectEnumerator];
    NSString *subpath;
    while ((subpath = [enumerator nextObject])) {
      if ([subpath hasPrefix:@"."]) continue;
      // if we have a query string, we exact prefix match (no tokenize, etc.)
      if ([queryString length] && ![subpath hasCaseInsensitivePrefix:queryString]) continue;
      subpath = [path stringByAppendingPathComponent:subpath];
      
      HGSObject *result = [HGSObject objectWithFilePath:subpath 
                                                 source:self 
                                             attributes:nil];
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
        HGSObject *result = [HGSObject objectWithFilePath:path 
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
              HGSObject *object = [HGSObject objectWithFilePath:path
                                                         source:self
                                                     attributes:nil];
              [contents addObject:object];
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
