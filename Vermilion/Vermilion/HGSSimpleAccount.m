//
//  HGSSimpleAccount.m
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

#import "HGSSimpleAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "HGSBundle.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"
#import "KeychainItem.h"
#import <GData/GDataHTTPFetcher.h>


// Authentication retry timing constants.
static const NSTimeInterval kAuthenticationRetryInterval = 0.1;
static const NSTimeInterval kAuthenticationGiveUpInterval = 30.0;


@implementation HGSSimpleAccount

@synthesize connection = connection_;

- (id)initWithName:(NSString *)userName {
  // Perform any adjustments on the account name required.
  userName = [self adjustUserName:userName];
  self = [super initWithName:userName];
  return self;
}

- (id)initWithConfiguration:(NSDictionary *)prefDict {
  if ((self = [super initWithConfiguration:prefDict])) {
    if ([self keychainItem]) {
      // We assume the account is still available but will soon be
      // authenticated (for sources that index) or as soon as an action
      // using the account is attempted.
      [self setAuthenticated:YES];
    } else {
      NSString *keychainServiceName = [self identifier];
      HGSLogDebug(@"No keychain item found for service name '%@'", 
                  keychainServiceName);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [self setConnection:nil];
  [super dealloc];
}

- (BOOL)isEditable {
  BOOL isEditable = NO;
  NSString *keychainServiceName = [self identifier];
  if ([keychainServiceName length]) {
    KeychainItem *item = [KeychainItem keychainItemForService:keychainServiceName 
                                                     username:nil];
    isEditable = (item != nil);
  }
  return isEditable;
}

- (void)remove {
  KeychainItem *keychainItem = [self keychainItem];
  [keychainItem removeFromKeychain];
  [super remove];
}

- (NSString *)password {
  // Retrieve the account's password from the keychain.
  KeychainItem *keychainItem = [self keychainItem];
  NSString *password = [keychainItem password];
  return password;
}

- (void)setPassword:(NSString *)password {
  KeychainItem *keychainItem = [self keychainItem];
  NSString *userName = [self userName];
  if (keychainItem) {
    [keychainItem setUsername:userName
                     password:password];
  } else {
    NSString *keychainServiceName = [self identifier];
    [KeychainItem addKeychainItemForService:keychainServiceName
                               withUsername:userName
                                   password:password]; 
  }
  [super setPassword:password];
}

- (NSString *)adjustUserName:(NSString *)userName {
  return userName;
}

- (void)authenticate {
  NSURLRequest *accountRequest = [self accountURLRequest];
  if (accountRequest) {
    NSURLConnection *connection
      = [NSURLConnection connectionWithRequest:accountRequest delegate:self];
    [self setConnection:connection];
  }
}

- (BOOL)authenticateWithPassword:(NSString *)password {
  BOOL authenticated = NO;
  // Test this account to see if we can connect.
  NSString *userName = [self userName];
  NSURLRequest *accountRequest = [self accountURLRequestForUserName:userName
                                                           password:password];
  if (accountRequest) {
    GDataHTTPFetcher* authenticateFetcher
    = [GDataHTTPFetcher httpFetcherWithRequest:accountRequest];
    NSArray *modes = [NSArray arrayWithObjects:
                      NSDefaultRunLoopMode, NSModalPanelRunLoopMode, nil];
    [authenticateFetcher setRunLoopModes:modes];
    [authenticateFetcher setIsRetryEnabled:YES];
    authenticationResult_ = NO;
    if ([authenticateFetcher beginFetchWithDelegate:self
                                  didFinishSelector:@selector(authenticateFetcher:
                                                              finishedWithData:)
                                    didFailSelector:@selector(authenticateFetcher:
                                                              failedWithError:)]) {
      // Block until this fetch is done to make it appear synchronous. Sleep
      // for a second and then check again until is has completed.  Just in
      // case, put an upper limit of 30 seconds before we bail.
      authenticationFinished_ = NO;
      NSDate *startTime = [NSDate date];
      NSRunLoop* loop = [NSRunLoop currentRunLoop];
      while (!authenticationFinished_) {
        [loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:
                            kAuthenticationRetryInterval]];
        NSTimeInterval elapsedTime = -[startTime timeIntervalSinceNow];
        if (elapsedTime > kAuthenticationGiveUpInterval) {
          [authenticateFetcher stopFetching];
          authenticationFinished_ = YES;
        }
      }
    }
    authenticated = authenticationResult_;
  }
  return authenticated;
}

- (NSURLRequest *)accountURLRequest {
  KeychainItem* keychainItem 
    = [KeychainItem keychainItemForService:[self identifier] 
                                  username:nil];
  NSString *userName = [keychainItem username];
  NSString *password = [keychainItem password];
  NSURLRequest *accountRequest = [self accountURLRequestForUserName:userName
                                                           password:password];
  return accountRequest;
}

- (NSURLRequest *)accountURLRequestForUserName:(NSString *)userName
                                      password:(NSString *)password {
  HGSLog(@"Class '%@' should override accountURLRequestForUserName:"
         @"password:.", [self className]);
  return nil;
}

- (void)setConnection:(NSURLConnection *)connection {
  [connection_ cancel];
  [connection_ release];
  connection_ = [connection retain];
}

#pragma mark HGSSimpleAccount Private Methods

- (KeychainItem *)keychainItem {
  NSString *keychainServiceName = [self identifier];
  NSString *userName = [self userName];
  KeychainItem *item = [KeychainItem keychainItemForService:keychainServiceName 
                                                   username:userName];
  return item;
}

#pragma mark GDataHTTPFetcher Callback Methods

- (void)authenticateFetcher:(GDataHTTPFetcher *)fetcher
           finishedWithData:(NSData *)data {
  authenticationResult_ = YES;
  authenticationFinished_ = YES;
}

- (void)authenticateFetcher:(GDataHTTPFetcher *)fetcher
            failedWithError:(NSError *)error {
  authenticationResult_ = NO;
  authenticationFinished_ = YES;
}

#pragma mark NSURLConnection Delegate Methods

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  HGSAssert(connection == connection_, nil);
  [self setConnection:nil];
  [self setAuthenticated:YES];
}

- (void)connection:(NSURLConnection *)connection 
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  HGSAssert(connection == connection_, nil);
  [self setAuthenticated:NO];
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error {
  HGSAssert(connection == connection_, nil);
  [self setConnection:nil];
  [self setAuthenticated:NO];
}

@end
