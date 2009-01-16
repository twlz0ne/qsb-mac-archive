//
//  HGSAccount.h
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

#import <Foundation/Foundation.h>
#import "HGSExtension.h"

// TODO(mrossetti): Refactor HGSExtension so that unessential features
// required for sources and actions is not also required for accounts.
// Also, move all notifications on add/remove/change into HSGExtension.

// Information about accounts that a UI can display and which source or
// actions can access.
//
@protocol HGSAccount <HGSExtension>

// Initialize a new account entry.
- (id)initWithName:(NSString *)accountName
          password:(NSString *)password
              type:(NSString *)type;

// Reconstitute an account entry from a dictionary.
- (id)initWithDictionary:(NSDictionary *)prefDict;

// Return a dictionary describing the account appropriate for archiving
// to preferences.
- (NSDictionary *)dictionaryValue;

// Return a display name for the account.
- (NSString *)displayName;

// Return the type (google/facebook/etc.) of the account.
- (NSString *)accountType;

// Return the account name.
- (NSString *)accountName;

// Get the password for the account.
- (NSString *)accountPassword;

// Set the account password.  Derived classes should always call this base
// function in order to insure notifications are sent.
- (void)setAccountPassword:(NSString *)password;

// Do what is appropriate in order to remove the account.  Derived classes
// should either call this base function in order to insure notifications
// are sent, or send both notifications itself.
- (void)remove;

// Determine if the account is editable.
- (BOOL)isEditable;

// Return YES if the account is valid (i.e. has been authenticated).
- (BOOL)isAuthenticated;

// Convenience function for testing account type and availability.
- (BOOL)isAccountTypeAndActive:(NSString *)type;

@end


// A protocol to which extensions wanting access to an account must adhere.
//
@protocol HGSAccountClientProtocol

// Inform an account clients that an account is going to be removed.  The
// client should return YES if it should be shut down and deleted.
- (BOOL)accountWillBeRemoved:(id<HGSAccount>)account;

@end


@interface HGSAccount : HGSExtension <HGSAccount> {
 @private
  NSString *accountName_;
  NSString *accountType_;
}

@property (nonatomic, copy) NSString *accountName;
@property (nonatomic, copy) NSString *accountType;

// Initialize a new account entry.
- (id)initWithName:(NSString *)accountName
          password:(NSString *)password
              type:(NSString *)accountType;

// Return a dictionary describing the account appropriate for archiving
// to preferences.
- (NSDictionary *)dictionaryValue;

// Return a display name for the account.
- (NSString *)displayName;

// Return the type (google/facebook/etc.) of the account.
- (NSString *)accountType;

// Return the account name.
- (NSString *)accountName;

// Get/set the password for the account.  The default does nothing.
- (NSString *)accountPassword;
- (void)setAccountPassword:(NSString *)password;

// Do what is appropriate in order to remove the account.  The default
// removes the account from the accounts extensions point.  If you derive
// a subclass then you should call super's (this) remove.
- (void)remove;

// Determine if the account is editable.  The default returns YES.
- (BOOL)isEditable;

// Determine if the account has been authenticated.  The default returns NO.
- (BOOL)isAuthenticated;

@end


// Notification sent whenever an account has been changed.  The |object|
// sent with the notification is the HGSAccount instance that has been changed.
extern NSString *const kHGSDidChangeAccountNotification;

// Notification sent by a search souce whenever a connection failure is
// experienced.  The |object| sent with the notification is a dictionary
// containing, at a minimum, items for kHGSExtensionIdentifierKey,
// kHGSAccountUsernameKey and kHGSAccountConnectionErrorKey.
extern NSString *const kHGSAccountConnectionFailureNotification;

// Keys used in describing an account connection error.
extern NSString *const kHGSAccountUsernameKey;
extern NSString *const kHGSAccountConnectionErrorKey;

// Keys used in the dictionary describing an account as stored in prefs.
//
// String specifying the type of the account.
extern NSString *const kHGSAccountTypeKey;
// String specifying the name of the account.
extern NSString *const kHGSAccountNameKey;
