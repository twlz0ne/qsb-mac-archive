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
#import "GoogleAccountSetUpViewController.h"
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "HGSGoogleAccountTypes.h"
#import "HGSLog.h"


static NSString *const kGoogleDomain = @"@google.com";
static NSString *const kGoogleUKDomain = @"@google.co.uk";
static NSString *const kGoogleURLString = @"http://www.google.com/";
static NSString *const kAccountTestFormat
  = @"https://www.google.com/accounts/ClientLogin?Email=%@&Passwd=%@"
    @"&source=GoogleQuickSearch&accountType=%@";
static NSString *const kGoogleAccountType = @"GOOGLE";
static NSString *const kGoogleCorpAccountType = @"HOSTED_OR_GOOGLE";
static NSString *const kHostedAccountType = @"HOSTED";
static NSString *const kAccountCaptchaFormat = @"&logintoken=%@&logincaptcha=%@";
static NSString *const kCaptchaImageURLPrefix
  = @"http://www.google.com/accounts/";


@interface GoogleAccountSetUpViewController ()

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
  return kHGSGoogleAccountType;
}

- (NSString *)adjustUserName:(NSString *)userName {
  if ([userName rangeOfString:@"@"].location == NSNotFound) {
    NSString *countryGMailCom = HGSLocalizedString(@"@gmail.com", nil);
    userName = [userName stringByAppendingString:countryGMailCom];
  }
  return userName;
}

- (NSURLRequest *)accountURLRequestForUserName:(NSString *)userName
                                      password:(NSString *)password {
  NSString *encodedAccountName = [userName gtm_stringByEscapingForURLArgument];
  NSString *encodedPassword = [password gtm_stringByEscapingForURLArgument];
  BOOL hosted = [self isKindOfClass:[GoogleAppsAccount class]];
  NSString *accountType = kHostedAccountType;
  if (!hosted) {
    accountType = kGoogleAccountType;
    NSRange atRange = [userName rangeOfString:@"@"];
    if (atRange.location != NSNotFound) {
      NSString *domainString = [userName substringFromIndex:atRange.location];
      // TODO(mrossetti): Determine if it is sufficient to test the domain
      // against '@google.~'.
      NSComparisonResult result
        = [kGoogleDomain compare:domainString options:NSCaseInsensitiveSearch];
      if (result != NSOrderedSame) {
        result = [kGoogleUKDomain compare:domainString
                                  options:NSCaseInsensitiveSearch];
      }
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

- (BOOL)validateResult:(NSData *)result statusCode:(NSInteger)statusCode {
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

+ (BOOL)isPartialMatchToGoogleDomain:(NSString *)domain {
  BOOL isPartialMatch = NO;
  NSUInteger domainLength = [domain length];
  NSUInteger googleDomainLength = [kGoogleDomain length];
  NSUInteger googleUKDomainLength = [kGoogleUKDomain length];
  NSRange domainRange = NSMakeRange(0, domainLength);
  if (domainLength <= googleDomainLength) {
    NSComparisonResult googleResult
      = [kGoogleDomain compare:domain
                       options:NSCaseInsensitiveSearch
                         range:domainRange];
    isPartialMatch = (googleResult == NSOrderedSame);
  }
  if (!isPartialMatch && domainLength <= googleUKDomainLength) {
    NSComparisonResult googleResult
      = [kGoogleUKDomain compare:domain
                         options:NSCaseInsensitiveSearch
                           range:domainRange];
    isPartialMatch = (googleResult == NSOrderedSame);
  }
  return isPartialMatch;
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

@end


@implementation GoogleAppsAccount

- (NSString *)type {
  return kHGSGoogleAppsAccountType;
}

@end
