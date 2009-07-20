//
//  ClipboardSearchSource.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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
#import "ClipboardSearchSource.h"
#import "GTMNSString+URLArguments.h"

static const NSTimeInterval kPasteboardPollInterval = 1.0;
static const NSInteger kMaxDisplayNameLength = 256;
static const NSInteger kMaxHistoryItems = 25;
static const NSInteger kMaxSnippetLines = 5;
static NSString *const kClipboardUrlScheme = @"vermilionclip";
static NSString *const kClipboardCopyAction
    = @"com.google.qsb.clipboard.action.copy";

@interface ClipboardSearchSource : HGSMemorySearchSource {
 @private
  __weak NSTimer *updateTimer_;
  NSArray *types_;
  NSMutableArray *recentResults_;
  NSInteger lastChangeCount_;
  NSImage *clipboardIcon_;
}
- (NSString *)nameFromStringValue:(NSString *)stringValue;
- (NSString *)snippetFromStringValue:(NSString *)stringValue;
@end

@implementation ClipboardSearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Create the first result as a persistent, pivotable "clipboard" item
    NSString *path = [HGSGetPluginBundle() pathForResource:@"clipboard"
                                                    ofType:@"icns"];
    clipboardIcon_ = [[NSImage alloc] initByReferencingFile:path];
    NSString *name
      = [HGSLocalizedString(@"Clipboard",
                            @"The generic search term used to bring up "
                            @"clipboard contents and history")
         gtm_stringByEscapingForURLArgument];
    NSString *urlString = [NSString stringWithFormat:@"%@://%@",
                           kClipboardUrlScheme, name];
    NSDictionary *attributes
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         clipboardIcon_, kHGSObjectAttributeIconKey,
         nil];
    HGSResult *result
      = [HGSResult resultWithURL:[NSURL URLWithString:urlString]
                            name:name
                            type:kTypeClipboardGeneric
                          source:self
                      attributes:attributes];
    recentResults_ = [[NSMutableArray arrayWithObject:result] retain];
    [self indexResult:result];
    types_ = [[NSArray arrayWithObjects:NSRTFPboardType, NSURLPboardType,
               NSStringPboardType, NSTIFFPboardType, NSPDFPboardType,
               NSPICTPboardType, nil] retain];
    updateTimer_
      = [NSTimer scheduledTimerWithTimeInterval:kPasteboardPollInterval
                                         target:self
                                       selector:@selector(updatePasteboard:)
                                       userInfo:nil
                                        repeats:YES];
  }
  return self;
}

- (void)dealloc {
  [updateTimer_ invalidate];
  [types_ release];
  [recentResults_ release];
  [clipboardIcon_ release];
  [super dealloc];
}

- (void)processMatchingResults:(NSMutableArray *)results
                      forQuery:(HGSQuery *)query {
  if ([query pivotObject]) {
    // We're pivoting off the persistent "Clipboard" result. Adjust the
    // ranking of the results so that they appear in chronological order
    // and remove the persistent result from the array
    [results removeObjectAtIndex:0];
    CGFloat rankIncrement = 1.0 / [results count], pos = 0;
    for (HGSMutableResult *result in results) {
      [result setRank:rankIncrement * pos];
      ++pos;
    }
  }
}

