//
//  QSBResultsViewBaseController.m
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
#import <Vermilion/Vermilion.h>
#import "QSBApplicationDelegate.h"
#import "QSBMoreStandardRowViewController.h"
#import "QSBQueryController.h"
#import "QSBTableResult.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "QSBTopStandardRowViewController.h"
#import "GTMGeometryUtils.h"

static const CGFloat kScrollViewMinusTableHeight = 7.0;
static NSString * const kQSBArrangedObjectsKVOKey = @"arrangedObjects";

@interface QSBResultsViewBaseController (QSBResultsViewBaseControllerPrivateMethods)

// Return our main search window controller.
- (QSBSearchWindowController *)searchWindowController;

@end


@implementation QSBResultsViewBaseController
- (void)awakeFromNib {
  rowViewControllers_ = [[NSMutableDictionary dictionary] retain];
  [resultsArrayController_ addObserver:self
                            forKeyPath:kQSBArrangedObjectsKVOKey
                               options:NSKeyValueObservingOptionNew
                               context:NULL];
  resultsNeedUpdating_ = YES;
  [resultsTableView_ setDoubleAction:@selector(openResultsTableItem:)];
  QSBSearchWindowController *controller = [self searchWindowController];
  [resultsTableView_ setTarget:controller];
}

- (void)dealloc {
  [rowViewControllers_ release];
  [resultsArrayController_ removeObserver:self
                               forKeyPath:kQSBArrangedObjectsKVOKey];
  [queryString_ release];
  [super dealloc];
}

- (QSBQueryController *)queryController {
  return queryController_;
}

- (NSArrayController *)arrayController {
  return resultsArrayController_;
}

- (NSView *)resultsView {
  return resultsView_;
}

- (QSBResultsViewTableView *)resultsTableView {
  return resultsTableView_;
}

- (CGFloat)minimumTableHeight {
  return 280.0;
}

- (CGFloat)maximumTableHeight {
  // TODO(mrossetti): We probably want to calculate the following based
  // on the screen geometry.
  return 650.0;
}

- (BOOL)isTransitionDirectionUp {
  return YES;
}

- (void)setResultsNeedUpdating:(BOOL)value {
  resultsNeedUpdating_ = value;
}

- (BOOL)resultsNeedUpdating {
  return resultsNeedUpdating_;
}

- (CGFloat)setIsShowing:(BOOL)value {
  if (value) {
    // See if we're about to be shown and we need updating.
    if ([self resultsNeedUpdating] && ![self isShowing]) {
      [self updateResultsView];
    }
    
    // Set origin to 0,0 and return previously calculated lastWindowHeight_.
    [resultsView_ setHidden:NO];
    [[resultsView_ animator] setFrameOrigin:NSMakePoint(0.0, 0.0)];
  } else {
    // Set origin to be off-screen in proper direction and it doesn't matter
    // what you return.
    NSPoint viewOrigin = [resultsView_ frame].origin;
    CGFloat resultsWindowHeight = NSHeight([[resultsView_ window] frame]);
    CGFloat transition = ([self isTransitionDirectionUp] ? 1.0 : -1.0);
    CGFloat viewYOffset = (resultsWindowHeight + 100.0) * transition;
    viewOrigin.y = viewYOffset;
    [[resultsView_ animator] setFrameOrigin:viewOrigin];
    [[resultsView_ animator] setHidden:YES];
  }
  isShowing_ = value;
  return lastWindowHeight_;
}

- (BOOL)isShowing {
  return isShowing_;
}

- (void)setSwapSelection {
  // The default behavior is to select the first row of the to-be-swapped-in
  // results view.
  [self scrollToBeginningOfDocument:self];
}

- (void)setQueryString:(NSString *)value {
  [queryString_ release];
  queryString_ = [value copy];
}

- (NSString *)queryString {
  return [[queryString_ retain] autorelease];
}

