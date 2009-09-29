//
//  QSBMoreResultsViewDelegate.m
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

#import "QSBMoreResultsViewDelegate.h"
#import "QSBApplicationDelegate.h"
#import "QSBCategoryTextAttachment.h"
#import "QSBSearchController.h"
#import "QSBSearchViewController.h"
#import "QSBPreferences.h"
#import "QSBTableResult.h"
#import "QSBResultsViewTableView.h"
#import "QSBSearchWindowController.h"
#import "QSBTopResultsViewDelegate.h"
#import "HGSLog.h"
#import "GTMGarbageCollection.h"
#import "GTMMethodCheck.h"
#import "QSBTableResult.h"
#import "NSAttributedString+Attributes.h"

// Extra space to allow for miscellaneous rows (such as fold) in the results table.
static const NSUInteger kCategoryRowOverhead = 3;
static const NSTimeInterval kFirstRowDownwardDelay = 0.6;
static const NSTimeInterval kFirstRowUpwardDelay = 0.4;

@interface QSBMoreResultsViewDelegate ()

// Get/set sorted array of localized category names, suitable
// for use as keys to the dictionary returned by resultsByCategory.
- (NSArray *)sortedCategoryNames;
- (void)setSortedCategoryNames:(NSArray *)value;

// Get/set an array, in one-to-one correspondence with the array returned
// by sortedCategoryNames, containing the index of the first results in
// our arrangedObjects for each category.
- (NSArray *)sortedCategoryIndexes;
- (void)setSortedCategoryIndexes:(NSArray *)value;

// Get/set an array, in one-to-one correspondence with the array returned
// by sortedCategoryNames, containing the counts of the number of results in
// our arrangedObjects for each category.
- (NSArray *)sortedCategoryCounts;
- (void)setSortedCategoryCounts:(NSArray *)value;

- (void)setCategoriesString:(NSAttributedString *)value;
- (void)updateCategoryNames;

// Determines if 'show all' is indicated for the given category.
- (BOOL)showAllForCategory:(NSString *)category;

// Set/get the 'show all' categories.
- (void)setShowAllCategoriesSet:(NSSet *)showAllCategoriesSet;
- (NSSet *)showAllCategoriesSet;

@end


@implementation QSBMoreResultsViewDelegate

GTM_METHOD_CHECK(NSMutableAttributedString, addAttributes:);

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
  [sortedCategoryNames_ release];
  [sortedCategoryIndexes_ release];
  [sortedCategoryCounts_ release];
  [categoriesString_ release];
  [showAllCategoriesSet_ release];
  [moreResultsDict_ release];
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

- (NSArray *)moreResults {
  return [[moreResults_ retain] autorelease];
}

- (void)setMoreResults:(NSArray *)value {
  [moreResults_ autorelease];
  moreResults_ = [value retain];
}

