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
#import "GDataEntryPhoto.h"
#import "GDataEntryPhotoAlbum.h"
#import "GDataFeedPhotoAlbum.h"
#import "GDataFeedPhotoUser.h"
#import "GDataMediaKeywords.h"
#import "GDataMediaThumbnail.h"
#import "GDataServiceGooglePhotos.h"
#import "KeychainItem.h"

static NSString *const kPhotosAlbumKey = @"kPhotosAlbumKey";

// Keys used in describing an account connection error.
static NSString *const kHGSPicasawebFetchTypeKey
  = @"HGSPicasawebFetchTypeKey";

// Strings identifying the fetch operation type.
static NSString *const kHGSPicasawebFetchOperationAlbum
  = @"HGSPicasawebFetchOperationAlbum";
static NSString *const kHGSPicasawebFetchOperationPhoto
  = @"HGSPicasawebFetchOperationPhoto";

static const NSTimeInterval kRefreshSeconds = 600.0;  // 10 minutes.

@interface PicasawebSource : HGSMemorySearchSource {
 @private
  GDataServiceGooglePhotos *picasawebService_;
  NSMutableSet *activeTickets_;
  NSTimer *updateTimer_;
  NSString *accountIdentifier_;
}

- (void)setUpPeriodicRefresh;
- (void)startAlbumInfoFetch;

- (void)cancelAllTickets;

- (void)indexAlbum:(GDataEntryPhotoAlbum *)album;
- (void)indexPhoto:(GDataEntryPhoto *)photo
         withAlbum:(GDataEntryPhotoAlbum *)album;

+ (void)setBestFitThumbnailFromMediaGroup:(GDataMediaGroup *)mediaGroup
                             inAttributes:(NSMutableDictionary *)attributes;

@end


@interface GDataMediaGroup (VermillionAdditions)

// Choose the best fitting thumbnail for this media item for the given
// |size|.
- (GDataMediaThumbnail *)getBestFitThumbnailForSize:(CGSize)bestSize;

@end


@implementation PicasawebSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Keep track of active tickets so we can cancel them if necessary.
    activeTickets_ = [[NSMutableSet set] retain];
    
    id<HGSAccount> account
      = [configuration objectForKey:kHGSExtensionAccountIdentifier];
    accountIdentifier_ = [[account identifier] retain];

    if (accountIdentifier_) {
      // Get album and photo metadata now, and schedule a timer to check
      // every so often to see if it needs to be updated.
      [self startAlbumInfoFetch];
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
  [self cancelAllTickets];
  [activeTickets_ release];
  [picasawebService_ release];
  if ([updateTimer_ isValid]) {
    [updateTimer_ invalidate];
  }
  [updateTimer_ release];
  [accountIdentifier_ release];

  [super dealloc];
}

- (void)cancelAllTickets {
  for (GDataServiceTicket *ticket in activeTickets_) {
    [ticket cancelTicket];
  }
  [activeTickets_ removeAllObjects];
}

#pragma mark -
#pragma mark Album Fetching

- (void)startAlbumInfoFetch {
  if (!picasawebService_) {
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
    picasawebService_ = [[GDataServiceGooglePhotos alloc] init];
    [picasawebService_ setUserAgent:@"PicasawebSource"];
    [picasawebService_ setUserCredentialsWithUsername:[keychainItem username]
                                       password:[keychainItem password]];
    [picasawebService_ setServiceShouldFollowNextLinks:YES];
    [picasawebService_ setIsServiceRetryEnabled:YES];
  }

  // Mark us as in the middle of a fetch so that if credentials change during
  // a fetch we don't destroy the service out from under ourselves.
  NSURL* albumFeedURL
    = [GDataServiceGooglePhotos photoFeedURLForUserID:[picasawebService_ username]
                                              albumID:nil
                                            albumName:nil
                                              photoID:nil
                                                 kind:nil
                                               access:nil];
  GDataServiceTicket *albumFetchTicket
    = [picasawebService_ fetchPhotoFeedWithURL:albumFeedURL
                                      delegate:self
                             didFinishSelector:@selector(albumInfoFetcher:finishedWithAlbum:)
                               didFailSelector:@selector(albumInfoFetcher:failedWithError:)];
  [activeTickets_ addObject:albumFetchTicket];
}

- (void)setUpPeriodicRefresh {
  // if we are already running the scheduled check, we are done.
  if ([updateTimer_ isValid])
    return;
  [updateTimer_ release];
  // Refresh every so many minutes.
  updateTimer_ = [[NSTimer scheduledTimerWithTimeInterval:kRefreshSeconds
                                                   target:self
                                                 selector:@selector(refreshAlbums:)
                                                 userInfo:nil
                                                  repeats:YES] retain];
}

- (void)refreshAlbums:(NSTimer*)timer {
  [self startAlbumInfoFetch];
}

