//
//  PicasawebSource.m
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
#import <GData/GData.h>
#import "KeychainItem.h"
#import "QSBHGSDelegate.h"

static NSString *const kPhotosAlbumKey = @"kPhotosAlbumKey";

// Keys used in describing an account connection error.
static NSString *const kHGSPicasawebFetchTypeKey
  = @"HGSPicasawebFetchTypeKey";

// Strings identifying the fetch operation type.
static NSString *const kHGSPicasawebFetchOperationAlbum
  = @"HGSPicasawebFetchOperationAlbum";
static NSString *const kHGSPicasawebFetchOperationPhoto
  = @"HGSPicasawebFetchOperationPhoto";

static const NSTimeInterval kRefreshSeconds = 3600.0;  // 60 minutes.
static const NSTimeInterval kErrorReportingInterval = 3600.0;  // 1 hour

@interface PicasawebSource : HGSMemorySearchSource <HGSAccountClientProtocol> {
 @private
  GDataServiceGooglePhotos *picasawebService_;
  NSMutableSet *activeTickets_;
  __weak NSTimer *updateTimer_;
  HGSAccount *account_;
  NSTimeInterval previousErrorReportingTime_;
  NSImage *placeholderIcon_;
}

- (void)setUpPeriodicRefresh;
- (void)startAlbumInfoFetch;

- (void)cancelAllTickets;

- (void)indexAlbum:(GDataEntryPhotoAlbum *)album;
- (void)indexPhoto:(GDataEntryPhoto *)photo
         withAlbum:(GDataEntryPhotoAlbum *)album;

// Utility function for reporting fetch errors.
- (void)reportErrorForFetchType:(NSString *)fetchType
                      errorCode:(NSInteger)errorCode;

+ (void)setBestFitThumbnailFromMediaGroup:(GDataMediaGroup *)mediaGroup
                             inAttributes:(NSMutableDictionary *)attributes;

@end


@interface GDataMediaGroup (VermillionAdditions)

// Choose the best fitting thumbnail for this media item for the given
// |bestSize|.
- (GDataMediaThumbnail *)getBestFitThumbnailForSize:(CGSize)bestSize;

@end


@implementation PicasawebSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Keep track of active tickets so we can cancel them if necessary.
    activeTickets_ = [[NSMutableSet set] retain];
    
    account_ = [[configuration objectForKey:kHGSExtensionAccount] retain];

    if (account_) {
      // Get album and photo metadata now, and schedule a timer to check
      // every so often to see if it needs to be updated.
      [self startAlbumInfoFetch];
      [self setUpPeriodicRefresh];

      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSAccountDidChangeNotification
               object:account_];

      // Pick up a placeholder icon.
      NSBundle *bundle = HGSGetPluginBundle();
      NSString *path
        = [bundle pathForResource:@"PicasaPlaceholder" ofType:@"icns"];
      if (path) {
        placeholderIcon_ = [[NSImage alloc] initByReferencingFile:path];
      } else {
        HGSLogDebug(@"PicasaPlaceholder.icns missing from PicasawebSource. "
                    @"The generic placeholder will be used instead.");
      }
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
  [self cancelAllTickets];
  [activeTickets_ release];
  [picasawebService_ release];
  [updateTimer_ invalidate];
  [account_ release];
  [placeholderIcon_ release];
  [super dealloc];
}

- (void)cancelAllTickets {
  for (GDataServiceTicket *ticket in activeTickets_) {
    [ticket cancelTicket];
  }
  [activeTickets_ removeAllObjects];
}

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeIconKey]) {
    value = placeholderIcon_;
  }
  if (!value) {
    value = [super provideValueForKey:key result:result];
  }
  return value;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  // If we're pivoting on an ablum then we can provide
  // a list of all of that albums images as results.
  if (!isValid) {
    HGSResult *pivotObject = [query pivotObject];
    isValid = ([pivotObject conformsToType:kHGSTypeWebPhotoAlbum]);
  }
  return isValid;
}

- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query {
  // Return photos matching the query for the pivot album.
  HGSResult *pivotObject = [query pivotObject];
  if ([pivotObject conformsToType:kHGSTypeWebPhotoAlbum]) {
    NSURL *albumURL = [pivotObject url];
    NSString *albumURLString = [albumURL absoluteString];
    // Remove things that aren't from this album.
    NSMutableIndexSet *itemsToRemove = [NSMutableIndexSet indexSet];
    NSUInteger indexToRemove = 0;
    for (HGSResult *result in results) {
      NSURL *photoURL = [result url];
      NSString *photoURLString = [photoURL absoluteString];
      if (![photoURLString hasPrefix:albumURLString]) {
        [itemsToRemove addIndex:indexToRemove];
      }
      ++indexToRemove;
    }
    [results removeObjectsAtIndexes:itemsToRemove];
  }
}