- (void)setMoreResultsWithDict:(NSDictionary *)rawDict {
  [moreResultsDict_ autorelease];
  moreResultsDict_ = [rawDict retain];

  // TODO(mrossetti): There may be a need to merge categories.
  BOOL firstCategory = YES;
  NSUInteger categoryLimit = [[NSUserDefaults standardUserDefaults]
                            integerForKey:kQSBMoreCategoryResultCountKey];
  
  // Compose a results dict with localized category as name then sort.
  NSMutableDictionary *localizedDict
    = [NSMutableDictionary dictionaryWithCapacity:[rawDict count]];
  NSBundle *bundle = [NSBundle mainBundle];
  for (NSString *rawCategoryName in [rawDict allKeys]) {
    NSString *localizedCategoryName 
      = [bundle localizedStringForKey:rawCategoryName 
                                value:nil 
                                table:nil];
    [localizedDict setObject:[rawDict objectForKey:rawCategoryName]
                      forKey:localizedCategoryName];
  }
  NSArray *sortedCategories = [[localizedDict allKeys]
                               sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
  
  // Size allows for |categoryLimit| results, a show all, and a separator for 
  // each category plus the 'Top Results' fold.
  NSUInteger catCount = [sortedCategories count];
  NSMutableArray *results = [NSMutableArray
                             arrayWithCapacity:(catCount * categoryLimit)
                                               + kCategoryRowOverhead];
  NSMutableArray *sortedIndexes = [NSMutableArray arrayWithCapacity:catCount];
  NSMutableArray *sortedCounts = [NSMutableArray arrayWithCapacity:catCount];

  for (NSString *categoryName in sortedCategories) {
    // Insert a separator if this is not the first category.
    if (firstCategory) {
      firstCategory = NO;
    } else {
      [results addObject:[QSBSeparatorTableResult tableResult]];
    }
    
    BOOL showAllInThisCategory = [self showAllForCategory:categoryName];
    NSArray *categoryArray = [localizedDict objectForKey:categoryName];
    NSUInteger categoryCount = [categoryArray count];
    [sortedCounts addObject:[NSNumber numberWithUnsignedInteger:categoryCount]];
    NSUInteger resultCounter = 0;
    
    if ([categoryArray count] == categoryLimit + 1) showAllInThisCategory = YES;
    for (HGSResult *result in categoryArray) {
      if (!showAllInThisCategory && resultCounter >= categoryLimit) {
        break;
      }
      QSBSourceTableResult *sourceResult 
        = [QSBSourceTableResult tableResultWithResult:result];
      if (resultCounter == 0) {
        // Tag this as the first row for a category so the title will show.
        NSString *localizedCategoryName 
          = GTMCFAutorelease(UTTypeCopyDescription((CFStringRef)categoryName));
        if (!localizedCategoryName) {
          localizedCategoryName = [bundle localizedStringForKey:categoryName
                                                          value:nil 
                                                          table:nil];
        }
        [sourceResult setCategoryName:localizedCategoryName];
        NSUInteger resultsCount = [results count];
        NSNumber *resultsCountNum 
          = [NSNumber numberWithUnsignedInteger:resultsCount];
        [sortedIndexes addObject:resultsCountNum];
        [results addObject:sourceResult];
      } else {
        [results addObject:sourceResult];
      }
      ++resultCounter;
    }
    
    categoryCount = [categoryArray count];
    if (resultCounter < categoryCount) {
      // Insert a 'Show all n...' cell.
      [results addObject:[QSBShowAllTableResult tableResultWithCategory:categoryName
                                                                  count:categoryCount]];
    }
  }
  
  [self setSortedCategoryNames:sortedCategories];
  [self setSortedCategoryIndexes:sortedIndexes];
  [self setSortedCategoryCounts:sortedCounts];

  [self setMoreResults:results];
  [self updateCategoryNames];
  
  // If we're setting to nil then we want to reset the expanded categories.
  if (!rawDict) {
    [self setShowAllCategoriesSet:nil];  // Reset categories which 'show all'.
  }
}

- (NSAttributedString *)categoriesString {
  return [[categoriesString_ retain] autorelease];
}

- (void)addShowAllCategory:(NSString *)category {
  NSSet *oldSet = [self showAllCategoriesSet];
  if (oldSet) {
    NSSet *newSet = [oldSet setByAddingObject:category];
    [self setShowAllCategoriesSet:newSet];
  } else {
    NSSet *brandNewSet = [NSSet setWithObject:category];
    [self setShowAllCategoriesSet:brandNewSet];
  }
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

#pragma mark NSTableView Delegate Methods

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

- (Class)rowViewControllerClassForResult:(QSBTableResult *)result {
  return [result moreResultsRowViewControllerClass];
}

- (NSArray *)sortedCategoryNames {
  return [[sortedCategoryNames_ retain] autorelease];
}

- (void)setSortedCategoryNames:(NSArray *)value {
  [sortedCategoryNames_ autorelease];
  sortedCategoryNames_ = [value retain];
}

- (NSArray *)sortedCategoryIndexes {
  return [[sortedCategoryIndexes_ retain] autorelease];
}

- (void)setSortedCategoryIndexes:(NSArray *)value {
  [sortedCategoryIndexes_ autorelease];
  sortedCategoryIndexes_ = [value retain];
}

- (NSArray *)sortedCategoryCounts {
  return [[sortedCategoryCounts_ retain] autorelease];
}

- (void)setSortedCategoryCounts:(NSArray *)value {
  [sortedCategoryCounts_ autorelease];
  sortedCategoryCounts_ = [value retain];
}

- (void)setCategoriesString:(NSAttributedString *)value {
  [categoriesString_ autorelease];
  categoriesString_ = [value retain];
}

- (void)updateCategoryNames {
  NSArray *categories = [self sortedCategoryNames];
  NSArray *categoryIndexes = [self sortedCategoryIndexes];
  NSArray *categoryCounts = [self sortedCategoryCounts];
  
  NSString *comma = NSLocalizedString(@", ", nil);
  NSAttributedString *separator
    = [[[NSAttributedString alloc] initWithString:comma] autorelease];
  NSMutableAttributedString *categoryString
    = [[[NSMutableAttributedString alloc] init] autorelease];
  NSMutableString *categorySummary = [NSMutableString string];
  BOOL first = YES;
  NSEnumerator *catIndexEnum = [categoryIndexes objectEnumerator];
  NSEnumerator *catCountEnum = [categoryCounts objectEnumerator];
  NSEnumerator *catEnum = [categories objectEnumerator];
  NSString *catString = nil;
  while ((catString = [catEnum nextObject])) {
    NSUInteger catIndex = [[catIndexEnum nextObject] unsignedIntValue];
    NSUInteger catCount = [[catCountEnum nextObject] unsignedIntValue];
    if (catCount == 1) {
      // Singularize the category string.
      NSBundle *bundle = [NSBundle mainBundle];
      catString = [bundle localizedStringForKey:catString 
                                          value:nil 
                                          table:@"CategorySingulars"];
    }
    QSBCategoryTextAttachment *catAttachment
      = [QSBCategoryTextAttachment categoryTextAttachmentWithString:catString
                                                             index:catIndex];
    if (first) {
      first = NO;
    } else {
      [categoryString appendAttributedString:separator];
      [categorySummary appendString:comma];
    }
    NSAttributedString *catTail
      = [NSAttributedString attributedStringWithAttachment:catAttachment];
    [categoryString appendAttributedString:catTail];
    [categorySummary appendFormat:@"%u %@", catCount, catString];
  }
  
  // Set the line break attribute.
  NSMutableParagraphStyle *lineBreakStyle
    = [[[NSMutableParagraphStyle alloc] init] autorelease];
  [lineBreakStyle setLineBreakMode:NSLineBreakByTruncatingTail];
  NSDictionary *lineBreakAttributes
    = [NSDictionary dictionaryWithObject:lineBreakStyle
                                forKey:NSParagraphStyleAttributeName];
  [categoryString addAttributes:lineBreakAttributes];
  [self setCategoriesString:categoryString];
  
  [[[self searchViewController] topResultsController]
   setCategorySummaryString:categorySummary];
}

- (void)textView:(NSTextView *)aTextView
   clickedOnCell:(id<NSTextAttachmentCell>)cell
          inRect:(NSRect)cellFrame
         atIndex:(NSUInteger)idx {
  QSBCategoryTextAttachmentCell *catCell = (QSBCategoryTextAttachmentCell *)cell;
  NSUInteger catIndex = [catCell tableIndex];
  QSBResultsViewTableView *resultsTableView = [self resultsTableView];
  [resultsTableView selectRow:catIndex byExtendingSelection:NO];
  if (![resultsTableView rowIsVisible:catIndex]) {
    [resultsTableView scrollRowToVisible:[resultsTableView numberOfRows] - 1];
    [resultsTableView scrollRowToVisible:catIndex];
  }
}

- (void)setShowAllCategoriesSet:(NSSet *)showAllCategoriesSet {
  [showAllCategoriesSet_ autorelease];
  showAllCategoriesSet_ = [showAllCategoriesSet retain];
}

- (NSSet *)showAllCategoriesSet {
  return [[showAllCategoriesSet_ retain] autorelease];
}

- (BOOL)showAllForCategory:(NSString *)category {
  BOOL showAll = ([showAllCategoriesSet_ containsObject:category]);
  return showAll;
}

@end
