//
//  GoogleDocsSaveAsActions.m
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

static NSString *const kDocumentDownloadFormat
  = @"http://docs.google.com/feeds/download/documents/Export?"
    @"docID=%@&exportFormat=%@";

// TODO(mrossetti): Spreadsheet exporting is not yet implemented.
static NSString *const kSpreadsheetDownloadFormat
  = @"http://spreadsheets.google.com/feeds/download/spreadsheets/Export?"
    @"key=%@&fmcmd=%d";
static NSString *const kWorksheetPageDownloadFormat = @"&gid=%u";

// Export values for the 'fmcmd' parameter found at:
// http://code.google.com/apis/documents/docs/2.0/reference.html#ExportParameters
enum {
  eFmcmdXLS = 4,    // Excel spreadsheet
  eFmcmdCSV = 5,    // Comma-spearated text file
  eFmcmdPDF = 12,   // PDF file
  eFmcmdODS = 13,   // OpenDocument spreadsheet
  eFmcmdTSV = 23,   // Tab-separated text file
  eFmcmdHTML = 102  // HTML file
};

// An action which supports saving a Google Docs as a local file.
//
// Note that when exporting a spreadsheet to CSV or TSV only one worksheet
// can be saved at a time (an API limitation).
//
@interface GoogleDocsSaveAsAction : HGSAction

// Common function that receives a download URL, the GData service
// associated with the download request, and the saveAs information
// needed by the fetcher handlers for completing the save.
- (void)downloadDocument:(NSString *)downloadCommand 
                 service:(GDataServiceGoogle *)service
              saveAsInfo:(NSDictionary *)saveAsInfo;

// Send a user notification to the Vermilion client.
- (void)informUserWithDescription:(NSString *)description
                      successCode:(NSInteger)successCode
                          fetcher:(GDataHTTPFetcher *)fetcher;
@end


@implementation GoogleDocsSaveAsAction

- (BOOL)appliesToResult:(HGSResult *)result {
  // TODO(mrossetti: Only accept webpage results created by the GoogleDocsSource.
  BOOL doesApply = ![result isFileResult];
  NSString *category = [result valueForKey:kGoogleDocsDocCategoryKey];
  doesApply = (category != nil);
  return doesApply;
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  id<HGSDelegate> delegate = [[HGSPluginLoader sharedPluginLoader] delegate];
  HGSResultArray *directObjects = [info objectForKey:kHGSActionDirectObjectsKey];
  for (HGSResult *directObject in directObjects) {
    NSDictionary *requestDict
      = [NSDictionary dictionaryWithObjectsAndKeys:
         self, kHGSSaveAsRequesterKey,
         directObject, kHGSSaveAsHGSResultKey,
         @"GoogleDocsSaveAs", kHGSSaveAsRequestTypeKey,
         nil];
    NSDictionary *responseDict = [delegate getActionSaveAsInfoFor:requestDict];
    NSNumber *successNum = [responseDict objectForKey:kHGSSaveAsAcceptableKey];
    BOOL success = [successNum boolValue];
    if (success) {
      NSString *extension
        = [responseDict objectForKey:kGoogleDocsDocSaveAsExtensionKey];
      NSString *docID = [directObject valueForKey:kGoogleDocsDocSaveAsIDKey];
      // Strip the document type prefix.
      NSSet *typePrefixes = [NSSet setWithObjects:
                             @"document:",
                             @"spreadsheet:",
                             @"presentation:",
                             nil];
      NSRange colonRange = [docID rangeOfString:@":"];
      if (colonRange.length) {
        NSString *prefix
          = [docID substringToIndex:colonRange.location + colonRange.length];
        if ([typePrefixes member:prefix]) {
          docID = [docID substringFromIndex:colonRange.location
                   + colonRange.length];
        }
      }
      docID = [GDataUtilities stringByURLEncodingForURI:docID];
      GoogleDocsSource *source
        = (GoogleDocsSource *)[directObject source];
      GDataServiceGoogle *service = [source serviceForDoc:directObject];
      HGSAssert(service, nil);

      // The method of retrieving the document is different for
      // docs/presentation and spreadsheets.
      NSString *category = [directObject valueForKey:kGoogleDocsDocCategoryKey];
      NSString *command = nil;
      if ([category isEqualToString:kDocCategorySpreadsheet]) {
        // Must use the fmcmd parameter and translate the extension into
        // a number: xls: 4, csv: 5, pdf: 12, ods: 13, tsv: 23, html:102.
        NSInteger formatNum = eFmcmdXLS;
        if ([extension isEqualToString:@"xls"]) {
          formatNum = eFmcmdXLS;
        } else if ([extension isEqualToString:@"csv"]) {
          formatNum = eFmcmdCSV;
        } else if ([extension isEqualToString:@"pdf"]) {
          formatNum = eFmcmdPDF;
        } else if ([extension isEqualToString:@"ods"]) {
          formatNum = eFmcmdODS;
        } else if ([extension isEqualToString:@"tsv"]) {
          formatNum = eFmcmdTSV;
        } else if ([extension isEqualToString:@"html"]) {
          formatNum = eFmcmdHTML;
        } else {
          HGSLogDebug(@"Unexpected extension type '%@'.", extension);
        }
        command = [NSString stringWithFormat:kSpreadsheetDownloadFormat,
                   docID, formatNum];
        if (formatNum == eFmcmdCSV || formatNum == eFmcmdTSV) {
          // Only one worksheet can be exported at a time for these formats.
          NSUInteger worksheetIndex = 0;
          NSNumber *worksheetNumber
            = [info objectForKey:kGoogleDocsDocSaveAsWorksheetIndexKey];
          if (worksheetNumber) {
            worksheetIndex = [worksheetNumber unsignedIntValue];
          }
          command
            = [command stringByAppendingFormat:kWorksheetPageDownloadFormat,
               worksheetIndex];
          [self downloadDocument:command
                         service:service
                      saveAsInfo:responseDict];
        } else {
          [self downloadDocument:command
                         service:service
                      saveAsInfo:responseDict];
        }
      } else {
        // Must use the exportFormat parameter.
        command = [NSString stringWithFormat:kDocumentDownloadFormat,
                   docID, extension];
        [self downloadDocument:command
                       service:service
                    saveAsInfo:responseDict];
      }
    }
  }
  return YES;
}

