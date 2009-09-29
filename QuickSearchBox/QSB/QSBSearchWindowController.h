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
#import <Vermilion/Vermilion.h>
#import "GTMDefines.h"

@class QSBTextFieldEditor;
@class QSBLargeIconView;
@class QSBMenuButton;
@class QSBCustomPanel;
@class QSBSearchViewController;
@class QSBWelcomeController;
@class QSBTableResult;
@class QSBViewAnimation;

extern const NSTimeInterval kQSBAppearDelay;

@interface QSBSearchWindowController : NSWindowController {
 @private
  IBOutlet QSBTextFieldEditor *searchTextFieldEditor_;
  IBOutlet NSTextField *searchTextField_;
  IBOutlet NSImageView *logoView_;
  IBOutlet QSBMenuButton *searchMenu_;
  IBOutlet QSBMenuButton *windowMenuButton_;
  IBOutlet QSBCustomPanel *resultsWindow_;
  IBOutlet NSWindow *shieldWindow_;
  IBOutlet NSView *resultsOffsetterView_;
  IBOutlet NSImageView *thumbnailView_;
  
  QSBSearchViewController *activeSearchViewController_;  // Currently active query.

  BOOL needToUpdatePositionOnActivation_;  // Do we need to reposition
  // (STRONG) Resets our query to "" after kQSBResetQueryTimeoutPrefKey seconds
  NSTimer *queryResetTimer_;
  NSInteger findPasteBoardChangeCount_;  // used to detect if the pasteboard has changed
  // (STRONG) controls whether we put the pasteboard data in the qsb
  NSTimer *findPasteBoardChangedTimer_;
  BOOL insertFindPasteBoardString_;  // should we use the find pasteboard string
  BOOL showResults_;
  // Our list of corpora for the searchMenu
  NSArray *corpora_;
  // The welcome window controller.
  QSBWelcomeController *welcomeController_;
  
  // Animations
  QSBViewAnimation *resultWindowVisibilityAnimation_;
  QSBViewAnimation *searchWindowVisibilityAnimation_;
  QSBViewAnimation *pivotingAnimation_;
}

@property (nonatomic, retain) QSBSearchViewController *activeSearchViewController;

// Designated initializer
- (id)init;

// Return the current search view controller.
- (QSBSearchViewController *)activeSearchViewController;

// Offset of all results views from top of window.
- (CGFloat)resultsViewOffsetFromTop;

// Change search window visibility
- (IBAction)showSearchWindow:(id)sender;
- (IBAction)hideSearchWindow:(id)sender;

// Hide/show the search window. Toggle is what caused the window to show.
// See kQSB*ChangeVisiblityToggle below.
- (void)showSearchWindowBecause:(NSString *)toggle;
- (void)hideSearchWindowBecause:(NSString *)toggle;

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

// Return our main results window.
- (NSWindow *)resultsWindow;

// Attempt to set the height of the results window while insuring that
// the results window fits comfortably on the screen along with the
// search box window.
- (void)setResultsWindowHeight:(CGFloat)height
                     animating:(BOOL)animating;

// Grab the selection from the Finder
- (IBAction)grabSelection:(id)sender;

// Drop the selection from the Finder on the current selection
- (IBAction)dropSelection:(id)sender;

// Reset the current query by unrolling all pivots, if any, and hiding the
// results window.  If no results are showing then hide the query window.
- (IBAction)resetSearchOrHideQuery:(id)sender;

// Search for a string in the UI
- (void)searchForString:(NSString *)string;

// Select an object in the UI
- (IBAction)selectResults:(HGSResultArray *)results;

// The hot key was hit.
- (void)hitHotKey:(id)sender;

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
#define kQSBSearchWindowChangeVisibilityToggleKey @"QSBSearchWindowChangeVisibilityToggleKey"
#define kQSBUnknownChangeVisibilityToggle @"QSBUnknownChangeVisiblityToggle"
#define kQSBReopenChangeVisiblityToggle @"QSBReopenChangeVisiblityToggle"
#define kQSBHotKeyChangeVisiblityToggle @"QSBHotKeyChangeVisiblityToggle"
#define kQSBExecutedChangeVisiblityToggle @"QSBExecutedChangeVisiblityToggle"
#define kQSBActivationChangeVisiblityToggle @"QSBActivationChangeVisiblityToggle"
#define kQSBDockMenuItemChangeVisiblityToggle @"QSBDockMenuChangeVisiblityToggle"
#define kQSBStatusMenuItemChangeVisiblityToggle @"QSBStatusMenuItemChangeVisiblityToggle"
#define kQSBFilesFromFinderChangeVisiblityToggle @"QSBFilesFromFinderChangeVisiblityToggle"
#define kQSBServicesMenuChangeVisiblityToggle @"QSBServicesMenuChangeVisiblityToggle"
#define kQSBAppLaunchedChangeVisiblityToggle @"QSBAppLaunchedChangeVisiblityToggle"
#define kQSBAppLostKeyFocusVisibilityToggle @"QSBAppLostKeyFocusVisibilityToggle"

// Notifications for pivoting
// Object is the QSBTableResult that is being pivoted on
#define kQSBWillPivotNotification @"QSBWillPivotNotification"
#define kQSBDidPivotNotification @"QSBDidPivotNotification"

// Some keys for QSB Notifications
// kQSBNotificationSearchControllerKey type is QSBSearchController *
#define kQSBNotificationSearchControllerKey @"QSBNotificationSearchControllerKey"
// kQSBNotificationDirectObjectsKey is HGSResultArray *
#define kQSBNotificationDirectObjectsKey @"QSBNotificationDirectObjectsKey" 
// kQSBNotificationIndirectObjectsKey is HGSResultArray *
#define kQSBNotificationIndirectObjectsKey @"QSBNotificationIndirectObjectsKey"
// kQSBNotificationSuccessKey type is NSNumber * representing a bool
#define kQSBNotificationSuccessKey @"QSBNotificationSuccessKey"


