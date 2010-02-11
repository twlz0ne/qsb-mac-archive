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
NSString *const kQSBSearchControllerWillChangeQueryStringNotification
  = @"QSBSearchControllerWillChangeQueryStringNotification";
NSString *const kQSBSearchControllerDidChangeQueryStringNotification
  = @"QSBSearchControllerDidChangeQueryStringNotification";
NSString *const kQSBSearchControllerResultCountByCategoryKey
  = @"QSBSearchControllerResultCountByCategoryKey";
NSString *const kQSBSearchControllerResultCountKey
    = @"QSBSearchControllerResultCountKey";

const NSTimeInterval kQSBDisplayTimerStages[] = { 0.1, 0.3, 0.7 };

@interface QSBSearchController ()

- (void)displayTimerElapsed:(NSTimer*)timer;

- (void)cancelAndReleaseQueryController;
- (void)updateResults;

- (void)resultCountValueChanged:(GTMKeyValueChangeNotification *)notification;

// Perform the actual query.  
- (void)performQuery;
- (NSDictionary *)resultCountByCategory;


@property(nonatomic, assign, getter=isQueryInProcess) BOOL queryInProcess;
@property(nonatomic, assign, getter=isGatheringFinished) BOOL gatheringFinished;
@end

@implementation QSBSearchController

@synthesize pushModifierFlags = pushModifierFlags_;
@synthesize results = results_;
@synthesize parentSearchController = parentSearchController_;
@synthesize queryInProcess = queryInProcess_;
@synthesize gatheringFinished = gatheringFinished_;

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
  if ((self = [super init])) {
    topResults_ = [[NSMutableArray alloc] init];
    
    // Set up our cache for where we store moreResults that we generate.
    // Unlike the topResults we generate these on demand.
    // NSPointerArrays are implemented as sparse arrays according to bbum:
    // http://stackoverflow.com/questions/1354955/how-to-do-sparse-array-in-cocoa/1357899
    NSArray *categories = [[QSBCategoryManager sharedManager] categories];
    NSMutableDictionary *moreResults 
      = [NSMutableDictionary dictionaryWithCapacity:[categories count]];
    for (QSBCategory *category in categories) {
      NSPointerArray *cache = [NSPointerArray pointerArrayWithStrongObjects];
      [moreResults setObject:cache forKey:category];
    }
    moreResults_ = [moreResults retain];
  }
  return self;
}

- (void)dealloc {
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  [prefs gtm_removeObserver:self
                 forKeyPath:kQSBResultCountKey
                   selector:@selector(resultCountValueChanged:)];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];

  // Cancel outstanding query requests and all timers.
  [self stopQuery];
  [tokenizedQueryString_ release];
  [results_ release];
  [parentSearchController_ release];
  [topResults_ release];
  [moreResults_ release];
  [lockedResults_ release];
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

- (void)resetMoreResults {
  // Reset our more results caches by setting the count to zero.
  NSArray *categories = [[QSBCategoryManager sharedManager] categories];
  for (QSBCategory *category in categories) {
    NSPointerArray *cache = [moreResults_ objectForKey:category];
    [cache setCount:0];
  }
}

