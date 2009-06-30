//
//  HGSGoogleDocsSource.m
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

#import "HGSGoogleDocsSource.h"
#import <GData/GData.h>
#import "KeychainItem.h"
#import "QSBHGSDelegate.h"
#import "GoogleDocsConstants.h"
#import "GTMNSEnumerator+Filter.h"
#import "GTMMethodCheck.h"

// Refresh the document cache once an hour.
static const NSTimeInterval kRefreshSeconds = 3600.0;  // 60 minutes.

// Only report errors to user once an hour.
static const NSTimeInterval kErrorReportingInterval = 3600.0;  // 1 hour

static NSString *const kGoogleDocsSpreadsheetDocResultPropertyKey
  = @"GoogleDocsSpreadsheetDocResultPropertyKey";
static NSString *const kGoogleDocsSpreadsheetDocPropertyKey
  = @"GoogleDocsSpreadsheetDocPropertyKey";


@interface HGSGoogleDocsSource ()

// Used to schedule refreshes of the document cache.
- (void)setUpPeriodicRefresh;

// Main indexing function for each document associated with the account.
- (void)indexDoc:(GDataEntryDocBase*)doc;

// Bottleneck function for kicking off a document fetch or refresh.
- (void)startAsynchronousDocsListFetch;

// Secondary indexing function used to retrieve worksheet information
// about a particular spreadsheet.
- (void)startAsyncSpreadsheetInfoFetchWithDoc:(GDataEntryDocBase*)doc
                                       result:(HGSResult *)docResult;

// Retrieve the authors information for a list of people associated
// with a document.
- (NSArray*)authorArrayForGDataPeople:(NSArray*)people;

// General purpose error reporting bottlenexk.
- (void)reportError:(NSError *)error;

// Call this function whenever all document fetches should be shut down.
- (void)resetAllFetches;

@end


@implementation HGSGoogleDocsSource

GTM_METHOD_CHECK(NSEnumerator,
                 gtm_enumeratorByMakingEachObjectPerformSelector:withObject:);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Cache the Google Docs icons
    NSBundle* sourceBundle = HGSGetPluginBundle();
    NSString *docPath = [sourceBundle pathForImageResource:@"gdocdocument"];
    HGSAssert(docPath, @"Icons for 'gdocdocument' are missing from the "
              @"HGSGoogleDocsSource bundle.");
    NSString *ssPath = [sourceBundle pathForImageResource:@"gdocspreadsheet"];
    HGSAssert(ssPath, @"Icons for 'gdocspreadsheet' are missing from the "
              @"HGSGoogleDocsSource bundle.");
    NSString *presPath = [sourceBundle pathForImageResource:@"gdocpresentation"];
    HGSAssert(presPath, @"Icons for 'gdocpresentation' are missing from the "
              @"HGSGoogleDocsSource bundle.");
    NSImage *docImage 
      = [[[NSImage alloc] initByReferencingFile:docPath] autorelease];
    NSImage *ssImage
       = [[[NSImage alloc] initByReferencingFile:ssPath] autorelease];
    NSImage *presImage
      = [[[NSImage alloc] initByReferencingFile:presPath] autorelease];
    docIcons_ = [[NSDictionary alloc] initWithObjectsAndKeys:
                  docImage, kDocCategoryDocument, 
                  ssImage, kDocCategorySpreadsheet, 
                  presImage, kDocCategoryPresentation,
                  nil];
    account_ = [[configuration objectForKey:kHGSExtensionAccount] retain];
    userName_ = [[account_ userName] copy];
    if (account_) {
      // Get a doc listing now, and schedule a timer to update it every hour.
      [self startAsynchronousDocsListFetch];
      [self setUpPeriodicRefresh];
      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSAccountDidChangeNotification
               object:account_];
    } else {
      HGSLogDebug(@"Missing account identifier for HGSGoogleDocsSource '%@'",
                  [self identifier]);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self resetAllFetches];
  [docIcons_ release];
  [updateTimer_ invalidate];
  [account_ release];
  [userName_ release];
  [super dealloc];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  // If we're pivoting on docs.google.com then we can provide
  // a list of all of our docs.
  if (!isValid) {
    HGSResult *pivotObject = [query pivotObject];
    if ([pivotObject conformsToType:kHGSTypeWebApplication]) {
      NSURL *url = [pivotObject url];
      NSString *host = [url host];
      NSComparisonResult compareResult
        = [host compare:@"docs.google.com" options:NSCaseInsensitiveSearch];
      isValid = compareResult == NSOrderedSame;
    }
  }
  return isValid;
}

