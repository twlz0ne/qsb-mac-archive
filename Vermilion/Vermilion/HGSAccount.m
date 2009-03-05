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
#import "HGSCoreExtensionPoints.h"
#import "HGSAccountsExtensionPoint.h"
#import "HGSLog.h"


NSString *const kHGSAccountDisplayNameFormat = @"%@ (%@)";
NSString *const kHGSAccountIdentifierFormat = @"com.google.qsb.%@.%@";


@implementation HGSAccount

@synthesize userName = userName_;
@synthesize type = type_;
@synthesize authenticated = authenticated_;

- (id)initWithName:(NSString *)userName
              type:(NSString *)accountType {
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSString *name = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
                    userName, accountType];
  NSString *identifier = [NSString stringWithFormat:kHGSAccountIdentifierFormat, 
                          accountType, userName];
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       bundle, kHGSExtensionBundleKey,
       name, kHGSExtensionUserVisibleNameKey,
       identifier, kHGSExtensionIdentifierKey,
       nil];
  if ((self = [super initWithConfiguration:configuration])) {
    [self setUserName:userName];
    [self setType:accountType];
    if (![self userName] || ![self type]) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary *)prefDict {
  NSString *userName = [prefDict objectForKey:kHGSAccountUserNameKey];
  NSString *accountType = [prefDict objectForKey:kHGSAccountTypeKey];
  self = [self initWithName:userName
                       type:accountType];
  return self;
}

- (NSDictionary *)dictionaryValue {
  NSDictionary *accountDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       [self userName], kHGSAccountUserNameKey,
       [self type], kHGSAccountTypeKey,
       nil];
  return accountDict;
}

- (void) dealloc {
  [userName_ release];
  [type_ release]; 
  [super dealloc];
}

- (NSString *)displayName {
  NSString *displayName
    = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
       [self userName], [self type]];
  return displayName;
}

- (NSString *)password {
  return nil;
}

- (BOOL)setPassword:(NSString *)password {
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter postNotificationName:kHGSAccountDidChangeNotification 
                               object:self];
  return YES;
}

+ (NSView *)setupViewToInstallWithParentWindow:(NSWindow *)parentWindow {
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
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSAccountWillBeRemovedNotification object:self];
  HGSExtensionPoint *accountsPoint = [HGSExtensionPoint accountsPoint];
  [accountsPoint removeExtension:self];
}

- (BOOL)isEditable {
  return YES;
}

- (void)authenticate {
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@:%p account='%@', type='%@'>",
          [self class], self, [self userName], type_];
}

@end

NSString *const kHGSAccountDidChangeNotification
  = @"HGSAccountDidChangeNotification";
NSString *const kHGSAccountWillBeRemovedNotification
  = @"HGSAccountWillBeRemovedNotification";

NSString *const kHGSAccountUserNameKey = @"HGSAccountUserNameKey";
NSString *const kHGSAccountConnectionErrorKey = @"HGSAccountConnectionErrorKey";
NSString *const kHGSAccountTypeKey = @"HGSAccountTypeKey";
