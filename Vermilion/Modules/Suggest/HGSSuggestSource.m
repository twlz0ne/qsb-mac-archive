//
//  HGSSuggestSource.m
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

#import "HGSSuggestSource.h"

#import "GTMHTTPFetcher.h"
#import "GTMDefines.h"
#import "GTMGarbageCollection.h"
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "GTMNSDictionary+URLArguments.h"
#import "NSScanner+BSJSONAdditions.h"
#import "NSString+ReadableURL.h"

#if TARGET_OS_IPHONE
#import "GMOCompletionSourceNotifications.h"
#import "GMONavSuggestSource.h"
#import "GMONetworkIndicator.h"
#import "GMOUserPreferences.h"
#else
#import "QSBPreferences.h"
#endif

#if ENABLE_SUGGEST_SOURCE_SQLITE_CACHING
#import "HGSSQLiteBackedCache.h"
#endif  // ENABLE_SUGGEST_SOURCE_SQLITE_CACHING

static NSString* const kHGSGoogleSuggestBase = @"%@/complete/search?";

static NSTimeInterval const kHGSNetworkTimeout = 10.0f;

typedef enum {
  kHGSSuggestTypeSuggest = 0,
  kHGSSuggestTypeNavSuggest = 5
} HGSSuggestType;

@interface HGSSuggestSource (PrivateMethods)
// Initiate an HTTP request for Google Suggest(ions) with the given query.
- (void)startSuggestionsRequestForOperation:(HGSSearchOperation *)operation;
// Called when the suggestions were successfully fetched from the network.
- (void)suggestionsRequestCompleted:(NSArray *)suggestions
                       forOperation:(HGSSearchOperation *)operation;
// Called when the suggestions request failed.
- (void)suggestionsRequestFailed:(HGSSearchOperation *)operation;

// Parses data from an HTTP response (|responseData|), caches the parsed
// response as a plist and converts it into an array of HGSObject(s).
//
// Filtering of the results is also applied to the suggestions.
- (NSArray *)parseAndCacheResponseData:(NSData *)responseData
                             withQuery:(HGSQuery *)query;
// Returns suggestion results that are ready to be used in the UI. Performs
// the necessary filtering and normalization to the parse response data.
//
// |response| is expected to be a parse JSON response that consists of a
//            2 element NSArray, first element being the query and second
//            being an NSArray of the suggestions.
- (NSArray *)filteredSuggestionsWithResponse:(NSArray *)response
                                   withQuery:(HGSQuery *)query;

// Parses the |responseData| (expected to be a UTF-8 JSON string) into a
// Foundation-based NSArray representation suitable to be passed on to
// suggestionsWithResponse:withQuery:.
- (NSArray *)responseWithJSONData:(NSData *)responseData;
// Convert a parsed JSON response into HGSObject(s).
- (NSMutableArray *)suggestionsWithResponse:(NSArray *)response
                                  withQuery:(HGSQuery *)query;
// Language of suggestions
- (NSString *)suggestLanguage;
// Filtering suggestions
@end

@interface HGSSuggestSource (Filtering)
// Filters out suggestions that only add 1 or 2 characters to the query string.
// We expect that these are less useful to the users and add to the cluster.
// |results| will be modified by this method.
- (void)filterShortResults:(NSMutableArray *)results
                 withQueryString:(NSString *)query;

// Filter out duplicate Google suggest results. (Doesn't touch navsuggest).
- (void)filterDuplicateSuggests:(NSMutableArray*)results;

// Filters out suggestions that do not have the same prefix (case-insensitive).
- (void)filterResults:(NSMutableArray *)results
        withoutPrefix:(NSString *)prefix;

// Truncates the display name of the suggestions if they have a common prefix
// with |query|.
- (void)truncateDisplayNames:(NSMutableArray *)results
             withQueryString:(NSString *)query;

// Replaces URL-like results with a kHGSUTTypeWebPage suggestion.
- (void)replaceURLLikeResults:(NSMutableArray *)results;

// Removes all URL-like results.
- (void)filterWebPageResults:(NSMutableArray*)results;
@end