- (NSArray *)archiveKeys {
  NSArray *archiveKeys = [NSArray arrayWithObjects:
                          kGoogleDocsDocCategoryKey,
                          kGoogleDocsDocSaveAsIDKey,
                          kGoogleDocsWorksheetNamesKey,
                          nil];
  return archiveKeys;
}

- (GDataServiceGoogle *)serviceForDoc:(HGSResult *)doc {
  GDataServiceGoogle *service = nil;
  NSString *category = [doc valueForKey:kGoogleDocsDocCategoryKey];
  if ([category isEqualToString:kDocCategoryDocument]
      || [category isEqualToString:kDocCategoryPresentation]) {
    service = docService_;
  } else if ([category isEqualToString:kDocCategorySpreadsheet]) {
    service = spreadsheetService_;
  } else {
    HGSLogDebug(@"Unexpected document category '%@'.", category);
  }
  return service;
}

- (NSArray*)authorArrayForGDataPeople:(NSArray*)people {
  NSMutableArray* peopleTerms 
  = [NSMutableArray arrayWithCapacity:(2 * [people count])];
  NSCharacterSet *wsSet = [NSCharacterSet whitespaceCharacterSet];
  NSEnumerator* enumerator = [people objectEnumerator];
  GDataPerson* person;
  while ((person = [enumerator nextObject])) {
    
    NSString* authorName = [[person name] stringByTrimmingCharactersInSet:wsSet];
    if ([authorName length] > 0) {
      [peopleTerms addObject:authorName];
    }
    // Grab the author's email username as well
    NSString* authorEmail = [person email];
    NSUInteger atSignLocation = [authorEmail rangeOfString:@"@"].location;
    if (atSignLocation != NSNotFound) {
      authorEmail = [authorEmail substringToIndex:atSignLocation];
    }
    if (authorEmail && ![peopleTerms containsObject:authorEmail]) {
      [peopleTerms addObject:authorEmail];
    }
  }
  return peopleTerms;
}

- (void)setUpPeriodicRefresh {
  // Kick off a timer if one is not already running.
  [updateTimer_ invalidate];
  // We add 5 minutes worth of random jitter.
  NSTimeInterval jitter = random() / (LONG_MAX / (NSTimeInterval)300.0);
  updateTimer_
    = [NSTimer scheduledTimerWithTimeInterval:kRefreshSeconds + jitter
                                       target:self
                                     selector:@selector(refreshDocs:)
                                     userInfo:nil
                                      repeats:NO];
}

- (void)refreshDocs:(NSTimer*)timer {
  updateTimer_ = nil;
  [self startAsynchronousDocsListFetch];
  [self setUpPeriodicRefresh];
}

- (void)loginCredentialsChanged:(NSNotification *)notification {
  HGSAccount *account = [notification object];
  HGSAssert(account == account_, @"Notification from bad account!");
  
  // Make sure we aren't in the middle of waiting for results; if we are, try
  // again later instead of changing things in the middle of the fetch.
  if (currentlyFetchingDocs_ || [activeSpreadsheetFetches_ count] != 0) {
    [self performSelector:@selector(loginCredentialsChanged:)
               withObject:notification
               afterDelay:60.0];
    return;
  }
  // Clear the services so that we make new ones with the correct credentials.
  [docServiceTicket_ release];
  docServiceTicket_ = nil;
  [docService_ release];
  docService_ = nil;
  
  [spreadsheetService_ release];
  spreadsheetService_ = nil;
  
  // When the login changes, we should update immediately, and make sure the
  // periodic refresh is enabled (it would have been shut down if the previous
  // credentials were incorrect).
  [self startAsynchronousDocsListFetch];
  [self setUpPeriodicRefresh];
}