- (QSBTableResult *)selectedObject {
  QSBTableResult *object = nil;
  NSInteger selectedRow = [resultsTableView_ selectedRow];
  if (selectedRow >= 0) {
    object = [self objectForRow:selectedRow];
  }
  return object;
}

- (QSBTableResult *)objectForRow:(NSInteger)row { 
  QSBTableResult *object = nil;
  NSArray *objects = [resultsArrayController_ arrangedObjects];
  if (row < [objects count]) {
    object = [objects objectAtIndex:row];
  }
  return object;
}

- (void)reset {
  // Reset our selection to be the first row.
  [self scrollToBeginningOfDocument:self];
}

- (CGFloat)updateResultsView {
  // All of the view components have a fixed height relationship.  Base all
  // calculations on the change in the scrollview's height.  The scrollview's
  // height is determined from the tableview's height but within limits.
  
  // Determine the new tableview height.
  CGFloat newTableHeight = 0.0;
  NSInteger lastCellRow = [resultsTableView_ numberOfRows] - 1;
  if (lastCellRow > -1) {
    NSRect firstCellFrame = [resultsTableView_ frameOfCellAtColumn:0 row:0];
    NSRect lastCellFrame = [resultsTableView_ frameOfCellAtColumn:0 
                                                              row:lastCellRow];
    newTableHeight = fabs(NSMinY(firstCellFrame) - NSMaxY(lastCellFrame));
  }
  
  CGFloat minTableHeight = [self minimumTableHeight];
  CGFloat maxTableHeight = [self maximumTableHeight];
  newTableHeight = MAX(newTableHeight, minTableHeight);
  newTableHeight = MIN(newTableHeight, maxTableHeight);
  
  lastWindowHeight_ = newTableHeight;
  
  return lastWindowHeight_;
}

- (CGFloat)windowHeight {
  return lastWindowHeight_;
}

- (BOOL)performSelectionMovementSelector:(SEL)selector {
  BOOL acceptable = (selector == @selector(moveUp:)
                     || selector == @selector(moveDown:)
                     || selector == @selector(scrollToBeginningOfDocument:)
                     || selector == @selector(scrollToEndOfDocument:)
                     || selector == @selector(scrollPageUp:)
                     || selector == @selector(scrollPageDown:));
  if (acceptable) {
    [self performSelector:selector
               withObject:self];
  }
  return acceptable;
}

- (void)moveUp:(id)sender {
  NSInteger newRow = [resultsTableView_ selectedRow] - 1;
  if (newRow >= 0) {
    [resultsTableView_ moveUp:nil];
    newRow = [resultsTableView_ selectedRow];
    [resultsTableView_ scrollRowToVisible:newRow];
  }
}

- (void)moveDown:(id)sender {
  NSInteger newRow = [resultsTableView_ selectedRow] + 1;
  if (newRow < [resultsTableView_ numberOfRows]) {
    [resultsTableView_ moveDown:nil];
    newRow = [resultsTableView_ selectedRow];
    [resultsTableView_ scrollRowToVisible:newRow];
  }
}

- (void)scrollToBeginningOfDocument:(id)sender {
  NSInteger selectedRow = [resultsTableView_ selectFirstSelectableRow];
  [resultsTableView_ scrollRowToVisible:selectedRow];
}

- (void)scrollToEndOfDocument:(id)sender {
  NSInteger selectedRow = [resultsTableView_ selectLastSelectableRow];
  [resultsTableView_ scrollRowToVisible:selectedRow];
}

- (void)scrollPageUp:(id)sender {
  // Scroll so that the first visible row is now shown at the bottom, but
  // select the top visible row, and adjust so it is shown top-aligned.
  NSRange visibleRows = [resultsTableView_ visibleRows];
  if (visibleRows.length) {
    NSInteger newBottomRow = visibleRows.location;
    [resultsTableView_ scrollRowToVisible:0];
    [resultsTableView_ scrollRowToVisible:newBottomRow];
    visibleRows = [resultsTableView_ visibleRows];
    [resultsTableView_ selectFirstSelectableRowByIncrementing:YES
                                                   startingAt:visibleRows.location];
    [resultsTableView_ scrollRowToVisible:[resultsTableView_ numberOfRows] - 1];
    [resultsTableView_ scrollRowToVisible:[resultsTableView_ selectedRow]];
  }
}