- (void)updatePasteboard:(NSTimer *)timer {
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  NSInteger changeCount = [pb changeCount];
  if (changeCount != lastChangeCount_) {
    // Add all of the available data to the result
    NSMutableDictionary *pasteboardValue = [NSMutableDictionary dictionary];
    NSArray *types = [pb types];
    for (NSString *type in types) {
      if ([type isEqualToString:NSStringPboardType]) {
        [pasteboardValue setValue:[pb stringForType:NSStringPboardType]
                           forKey:type];
      } else if ([type isEqualToString:NSURLPboardType]) {
        [pasteboardValue setValue:[NSURL URLFromPasteboard:pb]
                           forKey:type];
      } else {
        [pasteboardValue setValue:[pb dataForType:type]
                           forKey:type];
      }
    }
    
    NSString *historyName
      = [HGSLocalizedString(@"Clipboard History",
                            @"The user-visible name for the clipboard "
                            @"history search result")
         gtm_stringByEscapingForURLArgument];
    NSString *snippet = nil;
    NSImage *icon = clipboardIcon_;
    
    // Create the best available representation of the pasteboard data
    // for the name, snippet, icon, etc.
    NSMutableDictionary *dictionary = nil;
    NSString *type = [pb availableTypeFromArray:types_];
    if ([type isEqualToString:NSStringPboardType]) {
      // Plain text string
      NSString *value = [pb stringForType:NSStringPboardType];
      NSString *name = [self nameFromStringValue:value];
      NSURL *url
        = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%i",
           kClipboardUrlScheme, historyName, changeCount]];
      dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    name, kHGSObjectAttributeNameKey,
                    kTypeClipboardString, kHGSObjectAttributeTypeKey,
                    url, kHGSObjectAttributeURIKey,
                    nil];
      if (![value isEqualToString:name]) {
        snippet = [self snippetFromStringValue:value];
      }
    } else if ([type isEqualToString:NSRTFPboardType]) {
      // RTF data
      NSData *data = [pb dataForType:NSRTFPboardType];
      NSAttributedString *attributedString
        = [[NSAttributedString alloc] initWithRTF:data documentAttributes:NULL];
      NSString *value = [attributedString string];
      NSString *name = [self nameFromStringValue:value];
      NSURL *url
        = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%i",
           kClipboardUrlScheme, historyName, changeCount]];
      dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    name, kHGSObjectAttributeNameKey,
                    kTypeClipboardRTF, kHGSObjectAttributeTypeKey,
                    url, kHGSObjectAttributeURIKey,
                    nil];
      if (![value isEqualToString:name]) {
        snippet = [self snippetFromStringValue:value];
      }
    } else if ([type isEqualToString:NSURLPboardType]) {
      // URL
      NSURL *url = [NSURL URLFromPasteboard:pb];
      dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [url absoluteString], kHGSObjectAttributeNameKey,
                    kTypeClipboardURL, kHGSObjectAttributeTypeKey,
                    url, kHGSObjectAttributeURIKey,
                    nil];
    } else if ([type isEqualToString:NSTIFFPboardType] ||
               [type isEqualToString:NSPDFPboardType] ||
               [type isEqualToString:NSPICTPboardType]) {
      // Image
      icon = [[[NSImage alloc] initWithPasteboard:pb] autorelease];
      if (icon) {
        NSString *name
          = HGSLocalizedString(@"Clipboard Image",
                               @"The user-visible name for clipboard  "
                               @"image results");
        NSURL *url
          = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%i",
             kClipboardUrlScheme, historyName, changeCount]];
        dictionary = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                      name, kHGSObjectAttributeNameKey,
                      kTypeClipboardImage, kHGSObjectAttributeTypeKey,
                      url, kHGSObjectAttributeURIKey,
                      nil];
      }
    }
    // TODO(hawk): more specializations, such as files
    
    if (dictionary && pasteboardValue) {
      [dictionary setValue:pasteboardValue
                    forKey:kHGSObjectAttributePasteboardValueKey];
      [dictionary setValue:[NSDate date]
                    forKey:kHGSObjectAttributeLastUsedDateKey];
      HGSAction *action 
        = [[HGSExtensionPoint actionsPoint]
           extensionWithIdentifier:kClipboardCopyAction];
      if (action) {
        [dictionary setObject:action
                       forKey:kHGSObjectAttributeDefaultActionKey];
      }
      if (snippet) {
        [dictionary setValue:snippet forKey:kHGSObjectAttributeSnippetKey];
      }
      if (icon) {
        [dictionary setValue:icon forKey:kHGSObjectAttributeIconKey];
      }
      
      HGSResult *result = [HGSResult resultWithDictionary:dictionary 
                                                   source:self];
      if (result) {
        if ([recentResults_ count] > kMaxHistoryItems) {
          // Zero-index item in the array is the persistent clipboard result
          [recentResults_ removeObjectAtIndex:1];
        }
        [recentResults_ addObject:result];
        [self clearResultIndex];
        for (HGSResult *recentResult in recentResults_) {
          [self indexResult:recentResult];
        }
      }
    }
    
    lastChangeCount_ = changeCount;
  }
}

// Flatten a possibly long pasteboard value (say, the entire contents of a file)
// into something the can be displayed on a single line in a list. 
- (NSString *)nameFromStringValue:(NSString *)stringValue {
  stringValue = [stringValue stringByTrimmingCharactersInSet:
                 [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  NSArray *parts = [stringValue componentsSeparatedByCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  stringValue = [parts componentsJoinedByString:@" "];
  if ([stringValue length] > kMaxDisplayNameLength) {
    stringValue = [stringValue substringToIndex:kMaxDisplayNameLength];
  }
  return stringValue;
}

// Reduce a multi-line string to just the first few lines
- (NSString *)snippetFromStringValue:(NSString *)stringValue {
  NSArray *lines = [stringValue componentsSeparatedByCharactersInSet:
                    [NSCharacterSet newlineCharacterSet]];
  NSMutableArray *resultLines = [NSMutableArray array];
  NSCharacterSet *cs = [NSCharacterSet whitespaceCharacterSet];
  for (NSString *line in lines) {
    if ([[line stringByTrimmingCharactersInSet:cs] length]) {
      [resultLines addObject:line];
      if ([resultLines count] == kMaxSnippetLines) {
        break;
      }
    }
  }
  return [resultLines componentsJoinedByString:@"\n"];
}

@end