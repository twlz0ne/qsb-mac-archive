//
//  ApplicationsSource.m
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

@interface ApplicationsSource : HGSMemorySearchSource {
@private
  NSMetadataQuery *query_;
  NSCondition *condition_;
  BOOL indexing_;
}
@end

static NSString *const kPredicateString 
  = @"(kMDItemContentTypeTree == 'com.apple.application') "
    @"|| (kMDItemContentTypeTree == 'com.apple.systempreference.prefpane')";

@implementation ApplicationsSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // kick off a spotlight query for applications. it'll be a standing
    // query that we keep around for the duration of this source.
    query_ = [[NSMetadataQuery alloc] init];
    NSPredicate *predicate = [NSPredicate predicateWithFormat:kPredicateString];
    NSArray *scope = [NSArray arrayWithObject:NSMetadataQueryLocalComputerScope];
    [query_ setSearchScopes:scope];
    NSSortDescriptor *desc 
      = [[[NSSortDescriptor alloc] initWithKey:(id)kMDItemLastUsedDate 
                                     ascending:NO] autorelease];
    [query_ setSortDescriptors:[NSArray arrayWithObject:desc]];
    [query_ setPredicate:predicate];
    [query_ setNotificationBatchingInterval:10];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self 
           selector:@selector(queryNotification:) 
               name:nil 
             object:query_];
    [self loadResultsCache];
    if (![resultsArray_ count]) {
      // Cache didn't exist, hold queries until the first indexing run completes
      indexing_ = YES;
    }
    condition_ = [[NSCondition alloc] init];
    [query_ startQuery];
  }
  return self;
}

// Returns YES if the application is something a user would never realistically
// want to have show up as a match.
// TODO(stuartmorgan): make this more intelligent (e.g., suppressing pref
// panes and duplicate apps from the non-boot volume).
- (BOOL)pathShouldBeSuppressed:(NSString *)path {
  BOOL suppress = NO;
  if (!path) {
    suppress = YES;
  } else if ([[path pathExtension] caseInsensitiveCompare:@"prefPane"] 
             == NSOrderedSame) {
    // Only match pref panes if they are installed.
    // TODO(stuartmorgan): This should actually be looking specifically in the
    // boot volume
    suppress = ([path rangeOfString:@"/PreferencePanes/"].location 
                == NSNotFound);
  } else if (([path rangeOfString:@"/Library/"].location != NSNotFound &&
       [path rangeOfString:@"Finder.app"].location == NSNotFound) ||
      [path rangeOfString:@"/Developer/Platforms/"].location != NSNotFound) {
    // Quick and dirty blacklist of some polluting app locations. "/Library/" as 
    // a non-prefix may have false positives, but we punt for now in favor of
    // easily handling of user Library and non-boot volumes.
    suppress = YES;
  }
  return suppress;
}

