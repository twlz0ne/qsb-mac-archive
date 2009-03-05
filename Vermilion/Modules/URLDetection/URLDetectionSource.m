//
//  URLDetectionSource.m
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

// This source detects queries like "apple.com" and "http://merak" and turns 
// them into url results.
//
// WARNING: This source along w/ the suggest/navsuggest make for an interesting
// mix.  This source can decide not to accept something that source suggests, so
// if you are trying to debug something you don't want as a url result, it might
// not be this source.

@interface URLDetectionSource : HGSCallbackSearchSource
@end

@implementation URLDetectionSource

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // We use the raw query to see if it's url like
  BOOL isValid = [super isValidSourceForQuery:query];
  if (isValid) {

    // No spaces (can't use [query uniqueWords] because that would split on
    // punct in addition to spaces).
    NSString *urlString = [query rawQueryString];
    if ([urlString rangeOfString:@" "].location != NSNotFound) {
      isValid = NO;
    } else {
      // Does it appear to have a scheme?
      if ([urlString rangeOfString:@":"].location != NSNotFound) {
        // nothing to do, already set to yes
        // isValid = YES;
      } else {
        // If it doesn't have a '.' or '/', give up.  (covers "internalsite/bar"
        // and "google.com")
        if ([urlString rangeOfString:@"."].location == NSNotFound
            && [urlString rangeOfString:@"/"].location == NSNotFound) {
          isValid = NO;
        }
      }
    }
  }
  return isValid;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSString *queryString = [[operation query] rawQueryString];
  NSString *urlString = queryString;
  NSURL *url = [NSURL URLWithString:urlString];

  if ([url scheme]) {
    // NSURL seem happy, nothing more to do at this point, we'll use it.
  } else {
    // Try to see if it's "internalsite/bar" or "google.com" style
    NSArray *pathComponents = [urlString componentsSeparatedByString:@"/"];
    NSString *host = [pathComponents objectAtIndex:0];
    NSArray *hostComponents = [host componentsSeparatedByString:@"."];
    
    BOOL valid = NO;

    // IP Address
    if ([hostComponents count] == 4) {
      valid = YES;
    }
    // internalsite/[something]
    else if ([host length] && [hostComponents count] == 1
               && [pathComponents count] > 1) { 
      valid = YES;
    }
    // blah.com
    else if ([hostComponents count] > 1
             // Dissalow "default.htm*" and moo.228
             && ![[hostComponents lastObject] hasPrefix:@"htm"]
             && [[hostComponents lastObject] rangeOfCharacterFromSet:
                 [NSCharacterSet decimalDigitCharacterSet]].location == NSNotFound){
      valid = YES;
    }
    
    if (valid) {
      urlString = [@"http://" stringByAppendingString:urlString];
      url = [NSURL URLWithString:urlString];
    }
  }

  if (url) {
    NSDictionary *attributes
      = [NSDictionary dictionaryWithObjectsAndKeys:
         [NSImage imageNamed:@"blue-nav"], kHGSObjectAttributeIconKey,
         [NSNumber numberWithBool:YES], kHGSObjectAttributeAllowSiteSearchKey,
         urlString, kHGSObjectAttributeSourceURLKey,
         [NSNumber numberWithBool:YES], kHGSObjectAttributeIsSyntheticKey,
         [NSNumber numberWithFloat:1.0f], kHGSObjectAttributeRankKey,
         nil];
         
    HGSResult *result = [HGSResult resultWithURL:url
                                            name:queryString
                                            type:kHGSTypeWebpage
                                          source:self
                                      attributes:attributes];
    [operation setResults:[NSArray arrayWithObject:result]];
  }
}

@end

