//
//  WeatherSource.m
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
#import "GTMNSString+URLArguments.h"

// TODO: should either of these get a hl= based on our running UI?
static NSString *const kWeatherDataURL
  = @"http://www.google.com/ig/api?weather=%@&output=xml";
static NSString *const kWeatherResultURL
  = @"http://www.google.com/search?q=weather%%20%@";

static NSString *const kWeatherPrefix = @"weather ";

@interface WeatherSource : HGSCallbackSearchSource {
 @private
  NSCharacterSet *nonDigitSet_;
}
@end

@implementation WeatherSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    nonDigitSet_
      = [[[NSCharacterSet decimalDigitCharacterSet] invertedSet] retain];
  }
  return self;
}

- (void)dealloc {
  [nonDigitSet_ release];
  
  [super dealloc];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // Must be "weather [something]" or just a 5 digit zip code (all numbers)
  // TODO(dmaclach): any other zipcode/postal codes (CA, ???)
  NSString *rawQuery = [query rawQueryString];
  NSUInteger len = [rawQuery length];
  if (len == 5) {
    NSRange range = [rawQuery rangeOfCharacterFromSet:nonDigitSet_];
    return (range.location == NSNotFound);
  } else {
    NSUInteger prefixLen = [kWeatherPrefix length];
    if (len > prefixLen) {
      BOOL result = [rawQuery compare:kWeatherPrefix
                              options:NSCaseInsensitiveSearch
                                range:NSMakeRange(0, prefixLen)] == NSOrderedSame;
      return result;
    }
  }
  return NO;
}

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  NSString *rawQuery = [[operation query] rawQueryString];
  NSString *location;
  if ([rawQuery length] == 5) {
    // It's a zip
    location = rawQuery;
  } else {
    // Extract what's after our marker
    location = [rawQuery substringFromIndex:[kWeatherPrefix length]];
  }
  NSString *escapedLocation = [location gtm_stringByEscapingForURLArgument];
  
  NSString *urlStr = [NSString stringWithFormat:kWeatherDataURL, escapedLocation];
  NSURL *url = [NSURL URLWithString:urlStr];
  if (url) {
    // TODO: make this an async using GDataHTTPFetcher (means this search op is
    // concurrent), instead of blocking here.
    NSXMLDocument *xmlDoc
      = [[[NSXMLDocument alloc] initWithContentsOfURL:url
                                              options:0
                                                error:nil] autorelease];
    if (xmlDoc) {
      NSString *city
        = [[[xmlDoc nodesForXPath:@"/xml_api_reply/weather/forecast_information/city/@data"
                            error:nil] lastObject] stringValue];
      NSString *temp
        = [[[xmlDoc nodesForXPath:@"/xml_api_reply/weather/current_conditions/temp_f/@data"
                            error:nil] lastObject] stringValue];
      
      NSString *condition
        = [[[xmlDoc nodesForXPath:@"/xml_api_reply/weather/current_conditions/condition/@data"
                            error:nil] lastObject] stringValue];
      
      NSString *wind
        = [[[xmlDoc nodesForXPath:@"/xml_api_reply/weather/current_conditions/wind_condition/@data"
                            error:nil] lastObject] stringValue];
      
      if ([city length] && [temp length] && [condition length] && [wind length]) {
        // TODO(dmaclach): add localization support for these
        NSString *title
          = [NSString stringWithFormat:@"Weather for %@", city];
        NSString *details
          = [NSString stringWithFormat:@"%@° - %@ - %@", temp, condition, wind];
        
        // build an open url
        NSString *resultURLStr
          = [NSString stringWithFormat:kWeatherResultURL, escapedLocation];
        NSURL *resultURL = [NSURL URLWithString:resultURLStr];
        // Cheat, force this result high in the list.
        // TODO(dmaclach): figure out a cleaner way to get results like this high
        // in the results.
        NSMutableDictionary *attributes
          = [NSMutableDictionary dictionaryWithObjectsAndKeys:
             [NSNumber numberWithFloat:2.0f], kHGSObjectAttributeRankKey,
             details, kHGSObjectAttributeSnippetKey,
             nil];
        NSString *imageSRL
          = [[[xmlDoc nodesForXPath:@"/xml_api_reply/weather/current_conditions/icon/@data"
                              error:nil] lastObject] stringValue];
        if (imageSRL) {
          NSURL *imgURL = [NSURL URLWithString:imageSRL relativeToURL:url];
          // TODO: do we really want to use initByReferencingURL or should we
          // just fetch the image some other way?
          NSImage *image = [[[NSImage alloc] initByReferencingURL:imgURL] autorelease];
          if (image) {
            [attributes setObject:image forKey:kHGSObjectAttributeIconKey];
          }
        }
        HGSObject *hgsObject
          = [HGSObject objectWithIdentifier:resultURL
                                       name:title
                                       type:HGS_SUBTYPE(kHGSTypeOnebox, @"weather")
                                     source:self
                                 attributes:attributes];
        NSArray *resultsArray = [NSArray arrayWithObject:hgsObject];
        [operation setResults:resultsArray];
      }
    }
  }
  // query is concurrent, don't need to end it ourselves.
}

@end
