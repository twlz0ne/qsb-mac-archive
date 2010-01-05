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
#import <QSBPluginUI/QSBPluginUI.h>
#import "QSBApplication.h"
#import "QSBApplicationDelegate.h"
#import "QSBMoreResultsViewController.h"
#import "QSBPreferences.h"
#import "QSBTableResult.h"
#import "QSBResultsViewBaseController.h"
#import "GTMMethodCheck.h"
#import "GoogleCorporaSource.h"
#import "NSString+CaseInsensitive.h"
#import "NSString+ReadableURL.h"
#import "HGSOpenSearchSuggestSource.h"
#import "GTMNSObject+KeyValueObserving.h"

NSString *const kQSBSearchControllerDidUpdateResultsNotification
  = @"QSBSearchControllerDidUpdateResultsNotification";

@interface QSBSearchController ()

- (void)displayTimerElapsed:(NSTimer*)timer;

- (void)startDisplayTimer;
- (void)cancelDisplayTimer;

- (void)cancelAndReleaseQueryController;
- (void)updateResults;

- (void)resultCountValueChanged:(GTMKeyValueChangeNotification *)notification;

// Perform the actual query.  
- (void)performQuery;

@property(nonatomic, assign) BOOL queryIsInProcess;
@property(nonatomic, assign, getter=isQueryControllerFinished) BOOL queryControllerFinished;
@end

@implementation QSBSearchController

@synthesize pushModifierFlags = pushModifierFlags_;
@synthesize results = results_;
@synthesize parentSearchController = parentSearchController_;
@synthesize queryIsInProcess = queryIsInProcess_;
@synthesize queryControllerFinished = queryControllerFinished_;

GTM_METHOD_CHECK(NSString, qsb_hasPrefix:options:);
GTM_METHOD_CHECK(NSObject, gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);

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
  [typeCategoryDict_ release];
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  [prefs gtm_removeObserver:self
                 forKeyPath:kQSBResultCountKey
                   selector:@selector(resultCountValueChanged:)];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [super dealloc];
}

- (void)awakeFromNib {
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  [prefs gtm_addObserver:self
              forKeyPath:kQSBResultCountKey
                selector:@selector(resultCountValueChanged:)
                userInfo:nil
                 options:NSKeyValueObservingOptionNew];
  totalResultDisplayCount_ = [prefs integerForKey:kQSBResultCountKey];
}

- (void)startMixing {
  [queryController_ startMixingCurrentResults:self];
}


- (void)updateResults {
  HGSAssert(queryController_, nil);

  if (currentResultDisplayCount_ == 0) {
    HGSLog(@"updateDesktopResults called with display count still at 0!");
    return;
  }
  NSArray *rankedResults = [queryController_ rankedResults];
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

  HGSQuery *query = [queryController_ query];
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
  BOOL hasMoreStandardResults 
    = [rankedResults count] > currentResultDisplayCount_;
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
        = [result valueForKey:kQSBObjectTableResultAttributeKey];
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
  BOOL showMore = (hasMoreStandardResults
                   && ![[NSUserDefaults standardUserDefaults]
                        boolForKey:@"disableMoreResults"]);

  // Anything that ends up in the main results section should be locked down
  // to prevent any rearranging.
  [lockedResults_ release];
  lockedResults_ = [mainResults copy];

  // Is this search a generic, global search? (No pivot set)
  // If so, there may be special items above and/or below the search results
  NSMutableArray *suggestResults = [NSMutableArray array];
  NSUInteger queryLength = [[self queryString] length];
  
  if (!pivotObject) {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSInteger suggestCount = [prefs integerForKey:kGoogleSuggestCountKey];
    if (suggestCount) {
      if ([hgsSuggestions count] || queryLength < 3 || queryLength > 20) {
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
          QSBTableResult *qsbSuggest 
            = [suggest valueForKey:kQSBObjectTableResultAttributeKey];
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

  if (![[queryController_ query] pivotObject]) {
    // TODO(dmaclach): http://code.google.com/p/qsb-mac/issues/detail?id=871
    NSUInteger count = [newResults count];
    int searchItemsIndex = count;
    
    // Only rank the google query if the length > 3
    if (queryLength > 3 && count) {
      CGFloat moderateResultRank = HGSCalibratedScore(kHGSCalibratedModerateScore);
      for(searchItemsIndex = 0; searchItemsIndex < count; searchItemsIndex++) {
        QSBTableResult *item = [newResults objectAtIndex:searchItemsIndex];
        // List the google result lower if we have a moderate confidence result.
        if ([item rank] <= moderateResultRank) break;
      }
    }
    
    QSBSeparatorTableResult *spacer = [QSBSeparatorTableResult tableResult];
    
    if (searchItemsIndex > 0) {
      [newResults insertObject:spacer atIndex:searchItemsIndex++];
    }
    
    QSBGoogleTableResult *googleItem = [QSBGoogleTableResult
                                        tableResultForQuery:queryString_];
    [newResults insertObject:googleItem atIndex:searchItemsIndex];
    
    [newResults insertObject:spacer atIndex:searchItemsIndex + 1];
  }
  
  if (showMore) {
    if ([suggestResults count] > 0) {
      if (![[newResults lastObject]
            isKindOfClass:[QSBSeparatorTableResult class]]) {
        [newResults addObject:[QSBSeparatorTableResult tableResult]];
      }
      [newResults addObjectsFromArray:suggestResults];
    }
    if (![self isQueryControllerFinished]) {
      [newResults addObject:[QSBSearchStatusTableResult tableResult]];
    }
    [newResults addObject:[QSBFoldTableResult tableResult]];
  } else {
    if ([suggestResults count] > 0) {
      [newResults addObjectsFromArray:suggestResults];
    }
    if (![self isQueryControllerFinished]) {
      [newResults addObject:[QSBSearchStatusTableResult tableResult]];
    }
  }

  if ([self isQueryControllerFinished]) {
    [desktopResults_ setArray:newResults];
  }
  
  NSDictionary *resultsByCategory = [queryController_ rankedResultsByCategory];
  [moreResultsViewController_ setMoreResultsWithDict:resultsByCategory];  

  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBSearchControllerDidUpdateResultsNotification
                    object:self];
}

- (QSBTableResult *)topResultForIndex:(NSInteger)idx {
  QSBTableResult *result = nil;
  if (idx >= 0 && idx < [self topResultCount]) {
    result = [desktopResults_ objectAtIndex:idx];
  }
  return result;
}

- (NSUInteger)topResultCount {
  return [desktopResults_ count];
}

- (void)setQueryString:(NSString*)queryString {
#if DEBUG
  BOOL reportQueryStatusOnRestart = [[NSUserDefaults standardUserDefaults]
                                     boolForKey:@"reportQueryStatusOnRestart"];
  if (reportQueryStatusOnRestart) {
    HGSLog(@"QSB: Query Controller status before restart.\n  %@.", 
           queryController_);
  }
#endif
  [self stopQuery];
  [queryString_ autorelease];
  queryString_ = [queryString copy];
  if ([queryString_ length] || parentSearchController_) {
    [self performQuery];
  } else {
    [desktopResults_ removeAllObjects];
    [lockedResults_ release];
    lockedResults_ = nil;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:kQSBSearchControllerDidUpdateResultsNotification
                      object:self];
  }    
}

- (NSString*)queryString {
  return queryString_;
}

- (NSUInteger)maximumResultsToCollect {
  return totalResultDisplayCount_;
}

- (void)performQuery {
  [lockedResults_ release];
  lockedResults_ = nil;
  currentResultDisplayCount_ = (0.8 * [self maximumResultsToCollect]);
  [self cancelDisplayTimer];

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
    queryController_ = [[HGSQueryController alloc] initWithQuery:query];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(queryControllerDidFinish:)
               name:kHGSQueryControllerDidFinishNotification
             object:queryController_];
    [self setQueryIsInProcess:YES];
    [self setQueryControllerFinished:NO];

    // This became a separate call because some sources come back before
    // this call returns and queryController_ must be set first
    [queryController_ startQuery];
    [self startDisplayTimer];
    if (![self isQueryControllerFinished]) {
      [self startMixing];
    }
  }
}