#pragma mark -
#pragma mark Album Fetching

- (void)startAlbumInfoFetch {
  if ([activeTickets_ count] == 0) {
    if (!picasawebService_) {
      KeychainItem* keychainItem 
        = [KeychainItem keychainItemForService:[account_ identifier]
                                      username:nil];
      NSString *username = [keychainItem username];
      NSString *password = [keychainItem password];
      if ([username length]) {
        picasawebService_ = [[GDataServiceGooglePhotos alloc] init];
        [picasawebService_ setUserAgent:@"PicasawebSource"];
        // If there is no password then we will only fetch public albums.
        if ([password length]) {
          [picasawebService_ setUserCredentialsWithUsername:username
                                                   password:password];
        }
        [picasawebService_ setServiceShouldFollowNextLinks:YES];
        [picasawebService_ setIsServiceRetryEnabled:YES];
      } else {
        [updateTimer_ invalidate];
        updateTimer_ = nil;
        return;
      }
    }

    // Mark us as in the middle of a fetch so that if credentials change during
    // a fetch we don't destroy the service out from under ourselves.
    NSString *userName = [picasawebService_ username];
    NSURL* albumFeedURL
      = [GDataServiceGooglePhotos photoFeedURLForUserID:userName
                                                albumID:nil
                                              albumName:nil
                                                photoID:nil
                                                   kind:nil
                                                 access:nil];
    GDataServiceTicket *albumFetchTicket
      = [picasawebService_ fetchPhotoFeedWithURL:albumFeedURL
                                        delegate:self
                               didFinishSelector:@selector(albumInfoFetcher:
                                                           finishedWithAlbum:)
                                 didFailSelector:@selector(albumInfoFetcher:
                                                           failedWithError:)];
    [activeTickets_ addObject:albumFetchTicket];
  }
}

- (void)setUpPeriodicRefresh {
  [updateTimer_ invalidate];
  // We add 5 minutes worth of random jitter.
  NSTimeInterval jitter = random() / (LONG_MAX / (NSTimeInterval)300.0);
  updateTimer_
    = [NSTimer scheduledTimerWithTimeInterval:kRefreshSeconds + jitter
                                       target:self
                                     selector:@selector(refreshAlbums:)
                                     userInfo:nil
                                      repeats:NO];
}

- (void)refreshAlbums:(NSTimer*)timer {
  updateTimer_ = nil;
  [self startAlbumInfoFetch];
  [self setUpPeriodicRefresh];
}

- (void)loginCredentialsChanged:(NSNotification *)notification {
  HGSAccount *account = [notification object];
  HGSAssert(account == account_, @"Notification from bad account!");
  // If we're in the middle of a fetch then cancel it first.
  [self cancelAllTickets];
  
  // Clear the service so that we make a new one with the correct credentials.
  [picasawebService_ release];
  picasawebService_ = nil;
  // If the login changes, we should update immediately, and make sure the
  // periodic refresh is enabled (it would have been shut down if the previous
  // credentials were incorrect).
  [self startAlbumInfoFetch];
  [self setUpPeriodicRefresh];
}

#pragma mark -
#pragma mark Album information Extraction

