//
//  KeychainItemTest.m
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
#import "KeychainItem.h"

static NSString *const kServiceName = @"com.google.KeychainTest.serviceName";
static NSString *const kHostName = @"com.google.KeychainTest.hostName";
static NSString *const kUserName1 = @"userName1@keychaintest.com";
static NSString *const kUserName2 = @"userName2@keychaintest.com";
static NSString *const kPassword1 = @"PASSWORD1";
static NSString *const kPassword2 = @"PASSWORD2";


@interface KeychainItemTest : GTMTestCase 
@end

@implementation KeychainItemTest

- (void)setUp {
  // Cleanse the keychain in case something was leftover from the last test.
  NSArray *keychainItems
    = [KeychainItem allKeychainItemsForService:kServiceName];
  for (KeychainItem *keychainItem in keychainItems) {
    [keychainItem removeFromKeychain];
  }
}

- (void)tearDown {
  // Cleanse the keychain.
  NSArray *keychainItems
    = [KeychainItem allKeychainItemsForService:kServiceName];
  for (KeychainItem *keychainItem in keychainItems) {
    [keychainItem removeFromKeychain];
  }
}

#pragma mark Tests

- (void)testEmptyKeychainItem {
  // Nothing in keychain tests.
  KeychainItem *item = [KeychainItem keychainItemForService:kServiceName
                                                  username:kUserName1];
  STAssertNil(item, nil);
  item = [KeychainItem keychainItemForHost:kHostName
                                  username:kUserName1];
  STAssertNil(item, nil);
  NSArray *items = [KeychainItem allKeychainItemsForService:kServiceName];
  STAssertNotNil(items, nil);
  STAssertEquals([items count], (NSUInteger)0, nil);
}

- (void)testBadKeychainArgs {  
  // Create keychain items with bad args.
  KeychainItem *item = [KeychainItem addKeychainItemForService:nil
                                                  withUsername:nil
                                                      password:nil];
  STAssertNil(item, nil);
  item = [KeychainItem addKeychainItemForService:nil
                                    withUsername:nil
                                        password:kPassword1];
  STAssertNil(item, nil);
  item = [KeychainItem addKeychainItemForService:nil
                                    withUsername:kUserName1
                                        password:nil];
  STAssertNil(item, nil);
  item = [KeychainItem addKeychainItemForService:nil
                                    withUsername:kUserName1
                                        password:kPassword1];
  STAssertNil(item, nil);
}

#pragma mark Basic Tests

- (void)testKeychainItem {
  KeychainItem *item = [KeychainItem addKeychainItemForService:kServiceName
                                                  withUsername:nil
                                                      password:nil];
  STAssertNotNil(item, nil);
  NSString *userName = [item username];
  STAssertEqualObjects(userName, @"", nil);
  NSString *password = [item password];
  STAssertEqualObjects(password, @"", nil);

  // Retreive and validate.
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:kUserName1];
  STAssertNil(item, nil);
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:nil];
  STAssertNotNil(item, nil);
  userName = [item username];
  STAssertEqualObjects(userName, @"", nil);
  password = [item password];
  STAssertEqualObjects(password, @"", nil);
  
  // Remove
  [item removeFromKeychain];
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:nil];
  STAssertNil(item, nil);
}

- (void)testKeychainItemWithPassword {
  KeychainItem *item = [KeychainItem addKeychainItemForService:kServiceName
                                                  withUsername:nil
                                                      password:kPassword1];
  STAssertNotNil(item, nil);

  // Retreive and validate.
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:nil];
  STAssertNotNil(item, nil);
  NSString *userName = [item username];
  STAssertEqualObjects(userName, @"", nil);
#if !__POWERPC__
  // TODO(mrossetti): Come back to this and figure out why this is happening.
  // PPC requires user authentication to get to the keychain.
  NSString *password = [item password];
  STAssertEqualObjects(password, kPassword1, nil);
#endif
  // Remove
  [item removeFromKeychain];
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:nil];
  STAssertNil(item, nil);
}

- (void)testKeychainItemWithUserName {
  KeychainItem *item = [KeychainItem addKeychainItemForService:kServiceName
                                                  withUsername:kUserName1
                                                      password:nil];
  STAssertNotNil(item, nil);
  NSString *userName = [item username];
  STAssertEqualObjects(userName, kUserName1, nil);
  NSString *password = [item password];
  STAssertEqualObjects(password, @"", nil);
  
  // Retreive and validate.
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:kUserName1];
  STAssertNotNil(item, nil);
  userName = [item username];
  STAssertEqualObjects(userName, kUserName1, nil);
  password = [item password];
  STAssertEqualObjects(password, @"", nil);
  
  // Remove
  [item removeFromKeychain];
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:kUserName1];
  STAssertNil(item, nil);
}

- (void)testKeychainItemWithUserNamePassword {
  KeychainItem *item = [KeychainItem addKeychainItemForService:kServiceName
                                                  withUsername:kUserName1
                                                      password:kPassword1];
  STAssertNotNil(item, nil);
#if !__POWERPC__
  // PPC requires user authentication to get to the keychain.
  NSString *userName = [item username];
  STAssertEqualObjects(userName, kUserName1, nil);
  NSString *password = [item password];
  STAssertEqualObjects(password, kPassword1, nil);
  
  // Retreive and validate.
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:kUserName1];
  STAssertNotNil(item, nil);
  userName = [item username];
  STAssertEqualObjects(userName, kUserName1, nil);
  password = [item password];
  STAssertEqualObjects(password, kPassword1, nil);
#endif

  // Remove
  [item removeFromKeychain];
  item = [KeychainItem keychainItemForService:kServiceName
                                     username:kUserName1];
  STAssertNil(item, nil);
}

@end
