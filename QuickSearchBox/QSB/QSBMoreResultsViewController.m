//
//  QSBMoreResultsViewController.m
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

#import "QSBMoreResultsViewController.h"
#import "QSBApplicationDelegate.h"
#import "QSBSearchController.h"
#import "QSBSearchViewController.h"
#import "QSBPreferences.h"
#import "QSBTableResult.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "QSBTopResultsViewController.h"
#import "HGSLog.h"
#import "GTMGarbageCollection.h"
#import "GTMMethodCheck.h"
#import "GTMNSNumber+64Bit.h"
#import "NSAttributedString+Attributes.h"
#import "QSBHGSDelegate.h"

// Extra space to allow for miscellaneous rows (such as fold) in the results table.
static const NSUInteger kCategoryRowOverhead = 3;
static const NSTimeInterval kFirstRowDownwardDelay = 0.6;
static const NSTimeInterval kFirstRowUpwardDelay = 0.4;

@interface QSBMoreResultsViewController ()

- (void)updateCategoryNames:(NSArray *)names counts:(NSArray *)counts;

@end

@implementation QSBMoreResultsViewController

GTM_METHOD_CHECK(NSMutableAttributedString, addAttributes:);

- (id)initWithNibName:(NSString *)nibNameOrNil 
               bundle:(NSBundle *)nibBundleOrNil {
  if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
    rowHeightDict_ = [[NSMutableDictionary alloc] init];
    showAllCategoriesSet_ = [[NSMutableSet alloc] init];
  }
  return self;
}
  
- (void)awakeFromNib {  
  QSBResultsViewTableView *resultsTableView = [self resultsTableView];
  [resultsTableView setDataSource:self];
  [resultsTableView setDelegate:self];
  [resultsTableView reloadData];
  [resultsTableView setIntercellSpacing:NSMakeSize(0.0, 3.0)];

  // Hide and install the 'More' view.
  NSView *resultsView = [self resultsView];
  [resultsView setHidden:YES];
  [self setIsShowing:NO];
  NSRect viewFrame = [resultsView frame];

  // Nudge the view just out of visibility (by 100).
  CGFloat viewOffset = NSHeight(viewFrame) + 100.0;
  QSBSearchViewController *viewController = [self searchViewController];
  QSBSearchWindowController *windowController 
    = [viewController searchWindowController];
  NSWindow *resultsWindow = [windowController resultsWindow];
  NSView *contentView = [resultsWindow contentView];
  viewFrame.origin.y -= viewOffset;
  viewFrame.size.width = NSWidth([contentView frame]);
  [resultsView setFrame:viewFrame];
  [contentView addSubview:resultsView];
  blockTime_ = -1;
  // Must be called after the view has been added to the window.
  [super awakeFromNib];
}

- (void)dealloc {
  [moreResults_ release];
  [showAllCategoriesSet_ release];
  [moreResultsDict_ release];
  [rowHeightDict_ release];
  [super dealloc];
}

- (CGFloat)maximumTableHeight {
  // TODO(mrossetti): We probably want to calculate the following based
  // on the screen geometry.
  return 550.0;
}

- (BOOL)isTransitionDirectionUp {
  return NO;
}

- (QSBTableResult *)tableResultForRow:(NSInteger)row { 
  QSBTableResult *object = nil;
  if (row >= 0 && row < [moreResults_ count]) {
    object = [moreResults_ objectAtIndex:row];
  }
  return object;
}
 
- (NSDictionary *)localizedCategoryMap:(NSDictionary *)unlocalizedCategories {
  // Compose a results dict with localized category
  NSMutableDictionary *localizedDict
    = [NSMutableDictionary dictionaryWithCapacity:[unlocalizedCategories count]];
  NSBundle *bundle = [NSBundle mainBundle];
  for (NSString *rawCategoryName in unlocalizedCategories) {
    NSString *localizedCategoryName 
      = [bundle localizedStringForKey:rawCategoryName value:nil table:nil];
    id object = [unlocalizedCategories objectForKey:rawCategoryName];
    [localizedDict setObject:object forKey:localizedCategoryName];
  }
  return localizedDict;
}

