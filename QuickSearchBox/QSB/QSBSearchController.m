//
//  QSBSearchController.m
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
//

#import "QSBSearchController.h"
#import "QSBApplication.h"
#import "QSBApplicationDelegate.h"
#import "QSBMoreResultsViewDelegate.h"
#import "QSBPreferences.h"
#import "QSBTableResult.h"
#import "QSBResultsViewBaseController.h"
#import "GTMMethodCheck.h"
#import "GoogleCorporaSource.h"
#import "NSString+CaseInsensitive.h"
#import "NSString+ReadableURL.h"
#import "HGSOpenSearchSuggestSource.h"

static const NSUInteger kDefaultMaximumResultsToCollect = 500;
NSString *const kQSBSearchControllerDidUpdateResultsNotification 
  = @"QSBSearchControllerDidUpdateResultsNotification";

@interface QSBSearchController ()

- (void)displayTimerElapsed:(NSTimer*)timer;

- (void)startDisplayTimers;
- (void)cancelDisplayTimers;

- (void)cancelAndReleaseQueryController;

// Reset the 'More Results'
- (void)setMoreResults:(NSDictionary *)value;
- (void)updateMoreResults;

@end


@implementation QSBSearchController

@synthesize pushModifierFlags = pushModifierFlags_;
@synthesize results = results_;
@synthesize parentSearchController = parentSearchController_;
@synthesize queryIsInProcess = queryIsInProcess_;

GTM_METHOD_CHECK(NSString, qsb_hasPrefix:options:);

+ (void)initialize {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSArray *keys = [NSArray arrayWithObjects:@"showAllCategoriesSet", nil];
  [self setKeys:keys triggerChangeNotificationsForDependentKey:@"moreResults"];
  [pool release];
}

- (id)init {
  self = [super init];
  if (self != nil) {
    desktopResults_ = [[NSMutableArray alloc] init];
  }
  return self;
}

- (void)dealloc {
  // Cancel outstanding query requests and all timers.
  [self stopQuery];
  [self cancelAndReleaseQueryController];
  [queryString_ release];
  [results_ release];
  [parentSearchController_ release];
  [desktopResults_ release];
  [lockedResults_ release];
  [oldSuggestions_ release];
  [moreResults_ release];
  [typeCategoryDict_ release];
  [super dealloc];
}

