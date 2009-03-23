//
//  HGSAccountTest.m
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
#import <OCMock/OCMock.h>

@interface HGSAccountTest : GTMTestCase {
 @private
  BOOL receivedPasswordNotification_;
  BOOL receivedWillBeRemovedNotification_;
  HGSAccount *account_;
}

@property (getter=didReceivePasswordNotification)
  BOOL receivedPasswordNotification;
@property (getter=didReceiveWillBeRemovedNotification)
  BOOL receivedWillBeRemovedNotification;
@property (retain) HGSAccount *account;

- (void)passwordChanged:(NSNotification *)notification;
- (void)willBeRemoved:(NSNotification *)notification;

@end

@interface SimpleAccount : HGSAccount
@end

@implementation SimpleAccount

- (NSString *)type {
  return @"SimpleAccountType";
}

@end

@implementation HGSAccountTest

@synthesize receivedPasswordNotification = receivedPasswordNotification_;
@synthesize receivedWillBeRemovedNotification
  = receivedWillBeRemovedNotification_;
@synthesize account = account_;

- (void)setAccount:(HGSAccount *)account {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  if (account_) {
    [account_ release];
    [nc removeObserver:self];
  }
  if (account) {
    account_ = [account retain];
    [nc addObserver:self
           selector:@selector(passwordChanged:)
               name:kHGSAccountDidChangeNotification
             object:account];
    [nc addObserver:self
           selector:@selector(willBeRemoved:)
               name:kHGSAccountWillBeRemovedNotification
             object:account];
  }
}

- (void)dealloc {
  [self setAccount:nil];
  [super dealloc];
}

- (void)passwordChanged:(NSNotification *)notification {
  id notificationObject = [notification object];
  HGSAccount *expectedAccount = [self account];
  BOOL gotExpectedObject = (notificationObject == expectedAccount);
  [self setReceivedPasswordNotification:gotExpectedObject];
}

- (void)willBeRemoved:(NSNotification *)notification {
  id notificationObject = [notification object];
  HGSAccount *expectedAccount = [self account];
  BOOL gotExpectedObject = (notificationObject == expectedAccount);
  [self setReceivedWillBeRemovedNotification:gotExpectedObject];
}

#pragma mark Tests

- (void)testInit {
  // init
  HGSAccount *account = [[[HGSAccount alloc] init] autorelease];
  STAssertNil(account, @"|init| should not create new HSGAccount");
  // initWithName:
  account = [[[HGSAccount alloc] initWithName:nil] autorelease];
  STAssertNil(account, @"|initWithName:nil| should not create new HSGAccount");
  account = [[[HGSAccount alloc] initWithName:@""] autorelease];
  STAssertNil(account, @"|initWithName:@\"\"| should not create new HSGAccount");
  account = [[[HGSAccount alloc] initWithName:@"USERNAME"] autorelease];
  STAssertNil(account, nil);
  // initWithConfiguration:
  NSDictionary *configuration = [NSDictionary dictionary];
  account
    = [[[HGSAccount alloc] initWithConfiguration:configuration] autorelease];
  STAssertNil(account, nil);
  configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"USERNAME A", kHGSAccountUserNameKey,
                   nil];
  account
    = [[[HGSAccount alloc] initWithConfiguration:configuration] autorelease];
  STAssertNil(account, nil);
  configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"USERNAME B", kHGSAccountUserNameKey,
                   @"DUMMY TYPE B", kHGSAccountTypeKey,
                   nil];
  account
    = [[[HGSAccount alloc] initWithConfiguration:configuration] autorelease];
  STAssertNil(account, nil);
  // Initializations with test account type.  This is the only one that
  // should actually succeed in creating an account.
  configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                   @"USERNAME C", kHGSAccountUserNameKey,
                   nil];
  account
    = [[[SimpleAccount alloc] initWithConfiguration:configuration] autorelease];
  STAssertNotNil(account, nil);
}

- (void)testConfiguration {
  NSDictionary *configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"USERNAME D", kHGSAccountUserNameKey,
                                 nil];
  HGSAccount *account
    = [[[SimpleAccount alloc] initWithConfiguration:configuration] autorelease];
  NSDictionary *result = [account configuration];
  STAssertNotNil(result, nil);
  NSString * userName = [result objectForKey:kHGSAccountUserNameKey];
  STAssertEqualObjects(userName, @"USERNAME D", nil);
  NSString * accountType = [result objectForKey:kHGSAccountTypeKey];
  STAssertEqualObjects(accountType, @"SimpleAccountType", nil);
}

- (void)testAccessors {
  NSDictionary *configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"USERNAME E", kHGSAccountUserNameKey,
                                nil];
  HGSAccount *account
    = [[[SimpleAccount alloc] initWithConfiguration:configuration] autorelease];
  NSString *displayName = [account displayName];
  STAssertEqualObjects(displayName, @"USERNAME E (SimpleAccountType)", nil);
  NSString *accountType = [account type];
  STAssertEqualObjects(accountType, @"SimpleAccountType", nil);
  NSString *password = [account password];
  STAssertNil(password, nil);
  BOOL isEditable = [account isEditable];
  STAssertTrue(isEditable, nil);
  NSString *description = [account description];
  STAssertNotNil(description, nil);
  
  // Null operations.
  [account editWithParentWindow:nil];
  [account authenticate];
  
  // Class Accessors
  NSViewController *setupController
    = [HGSAccount setupViewControllerToInstallWithParentWindow:nil];
  STAssertNil(setupController, nil);
}

- (void)testSetPassword {
  NSDictionary *configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"USERNAME F", kHGSAccountUserNameKey,
                                 nil];
  HGSAccount *account
    = [[[SimpleAccount alloc] initWithConfiguration:configuration] autorelease];
  [self setAccount:account];
  [account setPassword:@"PASSWORD F"];
  STAssertTrue([self didReceivePasswordNotification], nil);
}

- (void)testRemove {
  NSDictionary *configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                                 @"USERNAME G", kHGSAccountUserNameKey,
                                 nil];
  HGSAccount *account
    = [[[SimpleAccount alloc] initWithConfiguration:configuration] autorelease];
  [self setAccount:account];
  [account remove];
  STAssertTrue([self didReceiveWillBeRemovedNotification], nil);
}

@end
