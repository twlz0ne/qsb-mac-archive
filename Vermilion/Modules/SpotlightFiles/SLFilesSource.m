//
//  SLFilesSource.m
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
#import "GTMNSFileManager+Carbon.h"
#import "GTMMethodCheck.h"
#import "GTMGarbageCollection.h"
#import "GTMExceptionalInlines.h"
#import "GTMNSNumber+64Bit.h"
#import "GTMMethodCheck.h"

static NSString *const kSpotlightSourceReturnIntermediateResultsKey = @"SLFilesSourceReturnIntermediateResults";
static CFStringRef kSpotlightGroupIdAttribute = CFSTR("_kMDItemGroupId");

typedef enum {
  SpotlightGroupMessage = 1,
  SpotlightGroupContact = 2,
  SpotlightGroupSystemPref = 3,
  SpotlightGroupFont = 4,
  SpotlightGroupWeb = 5,
  SpotlightGroupCalendar = 6,
  SpotlightGroupPresentation = 7,
  SpotlightGroupApplication = 8,
  SpotlightGroupDirectory = 9,
  SpotlightGroupMusic = 10,
  SpotlightGroupPDF = 11,
  SpotlightGroupMovie = 12,
  SpotlightGroupImage = 13,
  SpotlightGroupDocument = 14
} SpotlightGroup;

#pragma mark -

@class SLFilesOperation;

@interface SLFilesSource : HGSSearchSource {
 @private
  NSString *utiFilter_;
  BOOL rebuildUTIFilter_;
  NSArray *attributeArray_;
}
- (void)operationReceivedNewResults:(SLFilesOperation*)operation
                   withNotification:(NSNotification*)notification;
- (HGSResult *)hgsResultFromQueryItem:(MDItemRef)item 
                            operation:(SLFilesOperation *)operation;
- (void)operationCompleted:(SLFilesOperation*)operation;
- (void)startSearchOperation:(HGSSearchOperation*)operation;
- (void)extensionPointSourcesChanged:(NSNotification*)notification;
- (NSString *)utiFilter;
- (BOOL)isFilePackageAtPath:(NSString *)path;
@end

@interface SLFilesCreateContext : NSObject {
 @public
  HGSQuery *query_;
  NSString *userHomePath_;
  NSUInteger userHomePathLength_;
  NSString *userDesktopPath_;
  NSUInteger userDesktopPathLength_;
  NSString *userDownloadsPath_;
  NSUInteger userDownloadsPathLength_;
  NSSet *userPersistentItemPaths_;
  NSMutableIndexSet *hiddenFolderCatalogIDs_;
  NSMutableIndexSet *visibleFolderCatalogIDs_;
}
- (id)initWithQuery:(HGSQuery*)query;
// No accessors, this is just a bag of data
@end

@implementation SLFilesCreateContext

GTM_METHOD_CHECK(NSFileManager, gtm_pathFromAliasData:);
GTM_METHOD_CHECK(NSFileManager, gtm_FSRefForPath:);

- (id)initWithQuery:(HGSQuery*)query {
  if (!query) return nil;

  self = [super init];
  if (!self) return nil;

  // Cache query
  query_ = [query retain];

  // Home directories (standardized just in case its a symlink)
  userHomePath_ = [[NSHomeDirectory() stringByStandardizingPath] retain];
  userHomePathLength_ = [userHomePath_ length];
  userDesktopPath_ = [[userHomePath_ stringByAppendingPathComponent:@"Desktop"] retain];
  userDesktopPathLength_ = [userDesktopPath_ length];
  // TODO(aharper): Look up user's download folder preference
  userDownloadsPath_ = [[userHomePath_ stringByAppendingPathComponent:@"Downloads"] retain];
  userDownloadsPathLength_ = [userDownloadsPath_ length];

  // User persistent items
  userPersistentItemPaths_ = [[NSMutableSet set] retain];
  // Read the Dock prefs
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSDictionary *dockPrefs = [ud persistentDomainForName:@"com.apple.dock"];
  NSArray *persistentApps = [dockPrefs objectForKey:@"persistent-apps"];
  NSArray *persistentOthers = [dockPrefs objectForKey:@"persistent-others"];
  NSArray *dockItems 
    = [persistentApps arrayByAddingObjectsFromArray:persistentOthers];
  NSFileManager *fileManager = [NSFileManager defaultManager];
  for (NSDictionary *dockItem in dockItems) {
    NSDictionary *tileData = [dockItem objectForKey:@"tile-data"];
    NSDictionary *fileData = [tileData objectForKey:@"file-data"];
    NSData *aliasData = [fileData objectForKey:@"_CFURLAliasData"];
    NSString *dockItemPath = [fileManager gtm_pathFromAliasData:aliasData];
    if (dockItemPath) {
      [(NSMutableSet *)userPersistentItemPaths_ addObject:dockItemPath];
    }
  }
  // TODO(aharper): Read Finder.app sidebar info as persistent paths
  
  // Index set for tracking hidden folders
  hiddenFolderCatalogIDs_ = [[NSMutableIndexSet indexSet] retain];
  visibleFolderCatalogIDs_ = [[NSMutableIndexSet indexSet] retain];

  // Sanity
  if (!userHomePath_ || !userDesktopPath_ || !userDownloadsPath_ ||
      !userPersistentItemPaths_ ||
       !hiddenFolderCatalogIDs_ || !visibleFolderCatalogIDs_) {
    [self release];
    return nil;
  }

  return self;
} // init

