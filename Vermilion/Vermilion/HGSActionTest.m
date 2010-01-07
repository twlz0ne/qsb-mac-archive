//
//  HGSActionTest.m
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

#if !TARGET_OS_IPHONE
#import <Cocoa/Cocoa.h>
#else
#import <UIKit/UIKit.h>
#endif
#import "GTMSenTestCase.h"

#import "HGSAction.h"
#import "HGSResult.h"

// A special dummy subtype of the webpage type.
#define kHGSTypeWebFrammy HGS_SUBTYPE(kHGSTypeWebpage, @"frammy")

@interface HGSActionTest : GTMTestCase {
 @private
  NSBundle *bundle_;
}
@end

@interface MyObject : HGSResult
- (id)initWithIdentifier:(NSString*)identifier;
@end

@implementation MyObject
- (id)initWithIdentifier:(NSString*)identifier {
  return [super initWithURI:identifier
                       name:@"MyObject" 
                       type:@"test" 
                       rank:kHGSResultUnknownRank
                     source:nil
                 attributes:nil];
}
@end

@interface MyAction : HGSAction {
 @private
  NSImage *localIcon_;
}
@end

@implementation MyAction : HGSAction

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
     = [info objectForKey:kHGSActionDirectObjectsKey];
  return (directObjects != nil) ? YES : NO;
}

- (id)defaultObjectForKey:(NSString *)key {
  id value = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    value = localIcon_;
  }
  return value;
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    localIcon_ = [[NSImage alloc] initWithSize:NSMakeSize(128, 128)];
  }
  return self;
}

- (void)dealloc {
  [localIcon_ release];
  [super dealloc];
}
@end

#pragma mark -

@implementation HGSActionTest

- (void)setUp {
  bundle_ = [[NSBundle bundleForClass:[self class]] retain];
}

- (void)tearDown {
  [bundle_ release];
}

// creates and deletes actions. We explicitly call |-release| here to ensure
// that |-dealloc| gets covered by the test cases, as opposed to relying on the
// autorelease pool which may or may not count towards our test coverage.
- (void)testCreation {
  // test creating a basic HGSAction w/out a handler
  
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"designatedInit", kHGSExtensionUserVisibleNameKey,
       @"test1", kHGSExtensionIdentifierKey,
       bundle_, kHGSExtensionBundleKey,
       nil];
  HGSAction* action = [[HGSAction alloc] initWithConfiguration:configuration];
  STAssertNotNil(action, @"couldn't create action");
  [action release];
  
  // test passing a nil configuration.
  HGSAction* action1 = [[HGSAction alloc] initWithConfiguration:nil];
  STAssertNil(action1, @"Created action without a bundle");
  
  // test creating a subclass with all the trimmings
  NSDictionary *myConfig
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"designatedInit", kHGSExtensionUserVisibleNameKey,
       @"test2", kHGSExtensionIdentifierKey,
       bundle_, kHGSExtensionBundleKey,
       nil];
  HGSAction* myAction = [[MyAction alloc] initWithConfiguration:myConfig];
  STAssertNotNil(myAction, @"couldn't create action");
  STAssertNotNil([myAction description], @"no description");
  [myAction release];
  
  // test passing empty configuration
  NSDictionary *emptyConfig = [NSDictionary dictionary];
  HGSAction* emptyAction = [[MyAction alloc] initWithConfiguration:emptyConfig];
  STAssertNil(emptyAction, @"Created action without a bundle");
}

- (void)testDisplayName {
  NSString* path = @"file:///path/to/file";
  MyObject* obj = [[[MyObject alloc] initWithIdentifier:path] autorelease];
  STAssertNotNil(obj, @"couldn't create object");
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"action name", kHGSExtensionUserVisibleNameKey,
       @"test5", kHGSExtensionIdentifierKey,
       bundle_, kHGSExtensionBundleKey,
       nil];
  HGSAction* myAction = [[[MyAction alloc] initWithConfiguration:configuration]
                         autorelease];
  STAssertNotNil(myAction, @"couldn't create action");
  
  // the display name is set as the |name| parameter in the initializer, and
  // since it's already set, it won't go to our handler.
  HGSResultArray *results = [HGSResultArray arrayWithResult:obj];
  NSString* name = [myAction displayNameForResults:results];
  STAssertEqualStrings(name, @"action name", @"display name failed");
  
  // should still be the same, even for a nil object
  name = [myAction displayNameForResults:nil];
  STAssertEqualStrings(name, @"action name", @"display name failed");

}

