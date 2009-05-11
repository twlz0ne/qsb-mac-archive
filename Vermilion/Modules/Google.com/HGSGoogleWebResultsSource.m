//
//  HGSGoogleWebResultsSource.m
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
#import "JSON/JSON.h"
#import <GData/GDataHTTPFetcher.h>
#import "GTMMethodCheck.h"
#import "GTMNSDictionary+URLArguments.h"
#import "GTMNSString+HTML.h"
#import "NSArray+HGSCommonPrefixDetection.h"
#import "NSString+ReadableURL.h"

#if TARGET_OS_IPHONE
#import "GMOLocationManager.h"
#import "GMOProduct.h"
#import "GMOUserPreferences.h"
#endif

@interface HGSGoogleWebSearchOperation : HGSSearchOperation {
 @private
  GDataHTTPFetcher *fetcher_;
}
@end

@interface HGSGoogleWebResultsSource : HGSSearchSource
@end

NSString *const kJSONQueryURL = @"http://ajax.googleapis.com/ajax/services/search/web";

// Example response
//{"responseData": {
//  "results": [
//  {
//    "GsearchResultClass": "GwebSearch",
//    "unescapedUrl": "http://en.wikipedia.org/wiki/Paris_Hilton",
//    "url": "http://en.wikipedia.org/wiki/Paris_Hilton",
//    "visibleUrl": "en.wikipedia.org",
//    "cacheUrl": "http://www.google.com/search?q\u003dcache:TwrPfhd22hYJ:en.wikipedia.org",
//    "title": "\u003cb\u003eParis Hilton\u003c/b\u003e - Wikipedia, the free encyclopedia",
//    "titleNoFormatting": "Paris Hilton - Wikipedia, the free encyclopedia",
//    "content": "\[1\] In 2006, she released her debut album..."
//  },
//  {
//    "GsearchResultClass": "GwebSearch",
//    "unescapedUrl": "http://www.imdb.com/name/nm0385296/",
//    "url": "http://www.imdb.com/name/nm0385296/",
//    "visibleUrl": "www.imdb.com",
//    "cacheUrl": "http://www.google.com/search?q\u003dcache:1i34KkqnsooJ:www.imdb.com",
//    "title": "\u003cb\u003eParis Hilton\u003c/b\u003e",
//    "titleNoFormatting": "Paris Hilton",
//    "content": "Self: Zoolander. Socialite \u003cb\u003eParis Hilton\u003c/b\u003e..."
//  },
//  ...
//  ],
//  "cursor": {
//    "pages": [
//    { "start": "0", "label": 1 },
//    { "start": "4", "label": 2 },
//    { "start": "8", "label": 3 },
//    { "start": "12","label": 4 }
//    ],
//    "estimatedResultCount": "59600000",
//    "currentPageIndex": 0,
//    "moreResultsUrl": "http://www.google.com/search?oe\u003dutf8\u0026ie\u003dutf8..."
//  }
//}
//, "responseDetails": null, "responseStatus": 200}


@implementation HGSGoogleWebSearchOperation
GTM_METHOD_CHECK(NSArray, commonPrefixForStringsWithOptions:);
GTM_METHOD_CHECK(NSString, readableURLString);


- (void)dealloc {
  [fetcher_ release];
  [super dealloc];
}

- (NSString *)displayName {
  return HGSLocalizedString(@"Google", 
                            @"A label representing Google as a search source.");
}

