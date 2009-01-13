//
//  HGSTokenizerTest.m
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

#import "HGSTokenizer.h"

@interface HGSTokenizerTest : GTMTestCase
@end

@implementation HGSTokenizerTest

- (void)testInit {
  STAssertNil([HGSTokenizer wordEnumeratorForString:nil], nil);
  STAssertNotNil([HGSTokenizer wordEnumeratorForString:@""], nil);

  STAssertNil([HGSTokenizer tokenEnumeratorForString:nil], nil);
  STAssertNotNil([HGSTokenizer tokenEnumeratorForString:@""], nil);
}

- (void)testWordEnumASCBasics {
  NSEnumerator *e;
  
  // simple test
  
  e = [HGSTokenizer wordEnumeratorForString:@"this, this is a test."];
  STAssertNotNil(e, nil);
  STAssertEqualObjects([e nextObject], @"this", nil);
  STAssertEqualObjects([e nextObject], @"this", nil);
  STAssertEqualObjects([e nextObject], @"is", nil);
  STAssertEqualObjects([e nextObject], @"a", nil);
  STAssertEqualObjects([e nextObject], @"test", nil);
  STAssertNil([e nextObject], nil);

  // test allObjects

  e = [HGSTokenizer wordEnumeratorForString:@"this, this is a test."];
  STAssertNotNil(e, nil);
  NSArray *allTokens = [e allObjects];
  STAssertNotNil(allTokens, nil);
  NSArray *expectedTokens =
    [NSArray arrayWithObjects:@"this", @"this", @"is", @"a", @"test", nil];
  STAssertEqualObjects(allTokens, expectedTokens, nil);

  // now bang through a few different cases
  
  NSString *testData[] = {
    // format: query, words, nil.  a final nil ends all tests.
    @"ABC 123 A1B2C3 ABC-123 ABC_123 A#B",
    @"ABC", @"123", @"A1B2C3", @"ABC", @"123", @"ABC", @"123", @"A", @"B", nil,
    
    @"  abc123  ",
    @"abc123", nil,

    @"_-+  abc123 &*#.",
    @"abc123", nil,
    
    @"- - a -a- - ",
    @"a", @"a", nil,
    
    // test what we do w/ hyphenated words and underscore connections, not so
    // much to force the behavior, but so we realize when it changes and think
    // through any downstream effects.
    @"abc-xyz abc--xyz abc_xyz",
    @"abc", @"xyz", @"abc", @"xyz", @"abc", @"xyz", nil,
    
    // test what we do w/ contractions for the same reason.
    @"can't say i'd like that. i''d?",
    @"can't", @"say", @"i'd", @"like", @"that", @"i", @"d", nil,
    
    // test what happens w/ colons also for the same reasons.
    @"abc:xyz abc::xyz",
    @"abc", @"xyz", @"abc", @"xyz", nil,
    
    nil,
  };
  
  NSString **scan = testData;
  while (*scan != nil) {
    // collect the query
    NSString *query = *scan;
    ++scan;
    e = [HGSTokenizer wordEnumeratorForString:query];
    STAssertNotNil(e, @"failed to make enum for query -- %@", query);
    for (int idx = 0; *scan != nil; ++scan, ++idx) {
      STAssertEqualObjects([e nextObject], *scan,
                           @"item %d of query -- %@", idx, query);
    }
    STAssertNil([e nextObject],
                   @"failed to get nil at end of query -- %@", query);
    // advance to the next test
    ++scan;
  }
}

- (void)testTokenEnumASCBasics {
  NSEnumerator *e;
  
  // simple test
  
  e = [HGSTokenizer tokenEnumeratorForString:@"this, this is a test."];
  STAssertNotNil(e, nil);
  STAssertEqualObjects([e nextObject], @"this", nil);
  STAssertEqualObjects([e nextObject], @",", nil);
  STAssertEqualObjects([e nextObject], @"this", nil);
  STAssertEqualObjects([e nextObject], @"is", nil);
  STAssertEqualObjects([e nextObject], @"a", nil);
  STAssertEqualObjects([e nextObject], @"test", nil);
  STAssertEqualObjects([e nextObject], @".", nil);
  STAssertNil([e nextObject], nil);
  
  // test allObjects
  
  e = [HGSTokenizer tokenEnumeratorForString:@"this, this is a test."];
  STAssertNotNil(e, nil);
  NSArray *allTokens = [e allObjects];
  STAssertNotNil(allTokens, nil);
  NSArray *expectedTokens =
  [NSArray arrayWithObjects:@"this", @",", @"this", @"is", @"a", @"test", @".", nil];
  STAssertEqualObjects(allTokens, expectedTokens, nil);
  
  // now bang through a few different cases

  NSString *testData[] = {
    // format: query, words, nil.  a final nil ends all tests.
    @"ABC 123 A1B2C3 ABC-123 ABC_123 A#B",
    @"ABC", @"123", @"A1B2C3", @"ABC", @"-", @"123", @"ABC", @"_", @"123", @"A", @"#", @"B", nil,
    
    @"  abc123  ",
    @"abc123", nil,
    
    @"_-+  abc123 &*#.",
    @"_", @"-", @"+", @"abc123", @"&", @"*", @"#", @".", nil,
    
    @"- - a -a- - ",
    @"-", @"-", @"a", @"-", @"a", @"-", @"-", nil,
    
    // test what we do w/ hyphenated words and underscore connections, not so
    // much to force the behavior, but so we realize when it changes and think
    // through any downstream effects.
    @"abc-xyz abc--xyz abc_xyz",
    @"abc", @"-", @"xyz", @"abc", @"-", @"-", @"xyz", @"abc", @"_", @"xyz", nil,
    
    // test what we do w/ contractions for the same reason.
    @"can't say i'd like that. i''d?",
    @"can't", @"say", @"i'd", @"like", @"that", @".", @"i", @"'", @"'", @"d", @"?", nil,
    
    // test what happens w/ colons also for the same reasons.
    @"abc:xyz abc::xyz",
    @"abc", @":", @"xyz", @"abc", @":", @":", @"xyz", nil,

    nil,
  };
  
  NSString **scan = testData;
  while (*scan != nil) {
    // collect the query
    NSString *query = *scan;
    ++scan;
    e = [HGSTokenizer tokenEnumeratorForString:query];
    STAssertNotNil(e, @"failed to make enum for query -- %@", query);
    for (int idx = 0; *scan != nil; ++scan, ++idx) {
      STAssertEqualObjects([e nextObject], *scan,
                           @"item %d of query -- %@", idx, query);
    }
    STAssertNil([e nextObject],
                @"failed to get nil at end of query -- %@", query);
    // advance to the next test
    ++scan;
  }
}

@end
