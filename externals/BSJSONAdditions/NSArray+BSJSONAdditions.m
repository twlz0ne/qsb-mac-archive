//
//  NSArray+BSJSONAdditions.m
//  BSJSONAdditions
//
//  Created by Brad Jones on 9/11/08.
//  Copyright 2008 Google Inc. All rights reserved.
//

#import "BSJSON.h"
#import "NSArray+BSJSONAdditions.h"
#import "NSScanner+BSJSONAdditions.h"

@implementation NSArray (BSJSONAdditions)
+ (NSArray *)arrayWithJSONString:(NSString *)jsonString {
  NSScanner *scanner = [NSScanner scannerWithString:jsonString];
  NSArray *array = nil;
  [scanner scanJSONArray:&array];
  return array;
}

- (NSString*)jsonStringValue {
  // Leaning on the NSDictionary already having this implemented.
  return [BSJSON jsonStringForArray:self withIndentLevel:0];
}

@end
