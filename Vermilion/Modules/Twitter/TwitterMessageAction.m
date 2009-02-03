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
  = @"https://%@:%@@twitter.com/statuses/update.xml?status=%@";

// An action that will send a status update message for a Twitter account.
//
@interface TwitterSendMessageAction : HGSAction <HGSAccountClientProtocol> {
 @private
  NSString * accountIdentifier_;
}

- (void)sendTwitterStatus:(NSString *)twitterMessage;

@end


@implementation TwitterSendMessageAction

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    id<HGSAccount> account
      = [configuration objectForKey:kHGSExtensionAccountIdentifier];
    accountIdentifier_ = [[account identifier] retain];
    if (!accountIdentifier_) {
      HGSLogDebug(@"Missing account identifier for TwitterMessageAction '%@'",
                  [self identifier]);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [accountIdentifier_ release];
  [super dealloc];
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  BOOL success = NO;
  if (object) {
    // Pull something out of |object| that can be turned into a tweet.
    NSString *message = [object displayName];
    [self sendTwitterStatus:message];
    success = YES;
  }
  return success;
}

- (void)sendTwitterStatus:(NSString *)twitterMessage {
  if (twitterMessage) {
    KeychainItem* keychainItem 
      = [KeychainItem keychainItemForService:accountIdentifier_
                                    username:nil];
    if (keychainItem) {
      if ([twitterMessage length] > 140) {
        // TODO(mrossetti): Notify user that their message was truncated.
        twitterMessage = [twitterMessage substringToIndex:140];
      }
      
      NSString *encodedMessage = [twitterMessage gtm_stringByEscapingForURLArgument];
      NSString *encodedMessageBody = [NSString stringWithFormat:kMessageBodyFormat,
                                      encodedMessage];
      NSString *accountName = [keychainItem username];
      NSString *encodedAccountName = [accountName gtm_stringByEscapingForURLArgument];
      NSString *password = [keychainItem password];
      NSString *encodedPassword = [password gtm_stringByEscapingForURLArgument];
      NSString *sendStatusString = [NSString stringWithFormat:kSendStatusFormat,
                                    encodedAccountName, encodedPassword, encodedMessage];
      NSURL *sendStatusURL = [NSURL URLWithString:sendStatusString];
      
      // Construct an NSMutableURLRequest for the URL and set appropriate request method.
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
      
      // Set request body, if specified (hopefully so), with 'source' parameter if appropriate.
      NSData *bodyData = [encodedMessageBody dataUsingEncoding:NSUTF8StringEncoding];
      [sendStatusRequest setHTTPBody:bodyData];
      NSURLResponse *sendStatusResponse = nil;
      NSError *error = nil;
      [NSURLConnection sendSynchronousRequest:sendStatusRequest
                            returningResponse:&sendStatusResponse
                                        error:&error];
      // TODO(mrossetti): Notify user that their message was sent or not.
      if (error) {
        HGSLogDebug(@"Failed to send Twitter status message due to error: '"
                    @"%@'.", [error localizedDescription]);
      }
    } else {
      HGSLog(@"Cannot send Twitter status message due to missing keychain "
             @"item for '%@'.", accountIdentifier_);
    }
  }
}

#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(id<HGSAccount>)account {
  BOOL removeMe = YES;
  return removeMe;
}

@end