- (void)updateDesktopResults {  
  HGSQueryController* controller = queryController_;
  if (!controller) return;
  HGSAssert(controller, @"No controller?");
  
  if (currentResultDisplayCount_ == 0) {
    HGSLog(@"updateDesktopResults called with display count still at 0!");
    return;
  }
  
  NSArray *rankedResults = [controller rankedResults];
  NSMutableArray *hgsResults = [NSMutableArray array];
  NSMutableArray *hgsMutableSuggestions = [NSMutableArray array];
  for (HGSResult *result in rankedResults) {
    if ([result conformsToType:kHGSTypeSuggest]) {
      [hgsMutableSuggestions addObject:result];
    } else {
      [hgsResults addObject:result];
    }
  }
  NSArray *hgsSuggestions = (NSArray*)hgsMutableSuggestions;
  
  HGSQuery *query = [controller query];
  HGSResult *pivotObject = [query pivotObject];

  // TODO(dmaclach): we need to revisit this.  as shortcuts, suggest, and
  // regular results go in, they need to be deduped.  the current dedupe is in
  // the mixer as it does the merge, but we don't seem to want to use that here.
  // so we need to factor that logic into some way it can be used here.  we had
  // been using uris here, but we don't want to require them, and that's not the
  // same deduping that happens w/in mixer.
  
  // Build the main results list.
  // First anything that was locked down, then shortcuts, then the main results.
  // We have to do simple de-duping across the three, since there may be
  // duplication between the three sets.
  NSMutableArray *mainResults = [NSMutableArray array];
  
  // Keep what was locked in
  [mainResults addObjectsFromArray:lockedResults_];
  
  // Standard results
  BOOL hasMoreStandardResults = NO;
  NSMutableArray *belowTheFoldResults = [NSMutableArray array];
  for (HGSResult *result in hgsResults) {
    if ([mainResults count] >= currentResultDisplayCount_) {
      hasMoreStandardResults = YES;
      break;
    }
    // Simple de-dupe by looking for identical result matches.
    NSArray *mainHGSResults = [mainResults valueForKey:@"representedResult"];
    BOOL okayToAppend = YES;
    for (HGSResult *currentResult in mainHGSResults) {
      if ([currentResult isDuplicate:result]) {
        okayToAppend = NO;
        break;
      }
    }
    if (okayToAppend) {
      QSBSourceTableResult *sourceResult
        = [QSBSourceTableResult tableResultWithResult:result];
      CGFloat resultScore = [result rank];
      if (pivotObject
          || resultScore > HGSCalibratedScore(kHGSCalibratedInsignificantScore)) {
        if (pivotObject
            || (([result rankFlags] & eHGSBelowFoldRankFlag) == 0
                && resultScore > HGSCalibratedScore(kHGSCalibratedWeakScore))) {
          [mainResults addObject:sourceResult];
        } else {
          hasMoreStandardResults = YES;
          [belowTheFoldResults addObject:sourceResult];
        }
      }
    }
  }
  
  // If there were more results than could be shown in TOP then we'll
  // need a 'More' fold.
  BOOL showMore = ((hasMoreStandardResults
                    || ![self suppressMoreIfTopShowsAll])
                   && ![[NSUserDefaults standardUserDefaults]
                        boolForKey:@"disableMoreResults"]);
  
  // Anything that ends up in the main results section should be locked down
  // to prevent any rearranging.
  [lockedResults_ release];
  lockedResults_ = [mainResults copy];
  
  // Is this search a generic, global search? (No pivot set)
  // If so, there may be special items above and/or below the search results
  NSMutableArray *suggestResults = [NSMutableArray array];
  
  if (!pivotObject) {    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSInteger suggestCount = [prefs integerForKey:kGoogleSuggestCountKey];
    if (suggestCount) {
      NSUInteger length = [[self queryString] length];
      if ([hgsSuggestions count] || length < 3 || length > 20) {
        [oldSuggestions_ autorelease];
        oldSuggestions_ = [hgsSuggestions retain]; 
      } else {
        hgsSuggestions = oldSuggestions_;
      }
              
      NSUInteger minSuggestCount = ABS(suggestCount);
      if (minSuggestCount < 3)
        minSuggestCount = 3; // minimum of 3 for now

      if ([hgsSuggestions count] > minSuggestCount) {
        hgsSuggestions =
            [hgsSuggestions subarrayWithRange:NSMakeRange(0, minSuggestCount)];
      }
      
      if (minSuggestCount && [hgsSuggestions count]) {
        NSMutableArray *target = suggestResults;
        for (HGSResult *suggest in hgsSuggestions) {
          QSBTableResult *qsbSuggest = nil;
          qsbSuggest = [QSBSourceTableResult tableResultWithResult:suggest];
          [target addObject:qsbSuggest];
        }
      }
    }
  }
  
  // Build the actual list
  NSMutableArray *newResults = [NSMutableArray array];
  
  if ([mainResults count] > 0) {
    [newResults addObjectsFromArray:mainResults];
  }
  
  int searchItemsIndex = 0; 
  if (![[controller query] pivotObject]) {
    QSBSeparatorTableResult *spacer = [QSBSeparatorTableResult tableResult];
      
    // TODO(alcor): this is probably going to be done by the mixer eventually
    
    NSUInteger count = [newResults count];
    
    // TODO(alcor): we only cycle through this once because ranking is odd
    // at the moment. Eventually we want to unpin the google result
    count = MIN(1, count);
    
    if (count) {
      for(searchItemsIndex = 0; searchItemsIndex < count; searchItemsIndex++) {
      QSBTableResult *item = [newResults objectAtIndex:searchItemsIndex];
      // List the google result lower if we have a strong confidence result.
        if ([item rank] <= 0.667) break;
      }
    }
    
    if (searchItemsIndex > 0) {
      [newResults insertObject:spacer atIndex:searchItemsIndex++];
    }
    
    QSBGoogleTableResult *googleItem = [QSBGoogleTableResult
                                         tableResultForQuery:queryString_];
    [newResults insertObject:googleItem atIndex:searchItemsIndex];
    
    [newResults insertObject:spacer atIndex:searchItemsIndex + 1]; 
  }
  
  if ([newResults count] < [desktopResults_ count]) {
    NSRange newRange = NSMakeRange(0, [newResults count]);
    [desktopResults_ replaceObjectsInRange:newRange
                      withObjectsFromArray:newResults];
  } else {
    [desktopResults_ setArray:newResults];
  }

  // If there is still room in top results for things marked for showing
  // below the fold, then fill up top results with those below the fold items.
  NSInteger availableToMove = [belowTheFoldResults count];
  NSInteger countToMove = currentResultDisplayCount_ - [mainResults count];
  countToMove = MIN(countToMove, availableToMove);
  if (countToMove > 0) {
    showMore &= (countToMove < availableToMove);
    for (NSInteger idx = 0; idx < countToMove; ++idx) {
      QSBSourceTableResult *belowTheFoldResult
        = [belowTheFoldResults objectAtIndex:idx];
      [newResults addObject:belowTheFoldResult];
    }
  }
  
  if (showMore && [controller hasAnyRealResults]) {
    if ([suggestResults count] > 0) {
      if (![[newResults lastObject]
            isKindOfClass:[QSBSeparatorTableResult class]]) {
        [newResults addObject:[QSBSeparatorTableResult tableResult]];
      }
      [newResults addObjectsFromArray:suggestResults];
    }
    if (![controller queriesFinished]) {
      [newResults addObject:[QSBSearchStatusTableResult tableResult]];
    }    
    [newResults addObject:[QSBFoldTableResult tableResult]];
  } else {
    if ([suggestResults count] > 0) {
      [newResults addObjectsFromArray:suggestResults];
    }
    if (![controller queriesFinished]) {
      [newResults addObject:[QSBSearchStatusTableResult tableResult]];
    }    
  }
  
  if ([controller queriesFinished]) {
    [desktopResults_ setArray:newResults];
  }
  
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBSearchControllerDidUpdateResultsNotification 
                    object:self];
}

