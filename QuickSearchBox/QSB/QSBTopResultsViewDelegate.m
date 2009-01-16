//
//  QSBTopResultsViewDelegate.m
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

#import "QSBTopResultsViewDelegate.h"
#import <Vermilion/Vermilion.h>
#import "QSBApplicationDelegate.h"
#import "QSBTableResult.h"
#import "QSBQueryController.h"
#import "QSBResultRowViewController.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "GTMMethodCheck.h"
#import "NSAttributedString+Attributes.h"

@implementation QSBTopResultsViewDelegate

GTM_METHOD_CHECK(NSMutableAttributedString, addAttributes:);

- (void)awakeFromNib {  
  QSBResultsViewTableView *resultsTableView = [self resultsTableView];
  [resultsTableView setDataSource:self];
  [resultsTableView setDelegate:self];
  [resultsTableView reloadData];

  [resultsTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];

  // Adjust the 'Top' results view to properly fit.
  NSView *resultsView = [self resultsView];
  NSRect viewFrame = [resultsView frame];
  NSView *contentView
    = [[[[self queryController] searchWindowController] resultsWindow] contentView];
  viewFrame.size.width = NSWidth([contentView frame]);
  [resultsView setFrame:viewFrame];
  
  [super awakeFromNib];
}

- (void)dealloc {
  [categorySummaryString_ release];
  [super dealloc];
}

- (void)setSwapSelection {
  [self scrollToEndOfDocument:self];
}

- (NSString *)categorySummaryString {
  return [[categorySummaryString_ retain] autorelease];
}

- (void)setCategorySummaryString:(NSString *)value {
  [categorySummaryString_ release];
  categorySummaryString_ = [value copy];
}

- (CGFloat)updateResultsView {
  CGFloat tableHeight = [super updateResultsView];
  
  // Force a selection if there is not already a selection and if there
  // is no pivot.
  QSBResultsViewTableView *resultsTableView = [self resultsTableView];
  NSInteger lastCellRow = [resultsTableView numberOfRows] - 1;
  if (lastCellRow > -1) {
    NSUInteger selectedRow = [[self arrayController] selectionIndex];
    if (selectedRow == NSNotFound
        && ![[self queryController] pivotObject]) {
      [resultsTableView selectFirstSelectableRow];
    }
  }
  return tableHeight;
}

#pragma mark NSTableView Delegate Methods

- (void)moveDown:(id)sender {
  NSInteger newRow = [[self resultsTableView] selectedRow] + 1;
  if (newRow >= [self numberOfRowsInTableView:nil]) {
    QSBTableResult *result = [self selectedObject];
    if ([result isKindOfClass:[QSBFoldTableResult class]]) {
      // If we're on the last row and it's a fold then transition
      // to the 'Top' results view.
      [[self queryController] showMoreResults:sender];
    }
  } else {
    [super moveDown:sender];
  }
}

- (NSString *)rowViewNibNameForResult:(QSBTableResult *)result {
  return [result topResultsRowViewNibName];
}

#if TO_BE_IMPLEMENTED
// TODO(mrossetti): Adapt to the view-based scheme.
- (BOOL)tableView:(NSTableView *)tv
writeRowsWithIndexes:(NSIndexSet *)rowIndexes 
     toPasteboard:(NSPasteboard*)pboard {
  
  BOOL gotData = NO;
  unsigned row = [rowIndexes firstIndex];
  HGSObject *item = [self objectForRow:row];
  
  NSURL *url = [item valueForKey:kHGSObjectAttributeURIKey];
  if (url) {
    NSString *urlString = [url absoluteString];
    [pboard declareTypes:[NSArray arrayWithObjects:kWebURLsWithTitlesPboardType, 
                          kUTTypeURL,
                          @"public.url-name",
                          NSURLPboardType,
                          NSStringPboardType, 
                          nil] owner:nil];
    NSArray *urlArray = [NSArray arrayWithObject:urlString];
    NSString *title = [item valueForKey:kHGSObjectAttributeNameKey];
    NSArray *titleArray = [NSArray arrayWithObject:title];
    [pboard setPropertyList:[NSArray arrayWithObjects:urlArray, titleArray, nil]
                    forType:kWebURLsWithTitlesPboardType];
    [pboard setString:urlString
              forType:(NSString*)kUTTypeURL];
    [pboard setString:title
              forType:@"public.url-name"];
    [url writeToPasteboard:pboard];
    [pboard setString:urlString
              forType:NSStringPboardType];
    
    gotData = YES;
  }
  return gotData;
}
#endif

@end