// Methods to deal with caching and abstracting the type of caching. Currently
// implemented a regular NSMutbaleDictionary and SQLite backed.
@interface HGSSuggestSource (Caching)
- (void)initializeCache;
// Cache a value by a key. It is expected that the key is not nil and
// the key is the query submitted.
//
// If using the SQLite cache backend, cacheValue should be a property-list-able
// object (NSArray, NSDictionary, NSString, NSNumber, NSData).
- (void)cacheValue:(id)cacheValue forKey:(NSString *)key;
// Called by cacheValue:forKey: on the main thread as to not confuse SQLite
// if we are using that for the cache backend.
- (void)cacheKeyValuePair:(NSArray *)keyValue;
// Returns the cached value of the key.
- (id)cachedValueForKey:(NSString *)key;
@end

// Methods to deal with the suggest fetching thread and the manipulation of the
// fetch queue.
@interface HGSSuggestSource (FetchQueue)
- (void)startSuggestionFetchingThread;
- (void)suggestionFetchingThread:(id)context;
- (HGSSearchOperation *)nextOperation;
- (void)addOperation:(HGSSearchOperation *)newOperation;
- (void)signalOperationCompletion;
@end

@implementation HGSSuggestSource
GTM_METHOD_CHECK(NSString, readableURLString);
GTM_METHOD_CHECK(NSScanner, scanJSONArray:);
GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

#if TARGET_OS_IPHONE
- (NSSet *)pivotableTypes {
  // iPhone pivots on everything
  return [NSSet setWithObject:@"*"];
}
#endif

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  int suggestCount = [prefs integerForKey:kQSBSuggestCountKey];
  int navSuggestCount = [prefs integerForKey:kQSBNavSuggestCountKey];
  
  // Don't show suggestions for queries under 3 letters
  if ([[query rawQueryString] length] < 3) {
    return NO;
  }
  if (suggestCount + navSuggestCount <= 0) {  
    return NO;
  }
  return YES;
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  NSString *suggestHost
    = [[[HGSModuleLoader sharedModuleLoader] delegate] suggestHost];
  NSString *baseURL = [NSString stringWithFormat:kHGSGoogleSuggestBase, suggestHost];
  self = [self initWithConfiguration:configuration
                            baseURL:baseURL];
  return self;
}

- (id)initWithConfiguration:(NSDictionary *)configuration
                    baseURL:(NSString*)baseURL {
  if (![configuration objectForKey:kHGSExtensionIconImagePathKey]) {
    NSMutableDictionary *newConfig = [configuration mutableCopy];
#if TARGET_OS_IPHONE
    NSString *iconName = @"web-nav.png";
#else
    NSString *iconName = @"blue-nav.icns";
#endif
    [newConfig setObject:iconName forKey:kHGSExtensionIconImagePathKey];
    configuration = newConfig;
  }
  if ((self = [super initWithConfiguration:configuration])) {
    suggestBaseUrl_ = [baseURL copy];
    operationQueue_ = [[NSMutableArray alloc] init];
    isReady_ = YES;
    continueRunning_ = YES;
#if TARGET_OS_IPHONE
    truncateSuggestions_ = YES;
#endif
    lastResult_ = nil;
    [self initializeCache];
    [self startSuggestionFetchingThread];
  }
  return self;
}

- (void)dealloc {
  continueRunning_ = NO;
  [suggestBaseUrl_ release];
  [operationQueue_ release];
  [lastResult_ release];
  [cache_ release];
  [super dealloc];
}
  
#pragma mark Caching

- (void)initializeCache {
#if ENABLE_SUGGEST_SOURCE_SQLITE_CACHING
  NSString* cachePath = [[GDSourceConfigProvider defaultConfig] suggestCacheDbPath];
  if (cachePath) {
    cache_ = [[HGSSQLiteBackedCache alloc] initWithPath:cachePath];
  }
#else
  cache_ = [[NSMutableDictionary alloc] init];  // Runtime cache only.
#endif  // ENABLE_SUGGEST_SOURCE_SQLITE_CACHING
}

