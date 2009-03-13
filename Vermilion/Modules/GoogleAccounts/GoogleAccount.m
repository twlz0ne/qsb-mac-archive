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
static NSString *const kGoogleURLString = @"http://www.google.com/";
static NSString *const kGoogleAccountTypeName = @"Google";
static NSString *const kGoogleAppsAccountTypeName = @"GoogleApps";
static NSString *const kAccountTestFormat
  = @"https://www.google.com/accounts/ClientLogin?Email=%@&Passwd=%@"
    @"&source=GoogleQuickSearch&accountType=%@";
static NSString *const kGoogleAccountType = @"GOOGLE";
static NSString *const kHostedAccountType = @"HOSTED";
static NSString *const accountCaptchaFormat = @"&logintoken=%@&logincaptcha=%@";
static NSString *const kCaptchaImageURLPrefix
  = @"http://www.google.com/accounts/";

typedef enum {
  eGoogleAccountTypeChooseNeither = 1,
  eGoogleAccountTypeChooseSelected = 2
} GoogleAccountTypeChoice;


@interface GoogleAccount ()

// Check the authentication results to see if the request authenticated.
- (BOOL)validateResult:(NSData *)result;

// Open google.com in the user's preferred browser.
+ (BOOL)openGoogleHomePage;

@end


@interface SetUpGoogleAccountViewController ()

// Make sure the captcha portion of the setup view has been obscured.
- (void)resetCaptchaPresentation;

@end


@implementation GoogleAccount

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

@synthesize googleAppsAccount = googleAppsAccount_;
@synthesize accountTypeKnown = accountTypeKnown_;
@synthesize captchaImage = captchaImage_;
@synthesize captchaText = captchaText_;
@synthesize captchaToken = captchaToken_;

- (id)initWithName:(NSString *)userName
              type:(NSString *)type {
  self = [super initWithName:userName type:type];
  BOOL isAppsAccount = [type isEqualToString:kGoogleAppsAccountTypeName];
  [self setGoogleAppsAccount:isAppsAccount];
  return self;
}

- (void)dealloc {
  [responseData_ release];
  [captchaImage_ release];
  [captchaText_ release];
  [captchaToken_ release];
  [super dealloc];
}

+ (NSString *)accountType {
  return kGoogleAccountTypeName;
}

+ (NSView *)setupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
  NSBundle *ourBundle = HGSGetPluginBundle();
  SetUpGoogleAccountViewController *loadedViewController
    = [[[SetUpGoogleAccountViewController alloc]
        initWithNibName:kSetUpGoogleAccountViewNibName bundle:ourBundle]
       autorelease];
  if (loadedViewController) {
    [loadedViewController loadView];
    [loadedViewController resetCaptchaPresentation];
    [loadedViewController setParentWindow:parentWindow];
  } else {
    loadedViewController = nil;
    HGSLog(@"Failed to load nib '%@'.", kSetUpGoogleAccountViewNibName);
  }
  return [loadedViewController view];
}

- (NSString *)adjustUserName:(NSString *)userName {
  if ([userName rangeOfString:@"@"].location == NSNotFound) {
    NSString *countryGMailCom = HGSLocalizedString(@"@gmail.com", nil);
    userName = [userName stringByAppendingString:countryGMailCom];
  }
  return userName;
}

- (NSString *)editNibName {
  return @"EditGoogleAccount";
}

- (BOOL)authenticateWithPassword:(NSString *)password {
  BOOL authenticated = NO;
  // Test this account to see if we can connect.
  NSString *userName = [self userName];
  NSURLRequest *accountRequest = [self accountURLRequestForUserName:userName
                                                           password:password];
  if (accountRequest) {
    NSURLResponse *accountResponse = nil;
    NSError *error = nil;
    NSData *result = [NSURLConnection sendSynchronousRequest:accountRequest
                                           returningResponse:&accountResponse
                                                       error:&error];
    authenticated = [self validateResult:result];
  }
  return authenticated;
}