- (void)reportError:(NSError *)error {
  NSInteger errorCode = [error code];
  if (errorCode == kGDataBadAuthentication) {
    // If the login credentials are bad, don't keep trying.
    [updateTimer_ invalidate];
    updateTimer_ = nil;
    // Tickle the account so that if the preferences window is showing
    // the user will see the proper account status.
    [account_ authenticate];
  }
  NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
  NSTimeInterval timeSinceLastErrorReport
    = currentTime - previousErrorReportingTime_;
  if (timeSinceLastErrorReport > kErrorReportingInterval) {
    previousErrorReportingTime_ = currentTime;
    NSString *errorSummary
      = HGSLocalizedString(@"Google Docs fetch problem.", 
                           @"A dialog title for a dialog describing a Google "
                           @"Docs data fetch problem.");
    NSString *errorString = nil;
    if (errorCode == kGDataBadAuthentication) {
      NSString *errorFormat
        = HGSLocalizedString(@"Authentication for '%@' failed. Check your "
                             @"password.", 
                             @"A dialog lable denoting that authentication "
                             @"for account with username %@ failed");
      errorString = [NSString stringWithFormat:errorFormat,
                     [account_ displayName]];
      
    } else {
      NSString *errorFormat 
        = HGSLocalizedString(@"Fetch for '%1$@' failed. (%2$d)",
                             @"A dialog label denoting that an attempt to "
                             @"fetch data with the account for username $1$@ "
                             @"failed with errorcode %2$d");
      errorString = [NSString stringWithFormat:errorFormat,
                     [account_ displayName], [error code]];
    }
    NSNumber *successCode = [NSNumber numberWithInt:kHGSSuccessCodeError];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSDictionary *messageDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                 errorSummary, kHGSSummaryMessageKey,
                                 errorString, kHGSDescriptionMessageKey,
                                 successCode, kHGSSuccessCodeMessageKey,
                                 nil];
    [nc postNotificationName:kHGSUserMessageNotification 
                      object:self
                    userInfo:messageDict];
  }
  HGSLogDebug(@"HGSGoogleDocSource doc fetcher failed: error=%d, "
              @"userName=%@.",
              [error code], [account_ displayName]);
}

- (void)resetAllFetches {
  if (currentlyFetchingDocs_) {
    [docServiceTicket_ cancelTicket];
  }
  [docServiceTicket_ release];
  docServiceTicket_ = nil;
  [docService_ release];
  docService_ = nil;
  for (GDataServiceTicket *ticket in activeSpreadsheetFetches_) {
    [ticket cancelTicket];
  }
  [activeSpreadsheetFetches_ release];
  activeSpreadsheetFetches_ = nil;
  [spreadsheetService_ release];
  spreadsheetService_ = nil;
}

#pragma mark -
#pragma mark Docs Fetching

- (void)startAsynchronousDocsListFetch {
  if (!currentlyFetchingDocs_) {
    if (!docService_) {
      KeychainItem* keychainItem 
        = [KeychainItem keychainItemForService:[account_ identifier]
                                      username:nil];
      NSString *userName = [keychainItem username];
      NSString *password = [keychainItem password];
      if (userName && password) {
        docService_ = [[GDataServiceGoogleDocs alloc] init];
        [docService_ setUserAgent:@"HGSGoogleDocSource"];
        [docService_ setUserCredentialsWithUsername: userName
                                           password: password];
        [docService_ setIsServiceRetryEnabled:YES];
      } else {
        // Can't do much without a login; invalidate so we stop trying (until
        // we get a notification that the credentials have changed) and bail.
        [updateTimer_ invalidate];
        return;
      }
    }
    // Mark us as in the middle of a fetch so that if credentials change 
    // during a fetch we don't destroy the service out from under ourselves.
    currentlyFetchingDocs_ = YES;
    // If the doc feed is attempting an http request then upgrade it to https.
    NSString *urlString
      = [kGDataGoogleDocsDefaultPrivateFullFeed
         stringByReplacingOccurrencesOfString:@"http:"
                                   withString:@"https:"
                                      options:NSLiteralSearch
                                              | NSAnchoredSearch
                                        range:NSMakeRange(0, 5)];
    NSURL* docURL = [NSURL URLWithString:urlString];
    docServiceTicket_
      = [[docService_ fetchFeedWithURL:docURL
                              delegate:self
                     didFinishSelector:@selector(docServiceTicket:
                                                 finishedWithObject:
                                                 error:)]
         retain];
  }
}

- (void)docServiceTicket:(GDataServiceTicket *)docTicket
      finishedWithObject:(GDataFeedDocList *)docList
                   error:(NSError *)error {
  currentlyFetchingDocs_ = NO;
  if (!error) {
    [self clearResultIndex];
    
    NSEnumerator* docEnumerator = [[docList entries] objectEnumerator];
    GDataEntryDocBase* doc;
    while ((doc = [docEnumerator nextObject])) {
      [self indexDoc:doc];
    }
  } else {
    [self reportError:error];
  }
}

