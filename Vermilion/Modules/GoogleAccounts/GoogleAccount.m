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
static NSString *const kGoogleCorpAccountType = @"HOSTED_OR_GOOGLE";
static NSString *const kHostedAccountType = @"HOSTED";
static NSString *const kAccountCaptchaFormat = @"&logintoken=%@&logincaptcha=%@";
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

@property (nonatomic, getter=isGoogleAppsCheckboxShowing)
  BOOL googleAppsCheckboxShowing;
@property (nonatomic, getter=isWindowSizesDetermined) BOOL windowSizesDetermined;

// Pre-determine the various window heights.
- (void)determineWindowSizes;

// Determine height of window based on checkbox and captcha presentation.
- (CGFloat)windowHeightWithCheckboxShowing:(BOOL)googleAppsCheckboxShowing
                            captchaShowing:(BOOL)captchaShowing;
@end


@implementation GoogleAccount

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

@synthesize captchaImage = captchaImage_;
@synthesize captchaText = captchaText_;
@synthesize captchaToken = captchaToken_;

- (void)dealloc {
  [responseData_ release];
  [captchaImage_ release];
  [captchaText_ release];
  [captchaToken_ release];
  [super dealloc];
}

- (NSString *)type {
  return kGoogleAccountTypeName;
}

+ (NSViewController *)
    setupViewControllerToInstallWithParentWindow:(NSWindow *)parentWindow {
  NSBundle *ourBundle = HGSGetPluginBundle();
  SetUpGoogleAccountViewController *loadedViewController
    = [[[SetUpGoogleAccountViewController alloc]
        initWithNibName:kSetUpGoogleAccountViewNibName bundle:ourBundle]
       autorelease];
  if (loadedViewController) {
    [loadedViewController loadView];
    [loadedViewController setParentWindow:parentWindow];
  } else {
    loadedViewController = nil;
    HGSLog(@"Failed to load nib '%@'.", kSetUpGoogleAccountViewNibName);
  }
  return loadedViewController;
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
  BOOL hosted = [self isKindOfClass:[GoogleAppsAccount class]];
  NSString *accountType = kHostedAccountType;
  if (!hosted) {
    accountType = kGoogleAccountType;
    NSString *googleDomain = @"@google.com"; // Not localized.
    NSRange atRange = [userName rangeOfString:@"@"];
    if (atRange.location != NSNotFound) {
      NSString *domainString = [userName substringFromIndex:atRange.location];
      NSComparisonResult result
        = [googleDomain compare:domainString options:NSCaseInsensitiveSearch];
      if (result == NSOrderedSame) {
        accountType = kGoogleCorpAccountType;
      }
    }
  }
  NSString *accountTestString = [NSString stringWithFormat:kAccountTestFormat,
                                 encodedAccountName, encodedPassword,
                                 accountType];
  NSString *captchaText = [self captchaText];
  if ([captchaText length]) {
    NSString *captchaToken = [self captchaToken];
    accountTestString = [accountTestString stringByAppendingFormat:
                         kAccountCaptchaFormat, captchaToken, captchaText];
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

- (NSString *)type {
  return kGoogleAppsAccountTypeName;
}

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
  if ([account isKindOfClass:[GoogleAppsAccount class]]) {
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
@synthesize googleAppsAccount = googleAppsAccount_;
@synthesize googleAppsCheckboxShowing = googleAppsCheckboxShowing_;
@synthesize windowSizesDetermined = windowSizesDetermined_;

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
      BOOL googleAppsCheckboxShowing = [self isGoogleAppsCheckboxShowing];
      CGFloat newHeight
        = [self windowHeightWithCheckboxShowing:googleAppsCheckboxShowing
                                 captchaShowing:YES];
      NSRect windowFrame = [window frame];
      CGFloat deltaHeight = newHeight - NSHeight(windowFrame);
      windowFrame.size.height = newHeight;
      windowFrame.origin.y -= deltaHeight;
      [[window animator] setFrame:windowFrame display:YES];
    }
    
    [[captchaContainerView_ animator] setHidden:NO];
    [window makeFirstResponder:captchaTextField_];
    canGiveUserAnotherTry = YES;
    [account setCaptchaImage:nil];  // We've used it all up.
  } else if (resizeNeeded) {
    BOOL googleAppsCheckboxShowing = [self isGoogleAppsCheckboxShowing];
    CGFloat newHeight
      = [self windowHeightWithCheckboxShowing:googleAppsCheckboxShowing
                               captchaShowing:NO];
    NSRect windowFrame = [window frame];
    CGFloat deltaHeight = newHeight - NSHeight(windowFrame);
    windowFrame.size.height = newHeight;
    windowFrame.origin.y -= deltaHeight;
    [[window animator] setFrame:windowFrame display:YES];
  }
  return canGiveUserAnotherTry;
}

