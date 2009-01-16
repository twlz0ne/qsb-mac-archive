//
//  HGSGoogleAccount.m
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

#import "HGSGoogleAccount.h"
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "HGSLog.h"
#import "KeychainItem.h"


@interface HGSGoogleAccount (HGSGoogleAccountPrivateMethods)

// Retrieve the keychain item for our keychain service name, if any.
- (KeychainItem *)keychainItem;

// Test the account and password to see if they authenticate, sets
// |isAuthenticated| and returns |isAuthenticated| as a convenience.
- (BOOL)authenticateWithPassword:(NSString *)password;

@end


@implementation HGSGoogleAccount

@synthesize isAuthenticated = isAuthenticated_;

+ (NSSet *)keyPathsForValuesAffectingDisplayName {
  NSSet *affectingKeys = [NSSet setWithObjects:@"accountType"
                                               @"keychainServiceName",
                                               nil];
  return affectingKeys;
}

- (id)initWithName:(NSString *)accountName
          password:(NSString *)password
              type:(NSString *)type {
  if (![type isEqualToString:kHGSGoogleAccountTypeName]) {
    HGSLogDebug(@"Expected account type '%@' for account '%@' "
                @"but got '%@' instead", 
                kHGSGoogleAccountTypeName, [self accountName], type);
    [self release];
    self = nil;
  } else {
    if ([accountName rangeOfString:@"@"].location == NSNotFound) {
      // TODO(mrossetti): should we default to @googlemail.com for the UK
      // and Germany?
      accountName = [accountName stringByAppendingString:@"@gmail.com"];
    }

    if ((self = [super initWithName:accountName
                           password:password
                               type:kHGSGoogleAccountTypeName])) {
      NSString *keychainServiceName = [self identifier];

      // See if we already have a keychain item from which we can pull
      // the password, ignoring any password that's being passed in because
      // this will only be the case for prior existing accounts.
      // TODO(mrossetti): Is it possible to be passed a password if there
      // already is a keychain item?  Make sure it's not.
      KeychainItem *keychainItem = [self keychainItem];
      NSString *keychainPassword = [keychainItem password];
      if ([keychainPassword length]) {
        password = keychainPassword;
      }
      
      // Test this account to see if we can connect.
      BOOL authenticated = [self authenticateWithPassword:password];
      if (authenticated) {
        if (!keychainItem) {
          // If necessary, create the keychain entry now.
          [KeychainItem addKeychainItemForService:keychainServiceName
                                     withUsername:accountName
                                         password:password]; 
        }
        [self setIsAuthenticated:YES];
      } else {
        [self setIsAuthenticated:NO];
      }
    }
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary *)prefDict {
  if ((self = [super initWithDictionary:prefDict])) {
    NSString *keychainServiceName = [self identifier];
    if ([self keychainItem]) {
      if (![[self accountType] isEqualToString:kHGSGoogleAccountTypeName]) {
        HGSLogDebug(@"Expected account type '%@' for account '%@' "
                    @"but got '%@' instead", 
                    kHGSGoogleAccountTypeName, [self accountName],
                    [self accountType]);
        [self release];
        self = nil;
      }
    } else {
      HGSLogDebug(@"No keychain item found for service name '%@'", 
                  keychainServiceName);
      [self release];
      self = nil;
    }
  }
  return self;
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
  NSString *keychainServiceName = [self identifier];
  KeychainItem *item = [KeychainItem keychainItemForService:keychainServiceName 
                                                   username:nil];
  [item removeFromKeychain];
  [super remove];
}

- (NSString *)accountPassword {
  // Retrieve the account's password from the keychain.
  KeychainItem *keychainItem = [self keychainItem];
  NSString *password = [keychainItem password];
  return password;
}

- (void)setAccountPassword:(NSString *)password {
  KeychainItem *keychainItem = [self keychainItem];
  if (keychainItem) {
    [keychainItem setUsername:[self accountName]
                     password:password];
  }
  [self authenticateWithPassword:password];
}

@end


@implementation HGSGoogleAccount (HGSGoogleAccountPrivateMethods)

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

- (KeychainItem *)keychainItem {
  NSString *keychainServiceName = [self identifier];
  KeychainItem *item = [KeychainItem keychainItemForService:keychainServiceName 
                                                   username:nil];
  return item;
}

- (BOOL)authenticateWithPassword:(NSString *)password {
  // Test this account to see if we can connect.
  BOOL authenticated = NO;
  NSString * const accountTestFormat
    = @"https://www.google.com/accounts/ClientLogin?Email=%@&Passwd=%@"
      @"&source=GoogleQuickSearch&accountType=HOSTED_OR_GOOGLE";
  NSString *accountName = [self accountName];
  NSString *encodedAccountName = [accountName gtm_stringByEscapingForURLArgument];
  NSString *encodedPassword = [password gtm_stringByEscapingForURLArgument];
  NSString *accountTestString = [NSString stringWithFormat:accountTestFormat,
                                 encodedAccountName, encodedPassword];
  NSURL *accountTestURL = [NSURL URLWithString:accountTestString];
  NSURLRequest *accountRequest = [NSURLRequest requestWithURL:accountTestURL];
  NSURLResponse *accountResponse = nil;
  NSError *error = nil;
  NSData *result = [NSURLConnection sendSynchronousRequest:accountRequest
                                         returningResponse:&accountResponse
                                                     error:&error];
  NSString *answer = [[[NSString alloc] initWithData:result
                                            encoding:NSUTF8StringEncoding]
                      autorelease];
  // Simple test to see if the string contains 'SID=' at the beginning
  // of the first line and 'LSID=' on the beginning of the second.
  // For the gory details, please refer to:
  // http://wiki.corp.google.com/twiki/bin/view/Main/GaiaProgrammaticLoginV2#_https_www_google_com_accounts_C
  BOOL foundSID = NO;
  BOOL foundLSID = NO;
  NSArray *answers = [answer componentsSeparatedByString:@"\n"];
  if ([answers count] >= 2) {
    for (NSString *anAnswer in answers) {
      if (!foundSID && [anAnswer hasPrefix:@"SID="]) {
        foundSID = YES;
      } else if (!foundLSID && [anAnswer hasPrefix:@"LSID="]) {
        foundLSID = YES;
      }
    }
    authenticated = foundSID && foundLSID;
    if (!authenticated) {
      HGSLogDebug(@"Authentication for account '%@' failed with an error=%@",
                  [self accountName], answer);
    }
  }
  [self setIsAuthenticated:authenticated];
  return authenticated;  // Return as convenience.
}

@end


// Strings used to describe the google account.
NSString *const kHGSGoogleAccountTypeName = @"Google";