- (void)indexAlbum:(GDataEntryPhotoAlbum *)album {
  NSString* albumTitle = [[album title] stringValue];
  NSURL* albumURL = [[album HTMLLink] URL];
  if (albumURL) {
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    
    // We can't get last-used, so just use last-modified.
    [attributes setObject:[[album updatedDate] date]
                   forKey:kHGSObjectAttributeLastUsedDateKey];
    
    // Compose the contents of the path control.  First cell will be
    // 'Picasaweb', second cell will be the username, and the last cell
    // will be the album name.
    NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/",
                                           [albumURL scheme],
                                           [albumURL host]]];
    NSMutableArray *cellArray = [NSMutableArray array];
    NSString *picasaWeb = HGSLocalizedString(@"Picasaweb", 
                                             @"A label denoting the picasaweb "
                                             @"service.");
    NSDictionary *picasawebCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         picasaWeb, kQSBPathCellDisplayTitleKey,
         baseURL, kQSBPathCellURLKey,
         nil];
    [cellArray addObject:picasawebCell];
    
    NSURL *userURL 
      = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@/",
                              [albumURL scheme],
                              [albumURL host],
                              [picasawebService_ username]]];
    NSDictionary *userCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         [picasawebService_ username], kQSBPathCellDisplayTitleKey,
         userURL, kQSBPathCellURLKey,
         nil];
    [cellArray addObject:userCell];
    
    NSDictionary *albumCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   albumTitle, kQSBPathCellDisplayTitleKey,
                                   albumURL, kQSBPathCellURLKey,
                                   nil];
    [cellArray addObject:albumCell];
    [attributes setObject:cellArray forKey:kQSBObjectAttributePathCellsKey]; 

    // Remember the first photo's URL to ease on-demand fetching later.
    [PicasawebSource setBestFitThumbnailFromMediaGroup:[album mediaGroup]
                                          inAttributes:attributes];
      
    // Add album description and tags to enhance searching.
    NSString* albumDescription = [[album photoDescription] stringValue];
    

    // Set up the snippet and detail.
    [attributes setObject:albumDescription 
                   forKey:kHGSObjectAttributeSnippetKey];
    NSString *albumDetail = HGSLocalizedString(@"%u photos", 
                                               @"A label denoting %u number of "
                                               @"online photos");
    NSUInteger photoCount = [[album photosUsed] unsignedIntValue];
    albumDetail = [NSString stringWithFormat:albumDetail, photoCount],
    [attributes setObject:albumDetail forKey:kHGSObjectAttributeSnippetKey];
    
    HGSResult* result = [HGSResult resultWithURL:albumURL
                                            name:albumTitle
                                            type:kHGSTypeWebPhotoAlbum
                                          source:self
                                      attributes:attributes];
    [self indexResult:result
                 name:albumTitle
            otherTerm:albumDescription];
    
    // Now index the photos in the album.
    NSURL *photoInfoFeedURL = [[album feedLink] URL];
    if (photoInfoFeedURL) {
      GDataServiceTicket *photoInfoTicket
        = [picasawebService_ fetchPhotoFeedWithURL:photoInfoFeedURL
                                          delegate:self
                                 didFinishSelector:@selector(photoInfoFetcher:
                                                             finishedWithPhoto:)
                                   didFailSelector:@selector(photoInfoFetcher:
                                                             failedWithError:)];
      [photoInfoTicket setProperty:album forKey:kPhotosAlbumKey];
      [activeTickets_ addObject:photoInfoTicket];
    }
  }
}

- (void)albumInfoFetcher:(GDataServiceTicket *)ticket
       finishedWithAlbum:(GDataFeedPhotoUser *)albumList {
  [activeTickets_ removeObject:ticket];
  [self clearResultIndex];
  
  for (GDataEntryPhotoAlbum* album in [albumList entries]) {
    [self indexAlbum:album];
  }
}

- (void)albumInfoFetcher:(GDataServiceTicket *)ticket
         failedWithError:(NSError *)error {
  [activeTickets_ removeObject:ticket];

  // If nothing has changed since we last checked then don't have a cow.
  NSInteger errorCode = [error code];
  if (errorCode != kGDataHTTPFetcherStatusNotModified) {
    if (errorCode == kGDataBadAuthentication) {
      // If the login credentials are bad, don't keep trying.
      [updateTimer_ invalidate];
      updateTimer_ = nil;
    }
    NSString *fetchType = HGSLocalizedString(@"album", 
                                             @"A label denoting a Picasaweb "
                                             @"Photo Album");
    [self reportErrorForFetchType:fetchType errorCode:errorCode];
  }
}

#pragma mark -
#pragma mark Photo information Extraction

