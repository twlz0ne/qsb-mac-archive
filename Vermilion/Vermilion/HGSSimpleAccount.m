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
#import "HGSLog.h"
#import "KeychainItem.h"


@interface HGSSimpleAccount (HGSSimpleAccountPrivateMethods)

// Retrieve the keychain item for our keychain service name, if any.
- (KeychainItem *)keychainItem;

// Sets our edit controller.
- (void)setAccountEditController:(HGSSimpleAccountEditController *)controller;

// Finalize the account editing.
- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo;

@end


@interface HGSSetUpSimpleAccountViewController (HGSSetUpSimpleAccountViewControllerPrivateMethods)

- (void)presentMessageOffWindow:(NSWindow *)parentWindow
                    withSummary:(NSString *)summary
              explanationFormat:(NSString *)format
                     alertStyle:(NSAlertStyle)style;

@end


@implementation HGSSimpleAccount

@synthesize accountEditController = accountEditController_;

- (id)initWithName:(NSString *)accountName
          password:(NSString *)password
              type:(NSString *)type {
  // Perform any adjustments on the account name required.
  accountName = [self adjustAccountName:accountName];
  
  if ((self = [super initWithName:accountName
                         password:password
                             type:type])) {
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
  return self;
}

- (id)initWithDictionary:(NSDictionary *)prefDict {
  if ((self = [super initWithDictionary:prefDict])) {
    NSString *keychainServiceName = [self identifier];
    if ([self keychainItem]) {
      NSString *desiredAccountType = [self accountType];
      if (![[self accountType] isEqualToString:desiredAccountType]) {
        HGSLogDebug(@"Expected account type '%@' for account '%@' "
                    @"but got '%@' instead", 
                    desiredAccountType, [self accountName],
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

- (void)dealloc {
  [accountEditController_ release];
  [super dealloc];
}

+ (NSString *)accountType {
  HGSLogDebug(@"Class '%@', deriving from HGSSimpleAccount, should override "
              @"accountType.", [self class]);
  return nil;
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

+ (NSView *)accountSetupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
  HGSLogDebug(@"Class '%@', deriving from HGSSimpleAccount, should override "
              @"accountSetupViewToInstallWithParentWindow.", [self class]);
  return nil;
}

- (void)setAccountPassword:(NSString *)password {
  KeychainItem *keychainItem = [self keychainItem];
  if (keychainItem) {
    [keychainItem setUsername:[self accountName]
                     password:password];
  }
  [self authenticateWithPassword:password];
}

- (void)editWithParentWindow:(NSWindow *)parentWindow {
  NSString * const editNibName = [self editNibName];
  if ([NSBundle loadNibNamed:editNibName
                       owner:self]) {
    HGSSimpleAccountEditController *accountEditController
      = [self accountEditController];
    NSWindow *editAccountSheet = [accountEditController editAccountSheet];
    [NSApp beginSheet:editAccountSheet
       modalForWindow:parentWindow
        modalDelegate:self
       didEndSelector:@selector(accountSheetDidEnd:returnCode:contextInfo:)
          contextInfo:nil];
  } else {
    HGSLog(@"Failed to load nib '%@'.", editNibName);
  }
}

- (NSString *) adjustAccountName:(NSString *)accountName {
  return accountName;
}

- (NSString *)editNibName {
  HGSLogDebug(@"Class '%@', deriving from HGSSimpleAccount, should override "
              @"editNibName.", [self class]);
  return nil;
}

- (BOOL)authenticateWithPassword:(NSString *)password {
  // Test this account to see if we can connect.
  BOOL authenticated = YES;
  [self setIsAuthenticated:authenticated];
  return authenticated;
}

@end


@implementation HGSSimpleAccount (HGSSimpleAccountPrivateMethods)

- (KeychainItem *)keychainItem {
  NSString *keychainServiceName = [self identifier];
  KeychainItem *item = [KeychainItem keychainItemForService:keychainServiceName 
                                                   username:nil];
  return item;
}

- (void)setAccountEditController:(HGSSimpleAccountEditController *)controller {
  [accountEditController_ autorelease];
  accountEditController_ = [controller retain];
}

- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo {
  [sheet orderOut:self];
  [self setAccountEditController:nil];
}

@end


@implementation HGSSimpleAccountEditController

@synthesize accountPassword = accountPassword_;

- (void)dealloc {
  [accountPassword_ release];
  [super dealloc];
}

- (void)awakeFromNib {
  [account_ setAccountEditController:self];
  NSString *password = [account_ accountPassword];
  [self setAccountPassword:password];
}

- (NSWindow *)editAccountSheet {
  return editAccountSheet_;
}

- (IBAction)acceptEditAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  // The password field (NSSecureTextField) fails to stop editing regardless
  // of xib setting, validateImmediately, so we must force it to validate
  // and refresh the bound instance variable to prevent stale data when
  // authenticating.
  [editPasswordField_ selectText:self];  // Force password to freshen.
  [account_ setAccountPassword:[self accountPassword]];
  // See if the new password authenticates.
  if ([account_ isAuthenticated]) {
    [NSApp endSheet:sheet];
  } else {
    NSString *summaryFormat = NSLocalizedString(@"Could not set up that %@ "
                                                @"account.", nil);
    NSString *summary = [NSString stringWithFormat:summaryFormat,
                         [account_ accountType]];
    NSString *explanationFormat
      = NSLocalizedString(@"The %@ account ‘%@’ could not be set up for "
                          @"use.  Please insure that you have used the "
                          @"correct password.", nil);
    NSString *explanation = [NSString stringWithFormat:explanationFormat,
                             [account_ accountType],
                             [account_ accountName]];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert setMessageText:summary];
    [alert setInformativeText:explanation];
    [alert beginSheetModalForWindow:sheet
                      modalDelegate:self
                     didEndSelector:nil
                        contextInfo:nil];
  }
}

- (IBAction)cancelEditAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  [NSApp endSheet:sheet returnCode:NSAlertSecondButtonReturn];
}

@end


@implementation HGSSetUpSimpleAccountViewController

@synthesize accountName = accountName_;
@synthesize accountPassword = accountPassword_;

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

- (NSWindow *)parentWindow {
  return parentWindow_;
}

- (void)setParentWindow:(NSWindow *)parentWindow {
  parentWindow_ = parentWindow;
}

- (IBAction)acceptSetupAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  NSString *accountName = [self accountName];
  if ([accountName length] > 0) {
    // The password field (NSSecureTextField) fails to stop editing regardless
    // of xib setting, validateImmediately, so we must force it to validate
    // and refresh the bound instance variable to prevent stale data when
    // authenticating.
    [setupPasswordField_ selectText:self];  // Force password to freshen.
    // Create the new account entry.
    NSString *accountType = [accountTypeClass_ accountType];
    
    HGSSimpleAccount *newAccount
      = [[[accountTypeClass_ alloc] initWithName:accountName
                                        password:[self accountPassword]
                                            type:accountType]
         autorelease];
    
    // Update the account name in case initWithName: adjusted it.
    NSString *revisedAccountName = [newAccount accountName];
    if ([revisedAccountName length]) {
      accountName = revisedAccountName;
      [self setAccountName:accountName];
    }
    BOOL isGood = YES;
    
    // Make sure we don't already have this account registered.
    NSString *accountIdentifier = [newAccount identifier];
    HGSAccountsExtensionPoint *accountsExtensionPoint
      = [HGSAccountsExtensionPoint accountsExtensionPoint];
    if ([accountsExtensionPoint extensionWithIdentifier:accountIdentifier]) {
      isGood = NO;
      NSString *summary = NSLocalizedString(@"Account already set up.",
                                            nil);
      NSString *format
        = NSLocalizedString(@"The account ‘%@’ has already been set up for "
                            @"use in Quick Search Box.", nil);
      [self presentMessageOffWindow:sheet
                        withSummary:summary
                  explanationFormat:format
                         alertStyle:NSWarningAlertStyle];
    }
    
    // Authenticate the account.
    if (isGood) {
      isGood = [newAccount isAuthenticated];
      if (!isGood) {
        NSString *summary = NSLocalizedString(@"Could not authenticate that "
                                              @"account.", nil);
        NSString *format
          = NSLocalizedString(@"The account ‘%@’ could not be authenticated.  "
                              @"Please insure that you have used the correct "
                              @"account name and password.", nil);
        [self presentMessageOffWindow:sheet
                          withSummary:summary
                    explanationFormat:format
                           alertStyle:NSWarningAlertStyle];
      }
    }
    
    if (isGood) {
      isGood = [accountsExtensionPoint extendWithObject:newAccount];
      if (!isGood) {
        HGSLogDebug(@"Failed to install account extension for account '%@'.",
                    accountName);
      }
    }
    
    if (isGood) {
      [NSApp endSheet:sheet];
      NSString *summary = NSLocalizedString(@"Enable searchable items for this account.",
                                            nil);
      NSString *format
        = NSLocalizedString(@"One or more search sources may have been added "
                            @"for the account '%@'. It may be necessary to "
                            @"manually enable each search source that uses "
                            @"this account.  Do so via the 'Searchable Items' "
                            @"tab in Preferences.", nil);
      [self presentMessageOffWindow:[self parentWindow]
                        withSummary:summary
                  explanationFormat:format
                         alertStyle:NSInformationalAlertStyle];
      
      [self setAccountName:nil];
      [self setAccountPassword:nil];
    }
  }
}

- (IBAction)cancelSetupAccountSheet:(id)sender {
  [self setAccountName:nil];
  [setupPasswordField_ selectText:self];  // Force password to freshen.
  [self setAccountPassword:nil];
  NSWindow *sheet = [sender window];
  [NSApp endSheet:sheet];
}

@end


@implementation HGSSetUpSimpleAccountViewController (HGSSetUpSimpleAccountViewControllerPrivateMethods)

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

