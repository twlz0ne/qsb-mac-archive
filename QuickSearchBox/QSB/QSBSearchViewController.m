//
//  QSBSearchViewController.m
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

#import "QSBSearchViewController.h"
#import <QSBPluginUI/QSBPluginUI.h>

#import "QSBApplicationDelegate.h"
#import "QSBMoreResultsViewController.h"
#import "QSBSearchController.h"
#import "QSBTableResult.h"
#import "QSBResultsViewBaseController.h"
#import "QSBSearchWindowController.h"
#import "QSBTopResultsViewController.h"

NSString *const kScrollViewHiddenKeyPath = @"hidden";

@interface QSBSearchViewController ()

// Setter for specifying the active results view controller.
- (void)setActiveResultsViewController:(QSBResultsViewBaseController *)value
                               animate:(BOOL)animate;

- (void)updateViewsWithAnimation:(BOOL)animate;

@end


@implementation QSBSearchViewController
@synthesize searchWindowController = searchWindowController_;
@synthesize savedPivotQueryString = pivotQueryString_;
@synthesize savedPivotQueryRange = pivotQueryRange_;
@synthesize topResultsController = topResultsController_;
@synthesize moreResultsController = moreResultsController_;
@synthesize activeResultsViewController = activeResultsViewController_;
@synthesize searchController = searchController_;
@synthesize parentSearchViewController = parentSearchViewController_;

- (id)initWithWindowController:(QSBSearchWindowController *)searchWindowController {
  if ((self = [super initWithNibName:@"BaseResultsViews" bundle:nil])) {
    [self setSearchWindowController:searchWindowController];
    // TODO(alcor): this should be removed, but much of the searchWindow code
    // assumes the nib connections are intact when this method returns
    [self loadView];
  }
  return self;
}

- (void)awakeFromNib {
  [self setActiveResultsViewController:topResultsController_ animate:NO];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  QSBResultsViewTableView *topResultsView = [topResultsController_ resultsTableView];
  [nc addObserver:self 
         selector:@selector(tableViewSelectionDidChange:) 
             name:NSTableViewSelectionDidChangeNotification 
           object:topResultsView];
  QSBResultsViewTableView *moreResultsView = [moreResultsController_ resultsTableView];
  [nc addObserver:self 
         selector:@selector(tableViewSelectionDidChange:) 
             name:NSTableViewSelectionDidChangeNotification 
           object:moreResultsView];
  [nc addObserver:self 
         selector:@selector(tableViewSelectionDidChange:) 
             name:kQSBMoreResultsDidShowCategoryNotification 
           object:moreResultsController_];
  [nc addObserver:self 
         selector:@selector(tableViewSelectionDidChange:)
             name:kQSBSearchControllerDidUpdateResultsNotification
           object:searchController_];
}

- (void)dealloc {
  [parentSearchViewController_ release];
  [pivotQueryString_ release];
  [searchWindowController_ release];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (void)setParentSearchViewController:(QSBSearchViewController *)parentViewController {
  [parentSearchViewController_ autorelease];
  parentSearchViewController_ = [parentViewController retain];
  QSBSearchController *parentSearchController 
    = [parentViewController searchController];
  [searchController_ setParentSearchController:parentSearchController];
  QSBSourceTableResult *selectedObject 
    = (QSBSourceTableResult *)[parentViewController selectedTableResult];
  HGSAssert(!selectedObject 
            || [selectedObject isKindOfClass:[QSBSourceTableResult class]],
            @"expected a QSBSourceTableResult and got %@", selectedObject);
  HGSScoredResult *result = [selectedObject representedResult];
  HGSResultArray *results = [HGSResultArray arrayWithResult:result];
  [self setResults:results];
}

- (void)updateResultsViewNow {
  // Mark all results controllers as needing to be updated.
  [topResultsController_ setResultsNeedUpdating:YES];
  [moreResultsController_ setResultsNeedUpdating:YES];
  
  // Immediately update the active controller and determine window height.
  [[self activeResultsViewController] updateResultsView];
}

- (void)updateResultsView {
  [searchWindowController_ updateResultsView];
}

- (void)stopQuery {
  [searchController_ stopQuery];
}

- (CGFloat)windowHeight {
  return [[self activeResultsViewController] windowHeight]
    + NSHeight([statusBar_ bounds]);
}

- (void)setQueryString:(NSString *)queryString {
  HGSTokenizedString *tokenizedString
    = [HGSTokenizer tokenizeString:queryString];
  [self setTokenizedQueryString:tokenizedString];
}

- (void)setTokenizedQueryString:(HGSTokenizedString *)queryString {
  if ([self activeResultsViewController] != topResultsController_) {
    [self showTopResults:self];
  } else {
    // If we don't need to swap views, at least update the view locations
    // in case they have shifted
    // TODO(alcor): this causes the wrong size to be set. Fix
    //[self updateViewsWithAnimation:NO];
  }
  [searchController_ setTokenizedQueryString:queryString];
}

- (HGSTokenizedString *)tokenizedQueryString {
  return [searchController_ tokenizedQueryString];
}

- (QSBTableResult *)selectedTableResult {
  QSBResultsViewBaseController *controller = [self activeResultsViewController];
  QSBTableResult *result = [controller selectedTableResult];
  return result;
}

- (void)setResults:(HGSResultArray *)results {
  [searchController_ setResults:results];
}

- (HGSResultArray *)results {
  return [searchController_ results];
}

- (void)performAction:(HGSAction *)action
          withResults:(HGSResultArray *)results {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSMutableDictionary *userInfo 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       results, kQSBNotificationDirectObjectsKey,
       searchController_, kQSBNotificationSearchControllerKey,
       nil];
  [nc postNotificationName:kQSBQueryControllerWillPerformActionNotification
                    object:action
                  userInfo:userInfo];
  HGSActionOperation *op 
    = [[[HGSActionOperation alloc] initWithAction:action
                                    directObjects:results] autorelease];
  [op performAction]; 
}