- (void)indexDoc:(GDataEntryDocBase*)doc {
  NSString* docTitle = [[doc title] stringValue];
  NSURL* docURL = [[doc HTMLLink] URL];
  if (!docURL) {
    return;
  }
  // Set the icon by category
  NSImage* icon = nil;
  NSArray *kindArray = [GDataCategory categoriesWithScheme:kGDataCategoryScheme
                                            fromCategories:[doc categories]];
  NSString *categoryLabel
    = HGSLocalizedString(@"Unknown Google Docs Category",
                         @"Text explaining that the category of the "
                         @"could not be determined.");
  if (kindArray && [kindArray count]) {
    categoryLabel = [[kindArray objectAtIndex:0] label];
    icon = [docIcons_ objectForKey:categoryLabel];
  }
  if (!icon) {
    icon = [docIcons_ objectForKey:kDocCategoryDocument];
  }
  
  // Compose the contents of the path control.  First cell will be 'Google Docs',
  // last cell will be the document name.  A middle cell may be added if there
  // is a folder, but note that only the immediately containing folder will
  // be shown even if there are higher-level containing folders.
  NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/",
                                         [docURL scheme],
                                         [docURL host]]];
  NSMutableArray *cellArray = [NSMutableArray array];
  NSString *docsString = HGSLocalizedString(@"Google Docs", 
                                            @"A label denoting a Google Docs "
                                            @"result");
  NSDictionary *googleDocsCell 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       docsString, kQSBPathCellDisplayTitleKey,
       baseURL, kQSBPathCellURLKey,
       nil];
  [cellArray addObject:googleDocsCell];
  
  // See if there's an intervening folder.
  NSString *userName = [docService_ username];
  NSString *folderScheme = [kGDataNamespaceDocuments
                            stringByAppendingFormat:@"/folders/%@",
                            userName];
  NSArray *folders = [GDataCategory categoriesWithScheme:folderScheme
                                          fromCategories:[doc categories]];
  if (folders && [folders count]) {
    NSString *label = [[folders objectAtIndex:0] label];
    NSDictionary *folderCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                label, kQSBPathCellDisplayTitleKey,
                                nil];
    [cellArray addObject:folderCell];
  }
  
  NSDictionary *resultDocCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 docTitle, kQSBPathCellDisplayTitleKey,
                                 docURL, kQSBPathCellURLKey,
                                 nil];
  [cellArray addObject:resultDocCell];
  
  // Let's consider Docs to be an extension of home.
  // TODO(stuartmorgan): maybe this should be true only for docs where the
  // user is an author (or, if we can get it from GData, "owned by me")?
  // Consider "starred" to be equivalent to things like the Dock.  
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSUnderHomeRankFlag
                         | eHGSUserPersistentPathRankFlag];
  
  // We can't get last-used, so just use last-modified.
  NSDate *date = [[doc updatedDate] date];
  if (!date) {
    date = [NSDate distantPast];
  }
  NSString *docID = [doc resourceID];
  NSDictionary *attributes
    = [NSDictionary dictionaryWithObjectsAndKeys:
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       cellArray, kQSBObjectAttributePathCellsKey,
       date, kHGSObjectAttributeLastUsedDateKey,
       userName_, kHGSObjectAttributeSnippetKey,
       icon, kHGSObjectAttributeIconKey,
       categoryLabel, kGoogleDocsDocCategoryKey,
       docID, kGoogleDocsDocSaveAsIDKey,
     nil];
  HGSResult* result = [HGSResult resultWithURL:docURL
                                          name:docTitle
                                          type:kHGSTypeWebpage
                                        source:self
                                    attributes:attributes];
  
  // If this is a spreadsheet then we have to go off and fetch the worksheet
  // information in a spreadsheet feed.
  if ([categoryLabel isEqualToString:kDocCategorySpreadsheet]) {
    [self startAsyncSpreadsheetInfoFetchWithDoc:doc result:result];
  } else {
    // Also get author names and address, and store those as non-title-match data.
    NSArray* authorArray = [self authorArrayForGDataPeople:[doc authors]];
    
    [self indexResult:result
                 name:docTitle
           otherTerms:authorArray];
  }
}

#pragma mark -
#pragma mark Spreadsheet Info Fetching