- (NSString *)searchStatus {
  NSString *listSeparator 
    = HGSLocalizedString(@", ", @"A list delimiter.");
  NSArray *pendingQueries = [queryController_ pendingQueries];
  return [[pendingQueries valueForKey:@"displayName"]
          componentsJoinedByString:listSeparator];
}

- (QSBTableResult *)topResultForIndex:(NSInteger)idx {
  QSBTableResult *result = nil;
  if (idx >= 0 && idx < [self topResultCount]) {
    result = [desktopResults_ objectAtIndex:idx];
  }
  return result;
}

- (NSArray *)topResultsForRange:(NSRange)range {
  return [desktopResults_ subarrayWithRange:range];
}

- (NSUInteger)topResultCount {
  return [desktopResults_ count];
}

- (NSDictionary *)moreResults {
  return [[moreResults_ retain] autorelease];
}

// Restart the query with the current queryString_ and context
// this cancels the old query.
- (void)restartQueryClearingResults:(BOOL)clearResults {
#if DEBUG
  BOOL reportQueryStatusOnRestart = [[NSUserDefaults standardUserDefaults]
                                     boolForKey:@"reportQueryStatusOnRestart"];
  if (reportQueryStatusOnRestart) {
    HGSLog(@"QSB: Query Controller status before restart.\n  %@.", queryController_);
  }
#endif
  [self cancelAndReleaseQueryController];
  
  // wait before sending off our query to coalesce any other restarts in flight.
  // Must cancel any old requests as we only want one in the queue at a time.
  [NSObject cancelPreviousPerformRequestsWithTarget:self 
                                           selector:@selector(doDesktopQuery:) 
                                             object:nil];
  [self performSelector:@selector(doDesktopQuery:)
             withObject:nil
             afterDelay:0.0];
  
  if (clearResults) {
    [desktopResults_ removeAllObjects];
    [self setMoreResults:nil];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:kQSBSearchControllerDidUpdateResultsNotification 
                      object:self];    
  }
}

