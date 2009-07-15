//
//  GoogleDocsSource.h
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

/*!
 @header
 @discussion GoogleDocsSource -- Not for external use.  Exposed here
  for access by GoogleDocsSaveAsAction.
 */

#import <Vermilion/Vermilion.h>

@class GDataServiceGoogle;
@class GDataServiceGoogleDocs;
@class GDataServiceGoogleSpreadsheet;
@class GDataServiceTicket;

/*!
 A search source which indexes all Google Docs for a Google account.
*/
@interface GoogleDocsSource : HGSMemorySearchSource <HGSAccountClientProtocol> {
 @private
  GDataServiceGoogleDocs *docService_;
  GDataServiceTicket *docServiceTicket_;
  BOOL currentlyFetchingDocs_;
  GDataServiceGoogleSpreadsheet *spreadsheetService_;
  GDataServiceTicket *spreadsheetServiceTicket_;
  BOOL currentlyFetchingSpreadsheets_;
  NSMutableArray *activeSpreadsheetFetches_;
  __weak NSTimer *updateTimer_;
  NSDictionary *docIcons_;
  HGSAccount *account_;
  NSString *userName_;
  NSTimeInterval previousErrorReportingTime_;
}

/*!
 Returns the appropriate GData service for the doc result.
 
 At the current time, there are separate services for accessing spreadsheet.
 The service for spreadsheets may be merged into the service for docs in
 general in the future.
*/
- (GDataServiceGoogle *)serviceForDoc:(HGSResult *)doc;

@end