- (BOOL)performDefaultActionOnSelectedRow {
  QSBTableResult *result = [self selectedTableResult];
  return [result performDefaultActionWithSearchViewController:self];
}

- (BOOL)performSelectionMovementSelector:(SEL)selector {
  BOOL acceptable = [[self activeResultsViewController]
                     performSelectionMovementSelector:selector];
  return acceptable;
}

- (void)didMakeActiveSearchViewController {
  [self tableViewSelectionDidChange:nil];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  QSBTableResult *tableResult = [self selectedTableResult];
  NSArray *cellValues = nil;
  if ([tableResult respondsToSelector:@selector(representedResult)]) {
    HGSScoredResult *result 
      = [(QSBSourceTableResult *)tableResult representedResult];
    cellValues = [result valueForKey:kQSBObjectAttributePathCellsKey];
  }
  [statusBar_ setObjectValue:cellValues];
  
  NSDictionary *userInfo = nil;
  if (tableResult) {
    userInfo = [NSDictionary dictionaryWithObject:tableResult 
                                           forKey:kQSBSelectedTableResultKey];
  }
  [nc postNotificationName:kQSBSelectedTableResultDidChangeNotification
                    object:self 
                  userInfo:userInfo];
}

#pragma mark Top/More Results View Control
- (void)showTopResults:(id)sender {
  [self setActiveResultsViewController:topResultsController_ animate:YES];
}

- (void)showMoreResults:(id)sender {
  [self setActiveResultsViewController:moreResultsController_ animate:YES];
}

- (void)toggleTopMoreViews {
  if (activeResultsViewController_ == topResultsController_) {
    [self showMoreResults:self];
  } else {
    [self showTopResults:self];
  }
}

- (void)reset {
  // Give our results view controllers a chance to reset.
  [topResultsController_ reset];
  [moreResultsController_ reset];
}

- (void)updateViewsWithAnimation:(BOOL)animate {
  QSBSearchWindowController *searchWindowController
    = [self searchWindowController];
  QSBResultsViewBaseController *activeResultsViewController
    = [self activeResultsViewController];
  CGFloat newHeight = [activeResultsViewController windowHeight];
  newHeight += [searchWindowController resultsViewOffsetFromTop];
  
  int resizingMask = NSViewWidthSizable | NSViewHeightSizable;
  int pinToTopMask = NSViewWidthSizable | NSViewMinYMargin;
  
  NSView *topView = [topResultsController_ view];
  NSView *moreView = [moreResultsController_ view];
  
  [topView setAutoresizingMask:pinToTopMask];
  [moreView setAutoresizingMask:pinToTopMask];
  [searchWindowController setResultsWindowHeight:(newHeight
                                                  + NSHeight([statusBar_ bounds]))
                                       animating:NO];
  [topView setAutoresizingMask:resizingMask];
  [moreView setAutoresizingMask:resizingMask];
  
  NSRect viewBounds = [[self view] bounds];
  viewBounds.origin.y += NSHeight([statusBar_ bounds]);
  viewBounds.size.height -= NSHeight([statusBar_ bounds]);
  NSView *hideView = nil;
  NSRect topFrame = [topView frame];
  NSRect moreFrame = viewBounds;
  
  if (activeResultsViewController == moreResultsController_) { 
    [moreView setHidden:NO];
    
    if (![moreView superview]) {
      [[self view] addSubview:moreView 
                   positioned:NSWindowBelow
                   relativeTo:topView];
      NSRect moreStartFrame = moreFrame;
      moreStartFrame.origin.y = topFrame.origin.y - NSHeight(moreFrame);
      [moreView setFrame:moreStartFrame];
    }
    topFrame.origin.y = NSMaxY(viewBounds);   
    [topView setAutoresizingMask:pinToTopMask];
    hideView = topView;
  } else {
    topFrame = viewBounds;
    moreFrame.origin.y = NSMinY(viewBounds) - NSHeight(moreFrame);
    hideView = moreView;
  }
    
  if (animate) {
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.2];
    [[topView animator] setFrame:topFrame];
    [[moreView animator] setFrame:moreFrame];
    [NSAnimationContext endGrouping];
  } else {
    [topView setFrame:topFrame];
    [moreView setFrame:moreFrame];
  }
  if (hideView == topView) {
    [topView setHidden:YES];
    [moreView setHidden:NO];
  } else {
    [moreView setHidden:YES];
    [topView setHidden:NO];
  }
}

- (void)setActiveResultsViewController:(QSBResultsViewBaseController *)newController
                               animate:(BOOL)animate {
  
  if (activeResultsViewController_ != newController) {
    [newController updateResultsView];
     
    // Swap out the old view while swapping in the top results view.
    [newController setSwapSelection];
    
    [self willChangeValueForKey:@"activeResultsViewController"];
    activeResultsViewController_ = newController;
    [self didChangeValueForKey:@"activeResultsViewController"];
    [self updateViewsWithAnimation:animate];
    [self tableViewSelectionDidChange:nil];
  }
}
@end
