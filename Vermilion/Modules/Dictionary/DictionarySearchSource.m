//
//  DictionarySearchSource.m
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
#import <CoreServices/CoreServices.h>

static NSString *kDictionaryUrlFormat = @"qsbdict://%@";
static NSString *kDictionaryResultType
  = HGS_SUBTYPE(@"dictionary", @"definition");
NSString *kDictionaryRangeLocationKey = @"DictionaryRangeLocation";
NSString *kDictionaryRangeLengthKey = @"DictionaryRangeLength";
NSString *kDictionaryTermKey = @"DictionaryTerm";
static NSString *kShowInDictionaryAction
  = @"com.google.qsb.dictionary.action.open";
static const int kMinQueryLength = 3;

@interface DictionarySearchSource : HGSCallbackSearchSource {
 @private
  NSImage *dictionaryIcon_;
}
@end

@implementation DictionarySearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    dictionaryIcon_
      = [ws iconForFile:
         [ws absolutePathForAppBundleWithIdentifier:@"com.apple.Dictionary"]];
    [dictionaryIcon_ retain];
  }
  return self;
}

- (void) dealloc {
  [dictionaryIcon_ release];
  [super dealloc];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  if (isValid) {
    isValid = ([[query rawQueryString] length] >= kMinQueryLength);
  }
  return isValid;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSMutableSet *results = [NSMutableSet set];
  NSString *query = [[operation query] rawQueryString];
  CFRange range = DCSGetTermRangeInString(NULL, (CFStringRef)query, 0);
  if (range.location != kCFNotFound && range.length != kCFNotFound) {
    CFStringRef def = DCSCopyTextDefinition(NULL, (CFStringRef)query, range);
    if (def) {
      NSString *urlString 
        = [NSString stringWithFormat:kDictionaryUrlFormat,
           [query stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
      NSMutableDictionary *attributes
        = [NSMutableDictionary dictionaryWithObjectsAndKeys:
           (NSString *)def, kHGSObjectAttributeSnippetKey,
           dictionaryIcon_, kHGSObjectAttributeIconKey,
           [NSNumber numberWithInt:range.location], kDictionaryRangeLocationKey,
           [NSNumber numberWithInt:range.length], kDictionaryRangeLengthKey,
           query, kDictionaryTermKey,
           nil];
      HGSAction *action 
        = [[HGSExtensionPoint actionsPoint]
           extensionWithIdentifier:kShowInDictionaryAction];
      if (action) {
        [attributes setObject:action forKey:kHGSObjectAttributeDefaultActionKey];
      }
      NSString *definitionFormat = HGSLocalizedString(@"Definition of %@", nil);
      NSString *name
        = [NSString stringWithFormat:definitionFormat,
           [query substringWithRange:NSMakeRange(range.location, range.length)]];
      HGSResult *result 
        = [HGSResult resultWithURL:[NSURL URLWithString:urlString]
                              name:name
                              type:kDictionaryResultType
                            source:self
                        attributes:attributes];
      [results addObject:result];
      CFRelease(def);
    }
  }
  [operation setResults:[results allObjects]];
}

@end