- (void)indexPhoto:(GDataEntryPhoto *)photo
         withAlbum:(GDataEntryPhotoAlbum *)album {
  NSURL* photoURL = [[photo HTMLLink] URL];
  if (photoURL) {
    NSString* photoDescription = [[photo photoDescription] stringValue];
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    
    // We can't get last-used, so just use last-modified.
    [attributes setObject:[[photo updatedDate] date]
                   forKey:kHGSObjectAttributeLastUsedDateKey];
    
    // Compose the contents of the path control.  First cell will be
    // 'Picasaweb', second cell will be the username, the third will be the
    // album name, and the last cell will be the photo title.
    NSURL *baseURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/",
                                           [photoURL scheme],
                                           [photoURL host]]];
    NSMutableArray *cellArray = [NSMutableArray array];
    NSString *picasaWeb = HGSLocalizedString(@"Picasaweb", 
                                             @"A label denoting the picasaweb "
                                             @"service.");
    NSDictionary *picasawebCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         picasaWeb, kQSBPathCellDisplayTitleKey,
         baseURL, kQSBPathCellURLKey,
         nil];
    [cellArray addObject:picasawebCell];
    NSString *urlString = [NSString stringWithFormat:@"%@://%@/%@/",
                           [photoURL scheme],
                           [photoURL host],
                           [picasawebService_ username]];
    NSURL *userURL  = [NSURL URLWithString:urlString];
    NSDictionary *userCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         [picasawebService_ username], kQSBPathCellDisplayTitleKey,
         userURL, kQSBPathCellURLKey,
         nil];
    [cellArray addObject:userCell];
    
    NSString* albumTitle = [[album title] stringValue];
    NSURL* albumURL = [[album HTMLLink] URL];
    NSDictionary *albumCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                               albumTitle, kQSBPathCellDisplayTitleKey,
                               albumURL, kQSBPathCellURLKey,
                               nil];
    [cellArray addObject:albumCell];
    [attributes setObject:cellArray forKey:kQSBObjectAttributePathCellsKey]; 
    
    NSString* photoTitle = [[photo title] stringValue];
    if ([photoDescription length] == 0) {
      photoDescription = photoTitle;
    }
    NSDictionary *photoCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                               photoTitle, kQSBPathCellDisplayTitleKey,
                               photoURL, kQSBPathCellURLKey,
                               nil];
    [cellArray addObject:photoCell];
    [attributes setObject:cellArray forKey:kQSBObjectAttributePathCellsKey]; 
    
    // Remember the photo's first image URL.
    [PicasawebSource setBestFitThumbnailFromMediaGroup:[photo mediaGroup]
                                          inAttributes:attributes];
    
    // Add photo description and tags to enhance searching.
    NSMutableArray *otherStrings
      = [NSMutableArray arrayWithObjects:photoDescription,
                                         albumTitle,
                                         nil];

    // Add tags (aka 'keywords').
    NSArray *keywords = [[[photo mediaGroup] mediaKeywords] keywords];
    [otherStrings addObjectsFromArray:keywords];
    
    // TODO(mrossetti): Add name tags when available via the PWA API.
    
    // Set up the snippet and detail.
    NSString *photoSnippet = albumTitle;
    GDataPhotoTimestamp *photoTimestamp = [photo timestamp];
    if (photoTimestamp) {
      NSDate *timestamp = [photoTimestamp dateValue];
      NSDateFormatter *dateFormatter
        = [[[NSDateFormatter alloc] init]  autorelease];
      [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
      [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
      NSString *timestampString = [dateFormatter stringFromDate:timestamp];
      photoSnippet
        = [timestampString stringByAppendingFormat:@" (%@)", photoSnippet];
    }
    
    
    photoSnippet = [photoSnippet stringByAppendingFormat:@"\r%@", photoTitle];
    [attributes setObject:photoSnippet forKey:kHGSObjectAttributeSnippetKey];
    HGSResult* result = [HGSResult resultWithURL:photoURL
                                            name:photoDescription
                                            type:kHGSTypeWebImage
                                          source:self
                                      attributes:attributes];
    
    [self indexResult:result
                 name:photoTitle
           otherTerms:otherStrings];
    
  }
}

- (void)photoInfoFetcher:(GDataServiceTicket *)ticket
       finishedWithPhoto:(GDataFeedPhotoAlbum *)photoFeed {
  [activeTickets_ removeObject:ticket];
  
  NSArray *photoList = [photoFeed entries];
  for (GDataEntryPhoto *photo in photoList) {
    GDataEntryPhotoAlbum *album = [ticket propertyForKey:kPhotosAlbumKey];
    [self indexPhoto:photo withAlbum:album];
  }
}

- (void)photoInfoFetcher:(GDataServiceTicket *)ticket
         failedWithError:(NSError *)error {
  [activeTickets_ removeObject:ticket];
  // If nothing has changed since we last checked then don't have a cow.
  NSInteger errorCode = [error code];
  if (errorCode != kGDataHTTPFetcherStatusNotModified) {
    if (errorCode == kGDataBadAuthentication) {
      // If the login credentials are bad, don't keep trying.
      [updateTimer_ invalidate];
      updateTimer_ = nil;
      // Tickle the account so that if the user happens to have the preference
      // window open showing either the account or the search source they
      // will immediately see that the account status has changed.
      [account_ authenticate];
    }
    NSString *fetchType = HGSLocalizedString(@"photo", 
                                             @"A label denoting a Picasaweb "
                                             @"photo");
    [self reportErrorForFetchType:fetchType errorCode:errorCode];
  }
}