- (void)updateResults {
  HGSAssert(queryController_, nil);

  if (currentResultDisplayCount_ == 0) {
    HGSLog(@"updateDesktopResults called with display count still at 0!");
    return;
  }
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
  HGSQuery *query = [queryController_ query];
  HGSResult *pivotObject = [query pivotObject];
  
  // Get our top results that aren't suggestions. We group suggestions.
  NSRange resultRange = NSMakeRange(0, currentResultDisplayCount_);
  NSSet *suggestSet = [NSSet setWithObject:kHGSTypeSuggest];
  HGSTypeFilter *notSuggestionsFilter 
    = [HGSTypeFilter filterWithDoesNotConformTypes:suggestSet];
  NSArray *rankedHGSResults 
    = [queryController_ rankedResultsInRange:resultRange 
                                  typeFilter:notSuggestionsFilter
                            removeDuplicates:YES];

  // Keep what was locked in
  NSMutableArray *topQSBTableResults 
    = [NSMutableArray arrayWithArray:lockedResults_];
  NSMutableArray *hgsResults 
    = [topQSBTableResults valueForKey:@"representedResult"];
  HGSAssert(![hgsResults containsObject:[NSNull null]], nil);
  hgsResults = [NSMutableArray arrayWithArray:hgsResults];
  NSMutableArray *moreQSBTableResults = [NSMutableArray array];
  
  for (HGSScoredResult *scoredResult in rankedHGSResults) {
    if ([topQSBTableResults count] >= currentResultDisplayCount_) {
      break;
    }
    // Simple de-dupe by looking for identical result matches.
    BOOL okayToAppend = YES;
    for (HGSScoredResult *currentResult in hgsResults) {
      if ([currentResult isDuplicate:scoredResult]) {
        okayToAppend = NO;
        break;
      }
    }
    if (okayToAppend) {
      QSBSourceTableResult *tableResult
        = [scoredResult valueForKey:kQSBObjectTableResultAttributeKey];
      CGFloat resultScore = [scoredResult score];
      [hgsResults addObject:scoredResult];
      if (([scoredResult rankFlags] & eHGSBelowFoldRankFlag) == 0
          && resultScore > HGSCalibratedScore(kHGSCalibratedWeakScore)) {
        [topQSBTableResults addObject:tableResult];
      } else {
        [moreQSBTableResults addObject:tableResult];
      }
    }
  }

  // If we have less than currentResultDisplayCount_ objects, promote some
  // from moreQSBTableResults.
  NSUInteger topCount = [topQSBTableResults count];
  if (topCount < currentResultDisplayCount_) {
    [topQSBTableResults addObjectsFromArray:moreQSBTableResults];
    topCount = [topQSBTableResults count];
  }
  
  // If we have more than currentResultDisplayCount_ object, trim the array.
  if (topCount > currentResultDisplayCount_) {
    NSRange trimRange = NSMakeRange(currentResultDisplayCount_, 
                                    topCount - currentResultDisplayCount_);
    [topQSBTableResults removeObjectsInRange:trimRange];
  }
  
  // Anything that ends up in the main results section should be locked down
  // to prevent any rearranging.
  [lockedResults_ release];
  lockedResults_ = [topQSBTableResults copy];

  // Now get and add suggestions.
  NSArray *hgsSuggestions = nil;
  NSUInteger queryLength = [[self tokenizedQueryString] originalLength];
  if (!pivotObject) {
    NSInteger suggestCount = [userDefaults integerForKey:kGoogleSuggestCountKey];
    if (suggestCount && queryLength >= 3 && queryLength <= 20) {
      NSRange suggestRange = NSMakeRange(0, suggestCount);
      HGSTypeFilter *suggestionsFilter 
        = [HGSTypeFilter filterWithConformTypes:suggestSet];
      
      hgsSuggestions = [queryController_ rankedResultsInRange:suggestRange 
                                                   typeFilter:suggestionsFilter
                                             removeDuplicates:YES];
      NSArray *hgsTableSuggestions 
        = [hgsSuggestions valueForKey:kQSBObjectTableResultAttributeKey];
      HGSAssert(![hgsTableSuggestions containsObject:[NSNull null]], nil);
      [topQSBTableResults addObjectsFromArray:hgsTableSuggestions];
    }
  }
  
  // If there were more results than could be shown in TOP then we'll
  // need a 'More' fold.
  NSUInteger resultCount 
    = [queryController_ resultCountForFilter:notSuggestionsFilter];
  BOOL showMore = (resultCount > currentResultDisplayCount_
                   && ![userDefaults boolForKey:@"disableMoreResults"]);
  if (showMore) {
    [topQSBTableResults addObject:[QSBSeparatorTableResult tableResult]];
    [topQSBTableResults addObject:[QSBFoldTableResult tableResult]];
  }
  [topResults_ setArray:topQSBTableResults];

  [self resetMoreResults];
  NSDictionary *resultCountByCategory = [self resultCountByCategory];
  for (QSBCategory *category in resultCountByCategory) {
    NSNumber *nsValue = [resultCountByCategory objectForKey:category];
    NSUInteger value = [nsValue unsignedIntegerValue];
    NSPointerArray *cache = [moreResults_ objectForKey:category];
    [cache setCount:value];
  }
  resultsNeedUpdating_ = NO;
  
  NSDictionary *infoDict 
    = [NSDictionary dictionaryWithObjectsAndKeys:
       [self resultCountByCategory], 
       kQSBSearchControllerResultCountByCategoryKey,
       [NSNumber numberWithUnsignedInteger:resultCount],
       kQSBSearchControllerResultCountKey, 
       nil];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBSearchControllerDidUpdateResultsNotification
                    object:self
                  userInfo:infoDict];
}