- (void)cacheValue:(id)cacheValue forKey:(NSString *)key {
#if ENABLE_SUGGEST_SOURCE_SQLITE_CACHING
  if (cache_ && cacheValue && key) {
    [self performSelectorOnMainThread:@selector(cacheKeyValuePair:)
                           withObject:[NSArray arrayWithObjects:key, cacheValue, nil]
                        waitUntilDone:NO];
  }
#else
  [cache_ setValue:cacheValue forKey:key];
#endif  // ENABLE_SUGGEST_SOURCE_SQLITE_CACHING
}

- (void)cacheKeyValuePair:(NSArray *)keyValue {
  [cache_ setValue:[keyValue objectAtIndex:1] forKey:[keyValue objectAtIndex:0]];
}

- (id)cachedValueForKey:(NSString *)key {
  // TODO(altse): Move this to main thread like the cacheValue:forKey: since
  //              SQLite does not seem to be thread-safe.
  if (cache_) {
    id value = [cache_ valueForKey:key];
//    if (value && [value respondsToSelector:@selector(substringWithRange:)]) {
//      HGSLogDebug(@"SuggestCache[%@] = %@", key, [value substringWithRange:NSMakeRange(0, 20)]);
//    } else {
//      HGSLogDebug(@"SuggestCache[%@] = %@", key, value);
//    }
    return value;
  } else {
    return nil;
  }
}

#pragma mark Suggestion Fetching Thread

- (void)startSuggestionFetchingThread {
  isReady_ = YES;
  [self performSelectorInBackground:@selector(suggestionFetchingThread:)
                         withObject:nil];
}

// This is a long running thread that will continiously service search
// operation requests in the |operationQueue_|.
- (void)suggestionFetchingThread:(id)context {
  BOOL isRunning = YES;
  const NSTimeInterval pollingInterval = 1.0;
  const NSTimeInterval autoreleaseInterval = 300.0;
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [NSTimer scheduledTimerWithTimeInterval:pollingInterval
                                   target:self
                                 selector:@selector(processQueue:)
                                 userInfo:nil
                                 repeats:YES];

  do {
    NSAutoreleasePool *iterPool = [[NSAutoreleasePool alloc] init];
    isRunning = [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate dateWithTimeIntervalSinceNow:autoreleaseInterval]];
    [iterPool release];
  } while (isRunning && continueRunning_);

  [pool release];
}

- (void)stopFetching {
  continueRunning_ = NO;
}

-(void)processQueue:(id)sender {
  if (isReady_) {
    HGSSearchOperation *nextOperation = [[self nextOperation] retain];
    if (nextOperation) {
      isReady_ = NO;
      [self startSuggestionsRequestForOperation:nextOperation];  // retains nextOperation
      [nextOperation release];
    }
  }
}

// The |operationQueue| is checked for the last operation to run, and all the
// subsequent operations are discarded.
- (HGSSearchOperation *)nextOperation {
  @synchronized (operationQueue_) {
    if ([operationQueue_ count] > 0) {
      HGSSearchOperation *nextOperation = [[operationQueue_ lastObject] retain];
      for (NSUInteger i = 0; i < [operationQueue_ count] - 1; i++) {
        [[operationQueue_ objectAtIndex:i] finishQuery];
      }
      [operationQueue_ removeAllObjects];
      return [nextOperation autorelease];
    }
  }
  return nil;
}

// Adds an operation to the network operations queue.
- (void)addOperation:(HGSSearchOperation *)newOperation {
  @synchronized (operationQueue_) {
    [operationQueue_ addObject:newOperation];
  }
}

// Called to signal a network operation has completed and the instance is ready
// to start another request if there is one outstanding.
- (void)signalOperationCompletion {
  // TODO(altse): CFRunLoopStop?
#if TARGET_OS_IPHONE
  [[GMONetworkIndicator sharedNetworkIndicator] popEvent];
#endif  // TARGET_OS_IPHONE
  isReady_ = YES;
}

#pragma mark Suggestion Fetching

