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
#import "GTMGarbageCollection.h"
#import "HGSLog.h"
#import "HGSStringUtil.h"

@interface HGSTokenizerInternal : NSEnumerator {
@private
  CFStringTokenizerRef tokenizer_;
  CFCharacterSetRef numberSet_;
}

- (NSString *)tokenizeString:(NSString *)string;
@end
  
@implementation HGSTokenizerInternal
- (id)init {
  if ((self = [super init])) {
    // The header comments for CFStringTokenizerCreate and
    // kCFStringTokenizerUnitWord indicate the locale is unused for UnitWord;
    // so we just pass NULL here to avoid creating one.
    // Radar 6195821 has been filed to get the docs updated to match.    
    tokenizer_ = CFStringTokenizerCreate(NULL, 
                                         CFSTR(""), 
                                         CFRangeMake(0,0), 
                                         kCFStringTokenizerUnitWord, 
                                         NULL);
    numberSet_ 
      = CFCharacterSetCreateWithCharactersInString(NULL, 
                                                   CFSTR("0123456789,."));
    HGSAssert(tokenizer_, nil);
  }
  return self;
}

- (void)dealloc {
  if (tokenizer_) {
    CFRelease(tokenizer_);
    tokenizer_ = NULL;
  }
  if (numberSet_) {
    CFRelease(numberSet_);
    numberSet_ = NULL;
  }
  [super dealloc];
}

- (NSString *)tokenizeString:(NSString *)string {
  // Using define because the compiler gets upset when I use a const int
  // telling me that it can't protect me due to a variable sized array.
  // I am using a fixed size array and CF functions instead of a variable 
  // sized NSArray because it doubles our speed, and this is a performance
  // sensitive routine.
  NSLocale *currentLocale = [NSLocale currentLocale];
  NSStringCompareOptions options = (NSDiacriticInsensitiveSearch 
                                    | NSWidthInsensitiveSearch);
  string = [string stringByFoldingWithOptions:options 
                                       locale:currentLocale];
  
  // Used define hear because of
  // Radar 6765569 stack-protector gives bad warning when working with consts
  #define kHGSTokenizerInternalMaxRanges 100
  CFRange tokensRanges[kHGSTokenizerInternalMaxRanges];
  CFIndex currentRange = 0;
  
  CFRange tokenRange = CFRangeMake(0, [string length]);
  CFStringTokenizerSetString(tokenizer_,
                             (CFStringRef)string,
                             tokenRange);
  while (currentRange < kHGSTokenizerInternalMaxRanges) {
    CFStringTokenizerTokenType tokenType
      = CFStringTokenizerAdvanceToNextToken(tokenizer_);
    if (tokenType == kCFStringTokenizerTokenNone) {
      break;
    }
    CFRange subTokenRanges[kHGSTokenizerInternalMaxRanges];
    CFIndex rangeCount 
      = CFStringTokenizerGetCurrentSubTokens(tokenizer_, 
                                             subTokenRanges, 
                                             kHGSTokenizerInternalMaxRanges, 
                                             NULL);
    // If our subtokens contain numbers we want to rejoin the numbers back
    // up. 
    if (tokenType & kCFStringTokenizerTokenHasHasNumbersMask) {
      BOOL makingNumber = NO;
      CFRange newRange = CFRangeMake(subTokenRanges[0].location, 0);
      for (CFIndex i = 0; 
           i < rangeCount && currentRange < kHGSTokenizerInternalMaxRanges;  
           ++i) {
        UniChar theChar 
          = CFStringGetCharacterAtIndex((CFStringRef)string, 
                                        subTokenRanges[i].location);
        BOOL isNumber 
          = CFCharacterSetIsCharacterMember(numberSet_, theChar) ? YES : NO;
        if (isNumber == YES) {
          if (!makingNumber) {
            if (newRange.length > 0) {
              tokensRanges[currentRange++] = newRange;
            }
            newRange = CFRangeMake(subTokenRanges[i].location, 0);
            makingNumber = YES;
          } 
          newRange.length += subTokenRanges[i].length;
        } else {
          makingNumber = NO;
          if (newRange.length > 0) {
            tokensRanges[currentRange++] = newRange;
            newRange = CFRangeMake(subTokenRanges[i].location, 0);
          }
          if (currentRange < kHGSTokenizerInternalMaxRanges) {
            tokensRanges[currentRange++] = subTokenRanges[i];
          }
        }
      }
      if (newRange.length > 0) {
        tokensRanges[currentRange++] = newRange;
      }
    } else {
      if (rangeCount + currentRange > kHGSTokenizerInternalMaxRanges) {
        rangeCount = kHGSTokenizerInternalMaxRanges - currentRange;
      }
      memcpy(&tokensRanges[currentRange], subTokenRanges, 
             sizeof(CFRange) * rangeCount);
      currentRange += rangeCount;
    }
  }
  NSInteger length = [string length] + currentRange;
  NSMutableString *finalString = [NSMutableString stringWithCapacity:length];
  // Now that we have all of our ranges, break out our strings.
  for (CFIndex i = 0; i < currentRange; ++i) {
    NSRange nsRange = NSMakeRange(tokensRanges[i].location, 
                                  tokensRanges[i].length);
    NSString *subString = [string substringWithRange:nsRange];
    subString = [subString stringByFoldingWithOptions:NSCaseInsensitiveSearch
                                               locale:currentLocale];
    if (i != 0) {
      [finalString appendString:@" "];
    }
    [finalString appendString:subString];
  }
  return finalString;
}

@end

@implementation HGSTokenizer
+ (NSString *)tokenizeString:(NSString *)string {
  NSString *tokenizedString = nil;
  if (string) {
    NSThread *currentThread = [NSThread currentThread];
    NSMutableDictionary *threadDictionary = [currentThread threadDictionary];
    NSString *kHGSTokenizerThreadTokenizer = @"HGSTokenizerThreadTokenizer";
    HGSTokenizerInternal *internalTokenizer 
      = [threadDictionary objectForKey:kHGSTokenizerThreadTokenizer];
    if (!internalTokenizer) {
      internalTokenizer = [[[HGSTokenizerInternal alloc] init] autorelease];
      [threadDictionary setObject:internalTokenizer 
                           forKey:kHGSTokenizerThreadTokenizer];
    }
    tokenizedString = [internalTokenizer tokenizeString:string];
  }
  return tokenizedString;
}
@end

