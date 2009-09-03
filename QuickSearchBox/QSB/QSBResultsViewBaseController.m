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
#import "QSBMoreResultsViewControllers.h"
#import "QSBSearchViewController.h"
#import "QSBTableResult.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "QSBTopResultsViewControllers.h"
#import "GTMGeometryUtils.h"
#import "GTMNSObject+KeyValueObserving.h"
#import "GTMMethodCheck.h"
#import "QSBHGSDelegate.h"

static const CGFloat kScrollViewMinusTableHeight = 7.0;
static NSString * const kQSBArrangedObjectsKVOKey = @"arrangedObjects";

@interface QSBResultsViewBaseController ()

// Return our main search window controller.
- (QSBSearchWindowController *)searchWindowController;
- (void)resultsObjectsChanged:(GTMKeyValueChangeNotification *)notification;
@end


@implementation QSBResultsViewBaseController
GTM_METHOD_CHECK(NSObject, gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);

- (void)awakeFromNib {
  rowViewControllers_ = [[NSMutableDictionary dictionary] retain];
  [resultsArrayController_ gtm_addObserver:self
                                forKeyPath:kQSBArrangedObjectsKVOKey
                                  selector:@selector(resultsObjectsChanged:)
                                  userInfo:nil
                                   options:0];

  resultsNeedUpdating_ = YES;
  [resultsTableView_ setDoubleAction:@selector(openResultsTableItem:)];
  QSBSearchWindowController *controller = [self searchWindowController];
  [resultsTableView_ setTarget:controller];
}

- (void)dealloc {
  [rowViewControllers_ release];
  [resultsArrayController_ gtm_removeObserver:self
                                   forKeyPath:kQSBArrangedObjectsKVOKey
                                     selector:@selector(resultsObjectsChanged:)];
  [queryString_ release];
  [super dealloc];
}

- (QSBSearchViewController *)searchViewController {
  return searchViewController_;
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
  [self moveToBeginningOfDocument:self];
}

- (void)setQueryString:(NSString *)value {
  [queryString_ release];
  queryString_ = [value copy];
}

- (NSString *)queryString {
  return [[queryString_ retain] autorelease];
}

- (QSBTableResult *)selectedTableResult {
  QSBTableResult *tableResult = nil;
  NSInteger selectedRow = [resultsTableView_ selectedRow];
  if (selectedRow >= 0) {
    tableResult = [self tableResultForRow:selectedRow];
  }
  return tableResult;
}

- (QSBTableResult *)tableResultForRow:(NSInteger)row { 
  QSBTableResult *object = nil;
  NSArray *objects = [resultsArrayController_ arrangedObjects];
  if (row < [objects count]) {
    object = [objects objectAtIndex:row];
  }
  return object;
}

- (void)reset {
  // Reset our selection to be the first row.
  [self moveToBeginningOfDocument:self];
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

- (void)moveToBeginningOfDocument:(id)sender {
  NSInteger selectedRow = [resultsTableView_ selectFirstSelectableRow];
  [resultsTableView_ scrollRowToVisible:selectedRow];
}

- (void)moveToEndOfDocument:(id)sender {
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
      NSUInteger rowCount = [resultsTableView_ numberOfRows];
      [resultsTableView_ scrollRowToVisible:rowCount - 1];
      [resultsTableView_ scrollRowToVisible:newRow];
    }
  }
}

- (QSBSearchWindowController *)searchWindowController {
  return [searchViewController_ searchWindowController];
}

- (void)resultsObjectsChanged:(GTMKeyValueChangeNotification *)notification {
  id object = [notification object];
  NSArray *newArrangedObjects = [object arrangedObjects];
  rowCount_ = [newArrangedObjects count];
  [[self resultsTableView] reloadData];
  [searchViewController_ updateResultsView];
}

- (BOOL)tableView:(NSTableView *)tv
writeRowsWithIndexes:(NSIndexSet *)rowIndexes 
     toPasteboard:(NSPasteboard*)pb {
  unsigned row = [rowIndexes firstIndex];
  QSBTableResult *tableResult = [self tableResultForRow:row];
  return [tableResult copyToPasteboard:pb];
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
      oldController = nil;
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
      QSBTableResult *selectedObject = [[[self arrayController] selectedObjects]
                                        objectAtIndex:0];
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

- (BOOL)tableView:(NSTableView *)aTableView
  shouldSelectRow:(NSInteger)rowIndex {
  QSBTableResult *object = [self tableResultForRow:rowIndex];
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
      if (viewHeight > 0) {
        rowHeight = viewHeight;
      }
    }
  }
  return rowHeight;
}

#pragma mark NSDataSource protocol methods

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row {
  QSBTableResult *result = [self tableResultForRow:row];
  return [result isPivotable] ? [NSImage imageNamed:@"ChildArrow"] : nil;
}

@end