- (NSURL *)suggestUrl:(HGSSearchOperation *)operation { 
  // use the raw query so the server can try to parse it.
  NSString *escapedString = 
    [[[operation query] rawQueryString] gtm_stringByEscapingForURLArgument];

  NSMutableDictionary *argumentDictionary =
    [NSMutableDictionary dictionaryWithObjectsAndKeys:
#if TARGET_OS_IPHONE
    @"iphoneapp", @"client", 
#else   
     @"qsb-mac", @"client",
#endif
    @"t",@"hjson", // Horizontal JSON. http://wiki/Main/GoogleSuggestServerAPI
    @"t", @"types", // Add type of suggest (SuggestResults::SuggestType)
    [self suggestLanguage], @"hl", // Language (eg. en)
    escapedString, @"q", // Partial query.
    nil]; 
  
  // Enable spelling suggestions.
  [argumentDictionary setObject:@"t" forKey:@"spell"];
  
  // Enable calculator suggestions.
  //[argumentDictionary setObject:@"t" forKey:@"calc"];
  
  // Enable ads suggestions.
  //[argumentDictionary setObject:@"t" forKey:@"ads"];
  
  // Enable news suggestions.
  //[argumentDictionary setObject:@"t" forKey:@"news"];
  
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  NSNumber *suggestCount = [prefs objectForKey:kQSBSuggestCountKey];
  NSNumber *navSuggestCount = [prefs objectForKey:kQSBNavSuggestCountKey];
  
  // Enable calculator suggestions.
  
  if ([suggestCount boolValue]) {
    // Allow the default number of suggestions to come back
    // We truncate these later
     [argumentDictionary setObject:[NSNumber numberWithInt:5]
                            forKey:@"complete"];
  }  else {
    [argumentDictionary setObject:@"f" forKey:@"complete"];
  }
  
  if ([navSuggestCount boolValue]) {
    [argumentDictionary setObject:navSuggestCount
                           forKey:@"nav"];
  }
  
  NSString *suggestUrlString = [suggestBaseUrl_ stringByAppendingString:
                                [argumentDictionary gtm_httpArgumentsString]];
  
  return [NSURL URLWithString:suggestUrlString];
}

- (void)startSuggestionsRequestForOperation:(HGSSearchOperation *)operation {
  // TODO(altse): On the iPhone, NSURL uses SQLite cache and that is not
  //              thread-safe. So we disable local HTTP caching.
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self suggestUrl:operation]
                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                     timeoutInterval:kHGSNetworkTimeout];
  [request setHTTPShouldHandleCookies:NO];

  // Start the http fetch.
  GTMHTTPFetcher *fetcher = [GTMHTTPFetcher httpFetcherWithRequest:request];
  [fetcher setUserData:operation];
  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(httpFetcher:finishedWithData:)
                  didFailSelector:@selector(httpFetcher:didFail:)];

#if TARGET_OS_IPHONE
  [[GMONetworkIndicator sharedNetworkIndicator] pushEvent];
#endif  // TARGET_OS_IPHONE
}

- (void)httpFetcher:(GTMHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  HGSSearchOperation *fetchedOperation = (HGSSearchOperation *)[[[fetcher userData] retain] autorelease];
  [fetcher setUserData:nil];  // Make sure this operation isn't retained.

  // Parse the result.
  HGSQuery *query = [fetchedOperation query];
  NSArray *suggestions = [self parseAndCacheResponseData:retrievedData withQuery:query];
  if (suggestions) {
    [self suggestionsRequestCompleted:suggestions
                         forOperation:fetchedOperation];
  } else {
    [self suggestionsRequestFailed:fetchedOperation];
  }

  [self signalOperationCompletion];
}

- (void)httpFetcher:(GTMHTTPFetcher *)fetcher
            didFail:(NSError *)error {
  HGSLog(@"httpFetcher failed: %@ %@", [error description], [[fetcher request] URL]);
  [self signalOperationCompletion];

  HGSSearchOperation *fetchedOperation = (HGSSearchOperation *)[fetcher userData];
  [self suggestionsRequestFailed:fetchedOperation];
}

