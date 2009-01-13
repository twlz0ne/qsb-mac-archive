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

#import <Vermilion/Vermilion.h>
#import "GDataDocs.h"
#import "KeychainItem.h"

// Google Docs categories
static NSString* const kDocCategoryDocument = @"document";
static NSString* const kDocCategorySpreadsheet = @"spreadsheet";
static NSString* const kDocCategoryPresentation = @"presentation";

@interface HGSGoogleDocsSource : HGSMemorySearchSource {
 @private
  GDataServiceGoogleDocs* docService_;
  GDataServiceTicket *    serviceTicket_;
  NSTimer*                updateTimer_;
  NSDictionary*           docIcons_;
  BOOL                    currentlyFetching_;
  NSString *              accountIdentifier_;
}

- (void)setUpPeriodicRefresh;
- (void)startAsynchronousDocsListFetch;
- (void)indexDoc:(GDataEntryDocBase*)doc;
- (NSArray*)authorArrayForGDataPeople:(NSArray*)people;
@end

@implementation HGSGoogleDocsSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Cache the Google Docs icons
    NSBundle* sourceBundle = HGSGetPluginBundle();
    NSString *docPath = [sourceBundle pathForImageResource:@"gdocdocument"];
    HGSAssert(docPath, @"Icons for 'gdocdocument' are missing from the "
              @"HGSGoogleDocsSource module bundle.");
    NSString *ssPath = [sourceBundle pathForImageResource:@"gdocspreadsheet"];
    HGSAssert(ssPath, @"Icons for 'gdocspreadsheet' are missing from the "
              @"HGSGoogleDocsSource module bundle.");
    NSString *presPath = [sourceBundle pathForImageResource:@"gdocpresentation"];
    HGSAssert(presPath, @"Icons for 'gdocpresentation' are missing from the "
              @"HGSGoogleDocsSource module bundle.");
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
    id<HGSAccount> account
      = [configuration objectForKey:kHGSExtensionAccountIdentifier];
    accountIdentifier_ = [[account identifier] retain];
    if (accountIdentifier_) {
      // Get a doc listing now, and schedule a timer to update it every hour.
      [self startAsynchronousDocsListFetch];
      [self setUpPeriodicRefresh];
      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSDidChangeAccountNotification
               object:nil];
      [nc addObserver:self
             selector:@selector(willRemoveLoginCredentials:)
                 name:kHGSWillRemoveAccountNotification
               object:nil];
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
  [docService_ release];
  [serviceTicket_ release];
  [docIcons_ release];
  if ([updateTimer_ isValid])
    [updateTimer_ invalidate];
  [updateTimer_ release];
  [accountIdentifier_ release];
  [super dealloc];
}

#pragma mark -
#pragma mark Docs Fetching

- (void)startAsynchronousDocsListFetch {
  if (!docService_) {
    KeychainItem* keychainItem 
      = [KeychainItem keychainItemForService:accountIdentifier_
                                    username:nil];
    if (!keychainItem ||
        [[keychainItem username] length] == 0 ||
        [[keychainItem password] length] == 0) {
      // Can't do much without a login; invalidate so we stop trying (until
      // we get a notification that the credentials have changed) and bail.
      [updateTimer_ invalidate];
      return;
    }
    docService_ = [[GDataServiceGoogleDocs alloc] init];
    [docService_ setUserAgent:@"HGSGoogleDocSource"];
    [docService_ setUserCredentialsWithUsername:[keychainItem username]
                                       password:[keychainItem password]];
  }

  // Mark us as in the middle of a fetch so that if credentials change during
  // a fetch we don't destroy the service out from under ourselves.
  currentlyFetching_ = YES;
  NSURL* docURL = [NSURL URLWithString:kGDataGoogleDocsDefaultPrivateFullFeed];
  serviceTicket_
    = [[docService_ fetchDocsFeedWithURL:docURL
                                delegate:self
                       didFinishSelector:@selector(serviceTicket:finishedWithObject:)
                         didFailSelector:@selector(serviceTicket:failedWithError:)]
       retain];
  }

- (void)setUpPeriodicRefresh {
  // if we are already running the scheduled check, we are done.
  if ([updateTimer_ isValid])
    return;
  [updateTimer_ release];
  updateTimer_ = [[NSTimer scheduledTimerWithTimeInterval:(60 * 60)
                                                   target:self
                                                 selector:@selector(refreshDocs:)
                                                 userInfo:nil
                                                  repeats:YES] retain];
}

- (void)refreshDocs:(NSTimer*)timer {
  [self startAsynchronousDocsListFetch];
}

