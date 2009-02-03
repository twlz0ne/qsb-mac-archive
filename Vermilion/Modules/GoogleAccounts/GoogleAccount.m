//
//  GoogleAccount.m
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

#import "GoogleAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "HGSBundle.h"
#import "HGSLog.h"
#import "KeychainItem.h"


static NSString *const kSetUpGoogleAccountViewNibName = @"SetUpGoogleAccountView";
static NSString *const kGoogleAccountTypeName = @"Google";;

// A class which manages a Google account.
//
@interface GoogleAccount : HGSSimpleAccount
@end

@implementation GoogleAccount

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

+ (NSString *)accountType {
  return kGoogleAccountTypeName;
}

+ (NSView *)accountSetupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
  static HGSSetUpSimpleAccountViewController *sSetUpGoogleAccountViewController = nil;
  if (!sSetUpGoogleAccountViewController) {
    NSBundle *ourBundle = HGSGetPluginBundle();
    HGSSetUpSimpleAccountViewController *loadedViewController
      = [[[SetUpGoogleAccountViewController alloc]
          initWithNibName:kSetUpGoogleAccountViewNibName bundle:ourBundle]
         autorelease];
    if (loadedViewController) {
      [loadedViewController loadView];
      sSetUpGoogleAccountViewController = [loadedViewController retain];
    } else {
      HGSLog(@"Failed to load nib '%@'.", kSetUpGoogleAccountViewNibName);
    }
  }
  [sSetUpGoogleAccountViewController setParentWindow:parentWindow];
  return [sSetUpGoogleAccountViewController view];
}

- (NSString *)adjustAccountName:(NSString *)accountName {
  if ([accountName rangeOfString:@"@"].location == NSNotFound) {
    // TODO(mrossetti): should we default to @googlemail.com for the UK
    // and Germany?
    accountName = [accountName stringByAppendingString:@"@gmail.com"];
  }
  return accountName;
}

- (NSString *)editNibName {
  return @"EditGoogleAccount";
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
  NSURLRequest *accountRequest
    = [NSURLRequest requestWithURL:accountTestURL
                       cachePolicy:NSURLRequestUseProtocolCachePolicy
                   timeoutInterval:15.0];
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
      HGSLogDebug(@"Authentication for account <%p>:'%@' failed with an error=%@",
                  self, [self accountName], answer);
    }
  }
  [self setIsAuthenticated:authenticated];
  return authenticated;  // Return as convenience.
}

@end

@implementation SetUpGoogleAccountViewController

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil
                         bundle:nibBundleOrNil
               accountTypeClass:[GoogleAccount class]];
  return self;
}

@end
