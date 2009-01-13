//
//  HGSExtensionPointTest.m
//  GoogleDesktop
//
//  Created by Mike Pinkerton on 6/4/08.
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

#import "GTMSenTestCase.h"
#import "HGSCoreExtensionPoints.h"

@interface HGSExtensionPointTest : GTMTestCase {
  BOOL gotNotification_;
}
@end

@protocol TestProtocol <HGSExtension>
- (void)doNothing;
@end

@protocol AnotherTestProtocol <HGSExtension>
- (void)doMoreNothing;
@end

@interface BaseTestExtension : NSObject {
  NSString *identifier_;
}
- (id)initWithIdentifier:(NSString *)identifier;
- (NSString *)identifier;
@end

@implementation BaseTestExtension
- (id)initWithIdentifier:(NSString *)identifier {
  if ((self = [super init])) {
    identifier_ = [identifier copy];
  }
  return self;
}

- (NSString *)identifier {
  return identifier_;
}

@end

@interface MyTestExtension : BaseTestExtension<TestProtocol>
@end

@implementation MyTestExtension
- (void)doNothing { }  // COV_NF_LINE
@end

@interface MyOtherTestExtension : BaseTestExtension <AnotherTestProtocol>
@end

@implementation MyOtherTestExtension
- (void)doMoreNothing { }  // COV_NF_LINE
@end


@implementation HGSExtensionPointTest

- (void)testCorePoints {
  HGSExtensionPoint* actionPoint = [HGSExtensionPoint actionsPoint];
  STAssertNotNil(actionPoint, @"action point not created correctly");
  HGSExtensionPoint* sourcesPoint = [HGSExtensionPoint sourcesPoint];
  STAssertNotNil(sourcesPoint, @"sources point not created correctly");

  // make sure they're not the same
  STAssertNotEqualObjects(actionPoint, sourcesPoint,
                          @"action and sources point are the same");
}

- (void)testProtocolChanging {
  // create a new extension point, given it a protocol
  HGSExtensionPoint* newPoint
    = [HGSExtensionPoint pointWithIdentifier:@"testProtocolChanging"];
  STAssertNotNil(newPoint, @"");
  [newPoint setProtocol:@protocol(TestProtocol)];

  // create new objects that implement the protocol and verify it's valid
  MyTestExtension* extension 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test1"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension],
               @"protocol check failed");
  extension = [[[MyTestExtension alloc] initWithIdentifier:@"test2"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension],
               @"protocol check failed");
  extension = [[[MyTestExtension alloc] initWithIdentifier:@"test3"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension],
               @"protocol check failed");
  extension = [[[MyTestExtension alloc] initWithIdentifier:@"test4"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension],
               @"protocol check failed");
  extension = [[[MyTestExtension alloc] initWithIdentifier:@"test5"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension],
               @"protocol check failed");

  // check there are 5
  NSArray* extensionList = [newPoint extensions];
  STAssertEquals([extensionList count], (NSUInteger)5,
                 @"not all extensions present");

  // now change the protocol to be empty, should have no effect
  [newPoint setProtocol:nil];
  extensionList = [newPoint extensions];
  STAssertEquals([extensionList count], (NSUInteger)5,
                 @"not all extensions present");

  // change to a different protocol, should remove all elements of the list
  [newPoint setProtocol:@protocol(AnotherTestProtocol)];
  extensionList = [newPoint extensions];

  STAssertEquals([extensionList count], (NSUInteger)0,
                 @"extra extensions present");
}

- (void)testProtocol {
  // create a new extension point, given it a protocol
  HGSExtensionPoint* newPoint
    = [HGSExtensionPoint pointWithIdentifier:@"testProtocol"];
  STAssertNotNil(newPoint, @"");
  [newPoint setProtocol:@protocol(TestProtocol)];

  // create a new object that implements that protocol and verify it's valid
  MyTestExtension* extension 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test1"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension],
               @"protocol check failed");

  // create a new object that implements some other protocol and make sure
  // it fails to add correclty.
  MyOtherTestExtension* badExtension
    = [[[MyOtherTestExtension alloc] init] autorelease];
  STAssertFalse([newPoint extendWithObject:badExtension],
                @"protocol check failed");
}