- (void)setQueryString:(NSString*)queryString {
  BOOL isPrefix = NO;
  if (!queryString) {
    [queryString_ release];
    queryString_ = nil;
  } else if (![queryString_ isEqualToString:queryString]) {
    NSStringCompareOptions options = (NSCaseInsensitiveSearch 
                                      | NSWidthInsensitiveSearch 
                                      | NSDiacriticInsensitiveSearch);
    isPrefix = ([queryString_ length] > 0 && 
                [queryString length] > 0 && 
                ([queryString qsb_hasPrefix:queryString_ options:options] || 
                 [queryString_ qsb_hasPrefix:queryString options:options]));
    [queryString_ autorelease];
    queryString_ = [queryString copy];
  }
  [self restartQueryClearingResults:(!isPrefix)];
}

- (NSString*)queryString {
  return queryString_;
}

- (NSUInteger)maximumResultsToCollect {
  return kDefaultMaximumResultsToCollect;
}

- (BOOL)suppressMoreIfTopShowsAll {
  return YES;
}

- (void)doDesktopQuery:(id)ignoredValue {  
  [lockedResults_ release];
  lockedResults_ = nil;
  currentResultDisplayCount_ = 0;
  [self setQueryIsInProcess:YES];
  [self cancelDisplayTimers];
  
  if (queryString_ || results_) {
    
    HGSQueryFlags flags = 0;
    if (pushModifierFlags_ & NSAlternateKeyMask) {
      flags |= eHGSQueryShowAlternatesFlag;
    }
    
    HGSQuery *query = [[[HGSQuery alloc] initWithString:queryString_
                                                results:results_
                                             queryFlags:flags]
                       autorelease];
    [query setMaxDesiredResults:[self maximumResultsToCollect]];
    
    [self cancelAndReleaseQueryController];
    HGSMixer* mixer = [[[HGSMixer alloc] init] autorelease];
    queryController_ = [[HGSQueryController alloc] initWithQuery:query
                                                           mixer:mixer];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self 
           selector:@selector(queryControllerDidFinish:) 
               name:kHGSQueryControllerDidFinishNotification 
             object:queryController_];
    [nc addObserver:self 
           selector:@selector(queryControllerDidAddResults:) 
               name:kHGSQueryControllerDidUpdateResultsNotification 
             object:queryController_];
    [nc addObserver:self 
           selector:@selector(queryControllerDidFinishOperation:)
               name:kHGSQueryControllerDidFinishOperationNotification 
             object:queryController_];
    // This became a separate call because some sources come back before
    // this call returns and queryController_ must be set first
    [queryController_ startQuery];
    [self startDisplayTimers];
  }
}

- (void)stopQuery {
  [self cancelDisplayTimers];
  [NSObject cancelPreviousPerformRequestsWithTarget:self 
                                           selector:@selector(doDesktopQuery:) 
                                             object:nil];
  [queryController_ cancel];
  [self setQueryIsInProcess:NO];
}

#pragma mark Notifications

// Called when the last active query operation, and thus the query, has
// completed.  May be called even when there are more results that are
// possible, but the query has been stopped by the user or by the query
// reaching a time threshhold. 
- (void)queryControllerDidFinish:(NSNotification *)notification {
  [moreResultsUpdateTimer_ invalidate];
  moreResultsUpdateTimer_ = nil;
  currentResultDisplayCount_ = [self maximumResultsToCollect];
  [self updateDesktopResults]; 
  [self updateMoreResults];
#if DEBUG
  BOOL dumpTopResults = [[NSUserDefaults standardUserDefaults]
                         boolForKey:@"dumpTopResults"];
  if (dumpTopResults) {
    HGSLog(@"QSB: Desktop Results:\n%@", desktopResults_);
    HGSLog(@"QSB: More Results:\n%@", [self moreResults]);
  }
#endif
  
  [self setQueryIsInProcess:NO];
}

- (void)queryControllerDidFinishOperation:(NSNotification *)notification {
  [self willChangeValueForKey:@"searchStatus"];
  [self didChangeValueForKey:@"searchStatus"];
}

// Called when more results are added to the query.
- (void)queryControllerDidAddResults:(NSNotification *)notification {
  // We treat the shortcut source "specially" because it tends
  // to have high quality results.
  if (shortcutDisplayTimer_) {
    NSDictionary *userinfo = [notification userInfo];
    NSArray *ops = [userinfo objectForKey:kHGSQueryControllerOperationsKey];
    for (HGSSearchOperation *op in ops) {
      HGSSearchSource *source = [op source];
      NSString *identifier = [source identifier];
      if ([identifier isEqualToString:kHGSShortcutsSourceIdentifier]) {
        [shortcutDisplayTimer_ fire];
        shortcutDisplayTimer_ = nil;
      }
    }
  }
}

