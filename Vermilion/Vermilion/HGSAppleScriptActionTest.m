//
//  HGSAppleScriptActionTest.m
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
#import "HGSAppleScriptAction.h"
#import "HGSResult.h"
#import "HGSActionOperation.h"

@interface HGSAppleScriptActionTest : GTMTestCase 
@end

@implementation HGSAppleScriptActionTest
- (void)testBadConfig {
  HGSAppleScriptAction *action 
    = [[[HGSAppleScriptAction alloc] init] autorelease];
  STAssertNil(action, nil);
  
  NSDictionary *badConfig = [NSDictionary dictionaryWithObjectsAndKeys:nil];
  action = [[[HGSAppleScriptAction alloc] 
             initWithConfiguration:badConfig] autorelease];
  STAssertNil(action, nil);

  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  badConfig = [NSDictionary dictionaryWithObjectsAndKeys:
               bundle, kHGSExtensionBundleKey,
               @"BadName", kHGSAppleScriptFileNameKey, nil];
  action = [[[HGSAppleScriptAction alloc] 
             initWithConfiguration:badConfig] autorelease];
  STAssertNil(action, nil);
}

- (void)testMinimalConfig {
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSDictionary *config = [NSDictionary dictionaryWithObjectsAndKeys:
               bundle, kHGSExtensionBundleKey,
               @"applescript.test", kHGSExtensionIdentifierKey, nil];
  HGSAppleScriptAction *action = [[[HGSAppleScriptAction alloc] 
                                   initWithConfiguration:config] autorelease];
  STAssertNil(action, nil);
}

- (void)testAction {  
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSDictionary *config 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       bundle, kHGSExtensionBundleKey,
       @"HGSAppleScriptHandlerTest", kHGSAppleScriptFileNameKey, 
       @"testHandler", kHGSAppleScriptHandlerNameKey,
       @"*", kHGSActionDirectObjectTypesKey,
       @"applescript.test", kHGSExtensionIdentifierKey,
       nil];
  HGSAppleScriptAction *action 
    = [[[HGSAppleScriptAction alloc] initWithConfiguration:config] autorelease];
  STAssertNotNil(action, nil);
  
  NSURL *url = [NSURL URLWithString:@"applescript://test"];
  HGSResult *result1 = [HGSResult resultWithURL:url 
                                           name:@"test1" 
                                           type:kHGSTypeScript 
                                         source:nil 
                                     attributes:nil];
  STAssertNotNil(result1, nil);
  url = [NSURL URLWithString:@"applescript://test2"];
  HGSResult *result2 = [HGSResult resultWithURL:url 
                                           name:@"test2" 
                                           type:kHGSTypeScript 
                                         source:nil 
                                     attributes:nil];
  STAssertNotNil(result2, nil);
  NSArray *results = [NSArray arrayWithObjects:result1, result2, nil];
  HGSResultArray *hgsResults = [HGSResultArray arrayWithResults:results];
  STAssertNotNil(hgsResults, nil);
  STAssertTrue([action appliesToResults:hgsResults], nil);
  STAssertFalse([action showInGlobalSearchResults], nil);
  HGSActionOperation *operation 
    = [[[HGSActionOperation alloc] initWithAction:action 
                                    directObjects:hgsResults] autorelease];
  NSDictionary *opResults = [operation performAction];
  BOOL wasGood = [[opResults objectForKey:kHGSActionCompletedSuccessfully] 
                  boolValue];
  STAssertTrue(wasGood, nil);
  
  NSDictionary *openConfig
    = [NSDictionary dictionaryWithObjectsAndKeys:
       bundle, kHGSExtensionBundleKey,
       @"HGSAppleScriptHandlerTest", kHGSAppleScriptFileNameKey, 
       @"*", kHGSActionDirectObjectTypesKey,
       @"applescript.test2", kHGSExtensionIdentifierKey,
       nil];
  action = [[[HGSAppleScriptAction alloc] 
             initWithConfiguration:openConfig] autorelease];
  STAssertNotNil(action, nil);
  STAssertTrue([action appliesToResults:hgsResults], nil);
  STAssertFalse([action showInGlobalSearchResults], nil);
  operation 
    = [[[HGSActionOperation alloc] initWithAction:action 
                                    directObjects:hgsResults] autorelease];
  opResults = [operation performAction];
  wasGood = [[opResults objectForKey:kHGSActionCompletedSuccessfully] 
             boolValue];
  STAssertTrue(wasGood, nil);
}

- (void)testAppliesToRunningAppAction {  
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSDictionary *requiredAppDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"com.apple.finder", kHGSAppleScriptBundleIDKey,
       [NSNumber numberWithBool:YES], kHGSAppleScriptMustBeRunningKey,
       nil];
  NSArray *requiredApps = [NSArray arrayWithObject:requiredAppDict];
  NSDictionary *config 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       bundle, kHGSExtensionBundleKey,
       @"HGSAppleScriptHandlerTest", kHGSAppleScriptFileNameKey, 
       @"testHandler", kHGSAppleScriptHandlerNameKey,
       @"applescript.test", kHGSExtensionIdentifierKey,
       requiredApps, kHGSAppleScriptApplicationsKey,
       nil];
  HGSAppleScriptAction *action 
    = [[[HGSAppleScriptAction alloc] initWithConfiguration:config] autorelease];
  STAssertNotNil(action, nil);
  
  NSURL *url = [NSURL URLWithString:@"applescript://test"];
  HGSResult *result1 = [HGSResult resultWithURL:url 
                                           name:@"test1" 
                                           type:kHGSTypeScript
                                         source:nil 
                                     attributes:nil];
  STAssertNotNil(result1, nil);
  url = [NSURL URLWithString:@"applescript://test2"];
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"com.apple.finder", kHGSObjectAttributeBundleIDKey,
       nil];
  HGSResult *result2 = [HGSResult resultWithURL:url 
                                           name:@"test2" 
                                           type:kHGSTypeScript 
                                         source:nil 
                                     attributes:attributes];
  STAssertNotNil(result2, nil);
  NSArray *results = [NSArray arrayWithObjects:result1, result2, nil];
  HGSResultArray *hgsResults = [HGSResultArray arrayWithResults:results];
  STAssertNotNil(hgsResults, nil);
  STAssertTrue([action appliesToResults:hgsResults], nil);
  STAssertTrue([action showInGlobalSearchResults], nil);
}
@end