- (void)setMoreResultsWithDict:(NSDictionary *)rawDict {
  [moreResultsDict_ autorelease];
  moreResultsDict_ = [rawDict retain];

  // TODO(mrossetti): There may be a need to merge categories.
  BOOL firstCategory = YES;
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSUInteger categoryLimit = [ud integerForKey:kQSBMoreCategoryResultCountKey];
  NSDictionary *localizedDict = [self localizedCategoryMap:rawDict];
  SEL caseInsensitiveCompare = @selector(caseInsensitiveCompare:);
  NSArray *sortedCategories 
    = [[localizedDict allKeys] sortedArrayUsingSelector:caseInsensitiveCompare];
  
  // Size allows for |categoryLimit| results, a show all, and a separator for 
  // each category plus the 'Top Results' fold.
  NSUInteger catCount = [sortedCategories count];
  NSUInteger resultCount = (catCount * categoryLimit) + kCategoryRowOverhead;
  NSMutableArray *results = [NSMutableArray arrayWithCapacity:resultCount];
  NSMutableArray *sortedCounts = [NSMutableArray arrayWithCapacity:catCount];
  NSBundle *bundle = [NSBundle mainBundle];
  
  for (NSString *categoryName in sortedCategories) {
    // Insert a separator if this is not the first category.
    if (firstCategory) {
      firstCategory = NO;
    } else {
      [results addObject:[QSBSeparatorTableResult tableResult]];
    }
    
    BOOL showAllInThisCategory 
      = [showAllCategoriesSet_ containsObject:categoryName];
    NSArray *categoryArray = [localizedDict objectForKey:categoryName];
    NSUInteger categoryCount = [categoryArray count];
    [sortedCounts addObject:[NSNumber numberWithUnsignedInteger:categoryCount]];
    NSUInteger resultCounter = 0;
    
    if (categoryCount == categoryLimit + 1) {
      showAllInThisCategory = YES;
    }
    
    for (HGSResult *result in categoryArray) {
      if (!showAllInThisCategory && resultCounter >= categoryLimit) {
        break;
      }
      QSBSourceTableResult *sourceResult 
        = [result valueForKey:kQSBObjectTableResultAttributeKey];
      NSString *localizedCategoryName = nil;
      if (resultCounter == 0) {
        // Tag this as the first row for a category so the title will show.
        localizedCategoryName
          = GTMCFAutorelease(UTTypeCopyDescription((CFStringRef)categoryName));
        if (!localizedCategoryName) {
          localizedCategoryName = [bundle localizedStringForKey:categoryName
                                                          value:nil 
                                                          table:nil];
        }
      }
      [sourceResult setCategoryName:localizedCategoryName];
      [results addObject:sourceResult];
      ++resultCounter;
    }
    
    categoryCount = [categoryArray count];
    if (resultCounter < categoryCount) {
      // Insert a 'Show all n...' cell.
      QSBShowAllTableResult *result
        = [QSBShowAllTableResult tableResultWithCategory:categoryName
                                                   count:categoryCount];
      [results addObject:result];
    }
  }
  [moreResults_ autorelease];
  moreResults_ = [results retain];
  [[self resultsTableView] reloadData];
  [[self searchViewController] updateResultsView];
  
  [self updateCategoryNames:sortedCategories counts:sortedCounts];
  
  // If we're setting to nil then we want to reset the expanded categories.
  if (!rawDict) {
    [showAllCategoriesSet_ removeAllObjects];
  }
}

- (void)addShowAllCategory:(NSString *)category {
  [showAllCategoriesSet_ addObject:category];

  // Force our category lists and indexes to be regenerated.
  // The selection gets lost so save/restore the selection.
  QSBResultsViewTableView *resultsTableView = [self resultsTableView];
  NSUInteger selectedRow = [resultsTableView selectedRow];
  [self setMoreResultsWithDict:moreResultsDict_];
  [resultsTableView selectRow:selectedRow byExtendingSelection:NO];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSDictionary *userInfo 
    = [NSDictionary dictionaryWithObject:category 
                                  forKey:kQSBMoreResultsCategoryKey];
  [nc postNotificationName:kQSBMoreResultsDidShowCategoryNotification 
                    object:self 
                  userInfo:userInfo];
}