- (void)testExtendingPoint {
  HGSExtensionPoint* newPoint
    = [HGSExtensionPoint pointWithIdentifier:@"testExtendingPoint"];
  STAssertNotNil(newPoint, @"extension point creation failed");

  // test extending with nil object. There should be zero extensions at this
  // point.
  STAssertFalse([newPoint extendWithObject:nil],
                @"incorrectly added nil object");
  NSArray* extensionList = [newPoint extensions];
  STAssertEquals([extensionList count], (NSUInteger)0,
                 @"oddly has some extensions");
  
  // add some unique extensions
  MyTestExtension* extension1 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test1"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension1],
               @"extend failed");
  MyTestExtension* extension2 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test2"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension2],
               @"extend failed");
  MyTestExtension* extension3 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test3"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension3],
               @"extend failed");
  MyTestExtension* extension4 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test4"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension4],
               @"extend failed");
  MyTestExtension* extension5 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test5"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension5],
               @"extend failed");
  MyTestExtension* extension6 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test6"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension6],
               @"extend failed");

  // check there are 6
  extensionList = [newPoint extensions];
  STAssertEquals([extensionList count], (NSUInteger)6,
                 @"not all extensions present");
  NSArray *extensionIDList = [newPoint allExtensionIdentifiers];
  STAssertEquals([extensionIDList count], (NSUInteger)6,
                 @"not all extensions present");
  
  // check that adding the same id does not add a new item
  MyTestExtension* extension7 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test6"] autorelease];
  STAssertFalse([newPoint extendWithObject:extension7],
                @"extend failed");

  // check there are 6
  extensionList = [newPoint extensions];
  STAssertEquals([extensionList count], (NSUInteger)6,
                 @"not all extensions present");

  // check that adding the same extension again does not add a new item
  STAssertFalse([newPoint extendWithObject:extension6],
                @"extend failed");

  // check there are 6
  extensionList = [newPoint extensions];
  STAssertEquals([extensionList count], (NSUInteger)6,
                 @"not all extensions present");

  // check searching for identifiers
  MyTestExtension* result = [newPoint extensionWithIdentifier:@"test1"];
  STAssertEqualObjects(result, extension1, @"didn't find last object with id");
  [newPoint removeExtensionWithIdentifier:@"test1"];
  STAssertNil([newPoint extensionWithIdentifier:@"test1"], @"didn't remove");
  result = [newPoint extensionWithIdentifier:@"not found"];
  STAssertNil(result, @"found something with an identifier we didn't expect");
  result = [newPoint extensionWithIdentifier:nil];
  STAssertNil(result, @"found something with an identifier that was nil");

  NSString *description = [newPoint description];
  STAssertTrue([description hasPrefix:@"HGSExtensionPoint - testExtendingPoint"],
               nil);
}

- (void)pointNotification:(NSNotification *)notification {
  gotNotification_ = YES;
}

- (void)addExtensionToPoint:(HGSExtensionPoint *)point {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  MyTestExtension* extension 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test2"] autorelease];
  [point extendWithObject:extension];
  [pool release];
}

- (void)testNotification {
  HGSExtensionPoint* newPoint
    = [HGSExtensionPoint pointWithIdentifier:@"testNotification"];
  STAssertNotNil(newPoint, @"extension point creation failed");

  MyTestExtension* extension1 
    = [[[MyTestExtension alloc] initWithIdentifier:@"test1"] autorelease];
  STAssertTrue([newPoint extendWithObject:extension1],
               @"extend failed");

  // let notifications clear
  NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
  [runLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];

  NSNotificationCenter* nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self selector:@selector(pointNotification:)
             name:kHGSExtensionPointDidChangeNotification
           object:newPoint];

  // add on a thread, and make sure we get the notification
  STAssertFalse(gotNotification_, nil);
  [NSThread detachNewThreadSelector:@selector(addExtensionToPoint:)
                           toTarget:self
                         withObject:newPoint];
  [runLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
  STAssertTrue(gotNotification_, @"failed to get notification for add");

  [nc removeObserver:self
                name:kHGSExtensionPointDidChangeNotification
              object:newPoint];
}

@end
