//
//  HGSPythonActionTest.m
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
#import "HGSPythonAction.h"
#import "HGSResult.h"

@interface HGSPythonActionTest : GTMTestCase 
@end

@implementation HGSPythonActionTest

- (void)testAction {
  HGSPython *sharedPython = [HGSPython sharedPython];
  STAssertNotNil(sharedPython, nil);
  
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  [sharedPython appendPythonPath:[bundle resourcePath]];
  
  NSDictionary *config = [NSDictionary dictionaryWithObjectsAndKeys:
                          @"VermilionTest", kPythonModuleNameKey,
                          @"VermilionAction", kPythonClassNameKey,
                          @"python.test", kHGSExtensionIdentifierKey,
                          @"*", @"HGSActionDirectObjectTypes",
                          bundle, kHGSExtensionBundleKey,
                          nil];
  STAssertNotNil(config, nil);

  HGSPythonAction *action
    = [[[HGSPythonAction alloc] initWithConfiguration:config] autorelease];
  STAssertNotNil(action, nil);
  
  NSURL *url = [NSURL URLWithString:@"http://www.google.com/"];
  HGSResult *result = [HGSResult resultWithURL:url
                                          name:@"Google"
                                          type:kHGSTypeWebBookmark
                                        source:nil
                                    attributes:nil];
  STAssertNotNil(result, nil);
  HGSResultArray *results = [HGSResultArray arrayWithResult:result];
  STAssertNotNil(results, nil);
  
  STAssertTrue([action appliesToResults:results], nil);
  
  NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                        results, kHGSActionDirectObjectsKey, nil];
  STAssertNotNil(info, nil);
  
  STAssertTrue([action performWithInfo:info], nil);
  
  STAssertNotNil([action directObjectTypes], nil);
}

@end