- (void)setGoogleAppsAccount:(BOOL)googleAppsAccount {
  if (googleAppsAccount != googleAppsAccount_) {
    googleAppsAccount_ = googleAppsAccount;
    // Create an account of the appropriate type, hosted or non-hosted.
    NSString *userName = [self accountName];
    Class accountClass
      = (googleAppsAccount) ? [GoogleAppsAccount class] : [GoogleAccount class];
    HGSSimpleAccount *account
      = [[[accountClass alloc] initWithName:userName] autorelease];
    
    [self setAccount:account];
  }
}

- (void)setAccount:(HGSSimpleAccount *)account {
  // Remember the old captchaToken.
  GoogleAccount *oldAccount = (GoogleAccount *)[self account];
  NSString *captchaToken
    = (oldAccount) ? [NSString stringWithString:[oldAccount captchaToken]] : nil;
  [super setAccount:account];
  // If we're showing a captcha then we need to pass along the captcha text
  // to the account for authentication.
  if (captchaToken) {
    GoogleAccount *newAccount = (GoogleAccount *)account;
    NSString *captchaText = [self captchaText];
    [newAccount setCaptchaText:captchaText];
    [newAccount setCaptchaToken:captchaToken];
  }
  [self setCaptchaImage:nil];
}

- (void)setAccountName:(NSString *)userName {
  [super setAccountName:userName];
  
  BOOL showCheckbox = NO;
  if (userName) {
    NSString *gmailDomain = HGSLocalizedString(@"@gmail.com", nil);
    NSRange atRange = [userName rangeOfString:@"@"];
    if (atRange.location != NSNotFound) {
      NSString *domainString = [userName substringFromIndex:atRange.location];
      NSUInteger gmailDomainLength = [gmailDomain length];
      NSUInteger domainLength = [domainString length];
      if (domainLength) {
        showCheckbox = YES;
        if (domainLength <= gmailDomainLength) {
          NSRange domainRange = NSMakeRange(0, domainLength);
          NSComparisonResult gmailResult
            = [gmailDomain compare:domainString
                           options:NSCaseInsensitiveSearch
                             range:domainRange];
          showCheckbox = (gmailResult != NSOrderedSame);
        }
        NSString *googleDomain = @"@google.com"; // Not localized.
        NSUInteger googleDomainLength = [googleDomain length];
        if (showCheckbox && domainLength <= googleDomainLength) {
          NSRange domainRange = NSMakeRange(0, domainLength);
          NSComparisonResult googleResult
            = [googleDomain compare:domainString
                            options:NSCaseInsensitiveSearch
                              range:domainRange];
          showCheckbox = (googleResult != NSOrderedSame);
        }
      }
    }
  }
  if (showCheckbox != [self isGoogleAppsCheckboxShowing]) {
    [self setGoogleAppsCheckboxShowing:showCheckbox];
    [googleAppsCheckbox_ setEnabled:showCheckbox];
    if (showCheckbox) {
      [[googleAppsCheckbox_ animator] setHidden:NO];
    } else {
      [googleAppsCheckbox_ setHidden:YES];
    }

    BOOL captchaShowing = [self captchaImage] != nil;
    CGFloat newHeight = [self windowHeightWithCheckboxShowing:showCheckbox
                                               captchaShowing:captchaShowing];
    NSWindow *window = [captchaContainerView_ window];
    NSRect windowFrame = [window frame];
    CGFloat deltaHeight = newHeight - NSHeight(windowFrame);
    windowFrame.size.height = newHeight;
    windowFrame.origin.y -= deltaHeight;
    [[window animator] setFrame:windowFrame display:YES];
  }
}