// called when enough time has elapsed that we want to display some results
// to the user.
- (void)displayTimerElapsed:(NSTimer*)timer {
  if (timer == shortcutDisplayTimer_) {
    shortcutDisplayTimer_ = nil;
    currentResultDisplayCount_ = 1;
  } else if (timer == firstTierDisplayTimer_) {
    firstTierDisplayTimer_ = nil;
    // Fill most of the rows, but leave a few for good but slow results.
    currentResultDisplayCount_ = (int)(0.8 * [self maximumResultsToCollect]);
  } else if (timer == secondTierDisplayTimer_) {
    secondTierDisplayTimer_ = nil;
    // Leave one slot for the very best (queryDidFinish: sets
    // currentResultDisplayCount_ = [self maximumResultsToCollect]
    currentResultDisplayCount_ = [self maximumResultsToCollect] - 1;
  } else if (timer == moreResultsUpdateTimer_) {
    [self updateMoreResults];
  }
  [self updateDesktopResults];
  
  // If we've locked down all the rows, we can go ahead and cancel the query now
  if ([lockedResults_ count] == [self maximumResultsToCollect]) {
    [queryController_ cancel];
  }
}

// start three display timers for 100, 300 and 750ms. We retain them
// so we can cancel them if the query finishes early.
- (void)startDisplayTimers {
  // We need the first cutoff to be below the user's "instant" threshold
  // for autocomplete to feel right.
  const CGFloat kShortcutDisplayInterval = 0.100;
  const CGFloat kFirstTierDisplayInterval = 0.300;
  const CGFloat kSecondTierDisplayInterval = 0.750;
  const CGFloat kUpdateTierDisplayInterval = 3;
  [self cancelDisplayTimers];
  shortcutDisplayTimer_ =
    [NSTimer scheduledTimerWithTimeInterval:kShortcutDisplayInterval
                                     target:self
                                   selector:@selector(displayTimerElapsed:)
                                   userInfo:@"shortcutTimer"
                                    repeats:NO];
  firstTierDisplayTimer_ =
    [NSTimer scheduledTimerWithTimeInterval:kFirstTierDisplayInterval 
                                     target:self
                                   selector:@selector(displayTimerElapsed:)
                                   userInfo:@"firstTierTimer"
                                    repeats:NO];
  secondTierDisplayTimer_ =
    [NSTimer scheduledTimerWithTimeInterval:kSecondTierDisplayInterval 
                                     target:self
                                   selector:@selector(displayTimerElapsed:)
                                   userInfo:@"secondTierTimer"
                                    repeats:NO];
  moreResultsUpdateTimer_ 
    = [NSTimer scheduledTimerWithTimeInterval:kUpdateTierDisplayInterval
                                       target:self 
                                     selector:@selector(displayTimerElapsed:) 
                                     userInfo:@"updateMoreResultsTimer" 
                                      repeats:YES];
  
  
}

// cancels all timers and clears the member variables.
- (void)cancelDisplayTimers {
  [shortcutDisplayTimer_ invalidate];
  shortcutDisplayTimer_ = nil;
  [firstTierDisplayTimer_ invalidate];
  firstTierDisplayTimer_ = nil;
  [secondTierDisplayTimer_ invalidate];
  secondTierDisplayTimer_ = nil;
  [moreResultsUpdateTimer_ invalidate];
  moreResultsUpdateTimer_ = nil;
}

- (void)cancelAndReleaseQueryController {
  if (queryController_) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc removeObserver:self name:nil object:queryController_];
    [queryController_ cancel];
    [queryController_ release];
    queryController_ = nil;
  }
}

- (void)setMoreResults:(NSDictionary *)value {
  [moreResults_ autorelease];
  moreResults_ = [value retain];
  [moreResultsViewDelegate_ setMoreResultsWithDict:value];
}

- (void)updateMoreResults {
  NSDictionary *resultsByCategory = [queryController_ rankedResultsByCategory];
  [self setMoreResults:resultsByCategory];
}


@end
