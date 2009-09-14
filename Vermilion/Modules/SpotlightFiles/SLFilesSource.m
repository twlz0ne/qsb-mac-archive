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

#import "SLFilesSource.h"
#import "GTMMethodCheck.h"
#import "GTMGarbageCollection.h"
#import "GTMNSNumber+64Bit.h"
#import "GTMMethodCheck.h"

static NSString *const kSpotlightSourceReturnIntermediateResultsKey 
  = @"SLFilesSourceReturnIntermediateResults";

// Borrowing some private stuff from spotlight here.
static CFStringRef kSpotlightGroupIdAttribute 
  = CFSTR("_kMDItemGroupId");
extern CFStringRef _MDQueryCreateQueryString(CFAllocatorRef allocator, 
                                             CFStringRef query);
typedef enum {
  SpotlightGroupMessage = 1,
  SpotlightGroupContact = 2,
  SpotlightGroupSystemPref = 3,
  SpotlightGroupFont = 4,
  SpotlightGroupWeb = 5,
  SpotlightGroupCalendar = 6,
  SpotlightGroupMovie = 7,
  SpotlightGroupApplication = 8,
  SpotlightGroupDirectory = 9,
  SpotlightGroupMusic = 10,
  SpotlightGroupPDF = 11,
  SpotlightGroupPresentation = 12,
  SpotlightGroupImage = 13,
  SpotlightGroupDocument = 14
} SpotlightGroup;

@interface SLFilesOperation ()
@property (readwrite, assign, nonatomic) CFIndex nextQueryItemIndex;
@end

@implementation SLFilesOperation
@synthesize nextQueryItemIndex = nextQueryItemIndex_;

- (void)dealloc {
  [accumulatedResults_ release];
  [super dealloc];
}

- (void)main {
  [(SLFilesSource*)[self source] startSearchOperation:self];
}

- (void)runMDQuery:(MDQueryRef)query {
  HGSAssert(!accumulatedResults_, @"accumulatedResults_ should be empty");
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
    // COV_NF_START
    CFStringRef queryString = MDQueryCopyQueryString(query);
    // If something goes wrong, let the handler think we just completed with
    // no results so that we get cleaned up correctly.
    HGSLog(@"Failed to start mdquery: %@", queryString);
    CFRelease(queryString);
    // COV_NF_END
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

- (NSMutableArray*)accumulatedResults {
  return [[accumulatedResults_ retain] autorelease];
}

@end

@interface SLFilesSource ()
@property (readonly, nonatomic) NSString *utiFilter;
@end

@implementation SLFilesSource
@synthesize utiFilter = utiFilter_;
@synthesize attributeArray = attributeArray_;

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
    isValid = [pivotObject conformsToType:kHGSTypeContact];
  } else {
    // Since Spotlight can return a lot of stuff, we only run the query if
    // it is at least 5 characters long.
    isValid = [[query rawQueryString] length] >= 5;
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
    HGSAssert([pivotObject conformsToType:kHGSTypeContact], 
              @"Bad pivotObject: %@", pivotObject);
              
    NSString *emailAddress = [pivotObject valueForKey:kHGSObjectAttributeContactEmailKey];
    NSString *name = [pivotObject valueForKey:kHGSObjectAttributeNameKey];
    HGSAssert(name, 
              @"How did we get a pivotObject without a name? %@", 
              pivotObject);
    NSString *predString = nil;
    if (emailAddress) {
      predString 
        = [NSString stringWithFormat:@"(* = \"%@\"cdw || * = \"%@\"cdw)",
           name, emailAddress];
    } else {
      predString = [NSString stringWithFormat:@"(* = \"%@\"cdw)", name];
    } 
    [predicateSegments addObject:predString];
  }

  NSString *rawQueryString = [query rawQueryString];
  NSString *spotlightString
    = GTMCFAutorelease(_MDQueryCreateQueryString(NULL,
                                                 (CFStringRef)rawQueryString));
  [predicateSegments addObject:spotlightString];

  // if we have a uti filter, add it
  NSString *utiFilter = [self utiFilter];
  if (utiFilter) {
    [predicateSegments addObject:utiFilter];
  }

  // Make the final predicate string
  NSString *predicateString 
    = [predicateSegments componentsJoinedByString:@" && "];

  NSLog(@"Predicate String: %@", predicateString);
  // Build the query
  MDQueryRef mdQuery 
    = MDQueryCreate(kCFAllocatorDefault,
                    (CFStringRef)predicateString,
                    (CFArrayRef)attributeArray_,
                    // We must not sort here because it means that the
                    // result indexing will be stable (we leverage this
                    // behavior elsewhere)
                    NULL);
  if (!mdQuery) return;
  
  MDQueryBatchingParams params = MDQueryGetBatchingParameters(mdQuery);
  params.first_max_ms = 1000;
  params.progress_max_ms = 1000;
  MDQuerySetBatchingParameters(mdQuery, params);
  
  SLFilesOperation* filesOperation = (SLFilesOperation*)operation;

  // Run
  [filesOperation runMDQuery:mdQuery];
  // setting results and marking as finished are already handled by the callback
  CFRelease(mdQuery);
}