- (NSURLRequest *)accountURLRequestForUserName:(NSString *)userName
                                      password:(NSString *)password {
  NSString *encodedAccountName = [userName gtm_stringByEscapingForURLArgument];
  NSString *encodedPassword = [password gtm_stringByEscapingForURLArgument];
  BOOL hosted = [self isGoogleAppsAccount];
  NSString *accountType = (hosted) ? kHostedAccountType : kGoogleAccountType;
  NSString *accountTestString = [NSString stringWithFormat:kAccountTestFormat,
                                 encodedAccountName, encodedPassword,
                                 accountType];
  NSString *captchaText = [self captchaText];
  if ([captchaText length]) {
    NSString *captchaToken = [self captchaToken];
    accountTestString = [accountTestString stringByAppendingFormat:
                         accountCaptchaFormat, captchaToken, captchaText];
    // Clear for next time.
    [self setCaptchaImage:nil];
    [self setCaptchaText:nil];
    [self setCaptchaToken:nil];
  }
  NSURL *accountTestURL = [NSURL URLWithString:accountTestString];
  NSURLRequest *accountRequest
    = [NSURLRequest requestWithURL:accountTestURL
                       cachePolicy:NSURLRequestUseProtocolCachePolicy
                   timeoutInterval:15.0];
  return accountRequest;
}

- (BOOL)validateResult:(NSData *)result {
  NSString *answer = [[[NSString alloc] initWithData:result
                                            encoding:NSUTF8StringEncoding]
                      autorelease];
  // Simple test to see if the string contains 'SID=' at the beginning
  // of the first line and 'LSID=' on the beginning of the second.
  // While we're in here we'll look for a captcha request.
  BOOL validated = NO;
  BOOL foundSID = NO;
  BOOL foundLSID = NO;
  NSString *captchaToken = nil;
  NSString *captchaImageURLString = nil;
  NSString *const captchaTokenKey = @"CaptchaToken=";
  NSString *const captchaImageURLKey = @"CaptchaUrl=";
  
  NSArray *answers = [answer componentsSeparatedByString:@"\n"];
  if ([answers count] >= 2) {
    for (NSString *anAnswer in answers) {
      if (!foundSID && [anAnswer hasPrefix:@"SID="]) {
        foundSID = YES;
      } else if (!foundLSID && [anAnswer hasPrefix:@"LSID="]) {
        foundLSID = YES;
      } else if ([anAnswer hasPrefix:captchaTokenKey]) {
        captchaToken = [anAnswer substringFromIndex:[captchaTokenKey length]];
      } else if ([anAnswer hasPrefix:captchaImageURLKey]) {
        captchaImageURLString
          = [anAnswer substringFromIndex:[captchaImageURLKey length]];
      }
    }
    validated = foundSID && foundLSID;
    if (!validated) {
      if ([captchaToken length] && [captchaImageURLString length]) {
        // Retrieve the captcha image.
        NSString *fullURLString
          = [kCaptchaImageURLPrefix
             stringByAppendingString:captchaImageURLString];
        NSURL *captchaImageURL = [NSURL URLWithString:fullURLString];
        NSImage *captchaImage
          = [[[NSImage alloc] initWithContentsOfURL:captchaImageURL]
             autorelease];
        [self setCaptchaToken:captchaToken];
        [self setCaptchaImage:captchaImage];
        HGSLogDebug(@"Authentication for account <%p>:'%@' requires captcha.",
                    self, [self displayName]);
      } else {
        HGSLogDebug(@"Authentication for account <%p>:'%@' failed with an "
                    @"error=%@.", self, [self displayName], answer);
      }
    }
  }
  return validated;
}

+ (BOOL)openGoogleHomePage {
  NSURL *googleURL = [NSURL URLWithString:kGoogleURLString];
  BOOL success = [[NSWorkspace sharedWorkspace] openURL:googleURL];
  if (!success) {
    HGSLogDebug(@"Failed to open %@", kGoogleURLString);
    NSBeep();
  }
  return success;
}

#pragma mark NSURLConnection Delegate Methods

