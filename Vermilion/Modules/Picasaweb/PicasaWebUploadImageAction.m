//
//  PicasaWebUploadImageAction.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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
#import "HGSKeychainItem.h"
#import "NSNotificationCenter+MainThread.h"

// Keys for properties passed along in the tickets and entry objects.
static NSString *const kPicasaWebUploadImageActionAttemptNumberKey
  = @"PicasaWebUploadImageActionAttemptNumberKey";
static NSString *const kPicasaWebUploadImageActionImageEntryKey
  = @"PicasaWebUploadImageActionImageEntryKey";

// User Message Names
static NSString *const kPicasaWebUserMessageName
  = @"PicasaWebUserMessageName";

// The maximum number of times an upload will be attempted.
static NSUInteger const kMaxUploadAttempts = 3;

// Upload timing constants.
static const NSTimeInterval kUploadRetryInterval = 0.1;
static const NSTimeInterval kUploadGiveUpInterval = 30.0;

// An action that will upload one or more images and/or videoa
// to a Picasa account.
//
@interface PicasaWebUploadImageAction : HGSAction <HGSAccountClientProtocol> {
 @private
  HGSSimpleAccount *account_;
  GDataServiceGooglePhotos *picasaWebService_;
  NSURL *imagePostURL_;
  NSMutableSet *activeTickets_;
  BOOL userWasNoticed_;
  UInt64 bytesSent_;
}

@property (nonatomic, retain) GDataServiceGooglePhotos *picasaWebService;
@property (nonatomic, copy) NSURL *imagePostURL;
@property (nonatomic) BOOL userWasNoticed;
@property (assign) unsigned long long bytesSent;

- (void)cancelAllTickets;

// Upload all of the images.
- (void)uploadImages:(HGSResultArray *)imageResults;

// Bottleneck function to upload a single image.
- (void)uploadImage:(HGSResult *)image;

// Bottleneck function for retrying the upload a single image.
- (void)retryUploadImageEntry:(GDataEntryPhoto *)imageEntry;

// Utility function to send notification so user can be notified of
// success or failure.
- (void)informUserWithDescription:(NSString *)description
                             type:(HGSUserMessageType)type;

// Utility function used as a fall-back for determining the MIME
// type for a file at the given path.
+ (NSString *)staticMIMETypeForPath:(NSString *)path;

@end


@implementation PicasaWebUploadImageAction

@synthesize picasaWebService = picasaWebService_;
@synthesize imagePostURL = imagePostURL_;
@synthesize userWasNoticed = userWasNoticed_;
@synthesize bytesSent = bytesSent_;

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    account_ = [[configuration objectForKey:kHGSExtensionAccount] retain];
    if (account_) {
      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSAccountDidChangeNotification
               object:account_];
      // Keep track of active tickets so we can cancel them if necessary.
      activeTickets_ = [[NSMutableSet set] retain];
      // Pre-determine the URL used to post images.
      NSURL *imagePostURL
        = [GDataServiceGooglePhotos photoFeedURLForUserID:kGDataServiceDefaultUser
                                                  albumID:kGDataGooglePhotosDropBoxAlbumID
                                                albumName:nil
                                                  photoID:nil
                                                     kind:nil
                                                   access:nil];
      [self setImagePostURL:imagePostURL];
    } else {
      HGSLogDebug(@"Missing account identifier for PicasaWebUploadImageAction "
                  @"'%@'", [self identifier]);
      [self release];
      self = nil;
    }
  }
  return self;
}

// COV_NF_START
- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self cancelAllTickets];
  [account_ release];
  [super dealloc];
}
// COV_NF_END

- (void)cancelAllTickets {
  @synchronized (activeTickets_) {
    for (GDataServiceTicket *ticket in activeTickets_) {
      [ticket cancelTicket];
    }
    [activeTickets_ removeAllObjects];
  }
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  [self setUserWasNoticed:NO];
  HGSResultArray *directObjects
    = [info objectForKey:kHGSActionDirectObjectsKey];
  BOOL success = YES;
  NSUInteger uploadsToComplete = [directObjects count];
  if (uploadsToComplete) {
    [self uploadImages:directObjects];
  }
  return success;
}

