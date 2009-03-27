//
//  HGSAccountsExtensionPointTest.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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


#import "GTMSenTestCase.h"
#import "HGSAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "HGSCoreExtensionPoints.h"
#import <OCMock/OCMock.h>


@interface HGSAccountsExtensionPointTest : GTMTestCase {
 @private
  BOOL receivedAddAccountExtensionNotification_;
  BOOL receivedWillRemoveAccountExtensionNotification_;
  BOOL receivedWillRemoveAccountNotification_;
  BOOL receivedDidRemoveAccountExtensionNotification_;
  HGSAccount *expectedAccount_;
}

@property BOOL receivedAddAccountExtensionNotification;
@property BOOL receivedWillRemoveAccountNotification;
@property BOOL receivedWillRemoveAccountExtensionNotification;
@property BOOL receivedDidRemoveAccountExtensionNotification;
@property (retain) HGSAccount *expectedAccount;

@end


@interface TestAccount : HGSAccount
@end

static NSString *const kTestAccountType = @"TestAccountType";

@implementation TestAccount

- (NSString *)type {
  return kTestAccountType;
}

@end


@implementation HGSAccountsExtensionPointTest

@synthesize receivedAddAccountExtensionNotification
  = receivedAddAccountExtensionNotification_;
@synthesize receivedWillRemoveAccountNotification
  = receivedWillRemoveAccountNotification_;
@synthesize receivedWillRemoveAccountExtensionNotification
  = receivedWillRemoveAccountExtensionNotification_;
@synthesize receivedDidRemoveAccountExtensionNotification
  = receivedDidRemoveAccountExtensionNotification_;
@synthesize expectedAccount = expectedAccount_;

- (void)dealloc {
  [self setExpectedAccount:nil];
  [super dealloc];
}

- (void)setExpectedAccount:(HGSAccount *)expectedAccount {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  if (expectedAccount_) {
    [expectedAccount_ release];
    [nc removeObserver:self];
  }
  if (expectedAccount) {
    expectedAccount_ = [expectedAccount retain];
    [nc addObserver:self
           selector:@selector(didAddAccountExtensionNotification:)
               name:kHGSExtensionPointDidAddExtensionNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(willRemoveAccountExtensionNotification:)
               name:kHGSExtensionPointWillRemoveExtensionNotification
             object:nil];
    // TODO(mrossetti): Clearly, we don't need the following so remove it and
    // change over all such in QSB to use above notification instead.
    [nc addObserver:self
           selector:@selector(willRemoveAccountNotification:)
               name:kHGSAccountWillBeRemovedNotification
             object:nil];
    [nc addObserver:self
           selector:@selector(didRemoveAccountExtensionNotification:)
               name:kHGSExtensionPointDidRemoveExtensionNotification
             object:nil];
    
  }
}

- (BOOL)receivedAddAccountExtensionNotification {
  BOOL result = receivedAddAccountExtensionNotification_;
  receivedAddAccountExtensionNotification_ = NO;
  return result;
}

- (BOOL)receivedWillRemoveAccountExtensionNotification {
  BOOL result = receivedWillRemoveAccountExtensionNotification_;
  receivedWillRemoveAccountExtensionNotification_ = NO;
  return result;
}

- (BOOL)receivedWillRemoveAccountNotification {
  BOOL result = receivedWillRemoveAccountNotification_;
  receivedWillRemoveAccountNotification_ = NO;
  return result;
}

- (BOOL)receivedDidRemoveAccountExtensionNotification {
  BOOL result = receivedDidRemoveAccountExtensionNotification_;
  receivedDidRemoveAccountExtensionNotification_ = NO;
  return result;
}

#pragma mark Notification Handlers

- (void)didAddAccountExtensionNotification:(NSNotification *)notification {
  STAssertEquals([[notification object] class],
                 [HGSAccountsExtensionPoint class], nil);
  NSDictionary *userInfo = [notification userInfo];
  id notificationObject = [userInfo objectForKey:kHGSExtensionKey];
  HGSAccount *expectedAccount = [self expectedAccount];
  BOOL gotExpectedObject = (notificationObject == expectedAccount);
  [self setReceivedAddAccountExtensionNotification:gotExpectedObject];
}

- (void)willRemoveAccountExtensionNotification:(NSNotification *)notification {
  STAssertEquals([[notification object] class],
                 [HGSAccountsExtensionPoint class], nil);
  NSDictionary *userInfo = [notification userInfo];
  id notificationObject = [userInfo objectForKey:kHGSExtensionKey];
  HGSAccount *expectedAccount = [self expectedAccount];
  BOOL gotExpectedObject = (notificationObject == expectedAccount);
  [self setReceivedWillRemoveAccountExtensionNotification:gotExpectedObject];
}

- (void)willRemoveAccountNotification:(NSNotification *)notification {
  id notificationObject = [notification object];
  HGSAccount *expectedAccount = [self expectedAccount];
  BOOL gotExpectedObject = (notificationObject == expectedAccount);
  [self setReceivedWillRemoveAccountNotification:gotExpectedObject];
}

- (void)didRemoveAccountExtensionNotification:(NSNotification *)notification {
  STAssertEquals([[notification object] class],
                 [HGSAccountsExtensionPoint class], nil);
  NSDictionary *userInfo = [notification userInfo];
  id notificationObject = [userInfo objectForKey:kHGSExtensionKey];
  HGSAccount *expectedAccount = [self expectedAccount];
  BOOL gotExpectedObject = (notificationObject == expectedAccount);
  [self setReceivedDidRemoveAccountExtensionNotification:gotExpectedObject];
}

