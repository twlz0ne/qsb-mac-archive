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
- (HGSAction *)defaultAction {
  NSString *actionName = @"com.google.text.action.largetype";
  HGSAction *action 
    = [[HGSExtensionPoint actionsPoint] extensionWithIdentifier:actionName];
  if (!action) {
    HGSLog(@"Unable to get large type action (%@)", actionName);
  }
  return action;
}

- (NSSet *)resultTypes {
  return [NSSet setWithObject:kHGSTypeTextUserInput];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  if (isValid) {
  // TODO(thomasvl): support indirect w/o loading space
  
  // For top level, must start w/ our prefix.
    NSString *rawQuery = [query rawQueryString];
    NSUInteger len = [rawQuery length];
    NSUInteger prefixLen = [kInputPrefix length];
    if (len > prefixLen) {
      isValid = [rawQuery compare:kInputPrefix
                          options:NSCaseInsensitiveSearch
                            range:NSMakeRange(0, prefixLen)] == NSOrderedSame;
    } else {
      isValid = NO;
    }
  }
  return isValid;
}

- (void)performSearchOperation:(HGSCallbackSearchOperation *)operation {
  NSString *rawQuery = [[operation query] rawQueryString];

  // TODO(thomasvl): support indirect w/o loading space
  HGSAssert([rawQuery hasPrefix:kInputPrefix], nil);
  NSString *userText = [rawQuery substringFromIndex:[kInputPrefix length]];
  
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSString *fileType = NSFileTypeForHFSTypeCode(kClippingTextType);
  NSImage *image = [ws iconForFileType:fileType];
 
  NSString *details = HGSLocalizedString(@"Text", 
                                         @"A result label denoting text "
                                         @"typed in by the user");
  // Default action for text right now is large type
  HGSAction *largeTypeAction = [self defaultAction];
  // Cheat, force this result high in the list.
  // TODO(dmaclach): figure out a cleaner way to get results like this high
  // in the results.
  NSDictionary *attributes
    = [NSDictionary dictionaryWithObjectsAndKeys:
       [NSNumber numberWithFloat:2000.0f], kHGSObjectAttributeRankKey,
       details, kHGSObjectAttributeSnippetKey,
       image, kHGSObjectAttributeIconKey,
       largeTypeAction, kHGSObjectAttributeDefaultActionKey,
       nil];
  HGSResult *hgsObject
    = [HGSResult resultWithURI:@"userinput:text"
                          name:userText
                          type:kHGSTypeTextUserInput
                        source:self
                    attributes:attributes];

  // See if we need a version w/ stamps
  HGSResult *hgsObject2 = nil;
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
    
    details = HGSLocalizedString(@"Stamped text input", 
                                 @"A result label denoting text "
                                 @"typed in by the user that contains "
                                 @"some special markers that we replace with "
                                 @"data, such as the current date.");

    // Cheat, force this result high in the list.
    // TODO(dmaclach): figure out a cleaner way to get results like this high
    // in the results.
    attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                  [NSNumber numberWithFloat:2001.0f], kHGSObjectAttributeRankKey,
                  details, kHGSObjectAttributeSnippetKey,
                  image, kHGSObjectAttributeIconKey,
                  largeTypeAction, kHGSObjectAttributeDefaultActionKey,
                  nil];
    hgsObject2 = [HGSResult resultWithURI:@"userinput:text/stamped"
                                     name:worker
                                     type:kHGSTypeTextUserInput
                                   source:self
                               attributes:attributes];
  }
  
  NSArray *resultsArray = [NSArray arrayWithObjects:hgsObject, hgsObject2, nil];
  [operation setResults:resultsArray];
}

@end
