//
//  NSArray+BSJSONAdditions.h
//  BSJSONAdditions
//
//  Created by Brad Jones on 9/11/08.
//  Copyright 2008 Google Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (BSJSONAdditions)
+ (NSArray *)arrayWithJSONString:(NSString *)jsonString;
- (NSString *)jsonStringValue;
@end