- (void)uploadImages:(HGSResultArray *)imageResults {
  if ([imageResults count]) {
    GDataServiceGooglePhotos *picasaWebService = [self picasaWebService];
    if (!picasaWebService) {
      HGSKeychainItem* keychainItem 
        = [HGSKeychainItem keychainItemForService:[account_ identifier]
                                         username:nil];
      NSString *username = [keychainItem username];
      NSString *password = [keychainItem password];
      if ([username length]) {
        picasaWebService = [[[GDataServiceGooglePhotos alloc] init] autorelease];
        [self setPicasaWebService:picasaWebService];
        [picasaWebService setUserCredentialsWithUsername:username
                                                password:password];
        [picasaWebService
         setUserAgent:@"google-qsb-1.0"];
        [picasaWebService setShouldCacheDatedData:YES];
        [picasaWebService setServiceShouldFollowNextLinks:YES];
        [picasaWebService setIsServiceRetryEnabled:YES];
        SEL progressSel = @selector(inputStream:bytesSent:totalBytes:);
        [picasaWebService setServiceUploadProgressSelector:progressSel];
      }
    }
    if (picasaWebService) {
      for (HGSResult *imageResult in imageResults) {
        [self uploadImage:imageResult];
      }
    } else {
      NSString *errorString
        = HGSLocalizedString(@"Could not upload images. Please check the "
                             @"password for account '%@'.", 
                             @"A message explaining that the user could "
                             @"not upload Picasa Web images due to a bad "
                             @"password for account %@.");
      errorString = [NSString stringWithFormat:errorString,
                     [account_ identifier]];
      [self informUserWithDescription:errorString
                                 type:kHGSUserMessageErrorType];
      HGSLog(@"PicasaWebUploadAction upload to account '%@' failed due "
             @"to missing keychain item.", [account_ displayName]);
    }
  }
}

- (void)uploadImage:(HGSResult *)imageResult {
  GDataEntryPhoto *imageEntry = [GDataEntryPhoto photoEntry];
  NSString *imageName = [imageResult displayName];
  [imageEntry setTitleWithString:imageName];
  // TODO(mrossetti): Perhaps set this from metainfo in the image file
  // or to the file's creation date.
  [imageEntry setTimestamp:[GDataPhotoTimestamp
                            timestampWithDate:[NSDate date]]];
  NSString *imagePath = [imageResult filePath];
  NSData *imageData = [NSData dataWithContentsOfFile:imagePath];
  if (imageData) {
    [imageEntry setPhotoData:imageData];
    // TODO(mrossetti): Simplify the following if/when MIMETypeForFileAtPath:
    // is more reliable.
    NSString *mimeType = [GDataUtilities MIMETypeForFileAtPath:imagePath
                                               defaultMIMEType:nil];
    if (!mimeType) {
      mimeType = [PicasaWebUploadImageAction staticMIMETypeForPath:imagePath];
    }
    if (!mimeType) {
      mimeType = @"image/jpeg";
    }
    [imageEntry setPhotoMIMEType:mimeType];
    // Run the upload on our thread. Sleep for a second and then check 
    // to see if an upload has completed or if we've recorded some progress
    // in an upload byte-wise.  Give up if there has been no progress for
    // a while.
    NSTimeInterval endTime
      = [NSDate timeIntervalSinceReferenceDate] + kUploadGiveUpInterval;
    NSRunLoop* loop = [NSRunLoop currentRunLoop];
    GDataServiceGooglePhotos *picasaWebService = [self picasaWebService];
    GDataServiceTicket *uploadImageTicket
      = [picasaWebService fetchEntryByInsertingEntry:imageEntry
                                          forFeedURL:[self imagePostURL]
                                            delegate:self
                                   didFinishSelector:@selector(imageUploader:
                                                               finishedWithEntry:
                                                               error:)];
    [uploadImageTicket retain];
    [uploadImageTicket setProperty:imageEntry
                            forKey:kPicasaWebUploadImageActionImageEntryKey];
    @synchronized (activeTickets_) {
      [activeTickets_ addObject:uploadImageTicket];
    }
    unsigned long long lastBytesSent = 0;
    do {
      // Reset endTime if some progress occurred.  While |bytesSent| may be
      // shared between threads we don't care because we just care that it
      // has changed.
      unsigned long long bytesSent = [self bytesSent];
      if (lastBytesSent != bytesSent) {
        endTime = [NSDate timeIntervalSinceReferenceDate] + kUploadGiveUpInterval;
        lastBytesSent = bytesSent;
      }
      NSDate *sleepTilDate
        = [NSDate dateWithTimeIntervalSinceNow:kUploadRetryInterval];
      [loop runUntilDate:sleepTilDate];
      if ([NSDate timeIntervalSinceReferenceDate] > endTime) {
        [uploadImageTicket cancelTicket];
        @synchronized (activeTickets_) {
          [activeTickets_ removeObject:uploadImageTicket];
        }
        NSString *errorString
          = HGSLocalizedString(@"Upload of image '%@' timed out and could not "
                               @"be completed. Please check your connection to "
                               @"the Internet.", 
                               @"A message explaining that an image could "
                               @"not be uploaded to Picasa Web albums because "
                               @"it was taking too long.");
        errorString = [NSString stringWithFormat:errorString, imageName];
        [self informUserWithDescription:errorString
                                   type:kHGSUserMessageErrorType];
        HGSLog(@"PicasaWebUploadAction timed out uploading image '%@' to "
               @"account '%@'.", imagePath, [account_ displayName]);
      }
    } while ([activeTickets_ containsObject:uploadImageTicket]);
    [uploadImageTicket release];
  } else {
    HGSLogDebug(@"Failed to load imageData for '%@'.", imagePath);
  }
}

