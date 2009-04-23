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
  STAssertNil([HGSTokenizer tokenizeString:nil], nil);
  STAssertNotNil([HGSTokenizer tokenizeString:@""], nil);
}

- (void)testTokenize {
  NSString *tokenizedString = [HGSTokenizer tokenizeString:@"this, this is a test."];
  STAssertEqualObjects(tokenizedString, @"this this is a test", nil);

  // now bang through a few different cases
  struct {
    NSString *string;
    NSString *tokenized;
  } testData[] = {
    {
      // camelcase
      @"MacPython2.4",
      @"mac python 2.4"
    },
    {
      @"NSStringFormatter",
      @"ns string formatter"
    },
    {
      // format: query, words, nil.  a final nil ends all tests.
      @"ABC 123 A1B2C3 ABC-123 ABC_123 A#B A1.2b",
      @"abc 123 a 1 b 2 c 3 abc 123 abc 123 a b a 1.2 b"
    },
    {
      @"  abc123  ",
      @"abc 123"
    },
    {
      @"_-+  abc123 &*#.",
      @"abc 123"
    },
    {
      @"- - a -a- - ",
      @"a a"
    },
    {
      // test what we do w/ hyphenated words and underscore connections, not so
      // much to force the behavior, but so we realize when it changes and think
      // through any downstream effects.
      @"abc-xyz abc--xyz abc_xyz",
      @"abc xyz abc xyz abc xyz"
    },
    {
      // test what we do w/ contractions for the same reason.
      @"can't say i'd like that. i''d?",
      @"can't say i'd like that i d"
    },
    {
      // test what happens w/ colons also for the same reasons.
      @"abc:xyz abc::xyz",
      @"abc xyz abc xyz", 
    }
  };
  
  for (size_t i = 0; i < sizeof(testData) / sizeof(testData[0]); ++i) {
    // collect the query
    NSString *tokenTest = [HGSTokenizer tokenizeString:testData[i].string];
    STAssertEqualObjects(tokenTest, testData[i].tokenized, nil);
  }
}

@end
