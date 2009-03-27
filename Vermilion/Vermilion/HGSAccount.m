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
#import "HGSBundle.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSAccountsExtensionPoint.h"
#import "HGSLog.h"


NSString *const kHGSAccountDisplayNameFormat = @"%@ (%@)";
NSString *const kHGSAccountIdentifierFormat = @"com.google.qsb.%@.%@";

@interface HGSAccount ()

@property (nonatomic, copy) NSString *userName;

@end


@implementation HGSAccount

@synthesize userName = userName_;
@synthesize authenticated = authenticated_;

- (id)initWithName:(NSString *)userName {
  if ([userName length]) {
    // NOTE: The following call to -[type] resolves to a constant string
    // defined per-class.
    NSString *accountType = [self type];
    NSString *name = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
                      userName, accountType];
    NSString *identifier = [NSString stringWithFormat:kHGSAccountIdentifierFormat, 
                            accountType, userName];
    NSBundle *bundle = HGSGetPluginBundle();
    NSDictionary *configuration
      = [NSDictionary dictionaryWithObjectsAndKeys:
         name, kHGSExtensionUserVisibleNameKey,
         identifier, kHGSExtensionIdentifierKey,
         bundle, kHGSExtensionBundleKey,
         nil];
    if ((self = [super initWithConfiguration:configuration])) {
      [self setUserName:userName];
      if (![self userName] || ![self type]) {
        HGSLog(@"HGSAccounts require a userName and type.");
        [self release];
        self = nil;
      }
    }
  } else {
    [self release];
    self = nil;
  }
  return self;
}

- (id)initWithConfiguration:(NSDictionary *)prefDict {
  NSString *userName = [prefDict objectForKey:kHGSAccountUserNameKey];
  if ([userName length]) {
    // NOTE: The following call to -[type] resolves to a constant string
    // defined per-class.
    NSString *accountType = [self type];
    NSString *name = [prefDict objectForKey:kHGSExtensionUserVisibleNameKey];
    NSString *identifier = [prefDict objectForKey:kHGSExtensionIdentifierKey];
    NSBundle *bundle = [prefDict objectForKey:kHGSExtensionBundleKey];
    if (!name || !identifier || !bundle) {
      NSMutableDictionary *configuration
        = [NSMutableDictionary dictionaryWithDictionary:prefDict];
      if (!name) {
        name = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
                userName, accountType];
        [configuration setObject:name forKey:kHGSExtensionUserVisibleNameKey];
      }
      if (!identifier) {
        identifier = [NSString stringWithFormat:kHGSAccountIdentifierFormat, 
                      accountType, userName];
        [configuration setObject:identifier forKey:kHGSExtensionIdentifierKey];
      }
      if (!bundle) {
        bundle = HGSGetPluginBundle();
        if (!bundle) {
          HGSLog(@"HGSAccounts require bundle.");
          [self release];
          self = nil;
          return self;
        }
        [configuration setObject:bundle forKey:kHGSExtensionBundleKey];
      }
      prefDict = configuration;
    }
    if ((self = [super initWithConfiguration:prefDict])) {
      [self setUserName:userName];
      if (![self type]) {
        HGSLog(@"HGSAccounts require an account type.");
        [self release];
        self = nil;
      }
    }
  } else {
    HGSLog(@"HGSAccounts require a userName and type.");
    [self release];
    self = nil;
  }
  return self;
}

- (id)init {
  self = [self initWithName:nil];
  return self;
}

- (NSDictionary *)configuration {
  NSDictionary *accountDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       [self userName], kHGSAccountUserNameKey,
       [self type], kHGSAccountTypeKey,
       nil];
  return accountDict;
}

- (void) dealloc {
  [userName_ release];
  [super dealloc];
}

- (NSString *)displayName {
  NSString *localizedTypeName = HGSLocalizedString([self type], nil);
  NSString *displayName
    = [NSString stringWithFormat:kHGSAccountDisplayNameFormat,
       [self userName], localizedTypeName];
  return displayName;
}

- (NSString *)type {
  HGSAssert(@"Must be overridden by subclass", nil);
  return nil;
}

- (NSString *)password {
  return nil;
}

- (void)setPassword:(NSString *)password {
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter postNotificationName:kHGSAccountDidChangeNotification 
                               object:self];
}

+ (NSViewController *)
    setupViewControllerToInstallWithParentWindow:(NSWindow *)parentWindow {
  HGSLogDebug(@"Class '%@', deriving from HGSAccount, should override "
              @"accountSetupViewControllerToInstallWithParentWindow: if it "
              @"has an interface for setting up new accounts.", [self class]);
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
          [self class], self, [self userName], [self type]];
}

@end

NSString *const kHGSAccountDidChangeNotification
  = @"HGSAccountDidChangeNotification";
NSString *const kHGSAccountWillBeRemovedNotification
  = @"HGSAccountWillBeRemovedNotification";

NSString *const kHGSAccountUserNameKey = @"HGSAccountUserNameKey";
NSString *const kHGSAccountTypeKey = @"HGSAccountTypeKey";
