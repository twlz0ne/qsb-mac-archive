//
//  HGSQueryTest.m
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

#import <Foundation/Foundation.h>
#import "GTMSenTestCase.h"

#import "HGSQuery.h"

@interface HGSQueryTest : GTMTestCase
@end

@implementation HGSQueryTest

- (void)testInit {
  STAssertNotNil([[[HGSQuery alloc] initWithString:nil
                                           results:nil
                                        queryFlags:0] autorelease],
                 nil);
  STAssertNotNil([[[HGSQuery alloc] initWithString:@""
                                           results:nil
                                        queryFlags:0] autorelease],
                 nil);
  STAssertNotNil([[[HGSQuery alloc] initWithString:@"a"
                                           results:nil
                                        queryFlags:0] autorelease],
                 nil);
}

- (void)testTheWorksASCII {
  HGSQuery *query;
  NSSet *expectedWords;
  
  // NOTE: these tests include queries that appear to be phrases, the class
  // doesn't currently support phrase, just here because it's derived from the
  // version in googlemac/Vermilion/Query.
  
  // empty
  query = [[[HGSQuery alloc] initWithString:@""
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"", nil);
  expectedWords = [NSSet set];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // white space
  query = [[[HGSQuery alloc] initWithString:@"  "
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"  ", nil);
  expectedWords = [NSSet set];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // one word
  query = [[[HGSQuery alloc] initWithString:@"a"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a", nil);
  expectedWords = [NSSet setWithObject:@"a"];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // word repeated
  query = [[[HGSQuery alloc] initWithString:@"a A"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a A", nil);
  expectedWords = [NSSet setWithObject:@"a"];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  query = [[[HGSQuery alloc] initWithString:@"a B"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a B", nil);
  expectedWords = [NSSet setWithObjects:@"a", @"b", nil];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // word repeated and another word
  query = [[[HGSQuery alloc] initWithString:@"a a b"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a a b", nil);
  expectedWords = [NSSet setWithObjects:@"a", @"b", nil];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // two words and a phrase
  query = [[[HGSQuery alloc] initWithString:@"a \"b c\" d"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a \"b c\" d", nil);
  expectedWords = [NSSet setWithObjects:@"a", @"b", @"c", @"d", nil];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // two words and a phrase that isn't closed
  query = [[[HGSQuery alloc] initWithString:@"a d \"b c"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a d \"b c", nil);
  expectedWords = [NSSet setWithObjects:@"a", @"b", @"c", @"d", nil];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // an empty phrase, unclosed
  query = [[[HGSQuery alloc] initWithString:@"\""
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"\"", nil);
  expectedWords = [NSSet set];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // an empty phrase
  query = [[[HGSQuery alloc] initWithString:@"\" \""
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"\" \"", nil);
  expectedWords = [NSSet set];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
  // some words, phrase and some random punct and numbers
  query = [[[HGSQuery alloc] initWithString:@"a1 23 a-d% \"b$c"
                                    results:nil
                                 queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  STAssertEqualObjects([query rawQueryString], @"a1 23 a-d% \"b$c", nil);
  expectedWords
  = [NSSet setWithObjects:@"a", @"b", @"c", @"d", @"a1", @"23", nil];
  STAssertNotNil(expectedWords, nil);
  STAssertEqualObjects([query uniqueWords], expectedWords, nil);
  
}

- (void)testParent {
  HGSQuery *query1;
  HGSQuery *query2;
  
  query1 = [[[HGSQuery alloc] initWithString:@"abc"
                                     results:nil
                                  queryFlags:0] autorelease];
  STAssertNotNil(query1, nil);
  query2 = [[[HGSQuery alloc] initWithString:@"xyz"
                                     results:nil
                                  queryFlags:0] autorelease];
  STAssertNotNil(query2, nil);
  
  STAssertNil([query1 parent], nil);
  STAssertNil([query2 parent], nil);
  
  [query2 setParent:query1];
  
  STAssertNil([query1 parent], nil);
  STAssertNotNil([query2 parent], nil);
  STAssertEquals([query2 parent], query1, nil);
  
  [query2 setParent:nil];
  
  STAssertNil([query1 parent], nil);
  STAssertNil([query2 parent], nil);
}

@end