- (void)dealloc {
  [query_ release];
  [userHomePath_ release];
  [userDesktopPath_ release];
  [userDownloadsPath_ release];
  [userPersistentItemPaths_ release];
  [hiddenFolderCatalogIDs_ release];
  [visibleFolderCatalogIDs_ release];
  [super dealloc];
} // dealloc

@end

#pragma mark -

@interface SLFilesOperation : HGSSearchOperation {
 @private
  SLFilesCreateContext* context_;
  // TODO: it's kind of hacky for these and their accessors to be hard-coded
  // into this object when they are only used from outside; maybe there should
  // just be a dictionary of arbitrary context (here or in all operations) that
  // the result could use as it sees fit without coupling implementation.
  NSMutableArray* accumulatedResults_;
  size_t nextQueryItemIndex_;
  BOOL mdQueryFinished_;
}

- (id)initWithQuery:(HGSQuery *)query source:(SLFilesSource *)source;

// Runs |query|, calling back to |callbackHandler|.
- (void)runMDQuery:(MDQueryRef)query;

- (SLFilesCreateContext*)context;
- (void)setContext:(SLFilesCreateContext*)context;
- (size_t)nextQueryItemIndex;
- (void)setNextQueryItemIndex:(size_t)nextIndex;
// Using an accumulator rather than using setResults: directly allows us to
// control the timing of propagation of results to observers.
- (NSMutableArray*)accumulatedResults;

// Callbacksfor MDQuery updates
- (void)queryNotification:(NSNotification*)notification;
@end

@implementation SLFilesOperation
GTM_METHOD_CHECK(NSFileManager, gtm_FSRefForPath:);

- (id)initWithQuery:(HGSQuery *)query 
             source:(SLFilesSource *)source {
  return [super initWithQuery:query source:source];
}

- (void)dealloc {
  [context_ release];
  [accumulatedResults_ release];
  [super dealloc];
}

- (void)main {
  [(SLFilesSource*)[self source] startSearchOperation:self];
}

- (void)runMDQuery:(MDQueryRef)query {
  if (accumulatedResults_) {
    HGSLog(@"accumulatedResults_ should be empty");
  }
  accumulatedResults_ = [[NSMutableArray alloc] init];
  nextQueryItemIndex_ = 0;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self
         selector:@selector(queryNotification:)
             name:(NSString *)kMDQueryDidFinishNotification
           object:(id)query];
  [nc addObserver:self
         selector:@selector(queryNotification:)
             name:(NSString *)kMDQueryProgressNotification
           object:(id)query];
  mdQueryFinished_ = NO;
  if (MDQueryExecute(query, 0)) {
    // block until this query is done to make it appear synchronous. sleep for a
    // second and then check again. |queryComplete_| is set on
    // the main thread which is fine since we're not writing to it here.
    NSRunLoop* loop = [NSRunLoop currentRunLoop];
    while (!mdQueryFinished_ && ![self isCancelled]) {
      NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
      [loop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
      [innerPool release];
    }
  } else {
    CFStringRef queryString = MDQueryCopyQueryString(query);
    // If something goes wrong, let the handler think we just completed with
    // no results so that we get cleaned up correctly.
    HGSLog(@"Failed to start mdquery: %@", queryString);
    CFRelease(queryString);
  }
  [nc removeObserver:self
                name:nil
              object:(id)query];
  MDQueryStop(query);
  [(SLFilesSource*)[self source] operationCompleted:self];
}

