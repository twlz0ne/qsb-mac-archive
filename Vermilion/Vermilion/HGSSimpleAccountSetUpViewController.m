//
//  HGSSimpleAccountSetUpViewController.m
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

#import "HGSSimpleAccountSetUpViewController.h"
#import "HGSBundle.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSExtensionPoint.h"
#import "HGSLog.h"
#import "HGSSimpleAccount.h"
#import "KeychainItem.h"


@implementation HGSSimpleAccountSetUpViewController

@synthesize account = account_;
@synthesize accountName = accountName_;
@synthesize accountPassword = accountPassword_;
@synthesize accountTypeClass = accountTypeClass_;

- (id)init {
  self = [self initWithNibName:nil
                        bundle:nil
              accountTypeClass:nil];
  return self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil
      accountTypeClass:(Class)accountTypeClass {
  if ((self = [super initWithNibName:nibNameOrNil
                              bundle:nibBundleOrNil])) {
    if (accountTypeClass) {
      accountTypeClass_ = accountTypeClass;
    } else {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [account_ release];
  [accountName_ release];
  [accountPassword_ release];
  [super dealloc];
}


- (NSWindow *)parentWindow {
  return parentWindow_;
}

- (void)setParentWindow:(NSWindow *)parentWindow {
  parentWindow_ = parentWindow;
  // This call also gives us an opportunity to flush some old settings
  // from the previous use.
  [self setAccount:nil];
  [self setAccountName:nil];
  [self setAccountPassword:nil];
}

- (IBAction)acceptSetupAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  NSString *userName = [self accountName];
  if ([userName length] > 0) {
    NSString *password = [self accountPassword];

    // Create a new account entry.
    HGSSimpleAccount *newAccount
      = [[[accountTypeClass_ alloc] initWithName:userName] autorelease];
    [self setAccount:newAccount];
    
    // Update the account name in case initWithName: adjusted it.
    NSString *revisedAccountName = [newAccount userName];
    if ([revisedAccountName length]) {
      userName = revisedAccountName;
      [self setAccountName:userName];
    }
    
    BOOL isGood = YES;
    
    // Make sure we don't already have this account registered.
    NSString *accountIdentifier = [newAccount identifier];
    HGSAccountsExtensionPoint *accountsPoint
      = [HGSExtensionPoint accountsPoint];
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
    
    // Authenticate the account.
    if (isGood) {
      isGood = [newAccount authenticateWithPassword:password];
      [newAccount setAuthenticated:isGood];
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
        
        // Install the account.
        isGood = [accountsPoint extendWithObject:newAccount];
        if (isGood) {
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
      } else if (![self canGiveUserAnotherTryOffWindow:sheet]) {
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
    }
  }
}

- (IBAction)cancelSetupAccountSheet:(id)sender {
  [self setAccountName:nil];
  [self setAccountPassword:nil];
  NSWindow *sheet = [sender window];
  [NSApp endSheet:sheet];
}

- (BOOL)canGiveUserAnotherTryOffWindow:(NSWindow *)window {
  return NO;
}

- (void)presentMessageOffWindow:(NSWindow *)parentWindow
                    withSummary:(NSString *)summary
              explanationFormat:(NSString *)format
                     alertStyle:(NSAlertStyle)style {
  NSString *accountName = [self accountName];
  NSString *explanation = [NSString stringWithFormat:format, accountName];
  NSAlert *alert = [[[NSAlert alloc] init] autorelease];
  [alert setAlertStyle:style];
  [alert setMessageText:summary];
  [alert setInformativeText:explanation];
  [alert beginSheetModalForWindow:parentWindow
                    modalDelegate:self
                   didEndSelector:nil
                      contextInfo:nil];
}

@end

