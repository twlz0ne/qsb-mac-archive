//
//  HGSCaminoBookmarksSource.m
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

NSString *const kCaminoBookmarksPath 
  = @"~/Library/Application Support/Camino/Bookmarks.plist";

static NSURL* domainURLForURLString(NSString* urlString) {
  // This is parsed manually rather than round-tripped through NSURL so that
  // we can get domains from invalid URLs (like Camino search bookmarks).
  NSRange schemeEndRange = [urlString rangeOfString:@"://"];
  NSUInteger domainStartIndex = 0;
  if (schemeEndRange.location != NSNotFound)
    domainStartIndex = schemeEndRange.location + schemeEndRange.length;
  if (domainStartIndex >= [urlString length])
    return nil;

  NSRange domainRange = NSMakeRange(domainStartIndex,
                                    [urlString length] - domainStartIndex);
  NSRange pathStartRange = [urlString rangeOfString:@"/"
                                            options:0
                                              range:domainRange];
  NSString* domainString;
  if (pathStartRange.location == NSNotFound)
    domainString = urlString;
  else
    domainString = [urlString substringToIndex:pathStartRange.location];
  return [NSURL URLWithString:domainString];
}

@interface HGSCaminoBookmarksSource : HGSMemorySearchSource {
 @private
  GTMFileSystemKQueue *fileKQueue_;
}
- (void)updateIndex;
- (void)indexCaminoBookmarksForDict:(NSDictionary *)dict;
- (void)indexBookmark:(NSDictionary*)dict;
@end

@implementation HGSCaminoBookmarksSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSString *path = [kCaminoBookmarksPath stringByStandardizingPath];
    GTMFileSystemKQueueEvents caminoEvents = (kGTMFileSystemKQueueDeleteEvent 
                                              | kGTMFileSystemKQueueWriteEvent);
    fileKQueue_
      = [[GTMFileSystemKQueue alloc] initWithPath:path
                                        forEvents:caminoEvents
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

- (void)indexCaminoBookmarksForDict:(NSDictionary *)dict {
  NSArray *children = [dict objectForKey:@"Children"];
  if (children) {
    for (NSDictionary *child in children) {
      [self indexCaminoBookmarksForDict:child];
    }
  } else {
    [self indexBookmark:dict];
  }
}

- (void)indexBookmark:(NSDictionary*)dict {
  NSString* title = [dict objectForKey:@"Title"];
  NSString* urlString = [dict objectForKey:@"URL"];
  if (!title || !urlString) {
    return;
  }
  
  NSURL* url = [NSURL URLWithString:urlString];
  if (!url && [urlString rangeOfString:@"%s"].location != NSNotFound) {
    // If it couldn't make a URL because it choked on a search template
    // marker, just use the domain as a best-gues raw URL.
    url = domainURLForURLString(urlString);
  }
  if (!url) {
    return;
  }
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSUnderHomeRankFlag];
  NSImage *icon = [NSImage imageNamed:@"blue-nav"];
  NSMutableDictionary *attributes
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       urlString, kHGSObjectAttributeSourceURLKey, 
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       icon, kHGSObjectAttributeIconKey,
       @"star-flag", kHGSObjectAttributeFlagIconNameKey,
       nil];
  NSDate* lastVisit = [dict objectForKey:@"LastVisitedDate"];
  if (lastVisit) {
    [attributes setObject:lastVisit forKey:kHGSObjectAttributeLastUsedDateKey];
  }

  NSString *nameString = title;

  // Pre-parse the name into terms for faster searching, and store them.
  NSString* shortcut = [dict objectForKey:@"Keyword"];
  if (shortcut) {
    // add the shortcut for the nameString so it will be counted as a name match
    // when searching
    nameString = [nameString stringByAppendingFormat:@" %@", shortcut];
    // If it has a shortcut, it may be a search bookmark; if it is, mark it
    // appropriately.
    NSRange searchMarkerRange = [urlString rangeOfString:@"%s"];
    if (searchMarkerRange.location != NSNotFound) {
      NSMutableString* searchTemplate 
        = [NSMutableString stringWithString:urlString];
      [searchTemplate replaceCharactersInRange:searchMarkerRange 
                                    withString:@"{searchterms}"];
      [attributes setObject:searchTemplate 
                     forKey:kHGSObjectAttributeWebSearchTemplateKey];
    }
  }
  HGSResult* result 
    = [HGSResult resultWithURL:url
                          name:title
                          type:HGS_SUBTYPE(kHGSTypeWebBookmark, @"camino")
                        source:self
                    attributes:attributes];
  // Get description terms, and store those as non-title-match data.
  [self indexResult:result
               name:nameString
          otherTerm:[dict objectForKey:@"Description"]];
}

- (void)updateIndex {
  [self clearResultIndex];
  NSString *path = [kCaminoBookmarksPath stringByStandardizingPath];
  NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path];
  if (dict) {
    [self indexCaminoBookmarksForDict:dict];
  }
}

- (void)fileChanged:(GTMFileSystemKQueue *)queue 
              event:(GTMFileSystemKQueueEvents)event {
  [[self retain] autorelease];
  [self updateIndex];
}

@end