#pragma mark -

- (void)suggestionsRequestCompleted:(NSArray *)suggestions
                       forOperation:(HGSSearchOperation *)operation {
  [operation performSelectorOnMainThread:@selector(setResults:)
                              withObject:suggestions
                           waitUntilDone:YES];
  [operation performSelectorOnMainThread:@selector(finishQuery)
                              withObject:nil
                           waitUntilDone:YES];

  // Cache the last result.
  [self setLastResult:suggestions];
}

- (void)suggestionsRequestFailed:(HGSSearchOperation *)operation {
  [operation performSelectorOnMainThread:@selector(finishQuery)
                              withObject:nil
                           waitUntilDone:YES];
}

#pragma mark Response Data Manipulation

- (NSArray *)parseAndCacheResponseData:(NSData *)responseData
                             withQuery:(HGSQuery *)query {
  NSArray *response = [self responseWithJSONData:responseData];
  // Add parse response to the cache.
  if ([response count] > 0) {
    [self cacheValue:response forKey:[query rawQueryString]];
  }
  return [self filteredSuggestionsWithResponse:response withQuery:query];
}

- (NSArray *)filteredSuggestionsWithResponse:(NSArray *)response
                                   withQuery:(HGSQuery *)query {
  // Convert suggestions into HGSObjects.
  NSMutableArray *suggestions = [self suggestionsWithResponse:response
                                                      withQuery:query];
  
  // TODO(alcor): Don't filter for now, we need to decide whether to keep these
  // at all or to collapse them with like navsuggests
  // [self replaceURLLikeResults:suggestions];
  // [self filterWebPageResults:suggestions];
  
  NSString *queryString = [query rawQueryString];
  [self filterShortResults:suggestions withQueryString:queryString];
  if (truncateSuggestions_) {
    [self truncateDisplayNames:suggestions withQueryString:queryString];
  }

  [self filterDuplicateSuggests:suggestions];

  return suggestions;
}

// Parses the JSON response into Foundation objects.
- (NSArray *)responseWithJSONData:(NSData *)responseData {
  // Parse response.
  NSString *jsonResponse = [[NSString alloc] initWithData:responseData
                                                  encoding:NSUTF8StringEncoding];
  NSScanner *jsonScanner = [[NSScanner alloc] initWithString:jsonResponse];
  NSArray *response = nil;
  [jsonScanner scanJSONArray:&response];
  [jsonResponse release];
  [jsonScanner release];

  if (!response) {
    HGSLog(@"Unable to parse JSON");
    return [NSArray array];
  }

  if ([response count] < 2) {
    HGSLog(@"JSON Response does not match expected format.");
    return [NSArray array];
  }
  return response;
}

