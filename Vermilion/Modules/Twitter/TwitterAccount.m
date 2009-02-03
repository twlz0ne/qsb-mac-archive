//
//  TwitterAccount.m
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

#import "TwitterAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "HGSBundle.h"
#import "HGSLog.h"
#import "KeychainItem.h"
#import "GTMBase64.h"

static NSString *const kSetUpTwitterAccountViewNibName
  = @"SetUpTwitterAccountView";
static NSString *const kTwitterVerifyAccountURLString
  = @"https://twitter.com/account/verify_credentials.xml";
static NSString *const kTwitterURLString = @"http://twitter.com/";
static NSString *const kTwitterAccountTypeName = @"Twitter";;

// A class which manages a Twitter account.
//
@interface TwitterAccount : HGSSimpleAccount

// Open twitter.com in the user's preferred browser.
+ (BOOL)openTwitterHomePage;

@end

@implementation TwitterAccount

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

+ (NSString *)accountType {
  return kTwitterAccountTypeName;
}

+ (NSView *)accountSetupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
  static HGSSetUpSimpleAccountViewController *sSetUpTwitterAccountViewController = nil;
  if (!sSetUpTwitterAccountViewController) {
    NSBundle *ourBundle = HGSGetPluginBundle();
    HGSSetUpSimpleAccountViewController *loadedViewController
      = [[[SetUpTwitterAccountViewController alloc]
          initWithNibName:kSetUpTwitterAccountViewNibName bundle:ourBundle]
         autorelease];
    if (loadedViewController) {
      [loadedViewController loadView];
      sSetUpTwitterAccountViewController = [loadedViewController retain];
    } else {
      HGSLog(@"Failed to load nib '%@'.", kSetUpTwitterAccountViewNibName);
    }
  }
  [sSetUpTwitterAccountViewController setParentWindow:parentWindow];
  return [sSetUpTwitterAccountViewController view];
}

- (NSString *)editNibName {
  return @"EditTwitterAccount";
}

- (BOOL)authenticateWithPassword:(NSString *)password {
  // Test this account to see if we can connect.
  BOOL authenticated = NO;
  NSString *accountName = [self accountName];
  NSURL *accountTestURL = [NSURL URLWithString:kTwitterVerifyAccountURLString];
  NSMutableURLRequest *accountRequest
    = [NSMutableURLRequest requestWithURL:accountTestURL
                              cachePolicy:NSURLRequestUseProtocolCachePolicy
                          timeoutInterval:15.0];
  NSString *authStr = [NSString stringWithFormat:@"%@:%@",
                       accountName, password];
  NSData *authData = [authStr dataUsingEncoding:NSASCIIStringEncoding];
  NSString *authBase64 = [GTMBase64 stringByEncodingData:authData];
  NSString *authValue = [NSString stringWithFormat:@"Basic %@", authBase64];
  [accountRequest setValue:authValue forHTTPHeaderField:@"Authorization"];
  NSURLResponse *accountResponse = nil;
  NSError *error = nil;
  [NSURLConnection sendSynchronousRequest:accountRequest
                        returningResponse:&accountResponse
                                    error:&error];
  authenticated = (error == nil);
  [self setIsAuthenticated:authenticated];
  return authenticated;  // Return as convenience.
}

+ (BOOL)openTwitterHomePage {
  NSURL *twitterURL = [NSURL URLWithString:kTwitterURLString];
  BOOL success = [[NSWorkspace sharedWorkspace] openURL:twitterURL];
  return success;
}

@end

@implementation TwitterAccountEditController

- (IBAction)goToTwitter:(id)sender {
  BOOL success = [TwitterAccount openTwitterHomePage];
  if (!success) {
    NSBeep();
  }
}

@end

@implementation SetUpTwitterAccountViewController

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil
                         bundle:nibBundleOrNil
               accountTypeClass:[TwitterAccount class]];
  return self;
}

- (IBAction)goToTwitter:(id)sender {
  BOOL success = [TwitterAccount openTwitterHomePage];
  if (!success) {
    NSBeep();
  }
}

@end