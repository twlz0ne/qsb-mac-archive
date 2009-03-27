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
@class KeychainItem;

// An abstract base class which manages an account with an account name
// and password (stored in the user's keychain) and with which a search 
// source or action can be associated.  Management of a user interface is 
// provided for setting up a new account and editing an existing account.
//
// Use this as your account's base class if your account has the common
// pattern of requiring an account name and password for setup.  Your
// specialization of HGSSimpleAccount should have:
//
//  - Concrete account class (see GoogleAccount) providing:
//    - an +[accountType] method returning the name of the account
//      type which this account offers to sources and actions adhering to
//      the HGSAccountClientProtocol
//    - an +[accountSetupViewToInstallWithParentWindow:] method
//      that loads, sets up, and returns an account edit view that gets
//      inserted into the client's setup account window.
//    - an -[editNibName] method that returns the name of the nib file
//      containing the window with which an account is edited.
//    - an -[accountURLRequestForUserName:password:] method that composes
//      an NSURLRequest suitable for synchronously authenticating the
//      account.
//    - and -[authenticateWithPassword:] method that performs a synchronous
//      authentication of the account.  (Note: this method _should not_
//      set |authenticated|.
//    Optional:
//    - an -[accountURLRequest] method that composes an NSURLRequest 
//      suitable for asynchronously authenticating the account. 
//      (The default implementation retrieves the userName and
//      password from the keychain and calls through to
//      -[accountURLRequestForUserName:password:].)
//    - an -[authenticate] method that performs an asynchronous authentication
//      of the account and sets |authenticated|.
//  - A controller class deriving from HGSSimpleAccountSetUpViewController
//    that provides:
//    - an -[initWithNibName:bundle:] method that calls through to the
//      HGSSimpleAccountSetUpViewController
//      -[initWithNibName:bundle:accountTypeClass:] method while supplying
//      the class of the account being created.
//  - Your account extension's plist entry must include an entry
//    for HGSExtensionOfferedAccountType giving the accountType.
//
// Optionally, other functionality can be added to the 
// HGSSimpleAccountSetUpViewController and a specialization of the
// HGSSimpleAccountEditController can be supplied, if desired.
//
// See Vermilion/Modules/GoogleAccount/ for an example.
//
@interface HGSSimpleAccount : HGSAccount {
 @private
  HGSSimpleAccountEditController *accountEditController_;
  NSURLConnection *connection_; // Used by async authentication.
}

@property (nonatomic, retain)
  HGSSimpleAccountEditController *accountEditController;
@property (nonatomic, retain) NSURLConnection *connection;

// Adjust the account name, if desired.  The default implementation
// returns the original string.
- (NSString *)adjustUserName:(NSString *)userName;

// Provide the name of the edit nib.  Your implementation should
// return a valid nib name.
- (NSString *)editNibName;

// Retrieve the keychain item for our keychain service name, if any.
- (KeychainItem *)keychainItem;

// Test the account and password to see if they authenticate.
// The default implementation assumes the account is valid.  You
// should provide your own implementation.  Do not set
// authenticated_ in this method.
- (BOOL)authenticateWithPassword:(NSString *)password;

// Return an NSURLRequest appropriate for authenticating the account
// using the credentials currently stored in the keychain.
- (NSURLRequest *)accountURLRequest;

// Return an NSURLRequest appropriate for authenticating the account
// using the proposed account name and password.
- (NSURLRequest *)accountURLRequestForUserName:(NSString *)userName
                                      password:(NSString *)password;

@end