- (void)loginCredentialsChanged:(id)object {
  if ([accountIdentifier_ isEqualToString:object]) {
    // Make sure we aren't in the middle of waiting for results; if we are, try
    // again later instead of changing things in the middle of the fetch.
    if (currentlyFetching_) {
      [self performSelector:@selector(loginCredentialsChanged:)
                 withObject:nil
                 afterDelay:60.0];
      return;
    }
    // Clear the service so that we make a new one with the correct credentials.
    [serviceTicket_ release];
    serviceTicket_ = nil;
    [docService_ release];
    docService_ = nil;
    // If the login changes, we should update immediately, and make sure the
    // periodic refresh is enabled (it would have been shut down if the previous
    // credentials were incorrect).
    [self startAsynchronousDocsListFetch];
    [self setUpPeriodicRefresh];
  }
}

- (void)willRemoveLoginCredentials:(id)object {
  if ([accountIdentifier_ isEqualToString:object]) {
    if (currentlyFetching_) {
      [serviceTicket_ cancelTicket];
    }
    [serviceTicket_ release];
    serviceTicket_ = nil;
    [docService_ release];
    docService_ = nil;
  }
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
   finishedWithObject:(GDataFeedDocList *)docList {
  currentlyFetching_ = NO;
  [self clearResultIndex];

  NSEnumerator* docEnumerator = [[docList entries] objectEnumerator];
  GDataEntryDocBase* doc;
  while ((doc = [docEnumerator nextObject])) {
    [self indexDoc:doc];
  }
}

- (void)serviceTicket:(GDataServiceTicket *)ticket
      failedWithError:(NSError *)error {
   currentlyFetching_ = NO;
  if ([error code] == 403) {
    // If the login credentials are bad, don't keep trying.
    [updateTimer_ invalidate];
  }
  KeychainItem* keychainItem
    = [KeychainItem keychainItemForService:accountIdentifier_
                                  username:nil];
  NSString *username = [keychainItem username];
  HGSLogDebug(@"HGSGoogleDocSource doc fetcher failed: error=%d, "
              @"username=%@.",
              [error code], username);
  NSDictionary *noteDict = [NSDictionary dictionaryWithObjectsAndKeys:
                            kHGSExtensionIdentifierKey, [self identifier],
                            kHGSAccountUsernameKey, username,
                            kHGSAccountConnectionErrorKey, error,
                            nil];
  NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
  [defaultCenter postNotificationName:kHGSAccountConnectionFailureNotification 
                               object:noteDict];
}

#pragma mark -
#pragma mark Docs Info Extraction

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
  if (kindArray && [kindArray count]) {
    NSString *categoryLabel = [[kindArray objectAtIndex:0] label];
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
  NSDictionary *googleDocsCell 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       HGSLocalizedString(@"Google Docs", nil), kHGSPathCellDisplayTitleKey,
       baseURL, kHGSPathCellURLKey,
       nil];
  [cellArray addObject:googleDocsCell];
  
  // See if there's an intervening folder.
  KeychainItem* keychainItem 
    = [KeychainItem keychainItemForService:accountIdentifier_
                                  username:nil];
  NSString *folderScheme = [kGDataNamespaceDocuments
                            stringByAppendingFormat:@"/folders/%@",
                            [keychainItem username]];
  NSArray *folders = [GDataCategory categoriesWithScheme:folderScheme
                                          fromCategories:[doc categories]];
  if (folders && [folders count]) {
    NSString *label = [[folders objectAtIndex:0] label];
    NSDictionary *folderCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                label, kHGSPathCellDisplayTitleKey,
                                nil];
    [cellArray addObject:folderCell];
  }
  
  NSDictionary *resultDocCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                 docTitle, kHGSPathCellDisplayTitleKey,
                                 docURL, kHGSPathCellURLKey,
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
  NSDictionary *attributes
   = [NSDictionary dictionaryWithObjectsAndKeys:
      rankFlags, kHGSObjectAttributeRankFlagsKey,
      cellArray, kHGSObjectAttributePathCellsKey,
      date, kHGSObjectAttributeLastUsedDateKey,
      icon, kHGSObjectAttributeIconKey,
      nil];
  
  HGSObject* result = [HGSObject objectWithIdentifier:docURL
                                                 name:docTitle
                                                 type:kHGSTypeWebpage
                                               source:self
                                           attributes:attributes];
  
  // Also get author names and address, and store those as non-title-match data.
  NSArray* authorArray = [self authorArrayForGDataPeople:[doc authors]];

  [self indexResult:result
         nameString:docTitle
  otherStringsArray:authorArray];
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

@end
