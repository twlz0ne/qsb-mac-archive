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
#import <GData/GDataHTTPFetcher.h>
#import "KeychainItem.h"
#import "GTMGoogleSearch.h"


static const NSTimeInterval kRefreshSeconds = 3600.0;  // 60 minutes.

// Only report errors to user once an hour.
static const NSTimeInterval kErrorReportingInterval = 3600.0;  // 1 hour

@interface GoogleBookmarksSource : HGSMemorySearchSource <HGSAccountClientProtocol> {
 @private
  __weak NSTimer *updateTimer_;
  HGSSimpleAccount *account_;
  GDataHTTPFetcher *fetcher_;
  BOOL currentlyFetching_;
  NSUInteger previousFailureCount_;
}

- (void)setUpPeriodicRefresh;
- (void)startAsynchronousBookmarkFetch;
- (void)indexBookmarksFromData:(NSData*)data;
- (void)indexBookmarkNode:(NSXMLNode*)bookmarkNode;

@end

@implementation GoogleBookmarksSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    account_ = [[configuration objectForKey:kHGSExtensionAccount] retain];
    if (account_) {
      // Fetch, and schedule a timer to update every hour.
      [self startAsynchronousBookmarkFetch];
      [self setUpPeriodicRefresh];
      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSAccountDidChangeNotification
               object:account_];
    }
  }
  return self;
}

- (void)uninstall {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [updateTimer_ invalidate];
  updateTimer_ = nil;
  [fetcher_ release];
  fetcher_ = nil;
  [account_ release];
}


#pragma mark -
#pragma mark Bookmarks Fetching

- (void)startAsynchronousBookmarkFetch {
  if (!currentlyFetching_) {
    if (!fetcher_) {
      GTMGoogleSearch *gsearch = [GTMGoogleSearch sharedInstance];
      NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
                            @"rss", @"output", @"10000", @"num", nil];
      NSString *bookmarkRequestString
        = [gsearch searchURLFor:nil 
                         ofType:@"bookmarks/find" 
                      arguments:args];
      NSURL *bookmarkRequestURL = [NSURL URLWithString:bookmarkRequestString];
      NSMutableURLRequest *bookmarkRequest
        = [NSMutableURLRequest
           requestWithURL:bookmarkRequestURL 
              cachePolicy:NSURLRequestReloadIgnoringCacheData 
          timeoutInterval:15.0];
      fetcher_ = [[GDataHTTPFetcher httpFetcherWithRequest:bookmarkRequest]
                  retain];
      if (!fetcher_) {
        HGSLog(@"Failed to allocate GDataAuthenticationFetcher.");
      }
      KeychainItem* keychainItem 
        = [KeychainItem keychainItemForService:[account_ identifier]
                                      username:nil];
      NSString *userName = [keychainItem username];
      NSString *password = [keychainItem password];
      [fetcher_ setCredential:
       [NSURLCredential credentialWithUser:userName
                                  password:password
                               persistence:NSURLCredentialPersistenceNone]];
      [bookmarkRequest setHTTPMethod:@"POST"];
      [bookmarkRequest setHTTPShouldHandleCookies:NO];
      [fetcher_ setRequest:bookmarkRequest];
    }
      
    currentlyFetching_ = YES;
    [fetcher_ beginFetchWithDelegate:self
                   didFinishSelector:@selector(httpFetcher:finishedWithData:)
                     didFailSelector:@selector(httpFetcher:didFail:)];
  }
}

- (void)refreshBookmarks:(NSTimer *)timer {
  updateTimer_ = nil;
  [self startAsynchronousBookmarkFetch];
  [self setUpPeriodicRefresh];
}

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
  NSArray *nodeChildren = [bookmarkNode children];
  for (NSXMLNode *infoNode in nodeChildren) {
    NSString *infoNodeName = [infoNode name];
    if ([infoNodeName isEqualToString:@"title"]) {
      title = [infoNode stringValue];
    } else if ([infoNodeName isEqualToString:@"link"]) {
      url = [infoNode stringValue];
      // TODO(stuartmorgan): break the URI, and make those into title terms as well
    } else if ([infoNodeName isEqualToString:@"smh:bkmk_label"] ||
               [infoNodeName isEqualToString:@"smh:bkmk_annotation"]) {
      NSString *infoNodeString = [infoNode stringValue];
      [otherTermStrings addObject:infoNodeString];
    }
  }

  if (!url) {
    return;
  }
  
  NSImage *icon = [NSImage imageNamed:@"blue-nav"];
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSUnderHomeRankFlag];
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       url, kHGSObjectAttributeSourceURLKey,
       icon, kHGSObjectAttributeIconKey,
       @"star-flag", kHGSObjectAttributeFlagIconNameKey,
       nil];
  HGSResult* result 
    = [HGSResult resultWithURI:url
                          name:([title length] > 0 ? title : url)
                          type:HGS_SUBTYPE(kHGSTypeWebBookmark,
                                           @"googlebookmarks")
                        source:self
                    attributes:attributes];
  [self indexResult:result
               name:title
         otherTerms:otherTermStrings];
}

#pragma mark -
#pragma mark GDataHTTPFetcher Helpers

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  currentlyFetching_ = NO;
  [self indexBookmarksFromData:retrievedData];
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
            didFail:(NSError *)error {
  HGSLog(@"httpFetcher failed: %@ %@", error, [[fetcher request] URL]);
  currentlyFetching_ = NO;
}

#pragma mark -
#pragma mark Authentication & Refresh

- (void)loginCredentialsChanged:(NSNotification *)notification {
  HGSAccount *account = [notification object];
  HGSAssert(account == account_, @"Notification from bad account!");
  // Make sure we aren't in the middle of waiting for results; if we are, try
  // again later instead of changing things in the middle of the fetch.
  if (currentlyFetching_) {
    [self performSelector:@selector(loginCredentialsChanged:)
               withObject:notification
               afterDelay:60.0];
    return;
  }
  // If the login changes, we should update immediately, and make sure the
  // periodic refresh is enabled (it would have been shut down if the previous
  // credentials were incorrect).
  [self startAsynchronousBookmarkFetch];
  [self setUpPeriodicRefresh];
}

- (void)setUpPeriodicRefresh {
  [updateTimer_ invalidate];
  // We add 5 minutes worth of random jitter.
  NSTimeInterval jitter = random() / (LONG_MAX / (NSTimeInterval)300.0);
  updateTimer_ 
    = [NSTimer scheduledTimerWithTimeInterval:kRefreshSeconds + jitter
                                       target:self
                                     selector:@selector(refreshBookmarks:)
                                     userInfo:nil
                                      repeats:NO];
}

#pragma mark -
#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(HGSAccount *)account {
  HGSAssert(account == account_, @"Notification from bad account!");
  return YES;
}

@end
