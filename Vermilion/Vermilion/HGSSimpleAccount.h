//
//  HGSSimpleAccount.h
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

#import "HGSAccount.h"

@class HGSSimpleAccountEditController;

// An abstract base class which manages an account with an account name
// and password (stored in the user's keychain) and with which a search 
// source or action can be associated.  Management of a user interface is 
// provided for setting up a new account and editing an existing account.
//
// Use this as your account's base class if your account has the common
// pattern of requiring an account name and password for setup.  The
// minimum that you must provide when using HGSSimpleAccount are:
//
//  - Concrete account class (see GoogleAccount)
//    - with a +[accountType] method returning the name of the account
//      type which this account offers to sources and actions adhering to
//      the HGSAccountClientProtocol
//    - with a +[accountSetupViewToInstallWithParentWindow:] method
//      that loads, sets up, and returns an account edit view that gets
//      inserted into the client's setup account window.
//    - with a -[editNibName] method that returns the name of the nib file
//      containing the window with which an account is edited.
//  - A controller class deriving from HGSSetUpSimpleAccountViewController
//    that provides:
//    - an -[initWithNibName:bundle:] method that calls through to the
//      HGSSetUpSimpleAccountViewController
//      -[initWithNibName:bundle:accountTypeClass:] method while supplying
//      the class of the account being created.
//  - Your account extension's plist entry must include an entry
//    for HGSExtensionOfferedAccountType giving the accountType.
//
// Optionally, other functionality can be added to the 
// HGSSetUpSimpleAccountViewController and a specialization of the
// HGSSimpleAccountEditController can be supplied, if desired.
//
// See Vermilion/Modules/GoogleAccount/ for an example.
//
@interface HGSSimpleAccount : HGSAccount {
 @private
  HGSSimpleAccountEditController *accountEditController_;
}

@property (nonatomic, retain, readonly)
  HGSSimpleAccountEditController *accountEditController;

// Adjust the account name, if desired.  The default implementation
// returns the original string.
- (NSString *)adjustAccountName:(NSString *)accountName;

// Provide the name of the edit nib.  Your implementation should
// return a valid nib name.
- (NSString *)editNibName;

// Test the account and password to see if they authenticate, sets
// |isAuthenticated| and returns |isAuthenticated| as a convenience.
// The default implementation assumes the account is valid.  You
// should provide your own implementation.
- (BOOL)authenticateWithPassword:(NSString *)password;

@end


// A controller which manages a window used to update the password
// for the account account.
//
@interface HGSSimpleAccountEditController : NSWindowController {
 @private
  IBOutlet HGSSimpleAccount *account_;
  IBOutlet NSWindow *editAccountSheet_;
  IBOutlet NSSecureTextField *editPasswordField_;
  
  NSString *accountPassword_;
}

@property (nonatomic, copy) NSString *accountPassword;

// Gets the edit window associated with this controller.
- (NSWindow *)editAccountSheet;

// Called when the user presses 'OK'.
- (IBAction)acceptEditAccountSheet:(id)sender;

// Called when user presses 'Cancel'.
- (IBAction)cancelEditAccountSheet:(id)sender;

@end


// A controller which manages a view used to specify a new account's
// name and password during the setup process.  The view associated with
// this controller gets injected into a window provided by the user
// interface of the client.
//
@interface HGSSetUpSimpleAccountViewController : NSViewController {
 @private
  IBOutlet NSTextField *setupAccountNameField_;
  IBOutlet NSSecureTextField *setupPasswordField_;
  NSString *accountName_;
  NSString *accountPassword_;
  NSWindow *parentWindow_;  // WEAK
  Class accountTypeClass_;
}

@property (nonatomic, copy) NSString *accountName;
@property (nonatomic, copy) NSString *accountPassword;

// Designated initializer.
- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil
     accountTypeClass:(Class)accountTypeClass;
  
// Get/set the window off which to hang any alerts.
- (NSWindow *)parentWindow;
- (void)setParentWindow:(NSWindow *)parentWindow;

// Called when the user presses 'OK'.
- (IBAction)acceptSetupAccountSheet:(id)sender;

// Called when user presses 'Cancel'.
- (IBAction)cancelSetupAccountSheet:(id)sender;

@end