- (void)queryNotification:(NSNotification*)notification {
  NSString *name = [notification name];
  if ([name isEqualToString:(NSString *)kMDQueryProgressNotification]) {
    [(SLFilesSource*)[self source] operationReceivedNewResults:self 
                                              withNotification:notification];
  } else if ([name isEqualToString:(NSString*)kMDQueryDidFinishNotification]) {
    mdQueryFinished_ = YES;
  }
}

- (SLFilesCreateContext*)context {
  return context_;
}

- (void)setContext:(SLFilesCreateContext*)context {
  [context_ autorelease];
  context_ = [context retain];
}

- (size_t)nextQueryItemIndex {
  return nextQueryItemIndex_;
}

- (void)setNextQueryItemIndex:(size_t)nextIndex {
  nextQueryItemIndex_ = nextIndex;
}

- (NSMutableArray*)accumulatedResults {
  return [[accumulatedResults_ retain] autorelease];
}

- (NSString *)displayName {
  return HGSLocalizedString(@"Spotlight", 
                            @"A label denoting a Spotlight result.");
}

@end


@implementation SLFilesSource

GTM_METHOD_CHECK(NSNumber, gtm_numberWithCGFloat:);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSDictionary *defaultsDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNumber numberWithBool:NO],
                                  kSpotlightSourceReturnIntermediateResultsKey,
                                  nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDict];
    
    // we need to build the filter
    rebuildUTIFilter_ = YES;
    
    NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
    HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
    [dc addObserver:self
           selector:@selector(extensionPointSourcesChanged:)
               name:kHGSExtensionPointDidAddExtensionNotification
             object:sourcesPoint];
    [dc addObserver:self
           selector:@selector(extensionPointSourcesChanged:)
               name:kHGSExtensionPointDidRemoveExtensionNotification
             object:sourcesPoint];
    
    attributeArray_ = [[NSArray alloc] initWithObjects:
                       (NSString *)kMDItemPath,
                       (NSString *)kMDItemTitle,
                       (NSString *)kMDItemLastUsedDate,
                       (NSString *)kMDItemContentType,
                       (NSString *)kSpotlightGroupIdAttribute,
                       nil];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [utiFilter_ release];
  [attributeArray_ release];
  [super dealloc];
}

// returns an operation to search this source for |query| and posts notifs
// to |observer|.
- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query {
  SLFilesOperation *searchOp
    = [[[SLFilesOperation alloc] initWithQuery:query source:self] autorelease];
  return searchOp;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = NO;
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    if ([pivotObject conformsToType:kHGSTypeContact]) {
      NSString *name = [pivotObject valueForKey:kHGSObjectAttributeNameKey];
      if (name) {
        isValid = YES;
      } else {
        NSString *emailAddress 
          = [pivotObject valueForKey:kHGSObjectAttributeContactEmailKey];
        if (emailAddress) {
          isValid = YES;
        }
      }
    }
  } else {
    // Since Spotlight can return a lot of stuff, we only run the query if
    // it is at least 5 characters long.
    isValid = [[query rawQueryString] length] >= 5 ? YES : NO;
  }
  return isValid;
}

