//
//  HGSWebSearchSource.m
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

#import "Vermilion/Vermilion.h"

#import "GTMDefines.h"
#import "GTMGarbageCollection.h"
#import "GTMNSString+URLArguments.h"

// TODO(dmaclach): should this be off webpage?
#define kHGSTypeSearchCorpus @"searchcorpus"

@interface HGSWebSearchSource : HGSCallbackSearchSource
+ (NSURL *)urlForQuery:(NSString *)queryString onSiteObject:(HGSObject *)object;
@end

#if TARGET_OS_IPHONE
#import "UTCoreTypes+Missing.h"
#import "GMOUserPreferences.h"
static NSString *const kWebSourceIconName = @"web-searchsubmit.png";
#else
static NSString *const kWebSourceIconName = @"blue-searchhistory";
#endif

static NSString* const kGoogleSiteSearchFormat = @"http://www.google.com/search?q=%@&as_sitesearch=%@";

@implementation HGSWebSearchSource

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // We are a valid source for any web page
  HGSObject *pivotObject = [query pivotObject];
  
  BOOL isSearchable = ([pivotObject valueForKey:kHGSObjectAttributeWebSearchTemplateKey] != nil) ||
    [[pivotObject valueForKey:kHGSObjectAttributeAllowSiteSearchKey] boolValue];
  return isSearchable;
}

+ (NSURL *)urlForQuery:(NSString *)queryString onSiteObject:(HGSObject *)object {
  NSString *searchFormat = [object valueForKey:kHGSObjectAttributeWebSearchTemplateKey];

  NSString *escapedString = [queryString gtm_stringByEscapingForURLArgument];
  NSString *fullURLString = nil;
  if (searchFormat && [escapedString length]) {
    fullURLString = [searchFormat stringByReplacingOccurrencesOfString:@"{searchterms}" withString:escapedString];
  } else {
    fullURLString = [NSString stringWithFormat:kGoogleSiteSearchFormat,
                     escapedString,
                     [[object identifier] host]];
  }
  return [NSURL URLWithString:fullURLString];
}

- (BOOL)isSearchConcurrent {
  return YES;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  HGSQuery *query = [operation query];
  HGSObject *pivotObject = [query pivotObject];
  if (pivotObject) {
    NSString *queryString = [query rawQueryString];
    NSURL *url = [[self class] urlForQuery:queryString onSiteObject:pivotObject];
    NSString *searchName = [pivotObject valueForKey:kHGSObjectAttributeWebSearchDisplayStringKey];
    if (!searchName) {
      NSString *searchLabel = HGSLocalizedString(@"Search %@",
                                                 @"Search <website|category> (eg. Wikipedia) (30 chars excluding <website>)");
      searchName = [NSString stringWithFormat:searchLabel, [[pivotObject identifier] host]];
    }
    if ([queryString length]) {
      BOOL searchInline = NO;
#if TARGET_OS_IPHONE
      searchInline =
        [[pivotObject valueForKey:@"kHGSObjectAttributeSearchInline"]
          boolValue];
#endif
      if (!searchInline) {
        NSImage *icon = [NSImage imageNamed:kWebSourceIconName];
        NSString *itemLabel = HGSLocalizedString(@"for \"%@\"",
                                                 @"[Search <website>] for <search_term> (30 chars excluding <search_term>)");
        NSString *details = [NSString stringWithFormat:itemLabel, queryString];
        NSDictionary *attributes
          = [NSDictionary dictionaryWithObjectsAndKeys:
             icon, kHGSObjectAttributeIconKey,
             details, kHGSObjectAttributeSnippetKey,
             nil];
        HGSObject *placeholderItem 
          = [HGSObject objectWithIdentifier:url
                                       name:searchName
                                       type:kHGSTypeSearchCorpus
                                     source:nil
                                 attributes:attributes];
        [operation setResults:[NSArray arrayWithObject:placeholderItem]];
      }
    } else {
      NSURL *identifier = [pivotObject identifier];
      NSString *openLabel = HGSLocalizedString(@"Open %@",
                                               @"Open <website> (eg. Wikipedia) (30 chars excluding <website>)");
      NSString *name = [NSString stringWithFormat:openLabel, [pivotObject displayName]];
      HGSObject *placeholderItem = [HGSObject objectWithIdentifier:identifier
                                                              name:name 
                                                              type:kHGSTypeWebpage 
                                                            source:nil 
                                                        attributes:nil];
      [operation setResults:[NSArray arrayWithObjects:placeholderItem, nil]];
    }
  }

  [operation finishQuery];
}

@end
