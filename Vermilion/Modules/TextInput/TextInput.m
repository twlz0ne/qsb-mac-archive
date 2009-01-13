//
//  TextInput.m
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

#import <Vermilion/Vermilion.h>

static NSString *const kInputPrefix = @" ";

static NSString *const kDateMarker = @"[DS]";
static NSString *const kTimeMarker = @"[TS]";
static NSString *const kDateTimeMarker = @"[DTS]";

@interface TextInput : HGSCallbackSearchSource
@end

@implementation TextInput

- (NSSet *)resultTypes {
  return [NSSet setWithObject:kHGSTypeUserInputText];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // TODO(thomasvl): support indirect w/o loading space
  
  // For top level, must start w/ our prefix.
  NSString *rawQuery = [query rawQueryString];
  NSUInteger len = [rawQuery length];
  NSUInteger prefixLen = [kInputPrefix length];
  if (len > prefixLen) {
    BOOL result = [rawQuery compare:kInputPrefix
                            options:NSCaseInsensitiveSearch
                              range:NSMakeRange(0, prefixLen)] == NSOrderedSame;
    return result;
  }
  return NO;
}

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  NSString *rawQuery = [[operation query] rawQueryString];

  // TODO(thomasvl): support indirect w/o loading space
  HGSAssert([rawQuery hasPrefix:kInputPrefix], nil);
  NSString *userText = [rawQuery substringFromIndex:[kInputPrefix length]];
  // TODO(alcor): we need an image we can use here
  NSString *imagePath = @"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ClippingText.icns";
  NSImage *image = [[[NSImage alloc] initByReferencingFile:imagePath] autorelease];
  NSString *details = HGSLocalizedString(@"Text", nil);

  // Cheat, force this result high in the list.
  // TODO(dmaclach): figure out a cleaner way to get results like this high
  // in the results.
  NSDictionary *attributes
    = [NSDictionary dictionaryWithObjectsAndKeys:
       [NSNumber numberWithFloat:2000.0f], kHGSObjectAttributeRankKey,
       details, kHGSObjectAttributeSnippetKey,
       image, kHGSObjectAttributeIconKey,
       nil];
  HGSObject *hgsObject
    = [HGSObject objectWithIdentifier:[NSURL URLWithString:@"userinput:text"]
                                 name:userText
                                 type:kHGSTypeUserInputText
                               source:self
                           attributes:attributes];

  // See if we need a version w/ stamps
  HGSObject *hgsObject2 = nil;
  if (([userText rangeOfString:kDateMarker
                       options:NSCaseInsensitiveSearch].location != NSNotFound) ||
      ([userText rangeOfString:kTimeMarker
                       options:NSCaseInsensitiveSearch].location != NSNotFound) ||
      ([userText rangeOfString:kDateTimeMarker
                       options:NSCaseInsensitiveSearch].location != NSNotFound)) {
    NSDateFormatter *dateFormatter
      = [[[NSDateFormatter alloc] init]  autorelease];
    NSDate *date = [NSDate date];
    NSMutableString *worker = [NSMutableString stringWithString:userText];

    [dateFormatter setDateStyle:NSDateFormatterShortStyle];
    [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
    [worker replaceOccurrencesOfString:kDateMarker
                            withString:[dateFormatter stringFromDate:date]
                               options:NSCaseInsensitiveSearch
                                 range:NSMakeRange(0, [worker length])];
    [dateFormatter setDateStyle:NSDateFormatterNoStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    [worker replaceOccurrencesOfString:kTimeMarker
                            withString:[dateFormatter stringFromDate:date]
                               options:NSCaseInsensitiveSearch
                                 range:NSMakeRange(0, [worker length])];
    [dateFormatter setDateStyle:NSDateFormatterShortStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    [worker replaceOccurrencesOfString:kDateTimeMarker
                            withString:[dateFormatter stringFromDate:date]
                               options:NSCaseInsensitiveSearch
                                 range:NSMakeRange(0, [worker length])];
    
    details = HGSLocalizedString(@"Stamped text input", nil);

    // Cheat, force this result high in the list.
    // TODO(dmaclach): figure out a cleaner way to get results like this high
    // in the results.
    attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                  [NSNumber numberWithFloat:2001.0f], kHGSObjectAttributeRankKey,
                  details, kHGSObjectAttributeSnippetKey,
                  image, kHGSObjectAttributeIconKey,
                  nil];
    NSURL *url = [NSURL URLWithString:@"userinput:text/stamped"];
    hgsObject2 = [HGSObject objectWithIdentifier:url
                                            name:worker
                                            type:kHGSTypeUserInputText
                                          source:self
                                      attributes:attributes];
  }
  
  NSArray *resultsArray = [NSArray arrayWithObjects:hgsObject, hgsObject2, nil];
  [operation setResults:resultsArray];
}

@end
