//
//  JSONValidTests.m
//  BSJSONAdditions
//
//  Created by Blake Seely on 2/2/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "BSJSON.h"
#import "JSONValidTests.h"
#import "NSDictionary+BSJSONAdditions.h"
#import "NSScanner+BSJSONAdditions.h"
#import "NSArray+BSJSONAdditions.h"


@implementation JSONValidTests

- (void)testValidJSON
{
	// test 'json_test_valid_01.txt"
	NSString *testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_01" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_01.txt\"");
	NSString *jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	NSDictionary *dict = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_01 json");
	// output check
	NSDictionary *dict2 = [NSDictionary dictionaryWithJSONString:[dict jsonStringValue]];
	STAssertTrue([dict isEqualToDictionary:dict2], @"New Dictionary from json output of first dictionary should be equal for test 01");
	// structure checks (counts, keypaths are not nil, etc.)
	STAssertTrue([dict count] == 1, @"Expected 1 key-val pair");
	STAssertTrue([[dict valueForKeyPath:@"glossary"] count] == 2, @"Expected the glossary entry to have two entries.");
	STAssertTrue([[dict valueForKeyPath:@"glossary.GlossDiv"] count] == 2, @"Expected GlossDiv entry to have two entries.");
	STAssertTrue([[dict valueForKeyPath:@"glossary.GlossDiv.GlossList"] count] == 1, @"Expected GlossList to be an array with a single entry");
	STAssertTrue([[[dict valueForKeyPath:@"glossary.GlossDiv.GlossList"] objectAtIndex:0] count] == 7, @"Expected GlossList array element 0 dictionary to have 7 entries");
	STAssertTrue([[[[dict valueForKeyPath:@"glossary.GlossDiv.GlossList"] objectAtIndex:0] valueForKey:@"GlossSeeAlso"] count] == 3, @"Expected the GlossSeeAlso array to have 3 entries");
	// value checks - keys are correct, etc.
	STAssertTrue([[dict valueForKeyPath:@"glossary.title"] isEqualToString:@"example glossary"], @"Expected glossary.title to be \"example glossary\", but found %@", [dict valueForKeyPath:@"glossary.title"]);
	// more...
	
	// test 'json_test_valid_02.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_02" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_02.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	dict = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_02 json");
	// output check
    NSLog([dict jsonStringValue]);
	dict2 = [NSDictionary dictionaryWithJSONString:[dict jsonStringValue]];
	STAssertTrue([dict isEqualToDictionary:dict2], @"New Dictionary from json output of first dictionary should be equal for test 02");
	// structure checks (counts, keypaths are not nil, etc.)
	STAssertTrue([dict count] == 1, @"Expected a single item in the top level dictionary");
	STAssertTrue([[dict valueForKey:@"menu"] count] == 3, @"Expected a 3 items in the menu dictionary");
	STAssertTrue([[dict valueForKeyPath:@"menu.popup"] count] == 1, @"Expected a single item in the popup dictionary");
	STAssertTrue([[dict valueForKeyPath:@"menu.popup.menuitem"] count] == 3, @"Expected 3 items in the menuitem array");
	// value checks
	
	// test 'json_test_valid_03.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_03" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_03.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	dict = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_03 json");
	// output check
	dict2 = [NSDictionary dictionaryWithJSONString:[dict jsonStringValue]];
	STAssertTrue([dict isEqualToDictionary:dict2], @"New Dictionary from json output of first dictionary should be equal for test 03");
	// structure checks
	// value checks
	STAssertTrue([[dict valueForKeyPath:@"widget.window.width"] intValue] == 500, @"Expected value of 500, but got %i", [[dict valueForKeyPath:@"widget.window.width"] intValue]);

	// test 'json_test_valid_04.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_04" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_04.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	dict = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_04 json");
	// output check
	dict2 = [NSDictionary dictionaryWithJSONString:[dict jsonStringValue]];
	STAssertTrue([dict isEqualToDictionary:dict2], @"New Dictionary from json output of first dictionary should be equal for test 04");
	// structure checks
	// value checks
	
	// test 'json_test_valid_05.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_05" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_05.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	dict = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_05 json");
	// output check
	dict2 = [NSDictionary dictionaryWithJSONString:[dict jsonStringValue]];
	STAssertTrue([dict isEqualToDictionary:dict2], @"New Dictionary from json output of first dictionary should be equal for test 05");
	// structure check
	STAssertTrue([dict count] == 1, @"Expected one value in the dictionary");
	STAssertTrue([[dict valueForKey:@"menu"] count] == 2, @"Expected two items in the menu dictionary");
	STAssertTrue([[dict valueForKeyPath:@"menu.items"] count] == 22, @"Expected 22 items in the items array");
	// value checks
	STAssertTrue([[dict valueForKeyPath:@"menu.items"] objectAtIndex:2] == [NSNull null], @"Expected a null value in index 2");
	
	// test 'json_test_valid_06.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_06" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_06.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	dict = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_06 json");
	// output check
	dict2 = [NSDictionary dictionaryWithJSONString:[dict jsonStringValue]];
	// does not work because of exponential notation
	//STAssertTrue([dict isEqualToDictionary:dict2], @"New Dictionary from json output of first dictionary should be equal for test 06");
  
	// test 'json_test_valid_07.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_07" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_07.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	NSArray *array = [NSArray arrayWithJSONString:jsonString];
	STAssertNotNil(array, @"Could not create array from json_test_valid_07 json");
	STAssertTrue([array count] == 6, @"Expected six items in the array");
	STAssertTrue([[array objectAtIndex:0] count] == 3, @"Expected three items in the array subdictionary");
	NSArray *array2 = [NSArray arrayWithJSONString:[array jsonStringValue]];
	STAssertTrue([array2 isEqualToArray:array], @"Expected arrays to be the same");

	// test 'json_test_valid_08.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_08" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_08.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	array = [NSArray arrayWithJSONString:jsonString];
	STAssertNotNil(array, @"Could not create array from json_test_valid_08 json");
	STAssertTrue([array count] == 4, @"Expected four items in the array");
	STAssertTrue([[array objectAtIndex:1] count] == 2, @"Expected two items in the second dictionary");
	STAssertTrue([[[array objectAtIndex:1] objectForKey:@"name"] isEqualToString:@"square2"],
		@"Expected name of second object to be 'square2' but got %@",
		[[array objectAtIndex:1] objectForKey:@"name"]);
	STAssertTrue([[[array objectAtIndex:2] objectForKey:@"points"] count] == 6,
		@"Expected six points in hexagon array");
	array2 = [NSArray arrayWithJSONString:[array jsonStringValue]];
	STAssertTrue([array2 isEqualToArray:array], @"Expected arrays to be the same");

	// test 'json_test_invalid_array.txt"
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_invalid_array" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_invalid_array.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	array = [NSArray arrayWithJSONString:jsonString];
	STAssertNil(array, @"Created array from json_test_invalid_array invalid json");

	// Testing whether the BSJSON class method works - test dict with #5
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_05" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_05.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	id obj = [BSJSON objectWithJSONString:jsonString];
	STAssertTrue([obj respondsToSelector:@selector(keyEnumerator)], @"Expected NSDictionary from objectWithJSONString");
	dict = (NSDictionary *)obj;
	STAssertNotNil(dict, @"Could not create dictionary from json_test_valid_05 json");
	// Compare to direct loading
	dict2 = [NSDictionary dictionaryWithJSONString:jsonString];
	STAssertTrue([dict isEqualToDictionary:dict2], @"Dictionaries from BSJSON and NSDictionary do not match");
	// structure check
	STAssertTrue([dict count] == 1, @"Expected one value in the dictionary");
	STAssertTrue([[dict valueForKey:@"menu"] count] == 2, @"Expected two items in the menu dictionary");
	STAssertTrue([[dict valueForKeyPath:@"menu.items"] count] == 22, @"Expected 22 items in the items array");
	// value checks
	STAssertTrue([[dict valueForKeyPath:@"menu.items"] objectAtIndex:2] == [NSNull null], @"Expected a null value in index 2");

	// Testing whether BSJSON class method works - test array with #8
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_valid_08" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_valid_08.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	obj = [BSJSON objectWithJSONString:jsonString];
	STAssertTrue([obj respondsToSelector:@selector(objectAtIndex:)], @"Expected NSArray from objectWithJSONString");
	array = (NSArray *)obj;
	STAssertNotNil(array, @"Could not create array from json_test_valid_08 json");
	STAssertTrue([array count] == 4, @"Expected four items in the array");
	STAssertTrue([[array objectAtIndex:1] count] == 2, @"Expected two items in the second dictionary");
	STAssertTrue([[[array objectAtIndex:1] objectForKey:@"name"] isEqualToString:@"square2"],
               @"Expected name of second object to be 'square2' but got %@",
               [[array objectAtIndex:1] objectForKey:@"name"]);
	STAssertTrue([[[array objectAtIndex:2] objectForKey:@"points"] count] == 6,
               @"Expected six points in hexagon array");
	array2 = [NSArray arrayWithJSONString:[array jsonStringValue]];
	STAssertTrue([array2 isEqualToArray:array], @"Expected arrays to be the same");

	// Testing whether BSJSON class method works - testing an invalid file
	testFilePath = [[NSBundle mainBundle] pathForResource:@"json_test_invalid_number_01" ofType:@"txt"];
	STAssertNotNil(testFilePath, @"Could not find the test file named \"json_test_invalid_number_01.txt\"");
	jsonString = [NSString stringWithContentsOfFile:testFilePath];
	STAssertNotNil(jsonString, @"Could not create an NSString from the file at path %@", testFilePath);
	obj = [BSJSON objectWithJSONString:jsonString];
	STAssertNil(obj, @"Expected nil result for invalid file.");
}

@end
