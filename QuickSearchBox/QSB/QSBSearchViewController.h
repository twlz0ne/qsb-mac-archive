//
//  QSBSearchViewController.h
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

#import <Cocoa/Cocoa.h>
#import "GTMDefines.h"

@class QSBMoreResultsViewController;
@class QSBSearchController;
@class QSBResultsViewBaseController;
@class QSBSearchWindowController;
@class QSBTopResultsViewController;
@class QSBTableResult;
@class HGSResultArray;
@class HGSAction;
@class HGSTokenizedString;

// The controller associated with a particular query responsible for
// managing the relationship between this query and any previous query
// from which this was pivoted.  Manages the visual presentation of the
// results of the query.  Handles user interaction upon a result item
// for pivoting further or performing an action.
// TODO(mrossetti): Most of this was functionality was migrated from
// QSBSearchWindowController but there is still some more functionality
// to be moved.
//
@interface QSBSearchViewController : NSViewController {
@private
  IBOutlet QSBSearchController *searchController_;
  IBOutlet QSBTopResultsViewController *topResultsController_;
  IBOutlet QSBMoreResultsViewController *moreResultsController_;
  IBOutlet NSPathControl *statusBar_;
  QSBSearchWindowController *searchWindowController_;
  __weak QSBResultsViewBaseController *activeResultsViewController_;
  // The view from which this query was pivoted, if any.
  QSBSearchViewController *parentSearchViewController_;
  NSString *pivotQueryString_;  // What was typed when the user pivoted.
  NSRange pivotQueryRange_;  // What was selected when the user pivoted.
}

@property(nonatomic, retain) QSBSearchWindowController *searchWindowController;
@property(nonatomic, copy) NSString *savedPivotQueryString;
@property(nonatomic, assign) NSRange savedPivotQueryRange;
@property(nonatomic, readonly, retain) QSBTopResultsViewController *topResultsController;
@property(nonatomic, readonly, retain) QSBMoreResultsViewController *moreResultsController;
@property(nonatomic, readonly, assign) QSBResultsViewBaseController *activeResultsViewController;
@property(nonatomic, readonly, assign) QSBSearchController *searchController;
@property(nonatomic, readwrite, retain) QSBSearchViewController *parentSearchViewController;
// The height of the results window necessary to accommodate the active view.
@property(nonatomic, readonly, assign) CGFloat windowHeight;
// The current results for the query.
@property(nonatomic, readwrite, retain) HGSResultArray *results;
// Return the selected table result from the active results controller.
@property(nonatomic, readonly, retain) QSBTableResult *selectedTableResult;

// Initialize and install into the search results window.  Designated initializer.
- (id)initWithWindowController:(QSBSearchWindowController *)searchWindowController;

// Update active results views immediately.
- (void)updateResultsViewNow;

// Post a desire for the results views to be updated soon.
- (void)updateResultsView;

// Stop all source operations for this query.
- (void)stopQuery;

// Just became active search controller
- (void)didMakeActiveSearchViewController;

// Show Top Results or More Results.
- (void)showTopResults:(id)sender;
- (void)showMoreResults:(id)sender;
- (void)toggleTopMoreViews;

// Reset our results views.
- (void)reset;

// Perform an action on results
- (void)performAction:(HGSAction *)action 
          withResults:(HGSResultArray *)results;

// Perform the default action on the selected object in the active results controller.
- (BOOL)performDefaultActionOnSelectedRow;

// Change the selection, if acceptable, in the active results presentation.
- (BOOL)performSelectionMovementSelector:(SEL)selector;

// Setting/Getting the query string
- (void)setQueryString:(NSString *)queryString;
- (void)setTokenizedQueryString:(HGSTokenizedString *)queryString;
- (HGSTokenizedString *)tokenizedQueryString;
@end

// Notification that an action will be performed.
// If you want to know that an action did get performed, look for the
// HGSActionDidPerformNotification
// Object is the action id<HGSAction>
// UserInfo keys
//   kQSBNotificationQueryKey - query that found the object that the action is 
//                             being performed on (QSBQuery)
//   kQSBNotificationDirectObjectKey - the direct object the action is being 
//                                     performed on(HGSScoredResult)
//   kQSBNotificationIndirectObjectKey - the indirect object the action is 
//                                       being performed on(HGSScoredResult)
//   kQSBNotificationSuccessKey - did the action complete successfully (NSNumber)
// object is the action being performed (HGSAction)
#define kQSBQueryControllerWillPerformActionNotification \
  @"QSBQueryControllerWillPerformActionNotification"

// Notification that the selected result did change.
// Object is the QSBSearchViewController
// Userinfo keys:
//   QSBSelectedTableResultKey - the QSBTableResult if one is selected.
//
// If nothing is selected, there will be no kQSBSelectedResultKey.
#define kQSBSelectedTableResultDidChangeNotification \
  @"QSBSelectedTableResultDidChangeNotification"
#define kQSBSelectedTableResultKey @"QSBSelectedTableResultKey"