- (void)connection:(NSURLConnection *)connection 
didReceiveResponse:(NSURLResponse *)response {
  HGSAssert(connection == [self connection], nil);
  [responseData_ release];
  responseData_ = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection 
    didReceiveData:(NSData *)data {
  HGSAssert(connection == [self connection], nil);
  [responseData_ appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  HGSAssert(connection == [self connection], nil);
  [self setConnection:nil];
  BOOL validated = [self validateResult:responseData_];
  [responseData_ release];
  responseData_ = nil;
  [self setAuthenticated:validated];
}

@end


@implementation GoogleAppsAccount

@end


@implementation GoogleAccountEditController

@synthesize captchaImage = captchaImage_;
@synthesize captchaText = captchaText_;

- (void)dealloc {
  [captchaImage_ release];
  [captchaText_ release];
  [super dealloc];
}

- (void)awakeFromNib {
  [super awakeFromNib];

  GoogleAccount *account = (GoogleAccount *)[self account];
  NSWindow *window = [self window];
  NSRect windowFrame = [window frame];
  CGFloat deltaHeight = 0.0;
  BOOL adjustWindow = NO;
  
  // Show the "Is a Google Apps account" text field.
  if ([account isGoogleAppsAccount]) {
    deltaHeight = NSHeight([googleAppsTextField_ frame]) + 8.0;
    [googleAppsTextField_ setHidden:NO];
    adjustWindow = YES;
  }
  
  // The captcha must be collapsed prior to first presentation.
  if (![captchaContainerView_ isHidden]) {
    CGFloat containerHeight = NSHeight([captchaContainerView_ frame]);
    deltaHeight -= containerHeight;
    adjustWindow = YES;
    [captchaContainerView_ setHidden:YES];
    [captchaTextField_ setEnabled:NO];
    [self setCaptchaText:@""];
    [self setCaptchaImage:nil];
    [account setCaptchaImage:nil];
  }
  
  if (adjustWindow) {
    windowFrame.origin.y -= deltaHeight;
    windowFrame.size.height += deltaHeight;
    [window setFrame:windowFrame display:YES];
  }
}

- (IBAction)acceptEditAccountSheet:(id)sender {
  // If we're showing a captcha then we need to pass along the captcha text
  // to the account for authentication.
  if ([self captchaImage]) {
    NSString *captchaText = [self captchaText];
    GoogleAccount *account = (GoogleAccount *)[self account];
    [account setCaptchaText:captchaText];
  }
  [super acceptEditAccountSheet:sender];
}

- (BOOL)canGiveUserAnotherTry {
  BOOL canGiveUserAnotherTry = NO;
  // If the last authentication attempt resulted in a captcha request then
  // we want to expand the account setup sheet and show the captcha.
  GoogleAccount *account = (GoogleAccount *)[self account];
  NSImage *captchaImage = [account captchaImage];
  BOOL resizeNeeded = ([self captchaImage] == nil);  // leftover captcha?
  NSWindow *window = [self window];
  if (captchaImage) {
    // Install the captcha image, enable the captcha text field,
    // expand the window to show the captcha.
    [captchaTextField_ setEnabled:YES];
    [self setCaptchaImage:captchaImage];
    
    if (resizeNeeded) {
      CGFloat containerHeight = NSHeight([captchaContainerView_ frame]);
      NSRect windowFrame = [window frame];
      windowFrame.origin.y -= containerHeight;
      windowFrame.size.height += containerHeight;
      [[window animator] setFrame:windowFrame display:YES];
    }
    
    [[captchaContainerView_ animator] setHidden:NO];
    [window makeFirstResponder:captchaTextField_];
    canGiveUserAnotherTry = YES;
    [account setCaptchaImage:nil];  // We've used it all up.
  } else {
    [window makeFirstResponder:passwordField_];
  }
  return canGiveUserAnotherTry;
}

- (IBAction)goToGoogle:(id)sender {
  [GoogleAccount openGoogleHomePage];
}

@end

@implementation SetUpGoogleAccountViewController

@synthesize captchaImage = captchaImage_;
@synthesize captchaText = captchaText_;

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil {
  self = [super initWithNibName:nibNameOrNil
                         bundle:nibBundleOrNil
               accountTypeClass:[GoogleAccount class]];
  return self;
}

- (void)dealloc {
  [captchaImage_ release];
  [captchaText_ release];
  [super dealloc];
}

- (IBAction)acceptSetupAccountSheet:(id)sender {
  // |newAccount| may be nil (first time through).
  GoogleAccount *newAccount = (GoogleAccount *)[self account];
  // If we're showing a captcha then we need to pass along the captcha text
  // to the account for authentication.  |newAccount| won't be nil since
  // a captcha will never be required on the first pass through.
  if ([self captchaImage]) {
    NSString *captchaText = [self captchaText];
    [newAccount setCaptchaText:captchaText];
  }
  // The rest of this is very similar to the implementation of
  // acceptSetupAccountSheet: found in HGSSimpleAccount, with changes
  // to support determining if this is a hosted or non-hosted account.
  NSWindow *sheet = [sender window];
  NSString *userName = [self accountName];
  if ([userName length] > 0) {
    NSString *password = [self accountPassword];
    if (newAccount) {
      [newAccount setUserName:userName];
    } else {
      // Create the new account entry.
      newAccount = [[[GoogleAccount alloc] initWithName:userName
                                                   type:kGoogleAccountTypeName]
                    autorelease];
      [self setAccount:newAccount];
      
      // Update the account name in case initWithName: adjusted it.
      NSString *revisedAccountName = [newAccount userName];
      if ([revisedAccountName length]) {
        userName = revisedAccountName;
        [self setAccountName:userName];
      }
    }
    
    // Authenticate the account for both hosted and non-hosted.
    BOOL hostedAuthenticated = NO;
    [newAccount setGoogleAppsAccount:YES];
    NSURLRequest *hostedRequest
      = [newAccount accountURLRequestForUserName:userName password:password];
    if (hostedRequest) {
      NSURLResponse *hostedResponse = nil;
      NSError *error = nil;
      NSData *result = [NSURLConnection sendSynchronousRequest:hostedRequest
                                             returningResponse:&hostedResponse
                                                         error:&error];
      hostedAuthenticated = [newAccount validateResult:result];
    }
    
    BOOL nonHostedAuthenticated = NO;
    [newAccount setGoogleAppsAccount:NO];
    NSURLRequest *nonHostedRequest
      = [newAccount accountURLRequestForUserName:userName password:password];
    if (nonHostedRequest) {
      NSURLResponse *nonHostedResponse = nil;
      NSError *error = nil;
      NSData *result = [NSURLConnection sendSynchronousRequest:nonHostedRequest
                                             returningResponse:&nonHostedResponse
                                                         error:&error];
      nonHostedAuthenticated = [newAccount validateResult:result];
    }
    
    BOOL isGood = NO;
    
    if (hostedAuthenticated && nonHostedAuthenticated) {
      // Both authenticated -- pathological case.  Let the user decide.
      GoogleAccountTypeSheetController *controller 
        = [[[GoogleAccountTypeSheetController alloc]
            initWithUserName:userName] autorelease];
      NSWindow *typeWindow = [controller window];
      NSInteger result = [NSApp runModalForWindow:typeWindow];
      [typeWindow orderOut:self];
      if (result == eGoogleAccountTypeChooseSelected) {
        BOOL useHosted = ([controller selectedAccountIndex] == 0);
        [newAccount setGoogleAppsAccount:useHosted];
        [newAccount setAccountTypeKnown:YES];
        isGood = YES;
      }
    } else if (hostedAuthenticated || nonHostedAuthenticated) {
      [newAccount setGoogleAppsAccount:hostedAuthenticated];
      [newAccount setAccountTypeKnown:YES];
      isGood = YES;
    } else if (![self canGiveUserAnotherTryOffWindow:sheet]) {
      // Neither authenticated so tell the abuser.
      // If we can't help the user fix things, tell them they've got
      // something wrong.
      NSString *summary = HGSLocalizedString(@"Could not authenticate that "
                                             @"account.", nil);
      NSString *format
        = HGSLocalizedString(@"The account '%@' could not be authenticated. "
                             @"Please check the account name and password "
                             @"and try again.", nil);
      [self presentMessageOffWindow:sheet
                        withSummary:summary
                  explanationFormat:format
                         alertStyle:NSWarningAlertStyle];
    }
    
    if (isGood) {
      // Adjust the type and identifier of the account if hosted.
      if ([newAccount isGoogleAppsAccount]) {
        // Adjusting requires that we create a new account instance
        // with the proper type.
        newAccount
          = [[[GoogleAppsAccount alloc] initWithName:userName
                                                type:kGoogleAppsAccountTypeName]
             autorelease];
        [self setAccount:newAccount];
      }
      // Make sure we don't already have this account registered.
      NSString *accountIdentifier = [newAccount identifier];
      HGSExtensionPoint *accountsPoint = [HGSExtensionPoint accountsPoint];
      if ([accountsPoint extensionWithIdentifier:accountIdentifier]) {
        isGood = NO;
        NSString *summary = HGSLocalizedString(@"Account already set up.",
                                               nil);
        NSString *format
          = HGSLocalizedString(@"The account '%@' has already been set up for "
                               @"use in Quick Search Box.", nil);
        [self presentMessageOffWindow:sheet
                          withSummary:summary
                    explanationFormat:format
                           alertStyle:NSWarningAlertStyle];
      }
      
      [newAccount setAuthenticated:isGood];
      if (isGood) {
        // Install the account.
        isGood = [accountsPoint extendWithObject:newAccount];
        if (isGood) {
          // If there is not already a keychain item create one.  If there is
          // then update the password.
          KeychainItem *keychainItem = [newAccount keychainItem];
          if (keychainItem) {
            [keychainItem setUsername:userName
                             password:password];
          } else {
            NSString *keychainServiceName = [newAccount identifier];
            [KeychainItem addKeychainItemForService:keychainServiceName
                                       withUsername:userName
                                           password:password]; 
          }
          
          [NSApp endSheet:sheet];
          NSString *summary
            = HGSLocalizedString(@"Enable searchable items for this account.",
                                 nil);
          NSString *format
            = HGSLocalizedString(@"One or more search sources may have been "
                                 @"added for the account '%@'. It may be "
                                 @"necessary to manually enable each search "
                                 @"source that uses this account.  Do so via "
                                 @"the 'Searchable Items' tab in Preferences.",
                                 nil);
          [self presentMessageOffWindow:[self parentWindow]
                            withSummary:summary
                      explanationFormat:format
                             alertStyle:NSInformationalAlertStyle];
          
          [self setAccountName:nil];
          [self setAccountPassword:nil];
        } else {
          HGSLogDebug(@"Failed to install account extension for account '%@'.",
                      userName);
        }
      }
    }
  }
}

- (IBAction)goToGoogle:(id)sender {
  [GoogleAccount openGoogleHomePage];
}

- (BOOL)canGiveUserAnotherTryOffWindow:(NSWindow *)window {
  BOOL canGiveUserAnotherTry = NO;
  // If the last authentication attempt resulted in a captcha request then
  // we want to expand the account setup sheet and show the captcha.
  GoogleAccount *account = (GoogleAccount *)[self account];
  NSImage *captchaImage = [account captchaImage];
  BOOL resizeNeeded = ([self captchaImage] == nil);  // leftover captcha?
  if (captchaImage) {
    // Install the captcha image, enable the captcha text field,
    // expand the window to show the captcha.
    [captchaTextField_ setEnabled:YES];
    [self setCaptchaImage:captchaImage];

    if (resizeNeeded) {
      CGFloat containerHeight = NSHeight([captchaContainerView_ frame]);
      NSRect windowFrame = [window frame];
      windowFrame.origin.y -= containerHeight;
      windowFrame.size.height += containerHeight;
      [[window animator] setFrame:windowFrame display:YES];
    }
    
    [[captchaContainerView_ animator] setHidden:NO];
    [window makeFirstResponder:captchaTextField_];
    canGiveUserAnotherTry = YES;
    [account setCaptchaImage:nil];  // We've used it all up.
  } else {
    [self resetCaptchaPresentation];
  }
  return canGiveUserAnotherTry;
}

#pragma mark SetUpGoogleAccountViewController Private Methods

- (void)resetCaptchaPresentation {
  // If we previously presented a captcha, resize our view, disable the captcha
  // text field, and clear our memory of the captcha.
  if (![captchaContainerView_ isHidden]) {
    [[captchaContainerView_ animator] setHidden:YES];
    CGFloat containerHeight = NSHeight([captchaContainerView_ frame]);
    NSWindow *window = [captchaContainerView_ window];
    if (window) {
      NSRect windowFrame = [window frame];
      windowFrame.origin.y += containerHeight;
      windowFrame.size.height -= containerHeight;
      [[window animator] setFrame:windowFrame display:YES];
      [window makeFirstResponder:userNameField_];
    } else {
      NSView *view = [self view];  // Resize
      NSSize frameSize = [view frame].size;
      frameSize.height -= containerHeight;
      [view setFrameSize:frameSize];
    }
    
    [captchaTextField_ setEnabled:NO];
    [self setCaptchaText:@""];
    [self setCaptchaImage:nil];
    GoogleAccount *account = (GoogleAccount *)[self account];
    [account setCaptchaImage:nil];
  }
}

@end


@implementation GoogleAccountTypeSheetController

@synthesize userName = userName_;
@synthesize googleAppsUserName = googleAppsUserName_;
@synthesize selectedAccountIndex = selectedAccountIndex_;

- (id)initWithUserName:(NSString *)userName {
  self = [super initWithWindowNibName:@"GoogleAccountTypeSheet"];
  if (self) {
    [self setUserName:userName];
    NSString *format = HGSLocalizedString(@"%@ — Google Apps", nil);
    NSString *appsName = [NSString stringWithFormat:format, userName];
    [self setGoogleAppsUserName:appsName];
  }
  return self;
}

- (IBAction)chooseNeither:(id)sender {
  [NSApp stopModalWithCode:(NSInteger)eGoogleAccountTypeChooseNeither];
}

- (IBAction)chooseSelected:(id)sender {
  [NSApp stopModalWithCode:(NSInteger)eGoogleAccountTypeChooseSelected];
}

@end