- (void)loginCredentialsChanged:(id)object {
  if ([accountIdentifier_ isEqualToString:object]) {
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
}

- (void)willRemoveLoginCredentials:(id)object {
  if ([accountIdentifier_ isEqualToString:object]) {
    // Cancel any outstanding fetches.
    [self cancelAllTickets];

    // And get rid of the service.
    [picasawebService_ release];
    picasawebService_ = nil;
  }
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
    NSDictionary *picasawebCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         HGSLocalizedString(@"Picasaweb", nil), kHGSPathCellDisplayTitleKey,
         baseURL, kHGSPathCellURLKey,
         nil];
    [cellArray addObject:picasawebCell];
    
    NSURL *userURL 
      = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@/",
                              [albumURL scheme],
                              [albumURL host],
                              [picasawebService_ username]]];
    NSDictionary *userCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         [picasawebService_ username], kHGSPathCellDisplayTitleKey,
         userURL, kHGSPathCellURLKey,
         nil];
    [cellArray addObject:userCell];
    
    NSDictionary *albumCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   albumTitle, kHGSPathCellDisplayTitleKey,
                                   albumURL, kHGSPathCellURLKey,
                                   nil];
    [cellArray addObject:albumCell];
    [attributes setObject:cellArray forKey:kHGSObjectAttributePathCellsKey]; 

    // Remember the first photo's URL to ease on-demand fetching later.
    [PicasawebSource setBestFitThumbnailFromMediaGroup:[album mediaGroup]
                                          inAttributes:attributes];
      
    // Add album description and tags to enhance searching.
    NSString* albumDescription = [[album photoDescription] stringValue];
    

    // Set up the snippet and detail.
    [attributes setObject:albumDescription 
                   forKey:kHGSObjectAttributeSnippetKey];
    NSString *albumDetail = HGSLocalizedString(@"%u photos", nil);
    NSUInteger photoCount = [[album photosUsed] unsignedIntValue];
    albumDetail = [NSString stringWithFormat:albumDetail, photoCount],
    [attributes setObject:albumDetail forKey:kHGSObjectAttributeSnippetKey];
    
    HGSObject* result = [HGSObject objectWithIdentifier:albumURL
                                                   name:albumTitle
                                                   type:kHGSTypeWebPhotoAlbum
                                                 source:self
                                             attributes:attributes];
    [self indexResult:result
           nameString:albumTitle
          otherString:albumDescription];
    
    // Now index the photos in the album.
    NSURL *photoInfoFeedURL = [[album feedLink] URL];
    if (photoInfoFeedURL) {
      GDataServiceTicket *photoInfoTicket
        = [picasawebService_ fetchPhotoFeedWithURL:photoInfoFeedURL
                                          delegate:self
                                 didFinishSelector:@selector(photoInfoFetcher:finishedWithPhoto:)
                                   didFailSelector:@selector(photoInfoFetcher:failedWithError:)];
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
    }
    KeychainItem* keychainItem
      = [KeychainItem keychainItemForService:accountIdentifier_
                                    username:nil];
    NSString *username = [keychainItem username];
    HGSLogDebug(@"PicasawebSource albumInfoFetcher failed: error=%d, "
                @"username=%@.",
                errorCode, username);       
    NSDictionary *noteDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              kHGSExtensionIdentifierKey, [self identifier],
                              kHGSAccountUsernameKey, username,
                              kHGSAccountConnectionErrorKey, error,
                              kHGSPicasawebFetchTypeKey,
                              kHGSPicasawebFetchOperationAlbum,
                              nil];
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter postNotificationName:kHGSAccountConnectionFailureNotification 
                                 object:noteDict];
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
    NSDictionary *picasawebCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         HGSLocalizedString(@"Picasaweb", nil), kHGSPathCellDisplayTitleKey,
         baseURL, kHGSPathCellURLKey,
         nil];
    [cellArray addObject:picasawebCell];
    
    NSURL *userURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/%@/",
                                           [photoURL scheme],
                                           [photoURL host],
                                           [picasawebService_ username]]];
    NSDictionary *userCell 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         [picasawebService_ username], kHGSPathCellDisplayTitleKey,
         userURL, kHGSPathCellURLKey,
         nil];
    [cellArray addObject:userCell];
    
    NSString* albumTitle = [[album title] stringValue];
    NSURL* albumURL = [[album HTMLLink] URL];
    NSDictionary *albumCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                               albumTitle, kHGSPathCellDisplayTitleKey,
                               albumURL, kHGSPathCellURLKey,
                               nil];
    [cellArray addObject:albumCell];
    [attributes setObject:cellArray forKey:kHGSObjectAttributePathCellsKey]; 
    
    NSString* photoTitle = [[photo title] stringValue];
    NSDictionary *photoCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                               photoTitle, kHGSPathCellDisplayTitleKey,
                               photoURL, kHGSPathCellURLKey,
                               nil];
    [cellArray addObject:photoCell];
    [attributes setObject:cellArray forKey:kHGSObjectAttributePathCellsKey]; 
    
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
      NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init]  autorelease];
      [dateFormatter setFormatterBehavior:NSDateFormatterBehavior10_4];
      [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
      NSString *timestampString = [dateFormatter stringFromDate:timestamp];
      photoSnippet = [timestampString stringByAppendingFormat:@" (%@)", photoSnippet];
    }
    
    
    photoSnippet = [photoSnippet stringByAppendingFormat:@"\r%@", photoTitle];
    [attributes setObject:photoSnippet forKey:kHGSObjectAttributeSnippetKey];
    HGSObject* result = [HGSObject objectWithIdentifier:photoURL
                                                   name:photoDescription
                                                   type:kHGSTypeWebImage
                                                 source:self
                                             attributes:attributes];
    
    [self indexResult:result
           nameString:photoTitle
    otherStringsArray:otherStrings];
    
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
    }
    KeychainItem* keychainItem
      = [KeychainItem keychainItemForService:accountIdentifier_
                                    username:nil];
    NSString *username = [keychainItem username];
    HGSLogDebug(@"PicasawebSource photoInfoFetcher failed: error=%d, "
                @"username=%@.",
                errorCode, username);       
    NSDictionary *noteDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              kHGSExtensionIdentifierKey, [self identifier],
                              kHGSAccountUsernameKey, username,
                              kHGSAccountConnectionErrorKey, error,
                              kHGSPicasawebFetchTypeKey,
                                kHGSPicasawebFetchOperationPhoto,
                              nil];
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    [defaultCenter postNotificationName:kHGSAccountConnectionFailureNotification 
                                 object:noteDict];
  }
}

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

@end


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
