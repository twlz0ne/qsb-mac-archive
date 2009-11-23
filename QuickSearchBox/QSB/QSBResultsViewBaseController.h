//
//  QSBResultsViewBaseController.h
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
#import "QSBViewTableViewDelegateProtocol.h"


@class QSBSearchViewController;
@class QSBResultsViewTableView;
@class QSBTableResult;

// Abstract base class for the result views which manages the presentation
// of results in the Top Results and the More Results views.
//
@interface QSBResultsViewBaseController : NSViewController <QSBViewTableViewDelegateProtocol> {
 @private
  IBOutlet QSBSearchViewController *searchViewController_;
  IBOutlet NSView *resultsView_;
  IBOutlet QSBResultsViewTableView *resultsTableView_;

  // Storage for our lazily created row results view controllers.
  NSMutableDictionary *rowViewControllers_;
  
  BOOL isShowing_;  // YES when our results section is showing.
  BOOL resultsNeedUpdating_;
  CGFloat lastWindowHeight_;  // Remember last calculated window height.
}

// Returns the query controller.
- (QSBSearchViewController *)searchViewController;

// Return the various views associated with this controller.
- (NSView *)resultsView;
- (QSBResultsViewTableView *)resultsTableView;

// Get some UI metrics
- (CGFloat)minimumTableHeight;
- (CGFloat)maximumTableHeight;
- (BOOL)isTransitionDirectionUp;

// Set/get that the results for this view need to be updated.
- (void)setResultsNeedUpdating:(BOOL)value;
- (BOOL)resultsNeedUpdating;

// Show or hide the results view.  Return the previously calculated
// window height if our results view is showing.
- (CGFloat)setIsShowing:(BOOL)value;
- (BOOL)isShowing;

// Call this when swapping in this view so that the proper selection
// is made in the result table.  The default behavior is to select
// the first selectable row.
- (void)setSwapSelection;

// Return the last selected table item.
- (QSBTableResult *)selectedTableResult;

// For a given row in the table, return the associated QSBTableResult
- (QSBTableResult *)tableResultForRow:(NSInteger)row;

// Reset due to a query restart.  The default implementation selects the
// first row of the results table.
- (void)reset;

// Update the metrics of our results presentation and propose a new window height.
- (CGFloat)updateResultsView;

// Return the most recently calculated window height to properly show ourself.
- (CGFloat)windowHeight;

// Determines if the provided selector is a selection movement selector,
// performs it if so, and returns whether it was performed.
- (BOOL)performSelectionMovementSelector:(SEL)selector;

// Select previous, next, first or last rows in the results table.
- (void)moveUp:(id)sender;
- (void)moveDown:(id)sender;
- (void)scrollToBeginningOfDocument:(id)sender;
- (void)scrollToEndOfDocument:(id)sender;
- (void)scrollPageUp:(id)sender;
- (void)scrollPageDown:(id)sender;

// Derived classes must provide a view controller class for a given result
- (Class)rowViewControllerClassForResult:(QSBTableResult *)result;

// Respond to a click in the path control.
- (void)pathControlClick:(id)sender;

@end