- (void)stopQuery {
  [self cancelDisplayTimer];
  [self cancelAndReleaseQueryController];
  [self setQueryIsInProcess:NO];
}

#pragma mark Notifications

// Called when the last active query operation, and thus the query, has
// completed.  May be called even when there are more results that are
// possible, but the query has been stopped by the user or by the query
// reaching a time threshold.
- (void)queryControllerDidFinish:(NSNotification *)notification { 
  currentResultDisplayCount_ = [self maximumResultsToCollect];
  [self setQueryControllerFinished:YES];
  HGSQueryController *queryController = [notification object];
  HGSAssert([queryController isKindOfClass:[HGSQueryController class]], nil);
  if (![queryController isCancelled]) {
    [self startMixing];
  }
}

// called when enough time has elapsed that we want to display some results
// to the user.
- (void)displayTimerElapsed:(NSTimer*)timer {
  if (![self isQueryControllerFinished]) {
    [self startMixing];
  }
  [self updateResults];
}

- (void)resultCountValueChanged:(GTMKeyValueChangeNotification *)notification {
  NSDictionary *change = [notification change];
  NSNumber *valueOfChange = [change valueForKey:NSKeyValueChangeNewKey];
  totalResultDisplayCount_ = [valueOfChange unsignedIntegerValue];
  [self performQuery];
}

- (void)mixerDidFinish:(HGSMixer *)mixer {
  if (![mixer isCancelled]) {
    [self updateResults];
    if ([self isQueryControllerFinished]) {
      [self setQueryIsInProcess:NO];
      [self cancelDisplayTimer];
    }    
#if DEBUG
    BOOL dumpTopResults = [[NSUserDefaults standardUserDefaults]
                           boolForKey:@"dumpTopResults"];
    if (dumpTopResults) {
      HGSLog(@"QSB: Desktop Results:\n%@", desktopResults_);
      HGSLog(@"QSB: More Results:\n%@", [mixer rankedResultsByCategory]);
    }
#endif    
  }
}

- (void)startDisplayTimer {
  HGSAssert(!displayTimer_, nil);
  displayTimer_
    = [NSTimer scheduledTimerWithTimeInterval:1
                                       target:self
                                     selector:@selector(displayTimerElapsed:)
                                     userInfo:@"displayTimer"
                                      repeats:YES];
}

// cancels all timers and clears the member variables.
- (void)cancelDisplayTimer {
  [displayTimer_ invalidate];
  displayTimer_ = nil;
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

@end
