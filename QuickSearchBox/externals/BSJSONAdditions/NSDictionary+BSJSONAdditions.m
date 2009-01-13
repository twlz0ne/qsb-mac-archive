//
//  BSJSONAdditions
//
//  Created by Blake Seely on 2/1/06.
//  Copyright 2006 Blake Seely - http://www.blakeseely.com  All rights reserved.
//  Permission to use this code:
//
//  Feel free to use this code in your software, either as-is or 
//  in a modified form. Either way, please include a credit in 
//  your software's "About" box or similar, mentioning at least 
//  my name (Blake Seely).
//
//  Permission to redistribute this code:
//
//  You can redistribute this code, as long as you keep these 
//  comments. You can also redistribute modified versions of the 
//  code, as long as you add comments to say that you've made 
//  modifications (keeping these original comments too).
//
//  If you do use or redistribute this code, an email would be 
//  appreciated, just to let me know that people are finding my 
//  code useful. You can reach me at blakeseely@mac.com

#import "BSJSON.h"
#import "NSDictionary+BSJSONAdditions.h"
#import "NSScanner+BSJSONAdditions.h"

@implementation NSDictionary (BSJSONAdditions)

+ (NSDictionary *)dictionaryWithJSONString:(NSString *)jsonString
{
	NSScanner *scanner = [[NSScanner alloc] initWithString:jsonString];
	NSDictionary *dictionary = nil;
	[scanner scanJSONObject:&dictionary];
	[scanner release];
	return dictionary;
}

- (NSString *)jsonStringValue
{
    return [self jsonStringValueWithIndentLevel:0];
}

@end

@implementation NSDictionary (PrivateBSJSONAdditions)

- (NSString *)jsonStringValueWithIndentLevel:(int)level
{
	NSMutableString *jsonString = [[NSMutableString alloc] init];
    [jsonString appendString:jsonObjectStartString];
	
	NSEnumerator *keyEnum = [self keyEnumerator];
	NSString *keyString = [keyEnum nextObject];
	NSString *valueString;
	if (keyString != nil) {
		valueString = [BSJSON jsonStringForValue:[self objectForKey:keyString] withIndentLevel:level];
        if (level != jsonDoNotIndent) { // indent before each key
            [jsonString appendString:[BSJSON jsonIndentStringForLevel:level]];
        }
		[jsonString appendFormat:@" %@ %@ %@", [BSJSON jsonStringForString:keyString], jsonKeyValueSeparatorString, valueString];
	}
	
	while ((keyString = [keyEnum nextObject])) {
		valueString = [BSJSON jsonStringForValue:[self objectForKey:keyString] withIndentLevel:level]; // TODO bail if valueString is nil? How to bail successfully from here?
        [jsonString appendString:jsonValueSeparatorString];
        if (level != jsonDoNotIndent) { // indent before each key
            [jsonString appendFormat:@"%@", [BSJSON jsonIndentStringForLevel:level]];
        }
		[jsonString appendFormat:@" %@ %@ %@", [BSJSON jsonStringForString:keyString], jsonKeyValueSeparatorString, valueString];
	}
	
	//[jsonString appendString:@"\n"];
	[jsonString appendString:jsonObjectEndString];
	
	return [jsonString autorelease];
}

@end