- (void)parseResultsOperation:(NSMetadataQuery *)query {
  [condition_ lock];
  indexing_ = YES;
  
  [self clearResultIndex];
  NSArray *mdAttributeNames = [NSArray arrayWithObjects:
                               (NSString*)kMDItemTitle,
                               (NSString*)kMDItemDisplayName,
                               (NSString*)kMDItemPath,
                               (NSString*)kMDItemLastUsedDate,
                               nil];
  NSUInteger resultCount = [query resultCount];
  //TODO(dmaclach): remove this once real ranking is in
  NSNumber *rank = [NSNumber numberWithFloat:0.9f];
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSLaunchableRankFlag];
  NSMutableDictionary *attributes
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       rank, kHGSObjectAttributeRankKey,
       nil];
  
  for (NSUInteger i = 0; i < resultCount; ++i) {
    NSMetadataItem *result = [query resultAtIndex:i];
    NSDictionary *mdAttributes = [result valuesForAttributes:mdAttributeNames];
    NSString *path = [mdAttributes objectForKey:(NSString*)kMDItemPath];

    if ([self pathShouldBeSuppressed:path])
      continue;
    
    NSString *name = [mdAttributes objectForKey:(NSString*)kMDItemTitle];
    if (!name) {
      name = [mdAttributes objectForKey:(NSString*)kMDItemDisplayName];
    }
    if (!name) {
      name = [[path lastPathComponent] stringByDeletingPathExtension];
    }
    
    NSString *pathExtension = [path pathExtension];
    if ([pathExtension caseInsensitiveCompare:@"prefPane"] == NSOrderedSame) {
      // Some prefpanes forget to localize their names and end up with
      // foo.prefpane as their kMDItemTitle. foo.prefPane Preference Pane looks
      // ugly.
      NSString *nameExtension = [name pathExtension];
      if ([nameExtension caseInsensitiveCompare:@"prefPane"] == NSOrderedSame) {
        name = [name stringByDeletingPathExtension];
      }
      name = [name stringByAppendingFormat:@" %@",
              HGSLocalizedString(@"Preference Pane", @"Preference Pane")];
    }

    if ([[path pathExtension] caseInsensitiveCompare:@"app"] == NSOrderedSame) {
      name = [name stringByDeletingPathExtension];
    }
        
    // set last used date
    NSDate *date = [mdAttributes objectForKey:(NSString*)kMDItemLastUsedDate];
    if (!date) {
      date = [NSDate distantPast];
    }
    
    [attributes setObject:date forKey:kHGSObjectAttributeLastUsedDateKey];

    // create a HGSObject to talk to the rest of the application
    HGSObject *hgsResult 
      = [HGSObject objectWithIdentifier:[NSURL fileURLWithPath:path]
                                   name:name
                                   type:kHGSTypeFileApplication
                                 source:self
                             attributes:attributes];
    
    // add it to the result array for searching
    [self indexResult:hgsResult
           nameString:name
          otherString:nil];
  }
  
  // Due to a bug in 10.5.6 we can't find the network prefpane
  // add it by hand
  // Radar 6495591 Can't find network prefpane using spotlight
  NSString *networkPath = @"/System/Library/PreferencePanes/Network.prefPane";
  NSBundle *networkBundle = [NSBundle bundleWithPath:networkPath];

  if (networkBundle) {
    NSString *name 
      = [networkBundle objectForInfoDictionaryKey:@"NSPrefPaneIconLabel"];
    
    NSURL *networkURL = [NSURL fileURLWithPath:networkPath];
    // Unfortunately last used date is hidden from us.
    [attributes removeObjectForKey:kHGSObjectAttributeLastUsedDateKey];

    HGSObject *hgsResult 
      = [HGSObject objectWithIdentifier:networkURL
                                   name:name
                                   type:kHGSTypeFileApplication
                                 source:self
                             attributes:attributes];

    [self indexResult:hgsResult
           nameString:name
          otherString:nil];
  } else {
    HGSLog(@"Unable to find Network.prefpane");
  }
  
  indexing_ = NO;
  [condition_ signal];
  [condition_ unlock];
  
  [self saveResultsCache];
  [query enableUpdates];
}

- (void)queryNotification:(NSNotification *)notification {
  NSString *name = [notification name];
  if ([name isEqualToString:NSMetadataQueryDidFinishGatheringNotification]
      || [name isEqualToString:NSMetadataQueryDidUpdateNotification] ) {
    NSMetadataQuery *query = [notification object];
    [query_ disableUpdates]; 
    NSOperation *op = [[[NSInvocationOperation alloc] initWithTarget:self
                                                            selector:@selector(parseResultsOperation:)
                                                              object:query]
                       autorelease];
    [[HGSOperationQueue sharedOperationQueue] addOperation:op];
  }
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [query_ release];
  [condition_ release];
  [super dealloc];
}

#pragma mark -

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  // Put a hold on queries while indexing
  [condition_ lock];
  while (indexing_) {
    [condition_ wait];
  }
  [condition_ signal];
  [condition_ unlock];
  
  [super performSearchOperation:operation];
}

@end