- (void)updateCategoryNames:(NSArray *)names counts:(NSArray *)counts {
  NSString *comma = nil;
  NSMutableString *categorySummary = [NSMutableString string];
  NSEnumerator *catCountEnum = [counts objectEnumerator];
  for (NSString *catString in names) {
    NSUInteger catCount = [[catCountEnum nextObject] unsignedIntValue];
    if (catCount == 1) {
      // Singularize the category string.
      NSBundle *bundle = [NSBundle mainBundle];
      catString = [bundle localizedStringForKey:catString 
                                          value:nil 
                                          table:@"CategorySingulars"];
    }
    if (!comma) {
      comma = NSLocalizedString(@", ", nil);
    } else {
      [categorySummary appendString:comma];
    }
    [categorySummary appendFormat:@"%u %@", catCount, catString];
  }

  [[[self searchViewController] topResultsController]
   setCategorySummaryString:categorySummary];
}

- (Class)rowViewControllerClassForResult:(QSBTableResult *)result {
  return [result moreResultsRowViewControllerClass];
}

#pragma mark NSResponder Overrides

- (void)moveUp:(id)sender {
  NSInteger row = [[self resultsTableView] selectedRow];
  
  NSTimeInterval timeToBlock = 0.0;
  
  if (row == 0) {
    timeToBlock = kFirstRowUpwardDelay; 
  }
  
  NSEvent *event = [NSApp currentEvent];
  if (timeToBlock > 0
      && [event type] == NSKeyDown
      && [event isARepeat]) {
    if (blockTime_ < 0) {
      blockTime_ = [NSDate timeIntervalSinceReferenceDate];
    }
    if ([NSDate timeIntervalSinceReferenceDate] - blockTime_ < timeToBlock) {
      return; 
    }
  }
  
  if (row == 0) {
    // If we're on the first row then transition to the 'Top' results view.
    [[self searchViewController] showTopResults:sender];
  } else {
    [super moveUp:sender];
  }
   blockTime_ = -1;
}

// Repeats can't move us past the first row until a delay passes. this prevents
// overshooting the top results
- (void)moveDown:(id)sender {
  NSInteger row = [[self resultsTableView] selectedRow];
  
  NSTimeInterval timeToBlock = 0.0;
  
  if (row == 0) {
    timeToBlock = kFirstRowDownwardDelay; 
  }
  // TODO(alcor): This is disabled until further experimentation can be done
  // else {
  //    NSObject *result = [self objectForRow:row - 1];
  //    if ([result isKindOfClass:[QSBSeparatorTableResult class]]) {
  //      timeToBlock = 0.2;
  //    }    
  //  }
  
  NSEvent *event = [NSApp currentEvent];
  if (timeToBlock > 0
      && [event type] == NSKeyDown
      && [event isARepeat]) {
    if (blockTime_ < 0) {
      blockTime_ = [NSDate timeIntervalSinceReferenceDate];
    }
    if ([NSDate timeIntervalSinceReferenceDate] - blockTime_ < timeToBlock) {
      return; 
    }
  }
  blockTime_ = -1;
  [super moveDown:sender];
}

#pragma mark NSTableViewDelegate Methods

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
  return [moreResults_ count];
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
  QSBTableResult *result = [self tableResultForRow:row];
  Class resultClass = [result class];
  NSNumber *nsHeight = [rowHeightDict_ objectForKey:resultClass];
  if (!nsHeight) {
    CGFloat rowHeight = [super tableView:tableView heightOfRow:row];
    nsHeight = [NSNumber gtm_numberWithCGFloat:rowHeight];
    [rowHeightDict_ setObject:nsHeight forKey:resultClass];
  }
  CGFloat height = [nsHeight gtm_cgFloatValue];
  return height;
}

@end