- (void)testDisplayIcon {
#if !TARGET_OS_IPHONE
  NSString* path = @"file:///path/to/file";
  MyObject* obj = [[[MyObject alloc] initWithIdentifier:path] autorelease];
  STAssertNotNil(obj, @"couldn't create object");
  NSImage* image = [[[NSImage alloc] initWithSize:NSMakeSize(128, 128)] autorelease];
  STAssertNotNil(image, @"couldn't create image");
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"action name", kHGSExtensionUserVisibleNameKey,
       @"test3", kHGSExtensionIdentifierKey,
       image, kHGSExtensionIconImageKey,
       bundle_, kHGSExtensionBundleKey,
       nil];
  HGSAction* myAction = [[[MyAction alloc] initWithConfiguration:configuration]
                         autorelease];
  STAssertNotNil(myAction, @"couldn't create action");
  
  // the display image is set as the |image| parameter in the initializer, and
  // since it's already set, it won't go to our handler.
  HGSResultArray *results = [HGSResultArray arrayWithResult:obj];
  NSImage* resultImage = [myAction displayIconForResults:results];
  // NOTE: We copy the image w/in the base HGSExtension, so EqualObjects here
  // would fail.  At this point we aren't really checking for a specific image
  // we just want to make sure an image is coming back (we could use GTM for an
  // exact image compare).
  STAssertNotNil(resultImage, @"display image failed");
  
  // should still be the same, even for a nil object
  resultImage = [myAction displayIconForResults:nil];
  // NOTE: same as above test
  STAssertNotNil(resultImage, @"display image failed");
#endif
}

- (void)testPerformingAction {
  NSString* path = @"file:///path/to/file";
  MyObject* obj = [[[MyObject alloc] initWithIdentifier:path] autorelease];
  STAssertNotNil(obj, @"couldn't create object");
  NSString* path2 = @"file:///path/to/file2";
  MyObject* obj2 = [[[MyObject alloc] initWithIdentifier:path2] autorelease];
  STAssertNotNil(obj2, @"couldn't create object");
  
  // test creating a subclass with an indirect object type
  NSDictionary *configuration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"designatedInit", kHGSExtensionUserVisibleNameKey,
       @"test4", kHGSExtensionIdentifierKey,
       bundle_, kHGSExtensionBundleKey,
       nil];
  HGSAction* myAction = [[[MyAction alloc] initWithConfiguration:configuration]
                         autorelease];
  STAssertNotNil(myAction, @"couldn't create action");
  
  NSMutableDictionary* info = [NSMutableDictionary dictionary];
  [info setObject:obj forKey:kHGSActionDirectObjectsKey];
  [info setObject:obj2 forKey:kHGSActionIndirectObjectsKey];
  
  BOOL result = [myAction performWithInfo:info];
  STAssertTrue(result, @"action failed");
}

- (void)testAppliesToResults {
  // Make an action which takes anything except a webpage.
  NSDictionary *actionConfiguration
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"Picky Action", kHGSExtensionUserVisibleNameKey,
       @"picky.action", kHGSExtensionIdentifierKey,
       bundle_, kHGSExtensionBundleKey,
       @"*", kHGSActionDirectObjectTypesKey,
       kHGSTypeWebpage, kHGSActionExcludedDirectObjectTypesKey,
       nil];
  // actionA should accept every result except those with a base type
  // of webpage.
  HGSAction* pickyAction
    = [[[MyAction alloc] initWithConfiguration:actionConfiguration]
       autorelease];
  
  // Various results with acceptable and unacceptable types.
  NSString* path = @"file:///path/to/file/is/irrelevant";
  HGSResult* acceptableText = [HGSResult resultWithURI:path 
                                                  name:@"acceptable"
                                                  type:kHGSTypeText
                                                  rank:kHGSResultUnknownRank
                                                source:nil
                                            attributes:nil];
  HGSResult* acceptableFile = [HGSResult resultWithURI:path 
                                                  name:@"acceptable"
                                                  type:kHGSTypeFile
                                                  rank:kHGSResultUnknownRank
                                                source:nil
                                            attributes:nil];
  HGSResult* unacceptableWebpage = [HGSResult resultWithURI:path 
                                                       name:@"not acceptable"
                                                       type:kHGSTypeWebpage
                                                       rank:kHGSResultUnknownRank
                                                     source:nil
                                                 attributes:nil];
  HGSResult* unacceptableFrammy = [HGSResult resultWithURI:path 
                                                      name:@"not acceptable"
                                                      type:kHGSTypeWebFrammy
                                                      rank:kHGSResultUnknownRank
                                                    source:nil
                                                attributes:nil];
  
  // Accept single result with type not webPage.
  HGSResultArray *results = [HGSResultArray arrayWithResult:acceptableText];
  STAssertTrue([pickyAction appliesToResults:results], nil);
  
  // Reject single result with type kHGSTypeWebpage.
  results = [HGSResultArray arrayWithResult:unacceptableWebpage];
  STAssertFalse([pickyAction appliesToResults:results], nil);

  // Reject single result with type kHGSTypeWebFrammy.
  results = [HGSResultArray arrayWithResult:unacceptableFrammy];
  STAssertFalse([pickyAction appliesToResults:results], nil);

  // Reject multiple results with mixed types and one of type kHGSTypeWebFrammy.
  results = [HGSResultArray arrayWithResults:
             [NSArray arrayWithObjects:acceptableText, unacceptableFrammy, nil]];
  STAssertFalse([pickyAction appliesToResults:results], nil);
  
  // Accept multiple results with mixed types but none of type kHGSTypeWebpage.
  results = [HGSResultArray arrayWithResults:
             [NSArray arrayWithObjects:acceptableText, acceptableFile, nil]];
  STAssertTrue([pickyAction appliesToResults:results], nil);
}

@end
