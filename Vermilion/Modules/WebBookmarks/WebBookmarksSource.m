//
//  WebBookmarksSource.m
//
//  Copyright (c) 2008-2009 Google Inc. All rights reserved.
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

#import "WebBookmarksSource.h"
#import "GTMFileSystemKQueue.h"

@implementation WebBookmarksSource

- (id)initWithConfiguration:(NSDictionary *)configuration 
            browserTypeName:(NSString *)browserTypeName
                fileToWatch:(NSString *)path {
  if ((self = [super initWithConfiguration:configuration])) {
    GTMFileSystemKQueueEvents queueEvents = (kGTMFileSystemKQueueDeleteEvent 
                                              | kGTMFileSystemKQueueWriteEvent);
    fileKQueue_ 
      = [[GTMFileSystemKQueue alloc] initWithPath:path
                                        forEvents:queueEvents
                                    acrossReplace:YES
                                           target:self
                                           action:@selector(fileChanged:event:)];
    browserTypeName_ = [browserTypeName copy];
    if (fileKQueue_ && browserTypeName_) {
      NSOperation *operation 
        = [HGSInvocationOperation diskInvocationOperationWithTarget:self
                                                           selector:@selector(updateIndexForPath:)
                                                             object:path];
      [[HGSOperationQueue sharedOperationQueue] addOperation:operation];
    } else {
      // Either we've got bad args, or the file we're looking for doesn't
      // exist.
      [self release];
      self = nil;
    }
  }
  return self;  
}

// COV_NF_START
- (void)dealloc {
  // plugins are never unloaded
  [fileKQueue_ release];
  [browserTypeName_ release];
  [super dealloc];
}
// COV_NF_END

- (void)indexResultNamed:(NSString *)name 
                     URL:(NSURL *)url
         otherAttributes:(NSDictionary *)otherAttributes {
  if (!name || !url) {
    HGSLogDebug(@"Missing name (%@) or url (%@) for bookmark. Source %@",
                name, url, self);
    return;
  }
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSUnderHomeRankFlag 
                         | eHGSNameMatchRankFlag];
  NSMutableDictionary *attributes
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       [url absoluteString], kHGSObjectAttributeSourceURLKey,
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       @"star-flag", kHGSObjectAttributeFlagIconNameKey,
       nil];
  if (otherAttributes) {
    [attributes addEntriesFromDictionary:otherAttributes];
  }
  
  NSString* type = [NSString stringWithFormat:@"%@.%@", 
                    kHGSTypeWebBookmark, browserTypeName_];
  HGSResult* result 
    = [HGSResult resultWithURL:url
                          name:name
                          type:type
                        source:self
                    attributes:attributes];
  [self indexResult:result];
}

- (void)fileChanged:(GTMFileSystemKQueue *)queue 
              event:(GTMFileSystemKQueueEvents)event {
  [[self retain] autorelease];
  [self clearResultIndex];
  [self updateIndexForPath:[queue path]];
}

- (NSURL *)domainURLForURLString:(NSString *)urlString {
  // This is parsed manually rather than round-tripped through NSURL so that
  // we can get domains from invalid URLs (like Camino search bookmarks).
  NSURL *url = nil;
  NSRange schemeEndRange = [urlString rangeOfString:@"://"];
  if (schemeEndRange.location != NSNotFound) {
    NSUInteger domainStartIndex = NSMaxRange(schemeEndRange);
    NSRange domainRange = NSMakeRange(domainStartIndex,
                                      [urlString length] - domainStartIndex);
    NSRange pathStartRange = [urlString rangeOfString:@"/"
                                            options:0
                                              range:domainRange];
    NSString* domainString;
    if (pathStartRange.location == NSNotFound) {
      domainString = urlString;
    } else {
      domainString = [urlString substringToIndex:pathStartRange.location];
    }
    url = [NSURL URLWithString:domainString];
  }
  return url;
}

// COV_NF_START
- (void)updateIndexForPath:(NSString *)path {
  HGSAssert(NO, @"Must be overridden by subclasses!");  
}
// COV_NF_END

@end