- (void)operationReceivedNewResults:(SLFilesOperation*)operation
                   withNotification:(NSNotification*)notification {
  NSMutableArray *accumulatedResults = [operation accumulatedResults];
  MDQueryRef mdQuery = (MDQueryRef)[notification object];
  CFIndex currentCount = MDQueryGetResultCount(mdQuery);
  CFIndex oldCount = [operation nextQueryItemIndex];
  if (currentCount != oldCount) {
    for (CFIndex i = oldCount; 
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
    // Next time around we can start from the current result count
    [operation setNextQueryItemIndex:currentCount];
    [operation setResults:accumulatedResults];
  }
}

- (HGSResult *)hgsResultFromQueryItem:(MDItemRef)item 
                            operation:(SLFilesOperation *)operation {
  HGSResult *result = nil;
  if (![operation isCancelled]) {
    result = [[[SLHGSResult alloc] initWithMDItem:item operation:operation] autorelease];
  }
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
        = [NSString stringWithFormat:@"( kMDItemContentTypeTree != '%@' )", uti];
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

@implementation SLHGSResult
- (id)initWithMDItem:(MDItemRef)mdItem 
           operation:(SLFilesOperation *)operation {
  SLFilesSource *source = (SLFilesSource *)[operation source];
  if (!mdItem || !source) {
    return nil;
  }
  NSString *uri = [NSString stringWithFormat:@"spotlightresult://%p", mdItem];
  NSString *iconFlagName = nil;
  NSArray *attributeArray = [source attributeArray];
  NSDictionary *attributes = GTMCFAutorelease(MDItemCopyAttributes(mdItem, 
                                              (CFArrayRef)attributeArray));
  NSString *name = [attributes objectForKey:(NSString *)kMDItemTitle]; 
  if (!name) {
    name = GTMCFAutorelease(MDItemCopyAttribute(mdItem, kMDItemDisplayName));
    if (!name) {
      name = GTMCFAutorelease(MDItemCopyAttribute(mdItem, kMDItemFSName));  // COV_NF_LINE
    }
  }  
  BOOL isURL = NO;
  NSString *contentType
    = [attributes objectForKey:(NSString *)kMDItemContentType];
  NSString *resultType = kHGSTypeFile;
  if (contentType) {
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
        resultType = kHGSTypeWebHistory;
        isURL = YES;
        NSString *uriPath = GTMCFAutorelease(MDItemCopyAttribute(mdItem, 
                                                                 kMDItemURL));
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
        break;
      case SpotlightGroupDocument:
      case SpotlightGroupPresentation:
      case SpotlightGroupFont:
      case SpotlightGroupCalendar:
      default: {
          if ([[name pathExtension] caseInsensitiveCompare:@"webloc"] 
              == NSOrderedSame) {
            resultType = kHGSTypeWebBookmark;
          } else if (UTTypeConformsTo((CFStringRef)contentType, 
                                      kUTTypePlainText)) {
            resultType = kHGSTypeTextFile;
          } else {
            resultType = kHGSTypeFile;
          }
        }
        break;
    }
  }
  
  // Cache values the query has already copied
  NSDate *lastUsedDate 
    = [attributes objectForKey:(NSString *)kMDItemLastUsedDate];
  if (!lastUsedDate) {
    lastUsedDate = [NSDate distantPast];  // COV_NF_LINE
  }
  NSString *tokenizedName = [HGSTokenizer tokenizeString:name];
  NSString *normalizedString = [[operation query] normalizedQueryString];
  CGFloat rank = HGSScoreTermForItem(tokenizedName, normalizedString, NULL);
  
  // TODO(mrossetti): Fix this once
  // http://code.google.com/p/qsb-mac/issues/detail?id=758 
  // is fixed. Right now 20 is just a guess.
  if (rank < 20) rank = 20;
  
  NSNumber *nsRank = [NSNumber gtm_numberWithCGFloat:rank];
  NSDictionary *hgsAttributes 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       lastUsedDate, kHGSObjectAttributeLastUsedDateKey,
       nsRank, kHGSObjectAttributeRankKey,
       (isURL ? uri : nil), kHGSObjectAttributeSourceURLKey,
       iconFlagName, kHGSObjectAttributeFlagIconNameKey,
       nil];
  if ((self = [super initWithURI:uri
                            name:name
                            type:resultType
                          source:source
                      attributes:hgsAttributes])) {
    mdItem_ = (MDItemRef)CFRetain(mdItem);
  }
  return self;
}

- (void)dealloc {
  if (mdItem_) {
    CFRelease(mdItem_);
  }
  [super dealloc];
}

- (NSString *)filePath {
  return GTMCFAutorelease(MDItemCopyAttribute(mdItem_, kMDItemPath));
}

- (NSURL *)url {
  NSURL *url = nil;
  NSString *urlString = GTMCFAutorelease(MDItemCopyAttribute(mdItem_, 
                                                             kMDItemURL));
  if (urlString) {
    url = [NSURL URLWithString:urlString];
  } else {
    url = [NSURL fileURLWithPath:[self filePath]];
  }
  return url;
}
  
@end