- (void)main {
  HGSQuery *query = [self query];

  NSString *queryString = [query rawQueryString];
  if (![queryString length]) {
    [self finishQuery];
    return;
  }

  HGSResult *pivotObject = [query pivotObject];
  
  NSURL *identifier = [pivotObject url];
  NSString *site = nil;

  
  if ([[identifier host] isEqualToString:@"www.google.com"]
      || [[identifier host] isEqualToString:@"google.com"]) {
    site = nil; 
  } else if ([[identifier host] isEqualToString:@"www.wikipedia.com"]
      || [[identifier host] isEqualToString:@"wikipedia.com"]) {
    // We hardcode www to en for wikipedia alone
    // TODO(alcor): figure a nicer way to do this, allowing localized urls
    site = @"en.wikipedia.org";
  } else {
    //TODO(alcor):verify that host is always good
    site = [identifier absoluteString];
  }

  NSString *location = nil;

#if TARGET_OS_IPHONE
  static NSTimeInterval const kThirtyMinutes = 60.0 * 30.0;
  if ([pivotObject valueForKey:@"kHGSObjectAttributeGoogleAPIIncludeLocation"]) {
    location = [[GMOLocationManager sharedLocationManager] currentLocationAsNameYoungerThan:kThirtyMinutes];
    if (!location) {
      [self finishQuery];
      return;
    }
  }
#endif

  NSString *baseURLString = kJSONQueryURL;

  NSString *altURLString = [pivotObject valueForKey:@"kHGSObjectAttributeGoogleAPIURL"];
  if (altURLString) {
    baseURLString = altURLString;
  }

  if (site && !altURLString) {
    queryString = [queryString stringByAppendingFormat:@" site:%@", site];
  }
  NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"1.0", @"v",
                             queryString, @"q",
                             //pivotObject ? @"large" :
                             @"small", @"rsz",
                             location, @"sll",
                             //@"0.065169,0.194149",@"sspn",
                             nil];

  NSString *urlString = [NSString stringWithFormat:@"%@?%@", baseURLString, [arguments gtm_httpArgumentsString]];
  NSURL *url = [NSURL URLWithString:urlString];

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  // TODO(alcor): why this referrer?
  [request setValue:@"http://google-mobile-internal.google.com" forHTTPHeaderField:@"Referer"];

  if (!fetcher_) {
    fetcher_ = [[GDataHTTPFetcher httpFetcherWithRequest:request] retain];
    [fetcher_ setUserData:self];
    [fetcher_ beginFetchWithDelegate:self
                   didFinishSelector:@selector(httpFetcher:finishedWithData:)
                     didFailSelector:@selector(httpFetcher:didFail:)];
  }
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  NSString *jsonResponse = [[[NSString alloc] initWithData:retrievedData
                                                  encoding:NSUTF8StringEncoding]
                            autorelease];
  NSDictionary *response = [jsonResponse JSONValue];
  if (!response) {
    [self finishQuery];
    return;
  }

  NSMutableArray *results = [NSMutableArray array];
  NSArray *googleResultArray = [response valueForKeyPath:@"responseData.results"];
  if (!googleResultArray) return;

  HGSResult *pivotObject = [[self query] pivotObject];
  id image = [pivotObject valueForKey:kHGSObjectAttributeIconKey];

  NSArray *unescapedNames = [googleResultArray valueForKeyPath:@"titleNoFormatting.gtm_stringByUnescapingFromHTML"];
  if (!unescapedNames) return;

  NSString *commonPrefix = [unescapedNames commonPrefixForStringsWithOptions:0];
  NSString *commonSuffix = [unescapedNames commonPrefixForStringsWithOptions:NSBackwardsSearch];

  NSEnumerator *resultEnumerator = [googleResultArray objectEnumerator];
  NSDictionary *resultDict;
  while ((resultDict  = [resultEnumerator nextObject])) {
    NSString *name = [resultDict objectForKey:@"titleNoFormatting"];
    name = [name gtm_stringByUnescapingFromHTML];

    NSString *resultClass = [resultDict objectForKey:@"GsearchResultClass"];

    NSString *content = [[resultDict objectForKey:@"content"] gtm_stringByUnescapingFromHTML];
    NSString *urlString = [[resultDict objectForKey:@"url"] gtm_stringByUnescapingFromHTML];
    if (!urlString) continue;
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    if ([resultClass isEqualToString:@"GlocalSearch"]) {
      NSString *address = [resultDict objectForKey:@"streetAddress"];
      NSString *city = [resultDict objectForKey:@"city"];
      if ([city length]) address = [NSString stringWithFormat:@"%@, %@", address, city];
      if (![name length]) {
        name = address;
      } else {
        [attributes setObject:address forKey:kHGSObjectAttributeSnippetKey];
      }
      if (!image) {
        image = [NSImage imageNamed:@"web-localresult"];
      }
    } else {
      
      [attributes setObject:[resultDict objectForKey:@"unescapedUrl"]
                     forKey:kHGSObjectAttributeSnippetKey];
      
#if TARGET_OS_IPHONE
      [attributes setObject:[NSNumber numberWithBool:YES]
                     forKey:kHGSObjectAttributeAllowSiteSearchKey];
#else
      // Enable site search for global results, but not in sub search
      if (!pivotObject) {
        [attributes setObject:[NSNumber numberWithBool:YES]
                       forKey:kHGSObjectAttributeAllowSiteSearchKey];
      }
#endif
      if (!image) {
        image = [NSImage imageNamed:@"web-nav"];
      }
    }
    [attributes setObject:image forKey:kHGSObjectAttributeIconKey];
#if TARGET_OS_IPHONE
    // The phone doesn't support attributed strings :(
    if (content) {
      content = [content stringByReplacingOccurrencesOfString:@"<b>" withString:@""];
    }
    if (content) {
      content = [content stringByReplacingOccurrencesOfString:@"</b>" withString:@""];
    }
#endif
    if (content) {
      [attributes setObject:content forKey:kHGSObjectAttributeSnippetKey];
    }
    
    if ([commonPrefix length] < [name length]) {
      name = [name substringFromIndex:[commonPrefix length]];
    }
    if ([commonSuffix length] < [name length]) {
      name = [name substringToIndex:[name length] - [commonSuffix length]];
    }
    
    HGSResult *result = [HGSResult resultWithURL:url
                                            name:name
                                            type:kHGSTypeWebpage // TODO: more complete type?
                                          source:[self source]
                                      attributes:attributes];
    
    [results addObject:result];

    // Only contribute 1 result to global search
    if (!pivotObject && ([results count] > 0)) break;
  }

  [self setResults:results];
  [self finishQuery];
  [fetcher_ release];
  fetcher_ = nil;
}

- (void)httpFetcher:(GDataHTTPFetcher *)fetcher
            didFail:(NSError *)error {
  HGSLog(@"httpFetcher failed: %@ %@", error, [[fetcher request] URL]);
  [self finishQuery];
  [fetcher_ release];
  fetcher_ = nil;
}

- (void)cancel {
  [fetcher_ stopFetching];
  [super cancel];
}

- (BOOL)isConcurrent {
  return YES;
}

@end

@implementation HGSGoogleWebResultsSource

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  if (isValid) {
    HGSResult *pivotObject = [query pivotObject];
    NSURL *url = [pivotObject url];
    NSNumber *hideResults 
      = [pivotObject valueForKey:@"kHGSObjectAttributeGoogleAPIAlwaysHideResults"];
    if ([hideResults boolValue]) {
      isValid = NO;
    } else if ([[url scheme] isEqualToString:@"http"]) {
      // We only work on URLs that are http and don't already have searchability
      isValid = YES;
    } else {
      isValid = NO;
    }
  }
  return isValid;
}

- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query {
  HGSGoogleWebSearchOperation *op
    = [[[HGSGoogleWebSearchOperation alloc] initWithQuery:query
                                                   source:self] autorelease];
  return op;
}

@end
