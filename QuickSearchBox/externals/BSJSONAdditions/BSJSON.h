//
//  BSJSON.h
//  BSJSONAdditions
//
//  Created by Brad Jones on 9/26/08.
//  Copyright 2008 Google Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BSJSON : NSObject
// Returns an object corresponding to the given JSON string; exact type
// depends on the top-level type in the JSON.  The most likely candidate
// is NSDictionary, but NSArray is also possible.
+ (id)objectWithJSONString:(NSString *)jsonString;

+ (NSString *)jsonStringForValue:(id)value withIndentLevel:(int)level;
+ (NSString *)jsonStringForArray:(NSArray *)array withIndentLevel:(int)level;
+ (NSString *)jsonStringForString:(NSString *)string;
+ (NSString *)jsonIndentStringForLevel:(int)level;
@end