- (void)scrollPageDown:(id)sender {
  // Scroll so that the last visible row is now show at the top.
  NSRange visibleRows = [resultsTableView_ visibleRows];
  if (visibleRows.length) {
    NSInteger newRow = visibleRows.location + visibleRows.length - 1;
    if ([resultsTableView_ selectFirstSelectableRowByIncrementing:YES
                                             startingAt:newRow]) {
      [resultsTableView_ scrollRowToVisible:[resultsTableView_ numberOfRows] - 1];
      [resultsTableView_ scrollRowToVisible:newRow];
    }
  }
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object 
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (object == resultsArrayController_) {
    if ([keyPath isEqualToString:kQSBArrangedObjectsKVOKey]) {
      NSArray *newArrangedObjects = [object arrangedObjects];
      rowCount_ = [newArrangedObjects count];
      [[self resultsTableView] reloadData];
      [queryController_ updateResultsView];
    }
  } 
}

#pragma mark QSBViewTableViewDelegateProtocol methods

- (NSView*)tableView:(NSTableView*)tableView
       viewForColumn:(NSTableColumn*)column
                 row:(NSInteger)row {
  // Initialize our custom view controller mapping.
  // NOTE: This leaks, but it's a very minor leak.
  // The default view controller for a row results view is
  // QSBResultRowViewController, so be sure to set the custom class
  // appropriately in your xib file.  If you need special behavior
  // in a row results view then make sure you use QSBResultRowViewController
  // as the base class and then add a mapping from the name of your .xib
  // file to the customized view controller class in the map below.
  // Not that there may be multiple views mapped to the same
  // view controller class.
  static NSDictionary *gCustomViewControllers = nil;
  if (!gCustomViewControllers) {
    gCustomViewControllers
      = [[NSDictionary dictionaryWithObjectsAndKeys:
          [QSBTopStandardRowViewController class], @"TopStandardResultView",
          // The following 2 views both use QSBMoreStandardRowViewController. 
          [QSBMoreStandardRowViewController class], @"MoreStandardResultView",
          [QSBMoreStandardRowViewController class], @"MoreCategoryResultView",
          nil] retain];
  }
  
  // Creating our views lazily.
  QSBResultRowViewController *oldController
    = [rowViewControllers_ objectForKey:[NSNumber numberWithInteger:row]];
  QSBResultRowViewController *newController = nil;
  
  // Decide what kind of view we want to use based on the result.
  QSBTableResult *result = [self objectForRow:row];
  if (result) {
    NSString *desiredRowViewName = [self rowViewNibNameForResult:result];
    if (desiredRowViewName) {
      if (!oldController
          || ![[oldController nibName] isEqualToString:desiredRowViewName]) {
        // We cannot reuse the old controller.
        Class newControllerClass
          = [gCustomViewControllers objectForKey:desiredRowViewName];
        if (!newControllerClass) {
          newControllerClass = [QSBResultRowViewController class];
        }
        newController
          = [[[newControllerClass alloc] initWithNibName:desiredRowViewName
                                                  bundle:nil
                                              controller:[self queryController]]
             autorelease];          
        [rowViewControllers_ setObject:newController
                                forKey:[NSNumber numberWithInteger:row]];
        [newController loadView];
        oldController = nil;
      } else {
        newController = oldController;
      }
      if ([newController representedObject] != result) {
        [newController setRepresentedObject:result];
      }
    } else {
      HGSLogDebug(@"\r  Unable to determine result row view for result %@ (row %d).",
                  result, row);
    }
  }
  
  if (!newController) {
    if (oldController
        && [[oldController nibName] isEqualToString:@"MorePlaceHolderResultView"]) {
      newController = oldController;
    } else {
      newController = [[[NSViewController alloc]
                        initWithNibName:@"MorePlaceHolderResultView"
                        bundle:nil] autorelease];
      [rowViewControllers_ setObject:newController
                              forKey:[NSNumber numberWithInteger:row]];
      oldController = nil;
    }
  }
  
  NSView *newView = [newController view];
  return newView;
}

