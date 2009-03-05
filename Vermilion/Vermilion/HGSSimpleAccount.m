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
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"
#import "HGSBundle.h"
#import "KeychainItem.h"


@interface HGSSimpleAccount ()

// Retrieve the keychain item for our keychain service name, if any.
- (KeychainItem *)keychainItem;

// Finalize the account editing.
- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo;

@property (nonatomic, retain, readwrite)
  HGSSimpleAccountEditController *accountEditController;

@end


@interface HGSSetUpSimpleAccountViewController ()

- (void)presentMessageOffWindow:(NSWindow *)parentWindow
                    withSummary:(NSString *)summary
              explanationFormat:(NSString *)format
                     alertStyle:(NSAlertStyle)style;

@end


@implementation HGSSimpleAccount

@synthesize accountEditController = accountEditController_;
@synthesize connection = connection_;

- (id)initWithDictionary:(NSDictionary *)prefDict {
  if ((self = [super initWithDictionary:prefDict])) {
    if ([self keychainItem]) {
      // We assume the account is still available but will soon be
      // authenticated (for sources that index) or as soon as an action
      // using the account is attempted.
      [self setAuthenticated:YES];
    } else {
      NSString *keychainServiceName = [self identifier];
      HGSLogDebug(@"No keychain item found for service name '%@'", 
                  keychainServiceName);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [self setConnection:nil];
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
  KeychainItem *keychainItem = [self keychainItem];
  [keychainItem removeFromKeychain];
  [super remove];
}

- (NSString *)password {
  // Retrieve the account's password from the keychain.
  KeychainItem *keychainItem = [self keychainItem];
  NSString *password = [keychainItem password];
  return password;
}

+ (NSView *)setupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
  HGSLogDebug(@"Class '%@', deriving from HGSSimpleAccount, should override "
              @"accountSetupViewToInstallWithParentWindow.", [self class]);
  return nil;
}

- (BOOL)setPassword:(NSString *)password {
  // Don't update the keychain unless we have a good password.
  BOOL passwordSet = NO;
  if ([self authenticateWithPassword:password]) {
    KeychainItem *keychainItem = [self keychainItem];
    if (keychainItem) {
      [keychainItem setUsername:[self userName]
                       password:password];
    } else {
      NSString *keychainServiceName = [self identifier];
      [KeychainItem addKeychainItemForService:keychainServiceName
                                 withUsername:[self userName]
                                     password:password]; 
    }
    [super setPassword:password];
    passwordSet = YES;
  }
  return passwordSet;
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

- (NSString *)adjustUserName:(NSString *)userName {
  return userName;
}

- (NSString *)editNibName {
  HGSLogDebug(@"Class '%@', deriving from HGSSimpleAccount, should override "
              @"editNibName.", [self class]);
  return nil;
}

- (void)authenticate {
  NSURLRequest *accountRequest = [self accountURLRequest];
  if (accountRequest) {
    NSURLConnection *connection
      = [NSURLConnection connectionWithRequest:accountRequest delegate:self];
    [self setConnection:connection];
  }
}

- (BOOL)authenticateWithPassword:(NSString *)password {
  return YES;
}

- (NSURLRequest *)accountURLRequest {
  KeychainItem* keychainItem 
  = [KeychainItem keychainItemForService:[self identifier] 
                                username:nil];
  NSString *userName = [keychainItem username];
  NSString *password = [keychainItem password];
  NSURLRequest *accountRequest = [self accountURLRequestForUserName:userName
                                                           password:password];
  return accountRequest;
}

- (NSURLRequest *)accountURLRequestForUserName:(NSString *)userName
                                      password:(NSString *)password {
  HGSLog(@"Class '%@' should override accountURLRequestForUserName:"
         @"password:.", [self className]);
  return nil;
}

- (void)setConnection:(NSURLConnection *)connection {
  [connection_ cancel];
  [connection_ release];
  connection_ = [connection retain];
}

#pragma mark HGSSimpleAccount Private Methods

- (KeychainItem *)keychainItem {
  NSString *keychainServiceName = [self identifier];
  KeychainItem *item = [KeychainItem keychainItemForService:keychainServiceName 
                                                   username:nil];
  return item;
}

- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo {
  [sheet orderOut:self];
  [self setAccountEditController:nil];
}

#pragma mark NSURLConnection Delegate Methods

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
  HGSAssert(connection == connection_, nil);
  [self setConnection:nil];
  [self setAuthenticated:YES];
}

- (void)connection:(NSURLConnection *)connection 
didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
  HGSAssert(connection == connection_, nil);
  [self setAuthenticated:NO];
}

- (void)connection:(NSURLConnection *)connection
  didFailWithError:(NSError *)error {
  HGSAssert(connection == connection_, nil);
  [self setConnection:nil];
  [self setAuthenticated:NO];
}

@end


@implementation HGSSimpleAccountEditController

@synthesize password = password_;

- (void)dealloc {
  [password_ release];
  [super dealloc];
}

- (void)awakeFromNib {
  [account_ setAccountEditController:self];
  NSString *password = [account_ password];
  [self setPassword:password];
}

- (HGSSimpleAccount *)account {
  return [[account_ retain] autorelease];
}

- (NSWindow *)editAccountSheet {
  return editAccountSheet_;
}

- (IBAction)acceptEditAccountSheet:(id)sender {
  NSWindow *sheet = [self window];
  BOOL passwordWasSet = [account_ setPassword:[self password]];
  // See if the new password authenticates.
  if (passwordWasSet) {
    [NSApp endSheet:sheet];
    [account_ setAuthenticated:YES];
  } else if (![self canGiveUserAnotherTry]) {
    NSString *summaryFormat = HGSLocalizedString(@"Could not set up that %@ "
                                                @"account.", nil);
    NSString *summary = [NSString stringWithFormat:summaryFormat,
                         [account_ type]];
    NSString *explanationFormat
      = HGSLocalizedString(@"The %@ account ‚Äò%@‚Äô could not be set up for "
                          @"use.  Please check your password and try "
                          @"again.", nil);
    NSString *explanation = [NSString stringWithFormat:explanationFormat,
                             [account_ type],
                             [account_ userName]];
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

- (BOOL)canGiveUserAnotherTry {
  return NO;
}

@end


@implementation HGSSetUpSimpleAccountViewController

@synthesize account = account_;
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
    HGSSimpleAccount *newAccount = [self account];
    if (newAccount) {
      [newAccount setUserName:userName];
    } else {
      // Create the new account entry.
      NSString *accountType = [accountTypeClass_ accountType];
      newAccount = [[[accountTypeClass_ alloc] initWithName:userName
                                                       type:accountType]
                    autorelease];
      [self setAccount:newAccount];

      // Update the account name in case initWithName: adjusted it.
      NSString *revisedAccountName = [newAccount userName];
      if ([revisedAccountName length]) {
        userName = revisedAccountName;
        [self setAccountName:userName];
      }
    }
    
    BOOL isGood = YES;
    
    // Make sure we don't already have this account registered.
    NSString *accountIdentifier = [newAccount identifier];
    HGSExtensionPoint *accountsPoint = [HGSExtensionPoint accountsPoint];
    if ([accountsPoint extensionWithIdentifier:accountIdentifier]) {
      isGood = NO;
      NSString *summary = HGSLocalizedString(@"Account already set up.",
                                            nil);
      NSString *format
        = HGSLocalizedString(@"The account ‚Äò%@‚Äô has already been set up for "
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
          = HGSLocalizedString(@"The account ‚Äò%@‚Äô could not be authenticated. "
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

#pragma mark HGSSetUpSimpleAccountViewController Private Methods

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