- (NSArray *)topResultsInRange:(NSRange)range {
  return [topResults_ subarrayWithRange:range];
}

- (QSBTableResult *)topResultForIndex:(NSInteger)idx {
  QSBTableResult *result = nil;
  if (idx >= 0 && idx < [self topResultCount]) {
    result = [topResults_ objectAtIndex:idx];
  }
  return result;
}

- (NSUInteger)topResultCount {
  return [topResults_ count];
}

- (QSBSourceTableResult *)rankedResultForCategory:(QSBCategory *)category 
                                          atIndex:(NSInteger)idx {
  // Check our cache, and if we don't have anything, generate it lazily and
  // cache it.
  NSPointerArray *resultsForCategory = [moreResults_ objectForKey:category];
  QSBSourceTableResult *result = [resultsForCategory pointerAtIndex:idx];
  if (!result) {
    HGSTypeFilter *typeFilter = [category typeFilter];
    NSArray *results = [queryController_ rankedResultsInRange:NSMakeRange(idx, 1)
                                                   typeFilter:typeFilter
                                             removeDuplicates:NO];
    if ([results count]) {
      HGSScoredResult *scoredResult = [results objectAtIndex:0];
      QSBSourceTableResult *tableResult 
        = [scoredResult valueForKey:kQSBObjectTableResultAttributeKey];
      if (!result) {
        result = tableResult;
      }
      [resultsForCategory replacePointerAtIndex:idx withPointer:tableResult];
      ++idx;
    }
  }
  return result;
}

- (NSDictionary *)resultCountByCategory {
  QSBCategoryManager *categoryMgr = [QSBCategoryManager sharedManager];
  NSArray *categories = [categoryMgr categories];
  NSMutableDictionary *resultCountByCategory 
    = [NSMutableDictionary dictionaryWithCapacity:[categories count]];
  for (QSBCategory *category in categories) {
    HGSTypeFilter *typeFilter = [category typeFilter];
    NSUInteger count = [queryController_ resultCountForFilter:typeFilter];
    NSNumber *value = [NSNumber numberWithUnsignedInteger:count];
    [resultCountByCategory setObject:value forKey:category];
  }
  return resultCountByCategory;
}

- (void)setTokenizedQueryString:(HGSTokenizedString *)queryString {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBSearchControllerWillChangeQueryStringNotification
                    object:self];
  [self stopQuery];
  [tokenizedQueryString_ autorelease];
  tokenizedQueryString_ = [queryString retain];
  if ([tokenizedQueryString_ tokenizedLength] || parentSearchController_) {
    [self performQuery];
  } else {
    [topResults_ removeAllObjects];
    [self resetMoreResults];
    [lockedResults_ release];
    lockedResults_ = nil;
    [nc postNotificationName:kQSBSearchControllerDidUpdateResultsNotification
                      object:self];
  }
  [nc postNotificationName:kQSBSearchControllerDidChangeQueryStringNotification
                    object:self];
}