- (void)reportErrorForFetchType:(NSString *)fetchType
                      errorCode:(NSInteger)errorCode {
  NSString *username = [picasawebService_ username];
  NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
  NSTimeInterval timeSinceLastErrorReport
    = currentTime - previousErrorReportingTime_;
  if (timeSinceLastErrorReport > kErrorReportingInterval) {
    previousErrorReportingTime_ = currentTime;
    NSString *errorSummary
      = HGSLocalizedString(@"Picasaweb fetch problem.", 
                           @"A dialog title denoting that we have encountered "
                           @"an error fetching data from Picasaweb.");
    NSString *errorString = nil;
    // A 404 from Picasa usually means that Picasa has not been enabled for
    // this account.  For additional information see:
    // http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html#sec10.4.5
    if (errorCode == 404) {
      NSString *errorFormat
        = HGSLocalizedString(@"Have you enabled Picasa for your '%1$@' account? "
                             @"(%2$d)", 
                             @"A dialog label asking if the user has enabled "
                             @"their Picasa account for the username %1$@. "
                             @"%2$d is an error code returned from Picasaweb");
      errorString = [NSString stringWithFormat:errorFormat,
                     username, errorCode];
    } else {
      NSString *errorFormat
        = HGSLocalizedString(@"Picasaweb %1$@ fetch for account '%2$@' failed. "
                             @"(%3$d)", 
                             @"A dialog label explaining that the fetch for "
                             @"the item denoted by %1$@ from the account with "
                             @"the username %2$@ failed. %3$d is an error code "
                             @"returned from Picasaweb");
      errorString = [NSString stringWithFormat:errorFormat,
                     fetchType, username, errorCode];
    }
    NSNumber *successCode = [NSNumber numberWithInt:kHGSSuccessCodeError];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSDictionary *messageDict
      = [NSDictionary dictionaryWithObjectsAndKeys:
         errorSummary, kHGSSummaryMessageKey,
         errorString, kHGSDescriptionMessageKey,
         successCode, kHGSSuccessCodeMessageKey,
         nil];
    [nc postNotificationName:kHGSUserMessageNotification 
                      object:self
                    userInfo:messageDict];
  }
  HGSLogDebug(@"PicasawebSource %@InfoFetcher failed: error=%d, username=%@.",
              fetchType, errorCode, username);       
}


#pragma mark -
#pragma mark Thumbnails

+ (void)setBestFitThumbnailFromMediaGroup:(GDataMediaGroup *)mediaGroup
                             inAttributes:(NSMutableDictionary *)attributes {
  // Since a source doesn't really know about the particular UI to which it
  // is providing the thumbnail we will hardcode a desired size, which
  // just happens to be the size of the preview image in the Quicksearch
  // Bar.
  const CGSize bestSize = { 96.0, 128.0 };
  GDataMediaThumbnail *bestThumbnail
    = [mediaGroup getBestFitThumbnailForSize:bestSize];

  if (bestThumbnail) {
    NSString *photoURLString = [bestThumbnail URLString];
    if (photoURLString) {
      [attributes setObject:[NSURL URLWithString:photoURLString]
                     forKey:kHGSObjectAttributeIconPreviewFileKey];
    }
  }
}

#pragma mark -
#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(HGSAccount *)account {
  HGSAssert(account == account_, @"Notification from bad account!");
  
  // Cancel any outstanding fetches.
  [self cancelAllTickets];
    
  // And get rid of the service.
  [picasawebService_ release];
  picasawebService_ = nil;

  return YES;
}

@end

#pragma mark -

@implementation GDataMediaGroup (VermillionAdditions)

- (GDataMediaThumbnail *)getBestFitThumbnailForSize:(CGSize)bestSize {
  // This approach works best when choosing an image that will be scaled.  A
  // different approach will be required if the image is going to be cropped.
  GDataMediaThumbnail *bestThumbnail = nil;
  NSArray *thumbnails = [self mediaThumbnails];
  CGFloat bestDelta = 0.0;

  for (GDataMediaThumbnail *thumbnail in thumbnails) {
    CGFloat trialWidth = [[thumbnail width] floatValue];
    CGFloat trialHeight = [[thumbnail height] floatValue];
    CGFloat trialDelta = fabs(bestSize.width - trialWidth)
                         + fabs(bestSize.height - trialHeight);
    if (!bestThumbnail || trialDelta < bestDelta) {
      bestDelta = trialDelta;
      bestThumbnail = thumbnail;
    }
  }
  return bestThumbnail;
}

@end
