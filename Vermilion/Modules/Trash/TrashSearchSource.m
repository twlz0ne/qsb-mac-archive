//
//  TrashSearchSource.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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

static NSString *kTrashResultType = HGS_SUBTYPE(@"trash", @"Trash");
static NSString *kTrashResultUrl = @"gtrash://trash/result";

@interface TrashSearchSource : HGSCallbackSearchSource {
 @private
  NSImage *trashIcon_;
}
@end

@implementation TrashSearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSString *path = [HGSGetPluginBundle() pathForResource:@"MoveToTrash"
                                                    ofType:@"icns"];
    trashIcon_= [[NSImage alloc] initByReferencingFile:path];
  }
  return self;
}

- (void) dealloc {
  [trashIcon_ release];
  [super dealloc];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // We're a valid source if the user is searching for "Trash",
  // from which we'll return our specialized result for the
  // trash; or if the user has pivoted on our specialized
  // result, from which we'll return the contents of the
  // trash(es). Those results are normal files and directories,
  // and can be pivoted upon and acted upon by the normal
  // contingent of plugins.
  HGSResult *pivotObject = [query pivotObject];
  BOOL isValid = NO;
  if (pivotObject) {
    isValid = [[pivotObject type] isEqual:kTrashResultType];
  } else {
    NSString *trash = HGSLocalizedString(@"Trash", 
                                         @"The label for a result denoting the "
                                         @"trash can found on your dock.");
    trash = [trash lowercaseString];
    NSString *queryString = [query normalizedQueryString];
    isValid = [trash hasPrefix:queryString];
  }
  return isValid;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSMutableArray *results = [NSMutableArray array];
  HGSQuery *query = [operation query];
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    OSErr err = noErr;
    NSString *normalizedQueryString = [query normalizedQueryString];
    for (ItemCount i = 1; err == noErr || err != nsvErr; ++i) {
      FSVolumeRefNum refNum;
      HFSUniStr255 name;
      FSVolumeInfo info;
      err = FSGetVolumeInfo(kFSInvalidVolumeRefNum, i, &refNum,
                           kFSVolInfoFSInfo, &info, &name, NULL);
      if (err == noErr) {
        FSRef trashRef;
        if (FSFindFolder(refNum, kTrashFolderType, kDontCreateFolder,
                         &trashRef) == noErr)  {
          UInt8 trashPath[PATH_MAX];
          if (FSRefMakePath(&trashRef, trashPath, PATH_MAX - 1) == noErr) {
            NSString *basePath
              = [NSString stringWithUTF8String:(char *)trashPath];
            NSArray *contents
              = [[NSFileManager defaultManager]
                 directoryContentsAtPath:basePath];
            NSUInteger normalizedLength = [normalizedQueryString length];
            for (NSString *file in contents) {
              CGFloat rank = 0;
              if (normalizedLength == 0) {
                rank = 1.0;
              } else {
                rank = HGSScoreForAbbreviation(file,
                                               normalizedQueryString, 
                                               NULL);
              }
              if (rank > 0) {
                NSNumber *nsRank = [NSNumber numberWithFloat:rank];
                NSDictionary *attributes 
                  = [NSDictionary dictionaryWithObjectsAndKeys:
                     nsRank, kHGSObjectAttributeRankKey, nil];
                NSString *fullPath
                  = [basePath stringByAppendingPathComponent:file];
                HGSResult *result = [HGSResult resultWithFilePath:fullPath
                                                           source:self
                                                       attributes:attributes];
                [results addObject:result];
              }
            }
          }
        }
      }
    }
  } else {
    NSDictionary *attributes
      = [NSDictionary dictionaryWithObjectsAndKeys:
         trashIcon_, kHGSObjectAttributeIconKey,
         nil];
    NSString *trash = HGSLocalizedString(@"Trash", 
                                         @"The label for a result denoting the "
                                         @"trash can found on your dock.");
    HGSResult *result 
      = [HGSResult resultWithURL:[NSURL URLWithString:kTrashResultUrl]
                            name:trash
                            type:kTrashResultType
                          source:self
                      attributes:attributes];
    [results addObject:result];
  }

  [operation setResults:results];
}

@end
