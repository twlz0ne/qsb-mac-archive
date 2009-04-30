//
//  TwitterMessageAction.m
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
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "KeychainItem.h"

static NSString *const kMessageBodyFormat = @"status=%@";
static NSString *const kSendStatusFormat
  = @"https://%@:%@@twitter.com/statuses/update.xml?"
    @"source=googlequicksearchboxmac&status=%@";

// An action that will send a status update message for a Twitter account.
//
@interface TwitterSendMessageAction : HGSAction <HGSAccountClientProtocol> {
 @private
  HGSSimpleAccount *account_;
  NSURLConnection *twitterConnection_;
}

// Called by performWithInfo: to actually send the message.
- (void)sendTwitterStatus:(NSString *)twitterMessage;

// Utility function to send notification so user can be notified of
// success or failure.
- (void)informUserWithDescription:(NSString *)description
                      successCode:(NSInteger)successCode;

@end


@implementation TwitterSendMessageAction

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    account_ = [[configuration objectForKey:kHGSExtensionAccount] retain];
    if (account_) {
      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSAccountDidChangeNotification
               object:account_];
    } else {
      HGSLogDebug(@"Missing account identifier for TwitterMessageAction '%@'",
                  [self identifier]);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [account_ release];
  [twitterConnection_ release];
  [super dealloc];
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
    = [info objectForKey:kHGSActionDirectObjectsKey];
  BOOL success = NO;
  if (directObjects) {
    // Pull something out of |directObjects| that can be turned into a tweet.
    NSString *message = [directObjects displayName];
    [self sendTwitterStatus:message];
    success = YES;
  }
  return success;
}

- (void)sendTwitterStatus:(NSString *)twitterMessage {
  if (twitterMessage) {
    KeychainItem* keychainItem 
      = [KeychainItem keychainItemForService:[account_ identifier]
                                    username:nil];
    NSString *username = [keychainItem username];
    NSString *password = [keychainItem password];
    if (username && password) {
      if ([twitterMessage length] > 140) {
        NSString *warningString
          = HGSLocalizedString(@"Message too long — truncated.", 
                               @"A dialog label explaining that their Twitter "
                               @"message was too long and was truncated");
        [self informUserWithDescription:warningString
                            successCode:kHGSSuccessCodeError];
        twitterMessage = [twitterMessage substringToIndex:140];
      }
      
      NSString *encodedMessage
        = [twitterMessage gtm_stringByEscapingForURLArgument];
      NSString *encodedMessageBody
        = [NSString stringWithFormat:kMessageBodyFormat, encodedMessage];
      NSString *encodedAccountName
        = [username gtm_stringByEscapingForURLArgument];
      NSString *encodedPassword = [password gtm_stringByEscapingForURLArgument];
      NSString *sendStatusString = [NSString stringWithFormat:kSendStatusFormat,
                                    encodedAccountName, encodedPassword,
                                    encodedMessage];
      NSURL *sendStatusURL = [NSURL URLWithString:sendStatusString];
      
      // Construct an NSMutableURLRequest for the URL and set appropriate
      // request method.
      NSMutableURLRequest *sendStatusRequest
        = [NSMutableURLRequest requestWithURL:sendStatusURL 
                                  cachePolicy:NSURLRequestReloadIgnoringCacheData 
                              timeoutInterval:15.0];
      [sendStatusRequest setHTTPMethod:@"POST"];
      [sendStatusRequest setHTTPShouldHandleCookies:NO];
      [sendStatusRequest setValue:@"QuickSearchBox"
               forHTTPHeaderField:@"X-Twitter-Client"];
      [sendStatusRequest setValue:@"1.0.0"
               forHTTPHeaderField:@"X-Twitter-Client-Version"];
      [sendStatusRequest setValue:@"http://www.google.com/qsb-mac"
               forHTTPHeaderField:@"X-Twitter-Client-URL"];
      
      // Set request body, if specified (hopefully so), with 'source'
      // parameter if appropriate.
      NSData *bodyData
        = [encodedMessageBody dataUsingEncoding:NSUTF8StringEncoding];
      [sendStatusRequest setHTTPBody:bodyData];
      twitterConnection_ 
        = [[NSURLConnection alloc] initWithRequest:sendStatusRequest 
                                          delegate:self];
    } else {
      NSString *errorString
        = HGSLocalizedString(@"Could not tweet. Please check the password for "
                             @"account %@", 
                             @"A dialog label explaining that the user could "
                             @"not send their Twitter data due to a bad "
                             @"password for account %@");
      errorString = [NSString stringWithFormat:errorString, username];
      [self informUserWithDescription:errorString
                          successCode:kHGSSuccessCodeError];
      HGSLog(@"Cannot send Twitter status message due to missing keychain "
             @"item for '%@'.", account_);
    }
  }
}