#pragma mark SetUpGoogleAccountViewController Private Methods

- (void)loadView {
  [super loadView];
  
  // Hide the captcha section.
  [captchaContainerView_ setHidden:YES];
  CGFloat containerHeight = NSHeight([captchaContainerView_ frame]);
  NSView *view = [self view];  // Resize
  NSSize frameSize = [view frame].size;
  frameSize.height -= containerHeight;
  
  // Hide the Google Apps checkbox.
  CGFloat checkboxHeight = NSHeight([googleAppsCheckbox_ frame]) + 4.0;
  [self setGoogleAppsCheckboxShowing:NO];
  [googleAppsCheckbox_ setHidden:YES];
  [googleAppsCheckbox_ setEnabled:NO];
  frameSize.height -= checkboxHeight;
  
  [view setFrameSize:frameSize];
  
  [captchaTextField_ setEnabled:NO];
  [self setCaptchaText:@""];
  [self setCaptchaImage:nil];
}

- (void)determineWindowSizes {
  // This assumes that the window has been resized to fit the view and the
  // view is not showing the checkbox of captcha.
  NSWindow *parentWindow = [captchaContainerView_ window];
  CGFloat checkboxHeight = NSHeight([googleAppsCheckbox_ frame]) + 4.0;;
  CGFloat captchaHeight = NSHeight([captchaContainerView_ frame]);
  
  windowHeightNoCheckboxNoCaptcha_ = NSHeight([parentWindow frame]);
  windowHeightNoCheckboxCaptcha_
    = windowHeightNoCheckboxNoCaptcha_ + captchaHeight;
  windowHeightCheckboxNoCaptcha_
    = windowHeightNoCheckboxNoCaptcha_ + checkboxHeight;
  windowHeightCheckboxCaptcha_
    = windowHeightNoCheckboxCaptcha_ + checkboxHeight;
  [self setWindowSizesDetermined:YES];
}

- (CGFloat)windowHeightWithCheckboxShowing:(BOOL)googleAppsCheckboxShowing
                            captchaShowing:(BOOL)captchaShowing {
  if (![self isWindowSizesDetermined]) {
    [self determineWindowSizes];
  }
  CGFloat newHeight = 0.0;
  if (googleAppsCheckboxShowing) {
    newHeight = (captchaShowing)
                ? windowHeightCheckboxCaptcha_
                : windowHeightCheckboxNoCaptcha_;
  } else {
    newHeight = (captchaShowing)
                ? windowHeightNoCheckboxCaptcha_
                : windowHeightNoCheckboxNoCaptcha_;
  }
  return newHeight;
}

- (void)setCaptchaImage:(NSImage *)captcha {
  if (captcha != captchaImage_) {
    BOOL didShow = (captchaImage_ != nil);
    BOOL willShow =  (captcha != nil);
    [captchaImage_ release];
    captchaImage_ = [captcha retain];
    // Show/hide the captcha image area.
    if (didShow != willShow) {
      BOOL googleAppsCheckboxShowing = [self isGoogleAppsCheckboxShowing];
      CGFloat newHeight
        = [self windowHeightWithCheckboxShowing:googleAppsCheckboxShowing
                                 captchaShowing:willShow];
      NSWindow *window = [captchaContainerView_ window];
      NSRect windowFrame = [window frame];
      CGFloat deltaHeight = newHeight - NSHeight(windowFrame);
      windowFrame.size.height = newHeight;
      windowFrame.origin.y -= deltaHeight;
      
      [captchaTextField_ setEnabled:willShow];
      [self setCaptchaText:nil];
      [[window animator] setFrame:windowFrame display:YES];
      if (willShow) {
        [[captchaContainerView_ animator] setHidden:NO];
      } else {
        [window makeFirstResponder:userNameField_];
        [captchaContainerView_ setHidden:YES];
      }
    }
  }
}

@end
