//
//  HGSAccount.m
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
#import "HGSAccountsExtensionPoint.h"
#import "HGSLog.h"


NSString *const kHGSAccountDisplayNameFormat = @"%@ (%@)";
NSString *const kHGSAccountIdentifierFormat = @"com.google.qsb.%@.%@";


@implementation HGSAccount

@synthesize accountName = accountName_;
@synthesize accountType = accountType_;
@synthesize isAuthenticated = isAuthenticated_;

- (id)initWithName:(NSString *)accountName
          password:(NSString *)password
              type:(NSString *)accountType {
  NSString *name = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
                    accountName, accountType];
  NSString *identifier = [NSString stringWithFormat:kHGSAccountIdentifierFormat, 
                          accountType, accountName];
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       name, kHGSExtensionUserVisibleNameKey,
       identifier, kHGSExtensionIdentifierKey,
       nil];
  if ((self = [super initWithConfiguration:configuration])) {
    [self setAccountName:accountName];
    [self setAccountType:accountType];
    if (![self accountName] || ![self accountType]) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary *)prefDict {
  NSString *accountName = [prefDict objectForKey:kHGSAccountNameKey];
  NSString *accountType = [prefDict objectForKey:kHGSAccountTypeKey];
  self = [self initWithName:accountName
                   password:nil
                       type:accountType];
  return self;
}

- (NSDictionary *)dictionaryValue {
  NSDictionary *accountDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       [self accountName], kHGSAccountNameKey,
       [self accountType], kHGSAccountTypeKey,
       nil];
  return accountDict;
}

- (void) dealloc {
  [accountName_ release];
  [accountType_ release]; 
  [super dealloc];
}

- (NSString *)displayName {
  NSString *displayName
    = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
       [self accountName], [self accountType]];
  return displayName;
}

- (NSString *)accountPassword {
  return nil;
}

- (void)setAccountPassword:(NSString *)password {
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter postNotificationName:kHGSDidChangeAccountNotification 
                               object:[self identifier]];
}

+ (NSView *)accountSetupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
  HGSLogDebug(@"Class '%@', deriving from HGSAccount, should override "
              @"accountSetupViewToInstallWithParentWindow: if it has an "
              @"interface for setting up new accounts.", [self class]);
  return nil;
}

- (void)editWithParentWindow:(NSWindow *)parentWindow {
  HGSLogDebug(@"Class '%@', deriving from HGSAccount, should override "
              @"editWithParentWindow: if it has an interface "
              @"for editing its account type.", [self class]);
}

- (void)remove {
  // Remove the account extension.
  HGSAccountsExtensionPoint *accountsExtensionPoint
    = [HGSAccountsExtensionPoint accountsExtensionPoint];
  [accountsExtensionPoint removeExtension:self];
}

- (BOOL)isEditable {
  return YES;
}

- (BOOL)isAccountTypeAndActive:(NSString *)type {
  return [self isAuthenticated] && [type isEqualToString:[self accountType]];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@:%p account='%@', type='%@'>",
          [self class], self, accountName_, accountType_];
}

@end

// Notification keys.
NSString *const kHGSDidChangeAccountNotification
  = @"HGSDidChangeAccountNotification";
NSString *const kHGSAccountConnectionFailureNotification
  = @"HGSAccountConnectionFailureNotification";

// Keys used in describing an account connection error.
NSString *const kHGSAccountUsernameKey
  = @"HGSAccountUsernameKey";
NSString *const kHGSAccountConnectionErrorKey
  = @"HGSAccountConnectionErrorKey";

// Dictionary keys for archived HGSAccounts.
NSString *const kHGSAccountTypeKey = @"HGSAccountType";
NSString *const kHGSAccountNameKey = @"HGSAccountName";