- (void)retryUploadImageEntry:(GDataEntryPhoto *)imageEntry {
  GDataServiceGooglePhotos *picasaWebService = [self picasaWebService];
  GDataServiceTicket *uploadImageTicket
    = [picasaWebService fetchEntryByInsertingEntry:imageEntry
                                        forFeedURL:[self imagePostURL]
                                          delegate:self
                                 didFinishSelector:@selector(imageUploader:
                                                             finishedWithEntry:
                                                             error:)];
  [uploadImageTicket setProperty:imageEntry
                          forKey:kPicasaWebUploadImageActionImageEntryKey];
  @synchronized (activeTickets_) {
    [activeTickets_ addObject:uploadImageTicket];
  }
}

- (void)imageUploader:(GDataServiceTicket *)ticket
    finishedWithEntry:(NSData *)data
                error:(NSError *)error {
  @synchronized (activeTickets_) {
    [activeTickets_ removeObject:ticket];
  }
  GDataEntryPhoto *imageEntry
    = [ticket propertyForKey:kPicasaWebUploadImageActionImageEntryKey];
  NSString *imageName = [[imageEntry title] stringValue];
  NSString *mimeType = [imageEntry photoMIMEType];
  if (!error) {
    // Only notify the user for the first success.
    if (![self userWasNoticed]) {
      [self setUserWasNoticed:YES];
      NSString *imageOrVideo = nil;
      if ([mimeType hasPrefix:@"image"]) {
        imageOrVideo
          = HGSLocalizedString(@"Image",
                               @"Used to specify that an image has been "
                               @"uploaded.  Note that the capitalization "
                               @"may need to be adjusted based on placement "
                               @"with the \"%1$@ '%2$@' uploaded to your Drop Box "
                               @"at Picasa Web.\" string.");
      } else {
        imageOrVideo
          = HGSLocalizedString(@"Video",
                               @"Used to specify that a video has been "
                               @"uploaded.  Note that the capitalization "
                               @"may need to be adjusted based on placement "
                               @"with the \"%1$@ '%2$@' uploaded to your Drop Box "
                               @"at Picasa Web.\" string.");
      }
      imageOrVideo
        = HGSLocalizedString(imageOrVideo,
                             @"Either 'Image' or 'Video' specifying the type "
                             @"of object being uploaded.");
      NSString *successFormat
        = HGSLocalizedString(@"%1$@ '%2$@' uploaded to your Drop Box at "
                             @"Picasa Web.", 
                             @"A message explaining to the user that an "
                             @"image was successfully uploaded. %1$@ "
                             @"is either 'image' or 'movie' and %2$@ "
                             @"is the name of the image or movie that was "
                             @"uploaded.  If the order of %1$@/%2$@ is "
                             @"changed you may need to change the "
                             @"capitalization of 'Image' and 'Video'.");
      NSString *successString = [NSString stringWithFormat:successFormat, 
                                 imageOrVideo, imageName];
      [self informUserWithDescription:successString
                                 type:kHGSUserMessageNoteType];
    }
  } else {
    // We will retry a limited number of times before giving up.
    NSNumber *attemptNumber
      = [imageEntry propertyForKey:kPicasaWebUploadImageActionAttemptNumberKey];
    NSUInteger attempt = [attemptNumber unsignedIntValue];
    if (attempt < kMaxUploadAttempts) {
      attemptNumber = [NSNumber numberWithUnsignedInteger:++attempt];
      [imageEntry setProperty:attemptNumber
                       forKey:kPicasaWebUploadImageActionAttemptNumberKey];

      // Get retry time in seconds from the response header (http://s/5398335)
      NSDictionary *responseHeaders = [[ticket currentFetcher] responseHeaders];
      NSString *retryStr = [responseHeaders objectForKey:@"Retry-After"];
      NSTimeInterval delay = [retryStr intValue];
      // If the retry time wasn't in the headers or was unreasonable, use
      // a standard short delay.
      if (delay <= 0 || delay >= 120) {
        delay = (NSTimeInterval)(2 << attempt);
      }
 
      GDataServiceGooglePhotos *picasaWebService = [self picasaWebService];
      NSArray *modes = [picasaWebService runLoopModes];
      if (modes) {
        [self performSelector:@selector(retryUploadImageEntry:)
                   withObject:imageEntry
                   afterDelay:delay
                      inModes:modes];
      }
      else {
        [self performSelector:@selector(retryUploadImageEntry:)
                   withObject:imageEntry
                   afterDelay:delay];
      }
    } else {
      NSString *errorFormat
        = HGSLocalizedString(@"Could not upload image '%1$@'. \"%2$@\" (%3$d)", 
                             @"A message explaining to the user that we "
                             @"could not upload an image. %1$@ is the "
                             @"name of the image to be uploaded.  %2$@ is "
                             @"the error description. And %3$d is the "
                             @"error code.");
      NSString *errorString = [NSString stringWithFormat:errorFormat,
                               [imageEntry title],
                               [error localizedDescription], [error code]];
      [self informUserWithDescription:errorString
                                 type:kHGSUserMessageErrorType];
      HGSLog(@"PicasaWebUploadAction upload of image '%@' to account '%@' "
             @"failed: error=%d '%@'.",
             [imageEntry title], [account_ displayName], [error code],
             [error localizedDescription]);
    }
  }
}