- (void)informUserWithDescription:(NSString *)description
                      successCode:(NSInteger)successCode {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSBundle *bundle = HGSGetPluginBundle();
  NSString *path = [bundle pathForResource:@"Twitter" ofType:@"icns"];
  NSImage *twitterT
    = [[[NSImage alloc] initByReferencingFile:path] autorelease];
  NSNumber *successNumber = [NSNumber numberWithInt:successCode];
  NSString *summary 
    = HGSLocalizedString(@"Twitter", 
                         @"A dialog title. Twitter is a product name");
  NSDictionary *messageDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       summary, kHGSSummaryMessageKey,
       twitterT, kHGSImageMessageKey,
       successNumber, kHGSSuccessCodeMessageKey,
       // Description last since it might be nil.
       description, kHGSDescriptionMessageKey,
       nil];
  [nc postNotificationName:kHGSUserMessageNotification 
                    object:self
                  userInfo:messageDict];
}

- (void)loginCredentialsChanged:(NSNotification *)notification {
  HGSAccount *account = [notification object];
  HGSAssert(account == account_, @"Notification from bad account!");
}

#pragma mark NSURLConnection Delegate Methods

- (void)connection:(NSURLConnection *)connection 
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  HGSAssert(connection == twitterConnection_, nil);
  KeychainItem* keychainItem 
    = [KeychainItem keychainItemForService:[account_ identifier]
                                  username:nil];
  NSString *userName = [keychainItem username];
  NSString *password = [keychainItem password];
  // See if the account still validates.
  BOOL accountAuthenticates = [account_ authenticateWithPassword:password];
  if (accountAuthenticates) {
    id<NSURLAuthenticationChallengeSender> sender = [challenge sender];
    NSInteger previousFailureCount = [challenge previousFailureCount];
    if (userName && password && previousFailureCount < 3) {
      NSURLCredential *creds 
        = [NSURLCredential credentialWithUser:userName
                                     password:password
                                  persistence:NSURLCredentialPersistenceNone];
      [sender useCredential:creds forAuthenticationChallenge:challenge];
    } else {
      [sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
  } else {
    NSString *errorString
      = HGSLocalizedString(@"Could not tweet. Please check the password for "
                           @"account %@", 
                           @"A dialog label explaining that the user could "
                           @"not send their Twitter data due to a bad "
                           @"password for account %@");
    errorString = [NSString stringWithFormat:errorString, userName];
    [self informUserWithDescription:errorString
                        successCode:kHGSSuccessCodeError];
    HGSLog(@"Twitter status message failed due to authentication failure "
           @"for account ''.", userName);
  }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  HGSAssert(connection == twitterConnection_, nil);
  NSString *successString = HGSLocalizedString(@"Message tweeted!", 
                                               @"A dialog label explaning that "
                                               @"the user's message has been "
                                               @"successfully sent to Twitter");
  [self informUserWithDescription:successString
                      successCode:kHGSSuccessCodeSuccess];
  [twitterConnection_ release];
  twitterConnection_ = nil;
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error {
  HGSAssert(twitterConnection_ == connection, nil);
  NSString *errorFormat
    = HGSLocalizedString(@"Could not tweet! (%d)", 
                         @"A dialog label explaining to the user that we could "
                         @"not tweet. %d is an error code.");
  NSString *errorString = [NSString stringWithFormat:errorFormat,
                           [error code]];
  [self informUserWithDescription:errorString
                      successCode:kHGSSuccessCodeBadError];
  HGSLog(@"Twitter status message failed due to error %d: '%@'.",
         [error code], [error localizedDescription]);
  [twitterConnection_ release];
  twitterConnection_ = nil;
}

#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(HGSAccount *)account {
  HGSAssert(account == account_, @"Notification from bad account!");
  return YES;
}

@end
