//
//  QSBResultTableView.m
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

#import "QSBResultTableView.h"
#import "QSBTableResult.h"
#import "QSBResultsViewBaseController.h"
#import "GTMGeometryUtils.h"
#import "GTMLinearRGBShading.h"
#import "GTMMethodCheck.h"
#import "GTMNSBezierPath+RoundRect.h"
#import "GTMNSBezierPath+Shading.h"


// TODO(mrossetti): Determine what drag/drop support is required then determine
// what to do in the code annotated with IS_THIS_NEEDED_FOR_DRAG_SUPPORT.


@interface QSBResultTableView (QSBResultTableViewPrivateMethods)
- (CGFloat)selectionLeftInset;
- (CGFloat)selectionRightInset;
- (CGFloat)selectionCornerRadius;
- (void)moveSelectionByARow:(BOOL)incrementing;
@end

@implementation QSBResultTableView

GTM_METHOD_CHECK(NSBezierPath, gtm_fillAxiallyFrom:to:extendingStart:extendingEnd:shading:);
GTM_METHOD_CHECK(NSBezierPath, gtm_bezierPathWithRoundRect:cornerRadius:);

- (BOOL)acceptsFirstResponder {
  return NO;
}

- (void)highlightSelectionInClipRect:(NSRect)rect {
  NSInteger selectedRow = [self selectedRow];
  if (selectedRow != -1) {
    NSColor *highlightBottom = nil;
    NSColor *highlightTop = nil;
    NSColor *mainColor = nil;
    // TODO(dmaclach): handle selection correctly
    if (YES) {
      NSColor *highlightColor = [NSColor selectedTextBackgroundColor];
      
      highlightTop = [highlightColor colorWithAlphaComponent:0.25];
      highlightBottom = [highlightColor colorWithAlphaComponent:0.5];
      mainColor = highlightColor;
    } else {
      mainColor = [NSColor colorWithCalibratedRed:166.0/255.0 
                                            green:193/255.0 
                                             blue:224/255.0
                                            alpha:1.0];
      highlightBottom = [mainColor colorWithAlphaComponent:0.75];
      highlightTop = [mainColor colorWithAlphaComponent:0.25];
    }
    NSRect selectedRect = [self rectOfRow:selectedRow];
    selectedRect = NSInsetRect(selectedRect, 0.5, 0.5);
    selectedRect.origin.x += [self selectionLeftInset];
    selectedRect.size.width -= [self selectionRightInset];
    CGFloat cornerRadius = [self selectionCornerRadius];
    NSBezierPath *roundPath 
      = [NSBezierPath gtm_bezierPathWithRoundRect:selectedRect
                                     cornerRadius:cornerRadius];
    
    GTMLinearRGBShading *shading 
      = [GTMLinearRGBShading shadingFromColor:highlightBottom
                                      toColor:highlightTop 
                               fromSpaceNamed:NSCalibratedRGBColorSpace];
    [roundPath gtm_fillAxiallyFrom:GTMNSMidMaxY(selectedRect) 
                                to:GTMNSMidMinY(selectedRect)
                    extendingStart:YES 
                      extendingEnd:YES 
                           shading:shading];
    [mainColor set];
    [roundPath stroke];
  }
}

- (id)_highlightColorForCell:(NSCell *)cell {
  return nil;
}

- (void)drawGridInClipRect:(NSRect)rect {
}


#if IS_THIS_NEEDED_FOR_DRAG_SUPPORT

- (void)awakeFromNib {
  [self setDraggingSourceOperationMask:NSDragOperationEvery forLocal:NO];
  [[self enclosingScrollView] setDrawsBackground:NO];
}

- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes 
                       atPoint:(NSPoint)mouseDownPoint {
  BOOL canDrag = NO;
  // TODO(mrossetti): Re-implement this once we've switched over to view tables.
  unsigned row = [rowIndexes firstIndex];
  NSCell *cell = [[self delegate] resultCellForRow:row];
  if ([cell isKindOfClass:[QSBQueryResultCell class]]) {
    NSInteger resultsIndex = [self columnWithIdentifier:@"QSBResults"];
    NSRect cellFrame = [self frameOfCellAtColumn:resultsIndex row:row];
    QSBQueryResultCell *queryResultCell = (QSBQueryResultCell *)cell;
    NSRect imageFrame = [queryResultCell iconRectForCellFrame:cellFrame];
    
    canDrag = NSPointInRect(mouseDownPoint, imageFrame);
  }
  return canDrag;
}

- (NSImage *)dragImageForRowsWithIndexes:(NSIndexSet *)dragRows 
                            tableColumns:(NSArray *)tableColumns 
                                   event:(NSEvent*)dragEvent 
                                  offset:(NSPointPointer)dragImageOffset {
  unsigned row = [dragRows firstIndex];
  HGSObject *item = [[self delegate] objectForRow:row];
  return [item displayIconWithLazyLoad:YES];
}