- (NSMutableArray *)suggestionsWithResponse:(NSArray *)response
                                  withQuery:(HGSQuery *)query {
  if (!response || [response count] < 2) {
    return [NSMutableArray array];
  }

  NSMutableArray *suggestions = [[[NSMutableArray alloc] initWithCapacity:[[response objectAtIndex:1] count]] autorelease];
  NSEnumerator *suggestionsEnum = [[response objectAtIndex:1] objectEnumerator];
  NSArray *suggestionItem = nil;

  while ((suggestionItem = [suggestionsEnum nextObject])) {
    if ([suggestionItem isKindOfClass:[NSArray class]] &&
        [suggestionItem count] > 0 &&
        [suggestionItem objectAtIndex:0]) {

      // expects > Google Suggest: suggestion NavSuggest: URL
      id suggestionString = [suggestionItem objectAtIndex:0];
      // expects > Google Suggest: 1,600,000 results, NavSuggest: Website Title.
      id suggestionLabel = [suggestionItem objectAtIndex:1];
      // expects > Google Suggest: 0 NavSuggest: 5
      NSInteger suggestionType = [[suggestionItem objectAtIndex:2] intValue];

      if ([suggestionString respondsToSelector:@selector(stringValue)]) {
        suggestionString = [suggestionString stringValue];
      } else if (![suggestionString isKindOfClass:[NSString class]]) {
        continue;
      }

      if (suggestionType == kHGSSuggestTypeSuggest) {
        NSString *escapedSuggestion = [suggestionString gtm_stringByEscapingForURLArgument];
        NSURL *completionId = [NSURL URLWithString:[NSString stringWithFormat:@"googlesuggest://%@", escapedSuggestion]];
        // TODO(altse): JSON response includes the type of the suggestion, we
        //              should import the enums.
        //              if (row[2] == 'calc') HGSCompletionTypeCalc;
        //              if (row[2] is integer) HGSCompletionTypeSuggest;
        NSMutableDictionary *attributes
          = [NSMutableDictionary dictionaryWithObjectsAndKeys:
             suggestionString, kHGSObjectAttributeStringValueKey,
             [self icon], kHGSObjectAttributeIconKey,
             nil];
        if ([suggestionItem count] > 3) {
          id isDidYouMean = [suggestionItem objectAtIndex:3];
          if ([isDidYouMean isKindOfClass:[NSString class]] &&
              [isDidYouMean isEqualToString:@"dym"]) {  // Did you mean?
            [attributes setObject:[NSNumber numberWithBool:YES]
                           forKey:kHGSObjectAttributeIsCorrectionKey];
          }
        }
        
        HGSObject* suggestion = [HGSObject objectWithIdentifier:completionId
                                                           name:suggestionString
                                                           type:kHGSTypeGoogleSuggest
                                                         source:self
                                                     attributes:attributes];
        [suggestions addObject:suggestion];
      } else if (suggestionType == kHGSSuggestTypeNavSuggest) {
        NSString *title = @"";
        if ([suggestionLabel respondsToSelector:@selector(stringValue)]) {
          title = [suggestionLabel stringValue];
        } else if ([suggestionLabel isKindOfClass:[NSString class]]) {
          title = suggestionLabel;
        }

        // Only create a navsuggest if it looks and smells like a URL.
        if ([title length] > 1 &&
            [suggestionString isKindOfClass:[NSString class]] &&
            [suggestionString hasPrefix:@"http://"]) {

          NSURL *url = [NSURL URLWithString:suggestionString];
          NSDictionary *attributes 
            = [NSDictionary dictionaryWithObjectsAndKeys:
               url, kHGSObjectAttributeURIKey,
               [NSNumber numberWithBool:YES], kHGSObjectAttributeAllowSiteSearchKey,
               [NSNumber numberWithBool:YES], kHGSObjectAttributeIsSyntheticKey,
               [url absoluteString], kHGSObjectAttributeSourceURLKey,
               nil];
          HGSObject *navsuggestion = [HGSObject objectWithIdentifier:url
                                                                name:title
                                                                type:kHGSTypeGoogleNavSuggest
                                                              source:self
                                                          attributes:attributes];
          [suggestions addObject:navsuggestion];
        }
      }
    }
  }

  return suggestions;
}

- (id)provideValueForKey:(NSString *)key result:(HGSObject *)result {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeIconKey] 
      || [key isEqualToString:kHGSObjectAttributeImmediateIconKey]) {
    value = [self icon];
  }
  return value;
}
//
- (void)filterWebPageResults:(NSMutableArray*)results {
  NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
  NSEnumerator *enumerator = [results objectEnumerator];
  HGSObject *result;
  for (NSUInteger i = 0; (result = [enumerator nextObject]); ++i) {
    if ([result conformsToType:kHGSTypeWebpage]) {
      [toRemove addIndex:i];
    }
  }
  [results removeObjectsAtIndexes:toRemove];
}