- (NSString *)rowViewNibNameForResult:(QSBTableResult *)result {
  HGSLogDebug(@"Your child class needs to handle this method.");
  return nil;
}

- (void)pathControlClick:(id)sender {
  // If the cell has a URI then dispatch directly to that URI, otherwise
  // ask the object if it wants to handle the click and, if so, tell it
  // which cell was clicked.
  NSPathControl *pathControl = sender;
  NSPathComponentCell *clickedComponentCell = [pathControl clickedPathComponentCell];
  if (clickedComponentCell) {
    NSURL *pathURL = [clickedComponentCell URL];
    if (!pathURL || ![[NSWorkspace sharedWorkspace] openURL:pathURL]) {
      // No URI or the URI launch failed.  Fallback to let the result take a shot.
      QSBTableResult *selectedObject = [[[self arrayController] selectedObjects]
                                        objectAtIndex:0];
      SEL cellClickHandler
      = NSSelectorFromString([selectedObject
                              valueForKey:kHGSObjectAttributePathCellClickHandlerKey]);
      if (cellClickHandler) {
        NSArray *pathComponentCells = [pathControl pathComponentCells];
        NSUInteger clickedCell = [pathComponentCells indexOfObject:clickedComponentCell];
        NSNumber *cellNumber = [NSNumber numberWithUnsignedInteger:clickedCell];
        [selectedObject performSelector:cellClickHandler withObject:cellNumber];
      }
    }
  }
}

#pragma mark Table Delegate Methods

// Sets us up so that the user can drag across us and get updated correctly
- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {
  NSTableView *view = (NSTableView *)[aNotification object];
  NSInteger newSelectedRow = [view selectedRow];
  NSIndexSet *selectionSet = nil;
  if (newSelectedRow >= 0) {
    selectionSet = [NSIndexSet indexSetWithIndex:newSelectedRow];
  } else {
    selectionSet = [NSIndexSet indexSet];
  }
  [resultsArrayController_ setSelectionIndexes:selectionSet];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
  [[[self queryController] searchWindowController] completeQueryText];    
}

- (BOOL)tableView:(NSTableView *)aTableView
  shouldSelectRow:(NSInteger)rowIndex {
  QSBTableResult *object = [self objectForRow:rowIndex];
  BOOL isSeparator = [object isKindOfClass:[QSBSeparatorTableResult class]];
  BOOL isMessage = [object isKindOfClass:[QSBMessageTableResult class]]; 
  BOOL isSelectable = object && !(isSeparator || isMessage);
  return isSelectable;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
  return rowCount_;
}

- (CGFloat)tableView:(NSTableView *)tableView
         heightOfRow:(NSInteger)row {
  // Scan all of the views for this row and return the height of the tallest.
  NSArray *columns = [tableView tableColumns];
  CGFloat rowHeight = [tableView rowHeight];
  NSEnumerator *columnEnum = [columns objectEnumerator];
  NSTableColumn *column = nil;
  while ((column = [columnEnum nextObject])) {
    NSView *colView = [self tableView:tableView
                        viewForColumn:column
                                  row:row];
    if (colView) {
      CGFloat viewHeight = NSHeight([colView frame]);
      if (viewHeight > rowHeight)
        rowHeight = viewHeight;
    }
  }
  return rowHeight;
}

#pragma mark NSDataSource protocol methods

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row {
  QSBTableResult *result = [self objectForRow:row];
  return [result isPivotable] ? [NSImage imageNamed:@"ChildArrow"] : nil;
}

@end


@implementation QSBResultsViewBaseController (QSBResultsViewBaseControllerPrivateMethods)

- (QSBSearchWindowController *)searchWindowController {
  return [queryController_ searchWindowController];
}

@end