// run through the list of applications looking for the ones that match
// somewhere in the title. When we find them, apply a local boost if possible.
// When we're done, sort based on ranking.
- (void)startSearchOperation:(HGSSearchOperation*)operation {
  
  NSMutableArray *predicateSegments = [NSMutableArray array];

  HGSQuery* query = [operation query];
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    if ([pivotObject conformsToType:kHGSTypeContact]) {
      NSString *emailAddress = [pivotObject valueForKey:kHGSObjectAttributeContactEmailKey];
      NSString *name = [pivotObject valueForKey:kHGSObjectAttributeNameKey];
      if (name && emailAddress) {
        [predicateSegments addObject:[NSString stringWithFormat:@"(* = \"%@\"cdw || * = \"%@\"cdw)",
                                      name, emailAddress]];
      } else if (name) {
        [predicateSegments addObject:[NSString stringWithFormat:@"(* = \"%@\"cdw)",
                                      name]];
      } else if (emailAddress) {
        [predicateSegments addObject:[NSString stringWithFormat:@"(* = \"%@\"cdw)",
                                      emailAddress]];
      } else {
        // Can't pivot off a contact with no name or email address
        return;
      }
    } else {
      // Unrecognized type of pivotObject
      return;
    }
  }

  NSString *const kPredicateString = @"(* = \"%@*\"cdw || kMDItemTextContent = \"%@*\"cdw)";

  NSString *rawQuery = [query rawQueryString];
  NSString *predicateSegment  = [NSString stringWithFormat:kPredicateString, 
                                 rawQuery, rawQuery];
  [predicateSegments addObject:predicateSegment];

  // if we have a uti filter, add it
  NSString *utiFilter = [self utiFilter];
  if (utiFilter) {
    [predicateSegments addObject:utiFilter];
  }

  // Make the final predicate string
  NSString *predicateString = [predicateSegments componentsJoinedByString:@" && "];

  // Build the query
  MDQueryRef mdQuery = MDQueryCreate(kCFAllocatorDefault,
                                     (CFStringRef)predicateString,
                                     (CFArrayRef)attributeArray_,
                                     // We must not sort here because it means that the
                                     // result indexing will be stable (we leverage this
                                     // behavior elsewhere)
                                     NULL);
  if (!mdQuery) return;

  SLFilesOperation* filesOperation = (SLFilesOperation*)operation;
  SLFilesCreateContext* context 
    = [[[SLFilesCreateContext alloc] initWithQuery:query] autorelease];
  [filesOperation setContext:context];

  // Run
  [filesOperation runMDQuery:mdQuery];
  // setting results and marking as finished are already handled by the callback
  CFRelease(mdQuery);
}

- (void)operationReceivedNewResults:(SLFilesOperation*)operation
                   withNotification:(NSNotification*)notification {
  NSMutableArray *accumulatedResults = [operation accumulatedResults];
  MDQueryRef mdQuery = (MDQueryRef)[notification object];

  // TODO(pink) - handle deletes and updates from the notification
  BOOL rescrapeAllResults = NO;

  // With deletes and updates done, its time to go looking for new results
  CFIndex currentCount = MDQueryGetResultCount(mdQuery);

  if (rescrapeAllResults) {
    // TODO(pink) - handle deletes and updates
  } else {
    // No rescrape needed so we can do the fast thing

    for (CFIndex i = [operation nextQueryItemIndex]; 
         i < currentCount && ![operation isCancelled]; 
         i++) {
      MDItemRef mdItem = (MDItemRef)MDQueryGetResultAtIndex(mdQuery, i);
      if (mdItem) {
        HGSResult *result = [self hgsResultFromQueryItem:mdItem 
                                               operation:operation];
        if (result) {
          [accumulatedResults addObject:result];
        }
      }
    }
  }

  // Next time around we can start from the current result count
  [operation setNextQueryItemIndex:currentCount];

  // We don't do incremental updates, because we don't want poor results to
  // get locked into the UI.
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  if ([ud boolForKey:kSpotlightSourceReturnIntermediateResultsKey]) {
    HGSLogDebug(@"... Spotlight complete got %d intermediate file results",
                [accumulatedResults count]);
    [operation setResults:accumulatedResults];
  }
}