- (void)downloadDocument:(NSString *)downloadCommand 
                 service:(GDataServiceGoogle *)service
              saveAsInfo:(NSDictionary *)saveAsInfo {
  NSURL *downloadURL = [NSURL URLWithString:downloadCommand];
  NSURLRequest *request = [service requestForURL:downloadURL
                                            ETag:nil
                                      httpMethod:nil];
  GDataHTTPFetcher *fetcher = [GDataHTTPFetcher
                               httpFetcherWithRequest:request];
  [fetcher setProperties:saveAsInfo];
  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(fetcher:finishedWithData:)
                  didFailSelector:@selector(fetcher:failedWithError:)];
}

- (void)fetcher:(GDataHTTPFetcher *)fetcher finishedWithData:(NSData *)data {
  // save the file to the local path specified by the user
  NSURL *saveURL = [fetcher propertyForKey:kHGSSaveAsURLKey];
  NSString *extension = [fetcher propertyForKey:kGoogleDocsDocSaveAsExtensionKey];
  NSString *savePath = [saveURL path];
  savePath = [savePath stringByAppendingPathExtension:extension];
  NSError *error = nil;
  BOOL didWrite = [data writeToFile:savePath
                            options:NSAtomicWrite
                              error:&error];
  if (!didWrite) {
    NSString *errorFormat
      = HGSLocalizedString(@"Could not save Google Doc ‘%@’! (%d)", 
                           @"A dialog label explaining to the user that we could "
                           @"not save a Google Doc. %d is an error code.");
    NSString *errorString = [NSString stringWithFormat:errorFormat,
                             savePath, [error code]];
    [self informUserWithDescription:errorString
                        successCode:kHGSSuccessCodeBadError
                            fetcher:fetcher];
    HGSLog(@"Error: %@ saving file: %@", error, savePath);
  }
}

- (void)fetcher:(GDataHTTPFetcher *)fetcher failedWithError:(NSError *)error {
  NSString *errorFormat
    = HGSLocalizedString(@"Could not fetch Google Doc! (%d)", 
                         @"A dialog label explaining to the user that we could "
                         @"not fetch a Google Doc. %d is an error code.");
  NSString *errorString = [NSString stringWithFormat:errorFormat,
                           [error code]];
  [self informUserWithDescription:errorString
                      successCode:kHGSSuccessCodeBadError
                          fetcher:fetcher];
  HGSLog(@"Google Doc fetch failed due to error %d: '%@'.",
         [error code], [error localizedDescription]);
}

- (void)informUserWithDescription:(NSString *)description
                      successCode:(NSInteger)successCode
                          fetcher:(GDataHTTPFetcher *)fetcher {
  HGSResult *result = [fetcher propertyForKey:kHGSSaveAsHGSResultKey];
  NSString *category = [result valueForKey:kGoogleDocsDocCategoryKey];
  HGSAssert(category, nil);
  category = [NSString stringWithFormat:@"gdoc%@", category];
  NSBundle *bundle = HGSGetPluginBundle();
  NSString *path = [bundle pathForResource:category ofType:@"icns"];
  NSImage *categoryIcon
    = [[[NSImage alloc] initByReferencingFile:path] autorelease];
  HGSAssert(categoryIcon, @"Missing Google Doc category icon.");
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSNumber *successNumber = [NSNumber numberWithInt:successCode];
  NSString *summary 
    = HGSLocalizedString(@"Google Docs", @"A dialog title.");
  NSDictionary *messageDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       summary, kHGSSummaryMessageKey,
       categoryIcon, kHGSImageMessageKey,
       successNumber, kHGSSuccessCodeMessageKey,
       // Description last since it might be nil.
       description, kHGSDescriptionMessageKey,
       nil];
  [nc postNotificationName:kHGSUserMessageNotification 
                    object:self
                  userInfo:messageDict];
}

@end
