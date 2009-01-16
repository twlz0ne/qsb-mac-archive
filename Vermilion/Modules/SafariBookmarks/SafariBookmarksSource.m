//
//  HGSSafariBookmarksSource.m
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
#import "GTMFileSystemKQueue.h"

NSString *const kSafariBookmarksPath = @"~/Library/Safari/Bookmarks.plist";

// In-memory storage keys
static NSString* const kCachedHGSResultObject = @"ResultObject";
static NSString* const kCachedNameTerms = @"NameTerms";

//
// HGSSafariBookmarksSource
//
// Implements a Search Source for finding Safari Bookmarks.
//
@interface HGSSafariBookmarksSource : HGSMemorySearchSource {
 @private
  GTMFileSystemKQueue* fileKQueue_;
}
- (void)updateIndex;
- (void)indexSafariBookmarksForDict:(NSDictionary *)dict;
- (void)indexBookmark:(NSDictionary*)dict;
@end

@implementation HGSSafariBookmarksSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSString *path = [kSafariBookmarksPath stringByStandardizingPath];
    GTMFileSystemKQueueEvents safariEvents = (kGTMFileSystemKQueueDeleteEvent 
                                              | kGTMFileSystemKQueueWriteEvent);

    fileKQueue_ 
      = [[GTMFileSystemKQueue alloc] initWithPath:path
                                        forEvents:safariEvents
                                    acrossReplace:YES
                                           target:self
                                           action:@selector(fileChanged:event:)];
    [self updateIndex];
  }
  return self;  
}

- (void)dealloc {
  [fileKQueue_ release];
  [super dealloc];
}

#pragma mark -

- (void)indexSafariBookmarksForDict:(NSDictionary *)dict {
  NSString *title = [dict objectForKey:@"Title"];
  if ([title isEqualToString:@"Archive"]) return; // Skip Archive folder

  NSEnumerator *childEnum = [[dict objectForKey:@"Children"] objectEnumerator];
  NSDictionary *child;
  while ((child = [childEnum nextObject])) {
    NSString *type = [child objectForKey:@"WebBookmarkType"];
    if ([type isEqualToString:@"WebBookmarkTypeLeaf"]) {
      [self indexBookmark:child];
    } else if ([type isEqualToString:@"WebBookmarkTypeList"]) {
      [self indexSafariBookmarksForDict:child];
    }
  }
}

- (void)indexBookmark:(NSDictionary*)dict {
  NSString* title = [[dict objectForKey:@"URIDictionary"] objectForKey:@"title"];
  NSString* urlString = [dict objectForKey:@"URLString"];
  
  if (!title || !urlString) {
    return;
  }
  NSURL* url = [NSURL URLWithString:urlString];
  if (!url) {
    return;
  }
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSUnderHomeRankFlag 
                         | eHGSNameMatchRankFlag];
  NSImage *icon = [NSImage imageNamed:@"blue-bookmark"];
  NSDictionary *attributes
    = [NSDictionary dictionaryWithObjectsAndKeys:
       urlString, kHGSObjectAttributeSourceURLKey,
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       icon, kHGSObjectAttributeIconKey,
       nil];
  HGSObject* result 
    = [HGSObject objectWithIdentifier:url
                                 name:title
                                 type:HGS_SUBTYPE(kHGSTypeWebBookmark, @"safari")
                               source:self
                           attributes:attributes];
  [self indexResult:result
         nameString:title
        otherString:nil];
}

- (void)updateIndex {
  [self clearResultIndex];
  NSString *path = [kSafariBookmarksPath stringByStandardizingPath];
  NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
  if (dict) {
    [self indexSafariBookmarksForDict:dict];
  }
}

- (void)fileChanged:(GTMFileSystemKQueue *)queue 
              event:(GTMFileSystemKQueueEvents)event {
  [self updateIndex];
}

@end