- (HGSResult *)hgsResultFromQueryItem:(MDItemRef)item 
                            operation:(SLFilesOperation *)operation {
  if ([operation isCancelled]) return nil;
  SLFilesCreateContext* context = [operation context];
  if (!context) return nil;
  
  NSString *iconFlagName = nil;
  
  HGSResult* result = nil;
  NSDictionary *attributes 
    = GTMCFAutorelease(MDItemCopyAttributes(item, (CFArrayRef)attributeArray_));
  // Path is used a lot but can't be obtained from the query
  NSString *path = [attributes objectForKey:(NSString *)kMDItemPath];
  // Don't use fileURLWithPath here because it hits the disk.
  NSString *uriPath = [path stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  NSString *uri = nil;
  if (uriPath) {
    uri = [@"file://" stringByAppendingString:uriPath];
  }
  BOOL isURL = NO;
  NSString *contentType
    = [attributes objectForKey:(NSString *)kMDItemContentType];
  NSString *resultType = kHGSTypeFile;
  if (contentType && uri) {
    NSNumber *typeGroupNumber
      = [attributes objectForKey:(NSString *)kSpotlightGroupIdAttribute];
    int typeGroup = [typeGroupNumber intValue];

    // TODO: further subdivide the result types.
    switch (typeGroup) {
      case SpotlightGroupApplication:
        // TODO: do we want a different type for prefpanes?
        resultType = kHGSTypeFileApplication; 
        break;
      case SpotlightGroupMessage:
        resultType = kHGSTypeEmail;
        break;
      case SpotlightGroupContact:
        resultType = kHGSTypeContact;
        break;
      case SpotlightGroupWeb:
        resultType = HGS_SUBTYPE(kHGSTypeWebpage, @"fileloc");
        isURL = YES;
        uriPath = GTMCFAutorelease(MDItemCopyAttribute(item, kMDItemURL));
        if (uriPath) {
          uri = uriPath;
        }
        // TODO(alcor): are there any items that are not history?
        iconFlagName = @"history-flag";
        break;
      case SpotlightGroupPDF:
        resultType = kHGSTypeFile;
        break;
      case SpotlightGroupImage:
        resultType = kHGSTypeFileImage;
        break;
      case SpotlightGroupMovie:
        resultType = kHGSTypeFileMovie;
        break;
      case SpotlightGroupMusic:
        resultType = kHGSTypeFileMusic;
        break;
      case SpotlightGroupDirectory:
        resultType = kHGSTypeDirectory;
        if ([self isFilePackageAtPath:path]) {
          resultType = kHGSTypeFile;
        }
        break;
      case SpotlightGroupDocument:
      case SpotlightGroupPresentation:
      case SpotlightGroupFont:
      case SpotlightGroupCalendar:
      default:
        if (UTTypeConformsTo((CFStringRef)contentType, kUTTypePlainText)) {
          resultType = kHGSTypeTextFile;
        } else {
          resultType = kHGSTypeFile;
        }
        break;
    }
  } else {
    CFStringRef description = CFCopyDescription(item);
    HGSLogDebug(@"%@ tossing result, no content type", description);
    CFRelease(description);
    return nil;
  }
  
  // Cache values the query has already copied
  NSDate *lastUsedDate 
    = [attributes objectForKey:(NSString *)kMDItemLastUsedDate];
  if (!lastUsedDate) {
    lastUsedDate = [NSDate distantPast];
  }
  NSString *name 
    = [attributes objectForKey:(NSString *)kMDItemTitle]; 
  if (!name) {
    name = GTMCFAutorelease(MDItemCopyAttribute(item, kMDItemDisplayName));
    if (!name) {
      name = GTMCFAutorelease(MDItemCopyAttribute(item, kMDItemFSName));
    }
  }
    
  NSString *normalizedString = [context->query_ normalizedQueryString];
  CGFloat rank = HGSScoreTermForItem(normalizedString, name, NULL);

  NSMutableDictionary *hgsAttributes 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       lastUsedDate, kHGSObjectAttributeLastUsedDateKey,
       iconFlagName, kHGSObjectAttributeFlagIconNameKey,
       [NSNumber gtm_numberWithCGFloat:rank], kHGSObjectAttributeRankKey,
       nil];
  if (isURL) {
    [hgsAttributes setObject:uri forKey:kHGSObjectAttributeSourceURLKey];
  }
  
  result = [HGSResult resultWithURI:uri
                               name:name
                               type:resultType
                             source:self
                         attributes:hgsAttributes];
  return result;
}

- (void)operationCompleted:(SLFilesOperation*)operation {
  if (![operation isCancelled]) {
    NSMutableArray *accumulatedResults = [operation accumulatedResults];
    [operation setResults:accumulatedResults];
  }
}

- (void)extensionPointSourcesChanged:(NSNotification*)notification {
  // since the notifications can come in batches as we load things (and if/when
  // we support enable/disable they too could come in batches), we just set a
  // flag to rebuild the string next time it's needed.
  rebuildUTIFilter_ = YES;
}

