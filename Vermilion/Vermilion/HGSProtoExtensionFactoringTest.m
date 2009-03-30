//
//  HGSProtoExtensionFactoringTest.m
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
#import "HGSExtensionPoint.h"
#import "HGSPlugin.h"
#import "HGSProtoExtension.h"
#import <OCMock/OCMock.h>

@interface HGSProtoExtensionFactoringTest : GTMTestCase {
 @private
  __weak HGSProtoExtension *expectedExtensionRemoved_;
}

@end


@interface FactorableAccount : HGSAccount
@end

// Account Extension Mock
static NSString *const kFactorableAccountType = @"FactorableAccountType";

@implementation FactorableAccount

- (NSString *)type {
  return kFactorableAccountType;
}

@end


@implementation HGSProtoExtensionFactoringTest

- (BOOL)expectedExtensionConstraint:(id)value {
  STAssertTrue([value isKindOfClass:[HGSProtoExtension class]], nil);
  BOOL isExpectedObject = (value == expectedExtensionRemoved_);
  return isExpectedObject;
}

- (void)testFactoring {
  // Set up the accounts point and add an account.
  id bundleMock = [OCMockObject mockForClass:[NSBundle class]];
  [[[bundleMock stub] andReturn:@"bundle.identifier"] 
   objectForInfoDictionaryKey:@"CFBundleIdentifier"];
  NSDictionary *accountDict = [NSDictionary dictionaryWithObjectsAndKeys:
                               kFactorableAccountType, kHGSAccountTypeKey,
                               bundleMock, kHGSExtensionBundleKey,
                               @"testAccount", kHGSAccountUserNameKey,
                               nil];
  NSArray *accountDicts = [NSArray arrayWithObject:accountDict];

  HGSAccountsExtensionPoint *aep = [HGSExtensionPoint accountsPoint];
  [aep addAccountType:kFactorableAccountType
            withClass:[FactorableAccount class]];
  [aep addAccountsFromArray:accountDicts];
  
  NSArray *accounts = [aep accountsForType:kFactorableAccountType];
  STAssertEquals([accounts count], (NSUInteger)1, nil);
  HGSAccount *account = [accounts objectAtIndex:0];
  [account setAuthenticated:YES];

  // Create the factorable extension.
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"DISPLAY NAME", kHGSExtensionUserVisibleNameKey,
       @"IDENTIFIER", kHGSExtensionIdentifierKey,
       @"CLASS NAME", kHGSExtensionClassKey,
       kHGSAccountsExtensionPoint, kHGSExtensionPointKey,
       [NSNumber numberWithBool:YES], kHGSExtensionEnabledKey,
       kFactorableAccountType, kHGSExtensionDesiredAccountTypes,
       [NSNumber numberWithBool:YES], kHGSExtensionIsUserVisible,
       nil];
  id pluginMock = [OCMockObject mockForClass:[HGSPlugin class]];
  [[[pluginMock stub] andReturn:@"PLUGIN"] displayName];
  [[[pluginMock stub] andReturn:@"BUNDLE PLACEHOLDER"] bundle];
  HGSProtoExtension *protoExtensionI
    = [[[HGSProtoExtension alloc] initWithConfiguration:configuration
                                                 plugin:pluginMock]
       autorelease];
  NSArray *factored = [protoExtensionI factor];
  STAssertEquals([factored count], (NSUInteger)1, nil);

  // Take the extension for a test drive.
  HGSProtoExtension *factoredExtension = [factored objectAtIndex:0];
  BOOL userVisible
    = [factoredExtension
       isUserVisibleAndExtendsExtensionPoint:kHGSAccountsExtensionPoint];
  STAssertTrue(userVisible, nil);
  BOOL yes = YES;
  [[[pluginMock stub] andReturnValue:OCMOCK_VALUE(yes)] isEnabled];
  STAssertTrue([factoredExtension canSetEnabled], nil);
  
  // TODO(mrossetti):Test installing by calling setEnabled:(YES|NO).

  // Remove the account.
  expectedExtensionRemoved_ = factoredExtension;
  id constraint
    = [OCMockArgConstraint constrainTo:@selector(expectedExtensionConstraint:)
                                    of:self];
  [[pluginMock expect] removeProtoExtension:constraint];
  [account remove];
  expectedExtensionRemoved_ = nil;
  [pluginMock verify];
}

@end
