//
//  HGSTokenizer.m
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

#import "HGSTokenizer.h"

//
// Design/Impl Issues
//
// Things that probably need followup either at this level or at the Predicate
// level, but noting them here for now.
//
// - email addresses : both in the query and in the content we want to search
//   you really don't want these broken into strings because you get lots of
//   false matches, so when breaking up the query and when doing the indexing
//   some layer needs to realize it's an email address and mail it a whole term.
// - email addresses, part 2 : but you always what to match a sub part of an
//   email address, prefix handles matching the account, but you might also
//   want to match the domain name.
// - domains : when domain appear in document, you probably don't want them
//   broken up either.
// - urls : should these be broken into all of their parts?
// - implicite quotes : if we did phrases, could some of the above be handled
//   within the predicate layer by realizing it's not just a sequence of words
//   and adding the implice phrase so we match the full address, instead of
//   the free standing words.
//

@interface HGSTokenizerEnumerator : NSEnumerator {
 @private
  CFStringTokenizerRef tokenizer_;
  NSString *stringToTokenize_;
  BOOL wordsOnly_;
  NSCharacterSet *nonWhiteSpaceCharSet_;
  // rangeToScan_ is used for feeding any non whitespace between words back.
  NSRange rangeToScan_;
  // savedWordRange_ is for a token range already returned that we haven't
  // been ready to return yet.
  NSRange savedWordRange_;
  // atEnd_ marks when the tokenizer has hit the end, so we don't call it
  // again.
  BOOL atEnd_;
}
- (id)initWithString:(NSString *)stringToTokenize wordsOnly:(BOOL)wordsOnly;
@end

@implementation HGSTokenizerEnumerator