#pragma mark Tests

- (void)testBasicAccountExtensions {
  HGSAccountsExtensionPoint *accountsPoint = [HGSExtensionPoint accountsPoint];
  STAssertNotNil(accountsPoint, nil);
  
  // Vain attempts to add bad account types
  [accountsPoint addAccountType:nil withClass:nil];
  NSUInteger typeCount = [[accountsPoint visibleAccountTypeDisplayNames] count];
  STAssertEquals(typeCount, (NSUInteger)0, nil);
  [accountsPoint addAccountType:nil withClass:[NSString class]];
  typeCount = [[accountsPoint visibleAccountTypeDisplayNames] count];
  STAssertEquals(typeCount, (NSUInteger)0, nil);
  [accountsPoint addAccountType:@"DUMMYTYPE" withClass:nil];
  typeCount = [[accountsPoint visibleAccountTypeDisplayNames] count];
  STAssertEquals(typeCount, (NSUInteger)0, nil);
  
  // Valid attempt to add good account type
  [accountsPoint addAccountType:kTestAccountType
                      withClass:[TestAccount class]];
  typeCount = [[accountsPoint visibleAccountTypeDisplayNames] count];
  STAssertEquals(typeCount, (NSUInteger)1, nil);
  Class class = [accountsPoint classForAccountType:kTestAccountType];
  STAssertEquals(class, [TestAccount class], nil);
  
  // There should be no accounts registered yet.
  NSArray *accounts = [accountsPoint accountsForType:@"DUMMYTYPE"];
  STAssertEquals([accounts count], (NSUInteger)0, nil);
  accounts = [accountsPoint accountsForType:kTestAccountType];
  STAssertEquals([accounts count], (NSUInteger)0, nil);

  // Attempt to add invalid accounts.
  STAssertFalse([accountsPoint extendWithObject:nil], nil);
  accounts = [accountsPoint extensions];
  STAssertEquals([accounts count], (NSUInteger)0, nil);
  accounts = [accountsPoint accountsAsArray];
  STAssertEquals([accounts count], (NSUInteger)0, nil);
  BOOL notified = [self receivedAddAccountExtensionNotification];
  STAssertFalse(notified, nil);
  
  // Add one valid account.
  TestAccount *account1
    = [[[TestAccount alloc] initWithName:@"account1"] autorelease];
  STAssertNotNil(account1, nil);
  [self setExpectedAccount:account1];
  STAssertTrue([accountsPoint extendWithObject:account1], nil);
  accounts = [accountsPoint accountsAsArray];
  STAssertEquals([accounts count], (NSUInteger)1, nil);
  notified = [self receivedAddAccountExtensionNotification];
  STAssertTrue(notified, nil);
  
  // Remove the account.
  [account1 remove];
  notified = [self receivedWillRemoveAccountNotification];
  STAssertTrue(notified, nil);
  notified = [self receivedWillRemoveAccountExtensionNotification];
  STAssertTrue(notified, nil);
  notified = [self receivedDidRemoveAccountExtensionNotification];
  STAssertTrue(notified, nil);
 
  [self setExpectedAccount:nil];
  
  // Add several accounts.
  id bundleMock = [OCMockObject mockForClass:[NSBundle class]];
  [[[bundleMock stub] andReturn:@"bundle.identifier"] 
   objectForInfoDictionaryKey:@"CFBundleIdentifier"];
  NSDictionary *accountDict1 = [NSDictionary dictionaryWithObjectsAndKeys:
                                kTestAccountType, kHGSAccountTypeKey,
                                bundleMock, kHGSExtensionBundleKey,
                                @"account1", kHGSAccountUserNameKey,
                                nil];
  NSDictionary *accountDict2 = [NSDictionary dictionaryWithObjectsAndKeys:
                                kTestAccountType, kHGSAccountTypeKey,
                                bundleMock, kHGSExtensionBundleKey,
                                @"account2", kHGSAccountUserNameKey,
                                nil];
  NSDictionary *accountDict3 = [NSDictionary dictionaryWithObjectsAndKeys:
                                kTestAccountType, kHGSAccountTypeKey,
                                bundleMock, kHGSExtensionBundleKey,
                                @"account3", kHGSAccountUserNameKey,
                                nil];
  NSDictionary *accountDict4 = [NSDictionary dictionaryWithObjectsAndKeys:
                                kTestAccountType, kHGSAccountTypeKey,
                                bundleMock, kHGSExtensionBundleKey,
                                @"account4", kHGSAccountUserNameKey,
                                nil];
  NSDictionary *accountDict5 = [NSDictionary dictionaryWithObjectsAndKeys:
                                kTestAccountType, kHGSAccountTypeKey,
                                bundleMock, kHGSExtensionBundleKey,
                                @"account5", kHGSAccountUserNameKey,
                                nil];
  NSArray *accountDicts = [NSArray arrayWithObjects:accountDict1, accountDict2,
                       accountDict3, accountDict4, accountDict5, nil];
  [accountsPoint addAccountsFromArray:accountDicts];
  accounts = [accountsPoint accountsForType:kTestAccountType];
  NSUInteger accountCount = [accounts count];
  STAssertEquals(accountCount, (NSUInteger)5, nil);
  
  NSString *description = [accountsPoint description];
  STAssertNotEquals([description length], (NSUInteger)0, nil);
}

@end
