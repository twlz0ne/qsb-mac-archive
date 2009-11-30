//
//  QSBTopResultsViewController.m
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

#import "QSBTopResultsViewController.h"
#import <Vermilion/Vermilion.h>
#import "QSBApplicationDelegate.h"
#import "QSBTableResult.h"
#import "QSBSearchViewController.h"
#import "QSBResultRowViewController.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "QSBSearchController.h"

@implementation QSBTopResultsViewController


- (void)awakeFromNib {  
  QSBResultsViewTableView *resultsTableView = [self resultsTableView];
  [resultsTableView setDataSource:self];
  [resultsTableView setDelegate:self];
  [resultsTableView reloadData];

  [resultsTableView setIntercellSpacing:NSMakeSize(0.0, 0.0)];
  
  // Adjust the 'Top' results view to properly fit.
  NSView *resultsView = [self resultsView];
  NSRect viewFrame = [resultsView frame];
  QSBSearchViewController *viewController = [self searchViewController];
  QSBSearchWindowController *windowController 
    = [viewController searchWindowController];
  NSWindow *resultsWindow = [windowController resultsWindow];
  NSView *contentView = [resultsWindow contentView];
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

#pragma mark NSTableView Delegate Methods

- (void)moveDown:(id)sender {
  NSInteger newRow = [[self resultsTableView] selectedRow] + 1;
  if (newRow >= [self numberOfRowsInTableView:nil]) {
    QSBTableResult *result = [self selectedTableResult];
    if ([result isKindOfClass:[QSBFoldTableResult class]]) {
      // If we're on the last row and it's a fold then transition
      // to the 'Top' results view.
      [[self searchViewController] showMoreResults:sender];
    }
  } else {
    [super moveDown:sender];
  }
}

- (Class)rowViewControllerClassForResult:(QSBTableResult *)result {
  return [result topResultsRowViewControllerClass];
}

- (QSBTableResult *)tableResultForRow:(NSInteger)row { 
  return [[[self searchViewController] searchController] topResultForIndex:row];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
  return [[[self searchViewController] searchController] topResultCount];
}


@end

