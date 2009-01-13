//
//  QSBSearchWindowController.h
//
//  Copyright (c) 2006-2008 Google Inc. All rights reserved.
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

@class QSBTextFieldEditor;
@class QSBLargeIconView;
@class QSBMenuButton;
@class QSBCustomPanel;
@class QSBQueryController;
@class CAAnimation;

const NSTimeInterval kQSBAppearDelay;

@interface QSBSearchWindowController : NSWindowController {
 @private
  IBOutlet QSBTextFieldEditor *searchTextFieldEditor_;
  IBOutlet NSTextField *searchTextField_;
  IBOutlet QSBLargeIconView *previewImageView_;
  IBOutlet NSImageView *logoView_;
  IBOutlet NSView *queryBackgroundView_;
  IBOutlet QSBMenuButton *searchMenu_;
  IBOutlet QSBMenuButton *windowMenuButton_;
  IBOutlet QSBCustomPanel *resultsWindow_;
  IBOutlet NSWindow *shieldWindow_;
  IBOutlet NSView *resultsOffsetterView_;

  QSBQueryController *activeQueryController_;  // Currently active query.

  BOOL needToUpdatePositionOnActivation_;  // Do we need to reposition
  // (STRONG) Resets our query to "" after kQSBResetQueryTimeoutPrefKey seconds
  NSTimer *queryResetTimer_;
  int findPasteBoardChangeCount_;  // used to detect if the pasteboard has changed
  // (STRONG) controls whether we put the pasteboard data in the qsb
  NSTimer *findPasteBoardChangedTimer_;
  BOOL insertFindPasteBoardString_;  // should we use the find pasteboard string
  BOOL showResults_;
  // YES after search text changes but results not yet acted upon.
  BOOL termChangedAndAwaitingAction_;
  CAAnimation *searchWindowSetAlphaAnimation_;
  // Our list of corpora for the searchMenu
  NSArray *corpora_;
}
@property(nonatomic, retain) QSBQueryController *activeQueryController;

// Designated initializer
- (id)init;

- (NSImageView *)previewImageView;

// Return the current query controller.
- (QSBQueryController *)activeQueryController;

// Offset of all results views from top of window.
- (float)resultsViewOffsetFromTop;

// Back up over any text or a the latest pivot, whichever comes first.
- (void)clearTextOrLastPivot:(id)sender;

// Change search window visibility
- (IBAction)hideSearchWindow:(id)sender;
- (IBAction)showSearchWindow:(id)sender;

// Take a corpus from a menu item
- (IBAction)selectCorpus:(id)sender;

// Search for current string - usually google, except in search contexts
- (IBAction)performSearch:(id)sender;

// Open a table item.
- (void)openResultsTableItem:(id)sender;

// Pivot on the current selection, if possible
- (void)pivotOnSelection;

// Utility function to handle everything that's needed when we change our results
// Resizes our window, and reloads our tableview.
- (void)updateResultsView;

// Call to signal that the query string should show best autocomplete match.
- (void)completeQueryText;

// Return our main results window.
- (NSWindow *)resultsWindow;

// Attempt to set the height of the results window while insuring that
// the results window fits comfortably on the screen along with the
// search box window.
- (void)setResultsWindowHeight:(float)height
                     animating:(bool)animating;

@end

// Notifications for showing and hiding the search window
// The object is the actual window, not the window controller.
// Note that these don't always balance. If the window is "shown" while
// the "hiding" animation is taking place, you will get
// kQSBSearchWindowWillHideNotification
// kQSBSearchWindowWillShowNotification
// kQSBSearchWindowDidShowNotification
// assuming that the show is allowed to finish.

#define kQSBSearchWindowWillShowNotification @"QSBSearchWindowWillShowNotification"
#define kQSBSearchWindowDidShowNotification @"QSBSearchWindowDidShowNotification"
#define kQSBSearchWindowWillHideNotification @"QSBSearchWindowWillHideNotification"
#define kQSBSearchWindowDidHideNotification @"QSBSearchWindowDidHideNotification"

// Notifications for pivoting
// Object is the QSBTableResult that is being pivoted on
#define kQSBWillPivotNotification @"QSBWillPivotNotification"
#define kQSBDidPivotNotification @"QSBDidPivotNotification"

// Some keys for QSB Notifications
// kQSBNotificationQueryKey type is QSBQuery *
#define kQSBNotificationQueryKey @"QSBNotificationQueryKey"
// kQSBNotificationDirectObjectKey is HGSObject *
#define kQSBNotificationDirectObjectKey @"QSBNotificationDirectObjectKey" 
// kQSBNotificationIndirectObjectKey is HGSObject *
#define kQSBNotificationIndirectObjectKey @"QSBNotificationIndirectObjectKey"
// kQSBNotificationSuccessKey type is NSNumber * representing a bool
#define kQSBNotificationSuccessKey @"QSBNotificationSuccessKey"
