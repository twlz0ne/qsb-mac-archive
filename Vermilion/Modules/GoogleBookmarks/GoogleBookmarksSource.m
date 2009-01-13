//
//  GoogleBookmarksSource.m
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
#import <Vermilion/KeychainItem.h>

// For now, use our own password so that we aren't trying to get bookmarks for
// hosted or non-bookmark-user accounts.
static NSString *const kBookmarksServiceName 
  = @"Vermilion Google Bookmarks Login";

static NSString *const kBookmarkFeedURL 
  = @"https://www.google.com/bookmarks/lookup?output=rss";

@interface GoogleBookmarksSource : HGSMemorySearchSource {
  NSTimer *updateTimer_;
  NSMutableData *bookmarkData_;
}
- (void)startAsynchronousBookmarkFetch;
- (void)indexBookmarksFromData:(NSData*)data;
- (void)indexBookmarkNode:(NSXMLNode*)bookmarkNode;
@end

@implementation GoogleBookmarksSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Fetch, and schedule a timer to update every hour.
    [self startAsynchronousBookmarkFetch];
    updateTimer_ 
      = [[NSTimer scheduledTimerWithTimeInterval:(60 * 60)
                                          target:self
                                        selector:@selector(refreshBookmarks:)
                                        userInfo:nil
                                         repeats:YES] retain];
  }
  return self;
}

- (void)dealloc {
  if ([updateTimer_ isValid]) {
    [updateTimer_ invalidate];
  }
  [updateTimer_ release];
  [bookmarkData_ release];

  [super dealloc];
}


#pragma mark -
#pragma mark Bookmarks Fetching

- (void)startAsynchronousBookmarkFetch {
  NSURL *bookmarkFeedURL = [NSURL URLWithString:kBookmarkFeedURL];
  NSURLRequest* request = [NSURLRequest requestWithURL:bookmarkFeedURL];
  [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)refreshBookmarks:(NSTimer *)timer {
  [self startAsynchronousBookmarkFetch];
}

#pragma mark -

- (void)indexBookmarksFromData:(NSData *)data {
  NSXMLDocument* bookmarksXML 
    = [[[NSXMLDocument alloc] initWithData:data
                                   options:0
                                     error:nil] autorelease];
  NSArray *bookmarkNodes = [bookmarksXML nodesForXPath:@"//item" error:NULL];
  [self clearResultIndex];
  NSEnumerator *nodeEnumerator = [bookmarkNodes objectEnumerator];
  NSXMLNode *bookmark;
  while ((bookmark = [nodeEnumerator nextObject])) {
    [self indexBookmarkNode:bookmark];
  }
}

- (void)indexBookmarkNode:(NSXMLNode*)bookmarkNode {
  NSString *title = nil;
  NSString *url = nil;
  NSMutableArray *otherTermStrings = [NSMutableArray array];
  NSEnumerator *infoNodeEnumerator = [[bookmarkNode children] objectEnumerator];
  NSXMLNode *infoNode;
  while ((infoNode = [infoNodeEnumerator nextObject])) {
    if ([[infoNode name] isEqualToString:@"title"]) {
      title = [infoNode stringValue];
    } else if ([[infoNode name] isEqualToString:@"link"]) {
      url = [infoNode stringValue];
      // TODO(stuartmorgan): break the URI, and make those into title terms as well
    } else if ([[infoNode name] isEqualToString:@"smh:bkmk_label"] ||
               [[infoNode name] isEqualToString:@"smh:bkmk_annotation"]) {
      [otherTermStrings addObject:[infoNode stringValue]];
    }
  }

  if (!url) {
    return;
  }
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSUnderHomeRankFlag];
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       url, kHGSObjectAttributeSourceURLKey,
       nil];
  HGSObject* result 
    = [HGSObject objectWithIdentifier:[NSURL URLWithString:url]
                                 name:([title length] > 0 ? title : url)
                                 type:HGS_SUBTYPE(kHGSTypeWebBookmark, @"googlebookmarks")
                               source:self
                           attributes:attributes];
  [self indexResult:result
         nameString:title
  otherStringsArray:otherTermStrings];
}

#pragma mark -

- (void)connection:(NSURLConnection *)connection 
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  KeychainItem *loginCredentials 
    = [KeychainItem keychainItemForService:kBookmarksServiceName
                                  username:nil];
  id<NSURLAuthenticationChallengeSender> sender = [challenge sender];
  if (loginCredentials && [challenge previousFailureCount] < 3) {
    NSURLCredential *creds 
      = [NSURLCredential credentialWithUser:[loginCredentials username]
                                   password:[loginCredentials password]
                                persistence:NSURLCredentialPersistenceForSession];
    [sender useCredential:creds forAuthenticationChallenge:challenge];
  } else {
    [sender continueWithoutCredentialForAuthenticationChallenge:challenge];
  }
}

- (void)connection:(NSURLConnection *)connection 
didReceiveResponse:(NSURLResponse *)response {
  [bookmarkData_ release];
  bookmarkData_ = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection 
    didReceiveData:(NSData *)data {
  [bookmarkData_ appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  [self indexBookmarksFromData:bookmarkData_];
  [bookmarkData_ release];
  bookmarkData_ = nil;
}

- (void)connection:(NSURLConnection *)connection 
  didFailWithError:(NSError *)error {
  [bookmarkData_ release];
  bookmarkData_ = nil;
}

@end
