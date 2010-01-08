//
//  QSBSearchController.h
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

#import <Cocoa/Cocoa.h>
#import <Vermilion/Vermilion.h>

@class QSBMoreResultsViewController;
@class QSBTableResult;

// Interface between QSB and the web suggestor and the desktop query
// takes a query string and is responsible for turning it into results.
@interface QSBSearchController : NSObject {
 @private
  NSMutableArray *desktopResults_;
  NSArray *lockedResults_;
  NSString *queryString_;  // Current query string entered by user.
  HGSResultArray *results_;
  NSUInteger currentResultDisplayCount_;
  HGSQueryController *queryController_;
  QSBSearchController *parentSearchController_;
  NSArray *oldSuggestions_; // The last suggestions seen
  NSMutableDictionary *typeCategoryDict_;  // type->category conversion.

  // used to update the UI at various times through the life of the query
  NSTimer *displayTimer_;
  BOOL queryIsInProcess_;  // Yes while a query is under way.
  BOOL queryControllerFinished_;  // Yes if the results gathering has completed.
  NSUInteger pushModifierFlags_; // NSEvent Modifiers at pivot time
  NSUInteger totalResultDisplayCount_;
  HGSMixer *mixer_;
}

// Sets/Gets NSEvent Modifiers at pivot time
@property(nonatomic, assign) NSUInteger pushModifierFlags;
// Sets/Gets a context (pivot object) for the current query.
@property(nonatomic, retain) HGSResultArray *results;
// Sets/Gets the parent query from which we were spawned.
@property(nonatomic, retain) QSBSearchController *parentSearchController;
// Set/Gets in-process indication for query.  Bound to the progress
// indicator.
@property(nonatomic, readonly, assign) BOOL queryIsInProcess;

// Returns the top results
- (QSBTableResult *)topResultForIndex:(NSInteger)idx;
- (NSArray *)topResultsInRange:(NSRange)range;
- (NSUInteger)topResultCount;

- (NSDictionary *)rankedResultsByCategory;

// Changes and restarts the query.
- (void)setQueryString:(NSString *)queryString;

// Returns the current query
- (NSString *)queryString;

// Returns the maximum number of results to present.
- (NSUInteger)maximumResultsToCollect;

// Stop all source operations for this query.
- (void)stopQuery;

@end

// Notification sent out when results have been updated.
// Object is QSBSearchController.
extern NSString *const kQSBSearchControllerDidUpdateResultsNotification;

