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
#import "QSBCategory.h"
#import "QSBTopResultsRowViewControllers.h"

@interface QSBTopResultsViewController ()
@property (readwrite, copy) NSString *categorySummaryString;
@end

@implementation QSBTopResultsViewController

@synthesize categorySummaryString = categorySummaryString_;

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
  NSView *contentView = [windowController resultsView];
  viewFrame.size.width = NSWidth([contentView frame]);
  [resultsView setFrame:viewFrame];
  
  rowViewControllers_ = [[NSMutableDictionary dictionary] retain];
  
  [super awakeFromNib];
}

- (void)dealloc {
  [rowViewControllers_ release];
  [categorySummaryString_ release];
  [super dealloc];
}

- (void)setSwapSelection {
  [self scrollToEndOfDocument:self];
}

- (void)updateCategorySummaryString:(NSDictionary *)resultCountByCategory {
  NSMutableString *categorySummary = [NSMutableString string];
  NSString *comma = nil;
  for (QSBCategory *category in resultCountByCategory) {
    NSNumber *nsValue = [resultCountByCategory objectForKey:category];
    NSUInteger catCount = [nsValue unsignedIntValue];
    if (catCount) {
      NSString *catString = nil;
      if (catCount == 1) {
        catString = [category localizedSingularName];
      } else {
        catString = [category localizedName];
      }
      if (!comma) {
        comma = NSLocalizedString(@", ", nil);
      } else {
        [categorySummary appendString:comma];
      }
      [categorySummary appendFormat:@"%u %@", catCount, catString];
    }
  }
  [self setCategorySummaryString:categorySummary];
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

- (QSBTableResult *)tableResultForRow:(NSInteger)row { 
  return [[[self searchViewController] searchController] topResultForIndex:row];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
  return [[[self searchViewController] searchController] topResultCount];
}

- (CGFloat)tableView:(NSTableView *)tableView
         heightOfRow:(NSInteger)row {
  NSArray *columns = [tableView tableColumns];
  NSTableColumn *column = [columns objectAtIndex:0];
  NSView *colView = [self tableView:tableView viewForColumn:column row:row];
  CGFloat rowHeight = NSHeight([colView frame]);
  return rowHeight;
}

- (BOOL)tableView:(NSTableView *)aTableView
  shouldSelectRow:(NSInteger)rowIndex {
  QSBTableResult *object = [self tableResultForRow:rowIndex];
  BOOL isSeparator = [object isKindOfClass:[QSBSeparatorTableResult class]];
  BOOL isMessage = [object isKindOfClass:[QSBMessageTableResult class]]; 
  BOOL isSelectable = object && !(isSeparator || isMessage);
  return isSelectable;
}

- (id)tableView:(NSTableView *)tableView
objectValueForTableColumn:(NSTableColumn *)tableColumn
            row:(NSInteger)row {
  QSBTableResult *result = [self tableResultForRow:row];
  return [result isPivotable] ? [NSImage imageNamed:@"ChildArrow"] : nil;
}

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
    = [result topResultsRowViewControllerClass];
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

#pragma mark Notifications
- (void)searchControllerDidUpdateResults:(NSNotification *)notification {
  NSDictionary *userInfo = [notification userInfo];
  NSDictionary *resultCountByCategory 
    = [userInfo objectForKey:kQSBSearchControllerResultCountByCategoryKey];
  [self updateCategorySummaryString:resultCountByCategory];
  [super searchControllerDidUpdateResults:notification];
}

@end

