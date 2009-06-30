//
//  GoogleDocsConstants.h
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
  @discussion GoogleDocsConstants
*/


@class NSString;

/*!
 A category which is used to identify the Google Doc as a 'document'.
*/
extern NSString* const kDocCategoryDocument;

/*!
 A category which is used to identify the Google Doc as a 'spreadsheet'.
*/
extern NSString* const kDocCategorySpreadsheet;

/*!
 A category which is used to identify the Google Doc as a 'presentation'.
*/
extern NSString* const kDocCategoryPresentation;

/*!
 The key to the NSString result attribute giving the category of the Google Doc.
*/
extern NSString* const kGoogleDocsDocCategoryKey;  // NSString - Doc category.

/*!
 The key to the NSArray result attribute giving the names of all worksheets
 in the Google Doc spreadsheet.
 */
extern NSString* const kGoogleDocsWorksheetNamesKey;  // NSArray.

/*!
 Keys to the information carried in the saveAsInfo dictionary.
*/
#define kGoogleDocsDocSaveAsExtensionKey @"GoogleDocsDocSaveAsExtensionKey"
#define kGoogleDocsDocSaveAsWorksheetIndexKey @"GoogleDocsDocSaveAsWorksheetIndexKey"
#define kGoogleDocsDocSaveAsIDKey @"GoogleDocsDocSaveAsIDKey"