- (id)initWithString:(NSString *)stringToTokenize wordsOnly:(BOOL)wordsOnly {
  self = [super init];
  if (self != nil) {
    stringToTokenize_ = [stringToTokenize copy];
    wordsOnly_ = wordsOnly;
    savedWordRange_.location = NSNotFound;
    if (!wordsOnly_) {
      NSCharacterSet *wsSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
      nonWhiteSpaceCharSet_ = [[wsSet invertedSet] retain];
    }
    if (stringToTokenize_) {
      // The header comments for CFStringTokenizerCreate and
      // kCFStringTokenizerUnitWord indicate the locale is unused for UnitWord;
      // so we just pass NULL here to avoid creating one.
      // Radar 6195821 has been filed to get the docs updated to match.
      CFRange tokenRange = CFRangeMake(0, [stringToTokenize_ length]);
      tokenizer_ = CFStringTokenizerCreate(NULL,
                                           (CFStringRef)stringToTokenize_,
                                           tokenRange,
                                           kCFStringTokenizerUnitWord,
                                           NULL);
    }
    if (!stringToTokenize_ ||
        !tokenizer_ ||
        (wordsOnly_  && nonWhiteSpaceCharSet_)) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void) dealloc {
  if (tokenizer_) {
    CFRelease(tokenizer_);
  }
  [stringToTokenize_ release];
  [nonWhiteSpaceCharSet_ release];

  [super dealloc];
}

- (id)nextObject {
  NSString *result = nil;
  
  // For wordsOnly we just use what the tokenizer says
  if (wordsOnly_) {
    CFStringTokenizerTokenType type;
    type = CFStringTokenizerAdvanceToNextToken(tokenizer_);
    if (type != kCFStringTokenizerTokenNone) {
      CFRange cfTokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer_);
      NSRange nsTokenRange = NSMakeRange(cfTokenRange.location, 
                                         cfTokenRange.length);
      result = [stringToTokenize_ substringWithRange:nsTokenRange];
    }
    return result;
  }
  
  // Not wordsOnly gets a little more complicated...

  // One would hope we could have used kCFStringTokenizerUnitWordBoundary for
  // not wordOnly mode, but in UnitWordBoundry "ABC_123" comes through as one
  // token but in UnitWord it gets broken into "ABC" and "123", so we always use
  // UnitWord and keep a side car of anything we skip and pull out the non
  // whitespace ourselves.
  
  // Do we still have something to scan?
  if (rangeToScan_.length > 0) {
    // find any non whitespace in it
    NSRange firstNonWhitespace =
      [stringToTokenize_ rangeOfCharacterFromSet:nonWhiteSpaceCharSet_
                                         options:0
                                           range:rangeToScan_];
    if (firstNonWhitespace.location != NSNotFound) {
      // pick off that one char
      result = [stringToTokenize_ substringWithRange:firstNonWhitespace];
      NSUInteger charsToAdvance =
        firstNonWhitespace.location - rangeToScan_.location + 1;
      rangeToScan_.location += charsToAdvance;
      rangeToScan_.length -= charsToAdvance;
      return result;
    }
    // clear our marker
    rangeToScan_.length = 0;
  }
  
  // see if we have a saved word range from a past call, and use it.
  if (savedWordRange_.location != NSNotFound) {
    result = [stringToTokenize_ substringWithRange:savedWordRange_];
    // advance the start of rangeToScan_ to the end of what we've used
    rangeToScan_.location = NSMaxRange(savedWordRange_);
    // clear our flag
    savedWordRange_.location = NSNotFound;
    return result;
  }
  
  // did we already finish w/ the tokeninzer?
  if (atEnd_) {
    return nil;
  }

  CFStringTokenizerTokenType tokenType;
  tokenType = CFStringTokenizerAdvanceToNextToken(tokenizer_);
  if (tokenType == kCFStringTokenizerTokenNone) {
    // at end, see if we skipped anything
    if (rangeToScan_.location != [stringToTokenize_ length]) {
      rangeToScan_.length = [stringToTokenize_ length] - rangeToScan_.location;
      NSRange firstNonWhitespace =
        [stringToTokenize_ rangeOfCharacterFromSet:nonWhiteSpaceCharSet_
                                          options:0
                                             range:rangeToScan_];
      if (firstNonWhitespace.location != NSNotFound) {
        // pick off that one char
        result = [stringToTokenize_ substringWithRange:firstNonWhitespace];
        // setup rangeToScan_ for next time
        NSUInteger charsToAdvance =
          firstNonWhitespace.location - rangeToScan_.location + 1;
        rangeToScan_.location += charsToAdvance;
        rangeToScan_.length -= charsToAdvance;
        // mark that we hit the end
        atEnd_ = YES;
        return result;
      }
    }
  } else {
    CFRange cfTokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer_);
    NSRange tokenRange = NSMakeRange(cfTokenRange.location, 
                                     cfTokenRange.length);
    // see if we skipped over anything that wasn't whitespace
    if (rangeToScan_.location != tokenRange.location) {
      rangeToScan_.length = tokenRange.location - rangeToScan_.location;
      NSRange firstNonWhitespace =
        [stringToTokenize_ rangeOfCharacterFromSet:nonWhiteSpaceCharSet_
                                           options:0
                                             range:rangeToScan_];
      if (firstNonWhitespace.location != NSNotFound) {
        // pick off that one char
        result = [stringToTokenize_ substringWithRange:firstNonWhitespace];
        // setup rangeToScan_ for next time
        NSUInteger charsToAdvance =
        firstNonWhitespace.location - rangeToScan_.location + 1;
        rangeToScan_.location += charsToAdvance;
        rangeToScan_.length -= charsToAdvance;
        // save off what we found for later
        savedWordRange_ = tokenRange;
        return result;
      }
      // clear our marker
      rangeToScan_.length = 0;
    }
    
    // use what we found
    result = [stringToTokenize_ substringWithRange:tokenRange];
    // advance the start of rangeToScan_ to the end of what we've used
    rangeToScan_.location = NSMaxRange(tokenRange);
  }
  return result;
}

@end

@implementation HGSTokenizer

+ (NSEnumerator *)wordEnumeratorForString:(NSString *)stringToTokenize {
  return [[[HGSTokenizerEnumerator alloc] initWithString:stringToTokenize
                                               wordsOnly:YES] autorelease];
}

+ (NSEnumerator *)tokenEnumeratorForString:(NSString *)stringToTokenize {
  return [[[HGSTokenizerEnumerator alloc] initWithString:stringToTokenize
                                               wordsOnly:NO] autorelease];
}

@end