// Replaces suggestions that look like URLs
- (void)replaceURLLikeResults:(NSMutableArray *)results {
  for (NSUInteger i = 0; i < [results count]; i++) {
    HGSObject *result = [results objectAtIndex:i];
    if (![result isOfType:kHGSTypeGoogleSuggest])
      continue;

    NSString *suggestion = [result valueForKey:kHGSObjectAttributeStringValueKey];
    // TODO(altse): Check for other TLDs too.
    if ([suggestion hasSuffix:@".com"] ||
        [suggestion hasPrefix:@"www."]) {
      NSString *normalized = [suggestion stringByReplacingOccurrencesOfString:@" "
                                                                   withString:@""];
      NSURL *url = [[[NSURL alloc] initWithScheme:@"http"
                                             host:normalized
                                             path:@"/"] autorelease];
      NSDictionary *attributes
        = [NSDictionary dictionaryWithObjectsAndKeys:
           url, kHGSObjectAttributeURIKey,
           suggestion, kHGSObjectAttributeStringValueKey,
           nil];
      HGSObject *urlResult = [HGSObject objectWithIdentifier:url
                                                        name:suggestion
                                                        type:kHGSTypeWebpage
                                                      source:self
                                                  attributes:attributes];
      [results replaceObjectAtIndex:i withObject:urlResult];
    }
  }
}

// Remove suggestions that are too short.
- (void)filterShortResults:(NSMutableArray *)results withQueryString:(NSString *)query {
  NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
  NSUInteger queryLength = [query length];
  NSUInteger lengthThreshold = 2;
  NSEnumerator *enumerator = [results objectEnumerator];
  HGSObject *result;
  for (NSUInteger i = 0; (result = [enumerator nextObject]); ++i) {
    if ([result isOfType:kHGSTypeGoogleSuggest] &&
        ![result valueForKey:kHGSObjectAttributeIsCorrectionKey] &&
        [[result valueForKey:kHGSObjectAttributeStringValueKey] length] < queryLength + lengthThreshold) {
      [toRemove addIndex:i];
    }
  }
  [results removeObjectsAtIndexes:toRemove];
}

// Truncate the display name for suggestions that have a common prefix with
// the query.
- (void)truncateDisplayNames:(NSMutableArray *)results withQueryString:(NSString *)query {
  NSUInteger queryLength = [query length];
  if (queryLength < 4) {
    return;
  }

  //NSString *ellipsisCharacter = @"+";
  NSString *ellipsisCharacter = [NSString stringWithFormat:@"%C",0x2025];

  // Work out the word boundaries.
  // TODO(alcor): this probably need to use a real tokenizer to be i18n happy
  BOOL onlyTruncateOnWordBreak = YES;
  NSCharacterSet *breakerSet = [NSCharacterSet characterSetWithCharactersInString:@" .-"];
  NSString *ellipsisableString = nil;
  NSInteger lastSpace = NSNotFound;
  if (onlyTruncateOnWordBreak) {
    lastSpace = [query rangeOfCharacterFromSet:breakerSet
                                       options:NSBackwardsSearch].location;
    if (lastSpace != NSNotFound) {
      ellipsisableString = [query substringToIndex:lastSpace];
    }
  }

  NSEnumerator *enumerator = [results objectEnumerator];
  HGSObject *result;
  while ((result = [enumerator nextObject])) {
    // Only truncate suggestions
    if (![result isOfType:kHGSTypeGoogleSuggest])
      continue;

    NSString *suggestion = [result valueForKey:kHGSObjectAttributeStringValueKey];
    if ((queryLength < [suggestion length]) &&
        [[suggestion lowercaseString] hasPrefix:[query lowercaseString]]) {
      BOOL nextCharacterIsBreak = [breakerSet characterIsMember:[suggestion characterAtIndex:queryLength]];
      NSString *searchString = query;
      if (onlyTruncateOnWordBreak && !nextCharacterIsBreak) {
        searchString = ellipsisableString;
      }

      NSRange searchRange = NSMakeRange(0, MIN([suggestion length], queryLength));

      if (!searchString) continue;

      suggestion = [suggestion stringByReplacingOccurrencesOfString:searchString
                                                         withString:ellipsisCharacter
                                                            options:NSCaseInsensitiveSearch | NSAnchoredSearch
                                                              range:searchRange];
      [result setValue:suggestion forKey:kHGSObjectAttributeNameKey];
    }
  }
}

