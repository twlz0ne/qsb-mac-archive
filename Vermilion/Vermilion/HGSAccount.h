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
- (id)initWithName:(NSString *)userName
              type:(NSString *)type;

// Reconstitute an account entry from a dictionary.
- (id)initWithDictionary:(NSDictionary *)prefDict;

// Return a dictionary describing the account appropriate for archiving
// to preferences.
- (NSDictionary *)dictionaryValue;

// Return a display name for the account.
- (NSString *)displayName;

// Return the type (google/facebook/etc.) of the account.
- (NSString *)type;

// Return the account name.
- (NSString *)userName;

// Get the password for the account.
- (NSString *)password;

// Set the account password.  Derived classes should always call this base
// function in order to insure notifications are sent.
- (void)setPassword:(NSString *)password;

// Provide a view that will be installed in an account setup window.
// |parentWindow| is provided as a place off which to hang alerts. 
+ (NSView *)setupViewToInstallWithParentWindow:(NSWindow *)parentWindow;

// Do whatever is appropriate in order to edit the account.  |parentWindow|
// is provided as a place off which to hang an edit sheet, if desired.
- (void)editWithParentWindow:(NSWindow *)parentWindow;

// Do what is appropriate in order to remove the account.  Derived classes
// should either call this base function in order to insure notifications
// are sent, or send both notifications itself.
- (void)remove;

// Determine if the account is editable.
- (BOOL)isEditable;

// Perform an asynchronous authentication for the account using its existing
// credentials.
- (void)authenticate;

// Return YES if the account is valid (i.e. has been authenticated).
- (BOOL)isAuthenticated;
- (void)setAuthenticated:(BOOL)isAuthenticated;

@end


// A protocol to which extensions wanting access to an account must adhere.
//
@protocol HGSAccountClientProtocol

// Inform an account clients that an account is going to be removed.  The
// client should return YES if it should be shut down and deleted.
- (BOOL)accountWillBeRemoved:(id<HGSAccount>)account;

@end


// A concrete representation of the HGSAccount protocol.
//
@interface HGSAccount : HGSExtension <HGSAccount> {
 @private
  NSString *userName_;
  NSString *type_;
  BOOL authenticated_;
}

@property (nonatomic, copy) NSString *userName;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, getter=isAuthenticated) BOOL authenticated;

// Initialize a new account entry.
- (id)initWithName:(NSString *)userName
              type:(NSString *)accountType;

// Return a dictionary describing the account appropriate for archiving
// to preferences.
- (NSDictionary *)dictionaryValue;

// Return a display name for the account.
- (NSString *)displayName;

// Return the type (google/facebook/etc.) of the account.
- (NSString *)type;

// Return the account name.
- (NSString *)userName;

// Get the password for the account.  The default returns nil.
- (NSString *)password;

// If the password authenticates then set it and return YES.
- (BOOL)setPassword:(NSString *)password;

// The default view provider returns nil.
+ (NSView *)setupViewToInstallWithParentWindow:(NSWindow *)parentWindow;

// The default account edit function does nothing.
- (void)editWithParentWindow:(NSWindow *)parentWindow;

// Do what is appropriate in order to remove the account.  The default
// removes the account from the accounts extensions point.  If you derive
// a subclass then you should call super's (this) remove.
- (void)remove;

// Determine if the account is editable.  The default returns YES.
- (BOOL)isEditable;

// Perform an asynchronous authentication for the account using its existing
// credentials.  The default does nothing.
- (void)authenticate;

@end


// Notification sent whenever an account has been changed. The |object|
// sent with the notification is the HGSAccount instance that has been changed.
extern NSString *const kHGSAccountDidChangeNotification;

// Notification sent when an account is going to be removed. The |object|
// sent with the notification is the HGSAccount instance that will be removed.
extern NSString *const kHGSAccountWillBeRemovedNotification;

// Keys used in describing an account connection error.
extern NSString *const kHGSAccountUserNameKey;
extern NSString *const kHGSAccountConnectionErrorKey;

// Keys used in the dictionary describing an account as stored in prefs.
//
// String specifying the type of the account.
extern NSString *const kHGSAccountTypeKey;
