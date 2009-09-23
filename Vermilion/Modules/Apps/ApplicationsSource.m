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

// Indexes Applications and Preference Panes. Allows pivoting on the
// System Preferences to find preference panes inside it.

@interface ApplicationsSource : HGSMemorySearchSource {
 @private
  NSMetadataQuery *query_;
  NSCondition *condition_;
  BOOL indexing_;
}

- (void)startQuery:(NSTimer *)timer;

@end

static NSString *const kApplicationSourcePredicateString 
  = @"(kMDItemContentTypeTree == 'com.apple.application') "
    @"|| (kMDItemContentTypeTree == 'com.apple.systempreference.prefpane')";

@implementation ApplicationsSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // kick off a spotlight query for applications. it'll be a standing
    // query that we keep around for the duration of this source.
    query_ = [[NSMetadataQuery alloc] init];
    NSPredicate *predicate 
      = [NSPredicate predicateWithFormat:kApplicationSourcePredicateString];
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
    condition_ = [[NSCondition alloc] init];
    if (![self loadResultsCache]) {
      // Cache didn't exist, hold queries until the first indexing run completes
      [self startQuery:nil];
    } else {
      // TODO(alcor): this retains us even if everyone else releases. 
      // add a teardown function for sources where they can invalidate
      [self performSelector:@selector(startQuery:) 
                 withObject:nil
                 afterDelay:10];
    }
  }
  return self;
}

- (void)dealloc {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [query_ release];
  [condition_ release];
  [super dealloc];
}

- (void)startQuery:(NSTimer *)timer {
  [query_ startQuery];
}

- (BOOL)pathIsPrefPane:(NSString *)path {
  NSString *ext = [path pathExtension];
  return [ext caseInsensitiveCompare:@"prefPane"] == NSOrderedSame;
}

// Returns YES if the application is something a user would never realistically
// want to have show up as a match.
// TODO(stuartmorgan): make this more intelligent (e.g., suppressing pref
// panes and duplicate apps from the non-boot volume).
- (BOOL)pathShouldBeSuppressed:(NSString *)path {
  BOOL suppress = NO;
  if (!path) {
    suppress = YES;
  } else if ([self pathIsPrefPane:path]) {
    // Only match pref panes if they are installed.
    // TODO(stuartmorgan): This should actually be looking specifically in the
    // boot volume
    suppress = ([path rangeOfString:@"/PreferencePanes/"].location 
                == NSNotFound);
  } else if ([path rangeOfString:@"/Library/"].location != NSNotFound) {
    // TODO(alcor): verify that these paths actually exist, or filter on bndleid
    NSArray *whitelist
      = [NSArray arrayWithObjects:
         @"/System/Library/CoreServices/Software Update.app",
         @"/System/Library/CoreServices/Finder.app",
         @"/System/Library/CoreServices/Archive Utility.app",
         @"/System/Library/CoreServices/Screen Sharing.app",
         @"/System/Library/CoreServices/Network Diagnostics.app",
         @"/System/Library/CoreServices/Network Setup Assistant.app",
         @"/System/Library/CoreServices/Installer.app",
         @"/System/Library/CoreServices/Kerberos.app",
         @"/System/Library/CoreServices/Dock.app",
         nil];
    if (![whitelist containsObject:path]) suppress = YES;
  } else if ([path rangeOfString:@"/Developer/Platforms/"].location != NSNotFound) {
    suppress = YES;
  }
  return suppress;
}

- (void)parseResultsOperation:(NSMetadataQuery *)query {
  [condition_ lock];
  indexing_ = YES;
  [self clearResultIndex];
  NSArray *mdAttributeNames = [NSArray arrayWithObjects:
                               (NSString *)kMDItemTitle,
                               (NSString *)kMDItemDisplayName,
                               (NSString *)kMDItemPath,
                               (NSString *)kMDItemLastUsedDate,
                               (NSString *)kMDItemCFBundleIdentifier,
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
  NSString *prefPaneString = HGSLocalizedString(@"Preference Pane", 
                                                @"A label denoting that this "
                                                @"result is a System "
                                                @"Preference Pane");
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
    
    NSString *fileSystemName = [path lastPathComponent];
    fileSystemName = [fileSystemName stringByDeletingPathExtension];
    if (!name) {
      name = fileSystemName;
    }
        
    if ([self pathIsPrefPane:path]) {
      // Some prefpanes forget to localize their names and end up with
      // foo.prefpane as their kMDItemTitle. foo.prefPane Preference Pane looks
      // ugly.
      if ([self pathIsPrefPane:name]) {
        name = [name stringByDeletingPathExtension];
      }
      name = [name stringByAppendingFormat:@" %@", prefPaneString];
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

    // Grab a bundle ID
    NSString *bundleID 
      = [mdAttributes objectForKey:(NSString *)kMDItemCFBundleIdentifier];
    if (bundleID) {
      [attributes setObject:bundleID forKey:kHGSObjectAttributeBundleIDKey];
    }
    
    // create a HGSResult to talk to the rest of the application
    HGSResult *hgsResult 
      = [HGSResult resultWithFilePath:path
                          source:self
                      attributes:attributes];
    
    // add it to the result array for searching
    // By adding the display name and the file system name this should help
    // with the can't find Quicksilver problem because somebody decided
    // to get fancy and encode Quicksilver's name in fancy high UTF codes.
    if (![name isEqualToString:fileSystemName]) {
      [self indexResult:hgsResult
                   name:name
              otherTerm:fileSystemName];
    } else {
      [self indexResult:hgsResult];
    }
  }
  
  // Due to a bug in 10.5.6 we can't find the network prefpane
  // add it by hand
  // Radar 6495591 Can't find network prefpane using spotlight
  NSString *networkPath = @"/System/Library/PreferencePanes/Network.prefPane";
  NSBundle *networkBundle = [NSBundle bundleWithPath:networkPath];

  if (networkBundle) {
    NSString *name 
      = [networkBundle objectForInfoDictionaryKey:@"NSPrefPaneIconLabel"];
    name = [name stringByAppendingFormat:@" %@", prefPaneString];
    // Unfortunately last used date is hidden from us.
    [attributes removeObjectForKey:kHGSObjectAttributeLastUsedDateKey];
    [attributes setObject:@"com.apple.preference.network"
                   forKey:kHGSObjectAttributeBundleIDKey];
    NSURL *url = [NSURL fileURLWithPath:networkPath];
    HGSResult *hgsResult 
      = [HGSResult resultWithURI:[url absoluteString]
                            name:name
                            type:kHGSTypeFileApplication
                          source:self
                      attributes:attributes];

    [self indexResult:hgsResult];
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
    NSOperation *op 
      = [[[NSInvocationOperation alloc] initWithTarget:self
                                              selector:@selector(parseResultsOperation:)
                                                object:query]
         autorelease];
    [[HGSOperationQueue sharedOperationQueue] addOperation:op];
  }
}

#pragma mark -

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  if (isValid) {
    HGSResult *pivotObject = [query pivotObject];
    if (pivotObject) {
      NSString *appName = [[pivotObject filePath] lastPathComponent];
      isValid = [appName isEqualToString:@"System%20Preferences.app"];
    }
  }
  return isValid;
}

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

- (HGSResult *)preFilterResult:(HGSResult *)result 
               matchesForQuery:(HGSQuery*)query
                   pivotObject:(HGSResult *)pivotObject {
  if (pivotObject) {
    // Remove things that aren't preference panes
    NSString *absolutePath = [result filePath];
    if (![self pathIsPrefPane:absolutePath]) {
      result = nil;
    }
  }
  return result;
}
  
@end