- (NSString *)utiFilter {
  // do we need to rebuild it?
  if (rebuildUTIFilter_) {
    // reset the flag first to avoid threading races w/o needing an @sync
    rebuildUTIFilter_ = NO;

    // collect the utis
    NSMutableSet *utiSet = [NSMutableSet set];
    NSArray *extensions = [[HGSExtensionPoint sourcesPoint] extensions];
    for (HGSSearchSource *searchSource in extensions) {
      NSSet *utis = [searchSource utisToExcludeFromDiskSources];
      if (utis) {
        [utiSet unionSet:utis];
      }
    }
    // make the filter string
    NSMutableArray *utiFilterArray = [NSMutableArray arrayWithCapacity:[utiSet count]];
    for (NSString *uti in utiSet) {
      NSString *utiFilterStr
        = [NSString stringWithFormat:@"( kMDItemContentType != '%@' )", uti];
      [utiFilterArray addObject:utiFilterStr];
    }
    NSString *utiFilter = [utiFilterArray componentsJoinedByString:@" && "];
    if ([utiFilter length] == 0) {
      // if there is no filter, we use nil to gate adding it when we run queries
      utiFilter = nil;
    }
    // save it off
    @synchronized(self) {
      [utiFilter_ release];
      utiFilter_ = [utiFilter retain];
      HGSLogDebug(@"Spotlight Source UTI Filter = %@", utiFilter_);
    }
  }

  NSString *result;
  @synchronized(self) {
    // We retain/autorelease to tie the lifetime of the current value to the
    // current thread's autorelease pool.  This way if the string gets updated
    // after we have returned it, the object won't disappear on the caller.
    result = [[utiFilter_ retain] autorelease];
  }
  return result;
}

- (BOOL)isFilePackageAtPath:(NSString *)path {
  NSFileManager *fileManager = [NSFileManager defaultManager];
  FSRef *pathRef = [fileManager gtm_FSRefForPath:path];
  if (!pathRef) return NO;
  
  LSItemInfoRecord infoRecord;
  OSStatus lsErr = LSCopyItemInfoForRef(pathRef, 
                                        kLSRequestBasicFlagsOnly, 
                                        &infoRecord);
  if (lsErr != noErr) {
    HGSLogDebug(@"LSCopyItemInfoForRef returned error %ld.", lsErr);
    return NO;
  }
  return (infoRecord.flags & kLSItemInfoIsPackage) != 0;
}

#pragma mark -

- (MDItemRef)mdItemRefForResult:(HGSResult*)result {
  MDItemRef mdItem = nil;
  NSURL *url = [result url];
  if ([url isFileURL]) {
    mdItem = MDItemCreate(kCFAllocatorDefault, (CFStringRef)[url path]);
    GTMCFAutorelease(mdItem);
  }
  return mdItem;
}

- (id)provideValueForKey:(NSString*)key result:(HGSResult*)result {
  MDItemRef mdItemRef = nil;
  id value = nil;

  if ([key isEqualToString:kHGSObjectAttributeIconKey]) {
    NSURL *url = [result url];
    if (![url isFileURL]) {
      value = [NSImage imageNamed:@"blue-nav"];
    }
  }
  if ([key isEqualToString:kHGSObjectAttributeEmailAddressesKey] &&
      (mdItemRef = [self mdItemRefForResult:result])) {
    NSMutableArray *allEmails = nil;
    NSArray *emails
      = GTMCFAutorelease(MDItemCopyAttribute(mdItemRef,
                                             kMDItemAuthorEmailAddresses));
    if (emails) {
      allEmails = [NSMutableArray arrayWithArray:emails];
    }
    emails = GTMCFAutorelease(MDItemCopyAttribute(mdItemRef,
                                                  kMDItemRecipientEmailAddresses));

    if (emails) {
      if (allEmails) {
        [allEmails addObjectsFromArray:emails];
      } else {
        allEmails = [NSMutableArray arrayWithArray:emails];
      }
    }
    if (allEmails) {
      value = allEmails;
    }
  } else if ([key isEqualToString:kHGSObjectAttributeContactsKey] &&
             (mdItemRef = [self mdItemRefForResult:result])) {
    NSMutableArray *allPeople = nil;
    NSArray *people = GTMCFAutorelease(MDItemCopyAttribute(mdItemRef,
                                                           kMDItemAuthors));
    if (people) {
      allPeople = [NSMutableArray arrayWithArray:people];
    }
    people = GTMCFAutorelease(MDItemCopyAttribute(mdItemRef, kMDItemRecipients));
    if (people) {
      if (allPeople) {
        [allPeople addObjectsFromArray:people];
      } else {
        allPeople = [NSMutableArray arrayWithArray:people];
      }
    }
    if (allPeople) {
      value = allPeople;
    }
  }
  if (!value) {
    value = [super provideValueForKey:key result:result];
  }
  
  return value;
}

@end