- (HGSTokenizedString *)tokenizedQueryString {
  return tokenizedQueryString_;
}

- (NSUInteger)maximumResultsToCollect {
  return totalResultDisplayCount_;
}

- (void)performQuery {
  [lockedResults_ release];
  lockedResults_ = nil;
  currentResultDisplayCount_ = (0.8 * [self maximumResultsToCollect]);

  if (tokenizedQueryString_ || results_) {

    HGSQueryFlags flags = 0;
    if ([self pushModifierFlags] & NSAlternateKeyMask) {
      flags |= eHGSQueryShowAlternatesFlag;
    }

    HGSQuery *query 
      = [[[HGSQuery alloc] initWithTokenizedString:tokenizedQueryString_
                                           results:results_
                                        queryFlags:flags]
                       autorelease];

    [self cancelAndReleaseQueryController];
    queryController_ = [[HGSQueryController alloc] initWithQuery:query];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(queryControllerWillStart:)
               name:kHGSQueryControllerWillStartNotification
             object:queryController_];
    [nc addObserver:self
           selector:@selector(queryControllerDidFinish:)
               name:kHGSQueryControllerDidFinishNotification
             object:queryController_];
    [nc addObserver:self 
           selector:@selector(queryControllerDidUpdateResults:) 
               name:kHGSQueryControllerDidUpdateResultsNotification 
             object:queryController_];

    // This became a separate call because some sources come back before
    // this call returns and queryController_ must be set first
    HGSAssert(!displayTimer_, nil);
    displayTimerStage_ = 0;
    displayTimer_
      = [NSTimer scheduledTimerWithTimeInterval:kQSBDisplayTimerStages[0]
                                         target:self
                                       selector:@selector(displayTimerElapsed:)
                                       userInfo:@"displayTimer"
                                        repeats:NO];    
    [queryController_ startQuery];
  }
}

- (void)stopQuery {
  if ([self isQueryInProcess]) {
    [displayTimer_ invalidate];
    displayTimer_ = nil;
    [self cancelAndReleaseQueryController];
    [self setQueryInProcess:NO];
  }
}

#pragma mark Notifications

- (void)queryControllerWillStart:(NSNotification *)notification { 
  [self setQueryInProcess:YES];
  [self setGatheringFinished:NO];
  resultsNeedUpdating_ = YES;
}

// Called when the last active query operation, and thus the query, has
// completed.  May be called even when there are more results that are
// possible, but the query has been stopped by the user or by the query
// reaching a time threshold.
- (void)queryControllerDidFinish:(NSNotification *)notification { 
  currentResultDisplayCount_ = [self maximumResultsToCollect];
  [self setGatheringFinished:YES];
  [self setQueryInProcess:NO];
  [self updateResults];
  [displayTimer_ invalidate];
  displayTimer_ = nil;
}

- (void)queryControllerDidUpdateResults:(NSNotification *)notification {
  resultsNeedUpdating_ = YES;
}

// called when enough time has elapsed that we want to display some results
// to the user.
- (void)displayTimerElapsed:(NSTimer*)timer {
  [self updateResults];
  ++displayTimerStage_;
  NSUInteger stages 
    = sizeof(kQSBDisplayTimerStages) / sizeof(kQSBDisplayTimerStages[0]);
  NSTimeInterval stage 
    = displayTimerStage_ >= stages ? 1.0 
                                   : kQSBDisplayTimerStages[displayTimerStage_];
  displayTimer_
    = [NSTimer scheduledTimerWithTimeInterval:stage
                                       target:self
                                     selector:@selector(displayTimerElapsed:)
                                     userInfo:@"displayTimer"
                                      repeats:NO];   
}

- (void)resultCountValueChanged:(GTMKeyValueChangeNotification *)notification {
  NSDictionary *change = [notification change];
  NSNumber *valueOfChange = [change valueForKey:NSKeyValueChangeNewKey];
  totalResultDisplayCount_ = [valueOfChange unsignedIntegerValue];
  [self performQuery];
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
