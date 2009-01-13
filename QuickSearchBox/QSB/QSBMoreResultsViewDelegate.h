//
//  QSBMoreResultsViewDelegate.h
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

#import "QSBResultsViewBaseController.h"

@class QSBQuery;

// A controller that manages the view-based 'More' results view.
//
@interface QSBMoreResultsViewDelegate : QSBResultsViewBaseController {
 @private
  IBOutlet QSBQuery *query_;
  
  // The results we are presenting.
  NSArray *moreResults_;
  NSArray *sortedCategoryNames_;
  NSArray *sortedCategoryIndexes_;
  NSArray *sortedCategoryCounts_;
  
  // List of all category titles available for presentation in 'More' view.
  NSAttributedString *categoriesString_;
  NSSet *showAllCategoriesSet_;  // Category keys for which to 'show all'.

  // Cache our results in case a category is fully exposed (Show All...)
  // and the indexes and counts need recalculating.
  NSDictionary *moreResultsDict_;
  
  NSTimeInterval blockTime_; // Time we started blocking repeats
}

// Set/get the full more results.
- (NSArray *)moreResults;
- (void)setMoreResults:(NSArray *)value;
- (void)setMoreResultsWithDict:(NSDictionary *)value;

// Returns a list of all categories available for presentation.
- (NSAttributedString *)categoriesString;

// Adds a category to the 'show all' list and then recalculates the
// contents of the more results dictionary.
- (void)addShowAllCategory:(NSString *)category;

@end

// Notification sent out when a category is displayed
// Object is QSBMoreResultsViewDelegate
// UserInfo contains
// kQSBMoreResultsCategoryKey
#define kQSBMoreResultsDidShowCategoryNotification @"QSBMoreResultsDidShowCategoryNotification"

#define kQSBMoreResultsCategoryKey @"QSBMoreResultsCategoryKey"  // NSString *