- (void)startAsyncSpreadsheetInfoFetchWithDoc:(GDataEntryDocBase *)doc
                                       result:(HGSResult *)docResult {
  // Set up our service, if necessary.
  if (!spreadsheetService_) {
    NSString *userName = nil;
    NSString *password = nil;
    // Use the most-likely-already-set-up doc service to get the credentials
    // to avoid having to go to the keychain and annoy the user.
    if (docService_) {
      userName = [docService_ username];
      password = [docService_ password];
    } else {
      KeychainItem* keychainItem 
        = [KeychainItem keychainItemForService:[account_ identifier]
                                      username:nil];
      userName = [keychainItem username];
      password = [keychainItem password];
    }
    if (userName && password) {
      spreadsheetService_ = [[GDataServiceGoogleSpreadsheet alloc] init];
      [spreadsheetService_ setUserAgent:@"HGSGoogleDocSource"];
      [spreadsheetService_ setUserCredentialsWithUsername: userName
                                                 password: password];
      [spreadsheetService_ setIsServiceRetryEnabled:YES];
    }
  }
  HGSAssert([doc isKindOfClass:[GDataEntrySpreadsheetDoc class]], nil);
  GDataEntrySpreadsheetDoc *spreadsheet = (GDataEntrySpreadsheetDoc *)doc;
  NSURL* spreadsheetFeedURL = [[spreadsheet worksheetsLink] URL];
  GDataServiceTicket *spreadsheetServiceTicket
    = [[spreadsheetService_ 
        fetchFeedWithURL:spreadsheetFeedURL
                delegate:self
       didFinishSelector:@selector(spreadsheetServiceTicket:
                                   finishedWithFeed:
                                   error:)]
       retain];
  [spreadsheetServiceTicket setProperty:docResult
                                 forKey:kGoogleDocsSpreadsheetDocResultPropertyKey];
  [spreadsheetServiceTicket setProperty:doc
                                 forKey:kGoogleDocsSpreadsheetDocPropertyKey];
  // Remember that we're fetching so that if credentials change 
  // during a fetch we don't destroy the service out from under ourselves.
  if (!activeSpreadsheetFetches_) {
    activeSpreadsheetFetches_ = [[NSMutableArray arrayWithCapacity:1] retain];
  }
  [activeSpreadsheetFetches_ addObject:spreadsheetServiceTicket];
}

- (void)spreadsheetServiceTicket:(GDataServiceTicket *)spreadsheetTicket
                finishedWithFeed:(GDataFeedWorksheet *)worksheetFeed
                           error:(NSError *)error {
  [activeSpreadsheetFetches_ removeObject:spreadsheetTicket];
  if (!error) {
    // Extracting the worksheet information.
    NSArray *worksheets = [worksheetFeed entries];
    NSEnumerator *worksheetTitleEnum
      = [[worksheets objectEnumerator]
         gtm_enumeratorByMakingEachObjectPerformSelector:@selector(title)
                                              withObject:nil];
    NSEnumerator *worksheetTitleStringEnum
      = [worksheetTitleEnum
         gtm_enumeratorByMakingEachObjectPerformSelector:@selector(stringValue)
         withObject:nil];
    NSArray *worksheetNames = [worksheetTitleStringEnum allObjects];
    HGSResult *docResult
      = [spreadsheetTicket
         propertyForKey:kGoogleDocsSpreadsheetDocResultPropertyKey];
    GDataEntryDocBase *doc
      = [spreadsheetTicket propertyForKey:kGoogleDocsSpreadsheetDocPropertyKey];
    HGSAssert(docResult, nil);
    if ([worksheetNames count]) {
      NSDictionary *attributes
        = [NSDictionary dictionaryWithObject:worksheetNames
                                      forKey:kGoogleDocsWorksheetNamesKey];
      HGSResult* worksheetResult = [HGSResult resultWithURL:[docResult url]
                                                       name:@"Ignored"
                                                       type:kHGSTypeWebpage
                                                     source:self
                                                 attributes:attributes];
      docResult = [docResult mergeWith:worksheetResult];
    }
    // Add author names and address as non-title-match data.
    NSArray* authorArray = [self authorArrayForGDataPeople:[doc authors]];
    [self indexResult:docResult
                 name:[[doc title] stringValue]
           otherTerms:authorArray];
  } else {
    [self reportError:error];
  }
}

#pragma mark -
#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(HGSAccount *)account {
  HGSAssert(account == account_, @"Notification from bad account!");
  [self resetAllFetches];
  return YES;
}

@end
