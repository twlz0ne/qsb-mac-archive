//
//  GoogleDocsUploadActions.m
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
#import "GoogleDocsSource.h"
#import "GoogleDocsConstants.h"
#import "HGSKeychainItem.h"

// Information on uploading documents to Google Docs can be found at:
// http://code.google.com/apis/documents/docs/2.0/developers_guide_protocol.html#UploadingDocs

// An action which supports uploading a local file to Google Docs with
// optional conversion to Google Docs format or OCRing of image files.
//
@interface GoogleDocsUploadAction : HGSGDataUploadAction 

// Bottleneck function that performs the uploading of each document in a loop.
// This function is called by child classes. |shouldConvert| causes the
// document being uploaded to be converted from its local format into the
// Google Docs format.  |shouldConvert| is ignored when |shouldOCR| is YES
// as all OCR actions result in conversion to Google Docs format.
- (BOOL)uploadResultsWithInfo:(NSDictionary*)info
                    shouldOCR:(BOOL)shouldOCR
                 souldConvert:(BOOL)souldConvert;

// Bottleneck function which dispatches the uploading of a single result and
// which is only called by -[uploadResultsWithInfo:shouldOCR:souldConvert:].
- (void)uploadResult:(HGSResult *)docResult
           shouldOCR:(BOOL)shouldOCR
        souldConvert:(BOOL)souldConvert
                item:(NSUInteger)item
                  of:(NSUInteger)count;

@end


// Action to upload a local file as a Google Doc.
@interface GoogleDocsUploadAsGoogleDocAction : GoogleDocsUploadAction
@end


// Action to upload an image file and perform OCR resulting in a Google Doc.
@interface GoogleDocsUploadAndOCRAsGoogleDocAction : GoogleDocsUploadAction
@end


// Action to upload a local file without converting it to Google Doc format.
// This action will succeed only for Premier accounts.
@interface GoogleDocsUploadWithoutConversionToGoogleDocsAction : GoogleDocsUploadAction
@end


@implementation GoogleDocsUploadAction

- (BOOL)uploadResultsWithInfo:(NSDictionary*)info
                    shouldOCR:(BOOL)shouldOCR
                 souldConvert:(BOOL)souldConvert {
  BOOL success = NO;
  GDataServiceGoogle *uploadService = [self uploadService];
  if (uploadService) {
    [self setUserWasNoticed:NO];
    HGSResultArray *results = [info objectForKey:kHGSActionDirectObjectsKey];
    NSUInteger resultCount = [results count];
    NSUInteger item = 0;
    for (HGSResult *result in results) {
      [self uploadResult:result
               shouldOCR:shouldOCR
            souldConvert:souldConvert
                    item:item
                      of:resultCount];
      ++item;
    }
    success = YES;
  }
  return success;
}

- (void)uploadResult:(HGSResult *)result
           shouldOCR:(BOOL)shouldOCR
        souldConvert:(BOOL)souldConvert
                item:(NSUInteger)item
                  of:(NSUInteger)count {
  // See if we can ascertain the type of the file being uploaded from
  // its extension.
  NSString *resultPath = [result filePath];
  NSString *resultTitle
    = [[NSFileManager defaultManager] displayNameAtPath:resultPath];
  NSString *mimeType = [GoogleDocsUploadAction mimeTypeForResult:result];
  if (mimeType) {
    Class entryClass
      = [GoogleDocsUploadAction dataEntryClassForMIMEType:mimeType];
    
    if (entryClass) {
      GDataEntryDocBase *entry = [entryClass documentEntry];
      [entry setTitleWithString:resultTitle];
      NSData *uploadData = [NSData dataWithContentsOfFile:resultPath];
      if (uploadData) {
        [entry setUploadData:uploadData];
        [entry setUploadMIMEType:mimeType];
        [entry setUploadSlug:[resultPath lastPathComponent]];
        [self uploadGDataEntry:entry
                    entryTitle:resultTitle
                          item:item
                            of:count];
      } else {
        HGSLogDebug(@"Failed to load data for file '%@'.", resultPath);
      }
    } else {
      NSString *errorString
        = HGSLocalizedString(@"Could not upload '%@' because the type of the "
                             @"file could not be determined.", 
                             @"A message explaining that a file could "
                             @"not be uploaded because the type of the file "
                             @"could not be determined.");
      errorString = [NSString stringWithFormat:errorString, resultTitle];
      [self informUserWithDescription:errorString
                                 type:kHGSUserMessageErrorType];
      HGSLogDebug(@"Could not determine GData class for MIME type '%@'.",
                  mimeType);
    }
  } else {
    NSString *errorString
      = HGSLocalizedString(@"Could not upload '%@' because the MIME type of "
                           @"the file could not be determined.", 
                           @"A message explaining that the file given by %@ "
                           @"could not be uploaded because the MIME type of "
                           @"the file could not be determined.");
    errorString = [NSString stringWithFormat:errorString, resultTitle];
    [self informUserWithDescription:errorString
                               type:kHGSUserMessageErrorType];
    HGSLogDebug(@"Could not determine MIME type for file '%@'.", resultPath);
  }
}

- (NSURL *)uploadURL {
  return [GDataServiceGoogleDocs docsUploadURL];
}

- (Class)serviceClass {
  return [GDataServiceGoogleDocs class];
}

- (NSString *)serviceName {
  NSString *name
      = HGSLocalizedString(@"Google Docs", 
                           @"The title of a service provided by Google.");
  return name;
}

- (NSImage *)serviceIcon {
  return [self imageNamed:@"GoogleDocs.icns"];
}

@end


@implementation GoogleDocsUploadAsGoogleDocAction

- (BOOL)performWithInfo:(NSDictionary*)info {
  return [self uploadResultsWithInfo:info shouldOCR:NO souldConvert:YES];
}

- (NSURL *)uploadURL {
  return [GDataServiceGoogleDocs docsUploadURL];
}

@end


@implementation GoogleDocsUploadAndOCRAsGoogleDocAction

- (BOOL)appliesToResult:(HGSResult *)result {
  NSSet *acceptableMIMETypes = [NSSet setWithObjects:
                                @"image/gif",
                                @"image/jpeg",
                                @"image/png",
                                nil];
  NSString *mimeType = [GoogleDocsUploadAction mimeTypeForResult:result];
  return [acceptableMIMETypes containsObject:mimeType];
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  return [self uploadResultsWithInfo:info shouldOCR:YES souldConvert:YES];
}

- (NSURL *)uploadURL {
  NSURL *uploadURL = [GDataServiceGoogleDocs docsUploadURL];
  GDataQueryDocs *query = [GDataQueryDocs queryWithFeedURL:uploadURL];
  [query setShouldConvertUpload:YES];
  [query setShouldOCRUpload:YES];
  uploadURL = [query URL];
  return uploadURL;
}

@end


@implementation GoogleDocsUploadWithoutConversionToGoogleDocsAction

- (BOOL)performWithInfo:(NSDictionary*)info {
  return [self uploadResultsWithInfo:info shouldOCR:NO souldConvert:NO];
}

- (NSURL *)uploadURL {
  NSURL *uploadURL = [GDataServiceGoogleDocs docsUploadURL];
  GDataQueryDocs *query = [GDataQueryDocs queryWithFeedURL:uploadURL];
  [query setShouldConvertUpload:NO];
  uploadURL = [query URL];
  return uploadURL;
}

@end
