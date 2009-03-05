//
//  HGSObjectTest.m
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


#import "GTMSenTestCase.h"
#import "HGSResult.h"
#import "HGSSearchSource.h"

@interface HGSObjectTest : GTMTestCase <HGSSearchSource>
@end

@implementation HGSObjectTest

- (void)testStaticInit {
  NSURL* path = [NSURL URLWithString:@"file://url/to/path"];
  // create an object with the full gamut and check the values
  HGSResult* obj1 = [HGSResult resultWithIdentifier:path 
                                               name:@"everything"
                                               type:@"text"
                                             source:nil
                                         attributes:nil];
  STAssertNotNil(obj1, @"can't create object");
  STAssertEqualObjects(path, 
                       [obj1 identifier], 
                       @"invalid uri");
  STAssertEqualStrings(@"everything", 
                       [obj1 valueForKey:kHGSObjectAttributeNameKey], 
                       @"invalid name");
  STAssertEqualStrings(@"text",
                       [obj1 valueForKey:kHGSObjectAttributeTypeKey], 
                       @"invalid type");
  
  // create an object with missing values and make sure they go through our
  // source, which will mirror the value as the provided key.
  HGSResult* obj2 = [HGSResult resultWithIdentifier:nil 
                                               name:nil
                                               type:NULL
                                             source:self
                                         attributes:nil];
  STAssertNil(obj2, @"created object");

  // create an object with everything nil
  HGSResult* obj3 = [HGSResult resultWithIdentifier:nil 
                                               name:nil
                                               type:NULL
                                             source:nil
                                         attributes:nil];
  STAssertNil(obj3, @"created object");
}

- (void)testStaticInitFromDictionary {
  NSString* path = @"file://bin/";

  // create an object from a dictionary and validate the keys are present. Since
  // we're setting the source, values we don't set should return non-nil.
  NSMutableDictionary* info = [NSMutableDictionary dictionary];
  [info setObject:path forKey:kHGSObjectAttributeURIKey];
  [info setObject:@"foo" forKey:kHGSObjectAttributeNameKey];
  [info setObject:@"bar" forKey:kHGSObjectAttributeTypeKey];
  HGSResult* infoObject = [HGSResult resultWithDictionary:info source:self];
  STAssertNotNil(infoObject, @"can't create object from dict");
  STAssertEqualObjects([NSURL URLWithString:path], 
                       [infoObject identifier], 
                       @"didn't find uri");
  STAssertEqualStrings(kHGSPathCellDisplayTitleKey, 
                       [infoObject valueForKey:kHGSPathCellDisplayTitleKey], 
                       @"didn't find title");
  
  // create an object from a dictionary where the source doesn't implement
  // the correct protocol. This shouldn't throw or crash.
  NSMutableDictionary* info2 = [NSMutableDictionary dictionary];
  [info2 setObject:path forKey:kHGSObjectAttributeURIKey];
  [info2 setObject:@"foo" forKey:kHGSObjectAttributeNameKey];
  [info2 setObject:@"bar" forKey:kHGSObjectAttributeTypeKey];
  HGSResult* infoObject2 = [HGSResult resultWithDictionary:info2 source:nil];
  STAssertNotNil(infoObject2, @"can't create object from dict");
  STAssertNil([infoObject2 valueForKey:kHGSPathCellDisplayTitleKey], 
              @"found a title");
 
  // create an object wil a nil dictionary
  HGSResult* nilObject = [HGSResult resultWithDictionary:nil source:nil];
  STAssertNil(nilObject, @"created object from nil dict");
  
  // create an object with an empty dictionary
  HGSResult* emptyObject 
    = [HGSResult resultWithDictionary:[NSDictionary dictionary]
                               source:nil];
  STAssertNil(emptyObject, @"created object from empty dict");
}