- (void)inputStream:(GDataProgressMonitorInputStream *)stream 
          bytesSent:(unsigned long long)bytesSent 
         totalBytes:(unsigned long long)totalBytes {
  [self setBytesSent:bytesSent];
}

#pragma mark Utility Methods

- (void)informUserWithDescription:(NSString *)description
                             type:(HGSUserMessageType)type {
  NSImage *picasaIcon = [self imageNamed:@"PicasaWeb.icns"];
  NSString *summary 
    = HGSLocalizedString(@"Picasa Web", 
                         @"A dialog title. Picasa Web is a product name");
  [HGSUserMessenger displayUserMessage:summary 
                           description:description 
                                  name:kPicasaWebUserMessageName 
                                 image:picasaIcon 
                                  type:type];
}

- (void)loginCredentialsChanged:(NSNotification *)notification {
  HGSAccount *account = [notification object];
  HGSAssert(account == account_, @"Notification from bad account!");
  // Halt any outstanding uploads and reset the service so that it
  // will get rebuilt with the new credentials.
  [self cancelAllTickets];
  [self setPicasaWebService:nil];
}

// staticMIMETypeForPath returns a hard-coded MIME type for the extension
// in the supplied path, or nil for failure.  We call this if
// -[GDataUtilities MIMETypeForFileAtPath:...] fails to properly
// identify the type.
+ (NSString *)staticMIMETypeForPath:(NSString *)path {
  NSDictionary *dict =  [NSDictionary dictionaryWithObjectsAndKeys:
                         @"image/jpeg",      @"jpg",
                         @"image/jpeg",      @"jpe",
                         @"image/jpeg",      @"jpeg",
                         @"image/gif",       @"gif",
                         @"image/png",       @"png",
                         @"image/bmp",       @"bmp",
                         
                         @"video/mp4",       @"mp4",
                         @"video/mpeg",      @"mpg",
                         @"video/mpeg",      @"mpeg",
                         @"video/mpeg",      @"m4v",
                         
                         @"video/quicktime", @"mov",
                         @"video/quicktime", @"qt",
                         @"video/3gpp",      @"3gp",
                         @"video/3gpp",      @"3gpp",
                         @"video/3gpp",      @"3g2",
                         
                         @"video/avi",       @"avi",
                         @"video/x-ms-wmv",  @"wmv",
                         @"video/x-ms-asf",  @"asf",
                         nil];
  
  NSString *extension = [path pathExtension];
  if (extension != nil) {
    NSString *mimeType = [dict objectForKey:[extension lowercaseString]];
    return mimeType;
  }
  return nil;
}

#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(HGSAccount *)account {
  HGSAssert(account == account_, @"Notification from bad account!");
  // Halt any outstanding uploads and reset the service.
  [self cancelAllTickets];
  [self setPicasaWebService:nil];
  return YES;
}

@end


@implementation NSNotificationCenter (PicasaWebUploadImageAction)

@end


