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
#import <QSBPluginUI/QSBPluginUI.h>

#import "QSBApplicationDelegate.h"
#import "QSBSearchViewController.h"
#import "QSBTableResult.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "QSBTopResultsRowViewControllers.h"
#import "GTMGeometryUtils.h"
#import "QSBSearchController.h"

static const CGFloat kScrollViewMinusTableHeight = 7.0;
static NSString * const kQSBArrangedObjectsKVOKey = @"arrangedObjects";

@interface QSBResultsViewBaseController ()

// Return our main search window controller.
- (QSBSearchWindowController *)searchWindowController;

// Update the metrics of our results presentation and propose a new table height.
- (void)updateTableHeight;
@end


@implementation QSBResultsViewBaseController

- (void)awakeFromNib {
  rowViewControllers_ = [[NSMutableDictionary dictionary] retain];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self 
         selector:@selector(searchControllerDidUpdateResults:) 
             name:kQSBSearchControllerDidUpdateResultsNotification 
           object:[searchViewController_ searchController]];

  resultsNeedUpdating_ = YES;
  [resultsTableView_ setDoubleAction:@selector(openResultsTableItem:)];
  QSBSearchWindowController *controller = [self searchWindowController];
  [resultsTableView_ setTarget:controller];
}

- (void)dealloc {
  [rowViewControllers_ release];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (QSBSearchViewController *)searchViewController {
  return searchViewController_;
}

- (NSView *)resultsView {
  return resultsView_;
}

- (QSBResultsViewTableView *)resultsTableView {
  return resultsTableView_;
}

- (CGFloat)minimumTableHeight {
  return 42.0;
}

- (CGFloat)maximumTableHeight {
  return 1024.0;
}

- (BOOL)isTransitionDirectionUp {
  return YES;
}

- (void)setResultsNeedUpdating:(BOOL)value {
  resultsNeedUpdating_ = value;
  [self updateTableHeight];
}

- (BOOL)resultsNeedUpdating {
  return resultsNeedUpdating_;
}

- (void)setShowing:(BOOL)value {
  if (value) {
    // See if we're about to be shown and we need updating.
    if ([self resultsNeedUpdating] && ![self isShowing]) {
      [self updateTableHeight];
    }
    [self scrollToBeginningOfDocument:self];

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
}

- (BOOL)isShowing {
  return isShowing_;
}

- (QSBTableResult *)selectedTableResult {
  return [self tableResultForRow:[resultsTableView_ selectedRow]];
}

- (void)reset {
  // Reset our selection to be the first row.
  [self scrollToBeginningOfDocument:self];
}

- (void)updateTableHeight {
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
  lastTableHeight_ = newTableHeight;
}

- (CGFloat)tableHeight {
  return lastTableHeight_;
}

- (BOOL)performSelectionMovementSelector:(SEL)selector {
  BOOL acceptable = (selector == @selector(moveUp:)
                     || selector == @selector(moveDown:)
                     || selector == @selector(scrollToBeginningOfDocument:)
                     || selector == @selector(scrollToEndOfDocument:)
                     || selector == @selector(moveToBeginningOfDocument:)
                     || selector == @selector(moveToEndOfDocument:)
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

- (void)moveToBeginningOfDocument:(id)sender {
  [self scrollToBeginningOfDocument:sender];
}

- (void)moveToEndOfDocument:(id)sender {
  [self scrollToEndOfDocument:sender];
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
      NSUInteger rowCount = [resultsTableView_ numberOfRows];
      [resultsTableView_ scrollRowToVisible:rowCount - 1];
      [resultsTableView_ scrollRowToVisible:newRow];
    }
  }
}

- (QSBSearchWindowController *)searchWindowController {
  return [searchViewController_ searchWindowController];
}

- (void)searchControllerDidUpdateResults:(NSNotification *)notification {
  NSTableView *resultsTableView = [self resultsTableView];
  [resultsTableView reloadData];
  if ([resultsTableView selectedRow] == -1) {
    [resultsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0]
                  byExtendingSelection:NO];
  }
  [searchViewController_ updateResultsView];
}

- (BOOL)tableView:(NSTableView *)tv
writeRowsWithIndexes:(NSIndexSet *)rowIndexes 
     toPasteboard:(NSPasteboard*)pb {
  NSUInteger row = [rowIndexes firstIndex];
  QSBTableResult *tableResult = [self tableResultForRow:row];
  return [tableResult copyToPasteboard:pb];
}

- (QSBTableResult *)tableResultForRow:(NSInteger)row {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

#pragma mark QSBViewTableViewDelegateProtocol methods

- (NSView*)tableView:(NSTableView*)tableView
       viewForColumn:(NSTableColumn*)column
                 row:(NSInteger)row {
  // Creating our views lazily.
  QSBResultRowViewController *oldController
    = [rowViewControllers_ objectForKey:[NSNumber numberWithInteger:row]];
  QSBResultRowViewController *newController = nil;
  
  // Decide what kind of view we want to use based on the result.
  QSBTableResult *result = [self tableResultForRow:row];
  Class aRowViewControllerClass 
    = [self rowViewControllerClassForResult:result];
  if (aRowViewControllerClass) {
    if (!oldController 
        || [oldController class] != aRowViewControllerClass) {
      // We cannot reuse the old controller.
      QSBSearchViewController *queryController = [self searchViewController];
      newController
        = [[[aRowViewControllerClass alloc] initWithController:queryController]
           autorelease];          
      [rowViewControllers_ setObject:newController
                              forKey:[NSNumber numberWithInteger:row]];
      [newController loadView];
    } else {
      newController = oldController;
    }
    if ([newController representedObject] != result) {
      [newController setRepresentedObject:result];
    }
  } 
  
  if (!newController) {
    HGSLogDebug(@"Unable to determine result row view for result %@ (row %d).",
                result, row);
  }
  
  NSView *newView = [newController view];
  return newView;
}

- (Class)rowViewControllerClassForResult:(QSBTableResult *)result {
  HGSLogDebug(@"Your child class needs to handle this method ([%@ %s]",
              [self class], _cmd);
  return nil;
}

- (void)pathControlClick:(id)sender {
  // If the cell has a URI then dispatch directly to that URI, otherwise
  // ask the object if it wants to handle the click and, if so, tell it
  // which cell was clicked.
  NSPathControl *pathControl = sender;
  NSPathComponentCell *clickedComponentCell 
    = [pathControl clickedPathComponentCell];
  if (clickedComponentCell) {
    NSURL *pathURL = [clickedComponentCell URL];
    if (!pathURL || ![[NSWorkspace sharedWorkspace] openURL:pathURL]) {
      // No URI or the URI launch failed.  Fallback to let the result take a shot.
      QSBTableResult *selectedObject = [self selectedTableResult];
      SEL cellClickHandler
        = NSSelectorFromString([selectedObject
                                valueForKey:kQSBObjectAttributePathCellClickHandlerKey]);
      if (cellClickHandler) {
        NSArray *pathComponentCells = [pathControl pathComponentCells];
        NSUInteger clickedCell 
          = [pathComponentCells indexOfObject:clickedComponentCell];
        NSNumber *cellNumber = [NSNumber numberWithUnsignedInteger:clickedCell];
        [selectedObject performSelector:cellClickHandler withObject:cellNumber];
      }
    }
  }
}

@end