- (void)testTypeCalls {
  NSURL* url = [NSURL URLWithString:@"http://someplace/"];
  STAssertNotNil(url, nil);
  
  typedef struct {
    NSString *theType;
    BOOL tests[8];
  } TestData;
  
  TestData data[] = {
    { @"test",         { YES, NO,  NO,  NO,  YES, NO,  NO,  NO  } },
    { @"test.bar",     { NO,  YES, NO,  NO,  YES, YES, NO,  NO  } },
    { @"test.baz",     { NO,  NO,  NO,  NO,  YES, NO,  NO,  NO  } },
    { @"testbar",      { NO,  NO,  YES, NO,  NO,  NO,  YES, NO  } },
    { @"test.bar.baz", { NO,  NO,  NO,  NO,  YES, YES, NO,  NO  } },
    { @"bar",          { NO,  NO,  NO,  YES, NO,  NO,  NO,  YES } },
  };
  
  for (size_t i = 0; i < sizeof(data) / sizeof(TestData); i++) {

    // Create an object
    HGSResult* obj = [HGSResult resultWithIdentifier:url 
                                                name:@"name"
                                                type:data[i].theType
                                              source:nil
                                          attributes:nil];
    STAssertNotNil(obj, @"type %@", data[i].theType);
    STAssertEqualObjects(data[i].theType, 
                         [obj type], @"type %@", 
                         data[i].theType);

    // Test isOfType:
    STAssertEquals(data[i].tests[0], 
                   [obj isOfType:@"test"], 
                   @"type %@", data[i].theType);
    STAssertEquals(data[i].tests[1],
                   [obj isOfType:@"test.bar"],
                   @"type %@", data[i].theType);
    STAssertEquals(data[i].tests[2],
                   [obj isOfType:@"testbar"],
                   @"type %@", data[i].theType);
    STAssertEquals(data[i].tests[3],
                   [obj isOfType:@"bar"],
                   @"type %@", data[i].theType);

    // Test conformsToType:
    STAssertEquals(data[i].tests[4],
                   [obj conformsToType:@"test"],
                   @"type %@", data[i].theType);
    STAssertEquals(data[i].tests[5],
                   [obj conformsToType:@"test.bar"],
                   @"type %@", data[i].theType);
    STAssertEquals(data[i].tests[6],
                   [obj conformsToType:@"testbar"],
                   @"type %@", data[i].theType);
    STAssertEquals(data[i].tests[7],
                   [obj conformsToType:@"bar"],
                   @"type %@", data[i].theType);

    // Test conformsToTypeSet:
    NSSet *testSet = [NSSet setWithObjects:@"spam", @"test", @"mumble", nil];
    STAssertNotNil(testSet, nil);
    STAssertEquals(data[i].tests[4], [obj conformsToTypeSet:testSet],
                   @"type %@", data[i].theType);
    testSet = [NSSet setWithObjects:@"spam", @"test.bar", @"mumble", nil];
    STAssertNotNil(testSet, nil);
    STAssertEquals(data[i].tests[5], [obj conformsToTypeSet:testSet],
                   @"type %@", data[i].theType);
    testSet = [NSSet setWithObjects:@"testbar", @"spam" @"mumble", nil];
    STAssertNotNil(testSet, nil);
    STAssertEquals(data[i].tests[6], [obj conformsToTypeSet:testSet],
                   @"type %@", data[i].theType);
    testSet = [NSSet setWithObjects:@"spam", @"mumble", @"bar", nil];
    STAssertNotNil(testSet, nil);
    STAssertEquals(data[i].tests[7], [obj conformsToTypeSet:testSet],
                   @"type %@", data[i].theType);
  }
}

#pragma mark fake extension

- (id)initWithConfiguration:(NSDictionary *)configuration {
  return [super init];
}

- (NSImage *)icon {
  return nil;
}

- (NSString *)name {
  return @"fakeSource";
}

- (NSString *)copyright {
  return nil;
}

- (NSString *)identifier {
  return @"fakeID";
}

- (NSAttributedString *)extensionDescription {
  return nil;
}

- (NSString *)extensionVersion {
  return nil;
}

#pragma mark fake search source

- (NSSet *)pivotableTypes {
  return nil;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  return NO;
}

- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query {
  return nil;
}

- (void)annotateResult:(HGSResult *)result withQuery:(HGSQuery *)query {
}

- (NSSet *)utisToExcludeFromDiskSources {
  return nil;
}

- (NSMutableDictionary*)archiveRepresentationForResult:(HGSResult*)result {
  return nil;
}

- (HGSResult *)resultWithArchivedRepresentation:(NSDictionary*)representation {
  return nil;
}

// simply fills in the same value as the given |key|. Won't be called if the
// value is already set.
- (id)provideValueForKey:(NSString*)key result:(HGSResult*)result {
  return key;
}

- (NSImage *)defaultIconForResult:(HGSResult *)result {
  return nil;
}
@end