// Filters out all the results that do not have suggestions with the same
// prefix.
- (void)filterResults:(NSMutableArray *)results withoutPrefix:(NSString *)prefix {
  NSMutableIndexSet *toRemove = [NSMutableIndexSet indexSet];
  NSEnumerator *enumerator = [results objectEnumerator];
  HGSObject *result;
  for (NSUInteger i = 0; (result = [enumerator nextObject]); ++i) {
    if (([result isOfType:kHGSTypeGoogleNavSuggest]
         || [result isOfType:kHGSTypeGoogleSuggest])
        && ![[result valueForKey:kHGSObjectAttributeStringValueKey] hasPrefix:prefix]) {
      [toRemove addIndex:i];
    }
  }
  [results removeObjectsAtIndexes:toRemove];
}

// Filter out duplicates
- (void)filterDuplicateSuggests:(NSMutableArray*)results {
  NSMutableSet* seenLabels = [NSMutableSet set];
  NSMutableIndexSet* toRemove = [NSMutableIndexSet indexSet];
  NSEnumerator *enumerator = [results objectEnumerator];
  HGSObject *result;
  for (NSUInteger i = 0; (result = [enumerator nextObject]); ++i) {
    if ([result isOfType:kHGSTypeGoogleSuggest]) {
      if ([seenLabels containsObject:[result valueForKey:kHGSObjectAttributeStringValueKey]]) {
        [toRemove addIndex:i];
      } else {
        [seenLabels addObject:[result valueForKey:kHGSObjectAttributeStringValueKey]];
      }
    }
  }
  [results removeObjectsAtIndexes:toRemove];
}

- (void)setLastResult:(NSArray *)lastResult {
  [lastResult_ autorelease];
  lastResult_ = [lastResult copy];
}

- (NSString *)suggestLanguage {
  NSString *suggestedLanguage = nil;
  suggestedLanguage = [[[HGSModuleLoader sharedModuleLoader] delegate] suggestLanguage];
  if (!suggestedLanguage) {
    // TODO(altse): Should this be "en" or "en_US" ? Right now it is just "en"
    suggestedLanguage = @"en";  // Default, just in case.
  }
  return suggestedLanguage;
}

#pragma mark HGSCallSearchSource Implementation

- (BOOL)isSearchConcurrent {
  return YES;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  HGSQuery *query = [operation query];
  _GTMDevAssert([operation isConcurrent],
                @"Implementation expects the operation to be set to concurrent.");
  NSString *queryTerm = [query rawQueryString];

#if TARGET_OS_IPHONE
  // iPhone lets more in during isValidSourceForQuery:
  if ([queryTerm length] == 0) {
    [operation setResults:nil];
    [operation finishQuery];
    return;
  }
#endif

  // Return a result from the cache if it exists.
  NSArray *cachedResponse = [self cachedValueForKey:queryTerm];
  if (cachedResponse) {
    NSArray *suggestions = [self filteredSuggestionsWithResponse:cachedResponse
                                                       withQuery:query];
    if ([suggestions count] > 0) {
      [operation setResults:suggestions];
      [operation finishQuery];
      [self setLastResult:suggestions];
      return;
    }
  }

#if TARGET_OS_IPHONE
  // Latency hiding by synthetically giving results based on our previous
  // real result. Uses the last "fetched" result and gives out all the  ones
  // with a matching prefix.
  if (lastResult_) {
    NSMutableArray *suggestions = [[lastResult_ mutableCopy] autorelease];
    [self filterResults:suggestions withoutPrefix:queryTerm];
    [self filterShortResults:suggestions withQueryString:queryTerm];
    if (truncateSuggestions_) {
      [self truncateDisplayNames:suggestions withQueryString:queryTerm];
    }
    if ([suggestions count] > 0) {
      [operation setResults:suggestions];
    }
  }
#endif
    
  [self addOperation:operation];
}

#pragma mark Clearing Cache

- (void)resetHistoryAndCache {
  if (cache_ && [cache_ respondsToSelector:@selector(removeAllObjects)]) {
    [cache_ removeAllObjects];
  }
}

@end
