//
//  HGSTestingSupport.m
//  GoogleMobile
//
//  Created by Alastair Tse on 2008/05/17.
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

#import "HGSTestingSupport.h"
#import "HGSObject.h"
#import "HGSPredicate.h"

#if TARGET_OS_IPHONE
#import "GTMSenTestCase.h"
#else
#import <SenTestingKit/SenTestingKit.h>
#endif

// A pretty long query.
static NSString* const kVeryLongQuery = @"abcdefghijklmnopqrstuvwxyz01234567890~!@#$%^&*()_+{}|:\"<>?,./;'[]\\-=`";

@implementation HGSTestingSupport

+ (NSArray*)predicates {
  return [NSArray arrayWithObjects:
    [HGSPredicate predicateWithQueryString:nil],
    [HGSPredicate predicateWithQueryString:@""],
    [HGSPredicate predicateWithQueryString:@"a"],
    [HGSPredicate predicateWithQueryString:@"d"],
    [HGSPredicate predicateWithQueryString:kVeryLongQuery],
    nil];
}

+ (NSInvocation*)resultComparator {
  NSMethodSignature* signature = [self methodSignatureForSelector:@selector(compareActualResult:expectedResult:forKeys:)];
  NSInvocation* invocation = [NSInvocation invocationWithMethodSignature:signature];
  [invocation setSelector:@selector(compareActualResult:expectedResult:forKeys:)];
  [invocation setTarget:self];
  return invocation;
}

+ (NSInvocation*)resultComparatorWithNameAndType {
  NSInvocation* comparator = [self resultComparator];
  NSArray* comparingKeys = [NSArray arrayWithObjects:
    kHGSObjectAttributeUTIKey,
    kHGSObjectAttributeNameKey,
    nil];
  [comparator setArgument:&comparingKeys atIndex:4];
  return comparator;
}

+ (void)compareActualResult:(HGSObject*)actualResult
             expectedResult:(HGSObject*)expectedResult
                    forKeys:(NSArray*)validKeys {
  if (actualResult == expectedResult) return;

  for (NSString* key in validKeys) {
    id actualValue = [actualResult valueForKey:key];
    id expectedValue = [expectedResult valueForKey:key];
    if (actualValue == expectedValue) continue;
    STAssertEqualObjects(actualValue,
                         expectedValue,
                         @"Value mismatch between results for key: %@",
                         key);
  }
}

+ (void)compareActualResults:(NSArray*)actualResults
             expectedResults:(NSArray*)expectedResults
              withComparator:(NSInvocation*)comparator {
  // Compare results if we are given both the result array and comparator.
  STAssertEquals([actualResults count],
                 [expectedResults count],
                 @"\nActual:\n%@\n\nExpected:\n%@",
                 [actualResults description],
                 [expectedResults description]);

  if (comparator) {
    for (NSUInteger i = 0; i < [actualResults count]; i++) {
      HGSObject* actualResult = [actualResults objectAtIndex:i];
      HGSObject* expectedResult = [expectedResults objectAtIndex:i];
      [comparator setArgument:&actualResult atIndex:2];
      [comparator setArgument:&expectedResult atIndex:3];
      [comparator invoke];
    }
  }
}

+ (NSArray*)objectsFromBundleResource:(NSString*)testResourceName {
  NSMutableArray* objects = [NSMutableArray array];
  // TODO(altse): Maybe mainBundle will not load resources if they're in a
  //              different bundle. iPhone doesn't do bundle loading so I
  //              can't test.
  NSString* path = [[NSBundle mainBundle] pathForResource:testResourceName
                                                   ofType:@"plist"];
  STAssertNotNil(path,
                 @"Given test resource does not exist: %@",
                 testResourceName);
  NSArray* objectsFromFile = [NSArray arrayWithContentsOfFile:path];
  STAssertNotNil(objectsFromFile,
                 @"Unable to read array from file: %@", path);
  for (NSDictionary* contents in objectsFromFile) {
    [objects addObject:[HGSObject objectWithDictionary:contents]];
  }
  return objects;
}
@end