#endif  // IS_THIS_NEEDED_FOR_DRAG_SUPPORT

- (BOOL)isOpaque {
  return NO;  
}

#if 0
// TODO(alcor): reenable this or remove depending on final UI
- (void)drawBackgroundInClipRect:(NSRect)clipRect {
  NSRect bounds = [self bounds];
  bounds.origin.x += kQSBUIElementValues[kQSBUIBoundingBoxLeftOffset][uiSet_];
  bounds.size.width -= kQSBUIElementValues[kQSBUIBoundingBoxLeftOffset][uiSet_];
  bounds = NSInsetRect(bounds, 0.5, 0.5);
  NSBezierPath *bezier = [NSBezierPath bezierPathWithRoundedRect:bounds
                                                         xRadius:3.5
                                                         yRadius:3.5];
  [[NSColor whiteColor] set];
  [bezier fill];
  [[NSColor colorWithCalibratedWhite:0.0 alpha:0.15] set];
  [bezier stroke];
}
#endif

- (void)moveUp:(id)sender {
  [self moveSelectionByARow:NO];
}

- (void)moveDown:(id)sender {
  [self moveSelectionByARow:YES];
}

- (NSInteger)selectFirstSelectableRow {
  [self selectFirstSelectableRowByIncrementing:YES
                                    startingAt:0];
  return [self selectedRow];
}

- (NSInteger)selectLastSelectableRow {
  NSInteger lastRow = [self numberOfRows] - 1;
  [self selectFirstSelectableRowByIncrementing:NO
                                    startingAt:lastRow];
  return [self selectedRow];
}

- (void)scrollWheel:(NSEvent *)event {
  if ([event deltaY] < 0) {
    [[self delegate] moveDown:self];
  } else if ([event deltaY] > 0) {
    [[self delegate] moveUp:self];
  }    
}

- (BOOL)selectFirstSelectableRowByIncrementing:(BOOL)incrementing 
                                    startingAt:(NSInteger)firstRow {
  BOOL haveSelection = NO;
  if (firstRow > -1) {
    id delegate = [self delegate];
    if ([delegate respondsToSelector:@selector(tableView:shouldSelectRow:)]
        && ![delegate tableView:self shouldSelectRow:firstRow]) {
      NSInteger currSelection = firstRow;
      int offset = incrementing ? 1 : -1;
      do {
        currSelection += offset;
        if (currSelection == [self numberOfRows]) {
          currSelection = 0;
        } else if (currSelection < 0) {
          currSelection = [self numberOfRows] - 1;
        }
      } while (![delegate tableView:self shouldSelectRow:currSelection]
               && currSelection != firstRow);
      if (currSelection == firstRow) {
        [self selectRowIndexes:[NSIndexSet indexSet] byExtendingSelection:NO];
        haveSelection = NO;
      } else {
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:currSelection] 
          byExtendingSelection:NO];
        haveSelection = YES;
      }
    } else {
      [self selectRowIndexes:[NSIndexSet indexSetWithIndex:firstRow] 
        byExtendingSelection:NO];
      haveSelection = YES;
    }
  }
  return haveSelection;
}

- (NSRange)visibleRows {
  NSRange visibleRows = NSMakeRange(NSNotFound, 0);
  NSView *contentView = [self superview];
  NSScrollView *scrollView = (NSScrollView *)[contentView superview];
  NSScroller *scroller = [scrollView verticalScroller];
  if (contentView && scrollView && scroller) {
    NSRect contentFrame = [contentView frame];
    CGFloat scrollPercentage = [scroller floatValue];
    CGFloat tableHeight = NSHeight([self frame]);
    CGFloat contentHeight = NSHeight(contentFrame);
    CGFloat contentOffset = (tableHeight - contentHeight) * scrollPercentage;
    contentFrame.origin.y = contentOffset;
    visibleRows = [self rowsInRect:contentFrame];
  }
  return visibleRows;
}

- (BOOL)rowIsVisible:(NSInteger)row {
  return (row >= 0 && NSLocationInRange(row, [self visibleRows]));
}

@end


@implementation QSBResultTableView (QSBResultTableViewPrivateMethods)

- (CGFloat)selectionLeftInset {
  //Stroke left and right outside the clipping area
  return -1;
}

- (CGFloat)selectionRightInset {
  //Stroke left and right outside the clipping area
  return -2;
}

- (CGFloat)selectionCornerRadius {
  return 0.0;
}

- (void)moveSelectionByARow:(BOOL)incrementing {
  NSInteger rowToSelect = [self selectedRow];
  NSInteger bottom = [self numberOfRows] - 1;
  if (incrementing) {
    if (rowToSelect < bottom) {
      rowToSelect +=1;
    }
  } else {
    if (rowToSelect > 0) {
      rowToSelect -=  1;
    }
  }
  [self selectFirstSelectableRowByIncrementing:incrementing 
                                    startingAt:rowToSelect];
}

@end
