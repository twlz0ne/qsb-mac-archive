//
//  GoogleCalendarsSource.m
//
//  Copyright (c) 2010 Google Inc. All rights reserved.
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

#import <Vermilion/Vermilion.h>
#import <GData/GData.h>
#import <GTM/GTMNSEnumerator+Filter.h>
#import <GTM/GTMDebugThreadValidation.h>
#import "GoogleAccountsConstants.h"
#import "HGSKeychainItem.h"
#import "QSBHGSResultAttributeKeys.h"

static NSString *const kGoogleCalendarIDKey = @"GoogleCalendarIDKey";
static NSString *const kGoogleCalendarEntryKey = @"GoogleCalendarEntryKey";
static NSString *const kGoogleCalendarURLKey = @"GoogleCalendarURLKey";
static NSString *const kGoogleCalendarEventStartTimeKey
  = @"GoogleCalendarEventStartTimeKey";
static NSString *const kGoogleCalendarEventEndTimeKey
  = @"GoogleCalendarEventEndTimeKey";

// This is a key for the fetch type that we add to the userInfo of NSErrors
// when errors occur in fetches.
static NSString *const kGoogleCalendarFetchTypeErrorKey 
  = @"GoogleCalendarFetchType";

static const NSTimeInterval kRefreshSeconds = 300.0;  // 5 minutes.
static const NSTimeInterval kErrorReportingInterval = 3600.0;  // 1 hour
static const NSTimeInterval kTwoYearInterval = 365.0 * 2.0 * 24.0 * 60.0 * 60.0;


@interface GoogleCalendarsSource : HGSMemorySearchSource <HGSAccountClientProtocol> {
 @private
  GDataServiceGoogleCalendar *service_;
  // We use activeTickets_ as a form of an event queue between threads.
  // Once it is empty the indexing thread will stop.
  // Be careful to synchronize when referencing it.
  NSMutableSet *activeTickets_;
  __weak NSTimer *updateTimer_;
  HGSAccount *account_;
  NSTimeInterval previousErrorReportingTime_;
  NSImage *calendarIcon_;
  NSImage *eventIcon_;
  HGSInvocationOperation *indexOp_;
  NSDateFormatter *shortDateShortTimeFormatter_;
  NSDateFormatter *noDateShortTimeFormatter_;
  NSDateFormatter *shortDateNoTimeFormatter_;
  NSDateFormatter *dayOfWeekFormatter_;
}

// Used to schedule refreshes of the calendar cache.
- (void)setUpPeriodicRefresh;

// Bottleneck function for kicking off a calendar fetch or refresh.
- (void)startAsyncCalendarsListFetch;

// Call this function whenever all calendar fetches should be shut down and
// the service reset.
- (void)cancelAllTickets;

// Indexing function for each calendar associated with the account.
- (void)indexCalendar:(GDataEntryCalendar *)calendarEntry;

// Indexing function for each event associated with a calendar.
- (void)indexEvent:(GDataEntryCalendarEvent *)eventEntry
      withCalendar:(GDataEntryCalendar *)calendarEntry;

// Make a nice snippet string giving times and locations for the event.
- (NSString *)snippetForEvent:(GDataEntryCalendarEvent *)eventEntry
                    startTime:(NSDate *)startTime
                      endTime:(NSDate *)endTime
                  weekdayName:(NSString *)weekdayName
                       allDay:(BOOL)allDay;

// Compose an URL string which can be used to open the account's
// calendar view in a browser.
- (NSString *)accountCalendarURLString;

// Utility function for reporting fetch errors.
- (void)reportError:(NSError *)error;

@end


@interface GDataDateTime (GoogleCalendarsSource)

// Utility function to make a GDataDateTime object for sometime today
+ (GDataDateTime *)dateTimeForTodayAtHour:(int)hour
                                   minute:(int)minute
                                   second:(int)second;

@end

@interface NSError (GoogleCalendarsSource)

// Create a new error by adding a fetch type to an existing errors userInfo.
- (NSError *)gcs_errorByAddingFetchType:(NSString *)fetchType;

@end


@interface NSDate (GoogleCalendarsSource)

// Return a date representing early this morning as of midnight.
+ (NSDate *)gcs_startOfToday;

// Return a date for |days| from today (preserving the time).
- (NSDate *)gcs_addDays:(NSInteger)days;

// Return YES if the date occurs on or after |otherTime| (where the time is
// significant).
- (BOOL)gcs_isAtOrAfter:(NSDate *)otherTime;

// Return the weekday name for the date if it is within seven days, otherwise
// return nil.
- (NSString *)gcs_weekdayName;

// Return 'today', 'tomorrow', or a weekday name for the date if it
// is within seven days, otherwise return nil.
- (NSString *)gcs_todayOrTomorrow;

@end


@implementation GoogleCalendarsSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Keep track of active tickets so we can cancel them if necessary.
    activeTickets_ = [[NSMutableSet alloc] init];
    account_ = [[configuration objectForKey:kHGSExtensionAccountKey] retain];
    if (account_) {
      // Get calendarEntry and event metadata now, and schedule a timer to
      // check every so often to see if it needs to be updated.
      [self startAsyncCalendarsListFetch];
      [self setUpPeriodicRefresh];
      
      // Watch for credential changes.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(loginCredentialsChanged:)
                 name:kHGSAccountDidChangeNotification
               object:account_];
      
      // Cache the Google Calendar icon
      calendarIcon_ = [[self imageNamed:@"gcalendar"] retain];
      HGSCheckDebug(calendarIcon_, nil);
      eventIcon_ = [[self imageNamed:@"gcalendarevent"] retain];
      HGSCheckDebug(eventIcon_, nil);
      
      // Creating NSDateFormatters is expensive, so we cache these ones.
      shortDateShortTimeFormatter_ = [[NSDateFormatter alloc] init];
      [shortDateShortTimeFormatter_ setDateStyle:NSDateFormatterShortStyle];
      [shortDateShortTimeFormatter_ setTimeStyle:NSDateFormatterShortStyle];
      
      noDateShortTimeFormatter_ = [[NSDateFormatter alloc] init];
      [noDateShortTimeFormatter_ setDateStyle:NSDateFormatterNoStyle];
      [noDateShortTimeFormatter_ setTimeStyle:NSDateFormatterShortStyle];
      
      shortDateNoTimeFormatter_ = [[NSDateFormatter alloc] init];
      [shortDateNoTimeFormatter_ setDateStyle:NSDateFormatterShortStyle];
      [shortDateNoTimeFormatter_ setTimeStyle:NSDateFormatterNoStyle];
    } else {
      HGSLogDebug(@"Missing account identifier for GoogleCalendarsSource '%@'",
                  [self identifier]);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [self cancelAllTickets];
  [shortDateShortTimeFormatter_ release];
  [noDateShortTimeFormatter_ release];
  [shortDateNoTimeFormatter_ release];
  [activeTickets_ release];
  [service_ release];
  [updateTimer_ invalidate];
  [account_ release];
  [calendarIcon_ release];
  [eventIcon_ release];
  [super dealloc];
}

- (void)cancelAllTickets {
  @synchronized (self) {
    [activeTickets_ makeObjectsPerformSelector:@selector(cancelTicket)];
    [activeTickets_ removeAllObjects];
  }
  [service_ release];
  service_ = nil;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  // If we're pivoting on an calendar then we can provide
  // a list of the events in that calendar as results.
  if (!isValid) {
    HGSResult *pivotObject = [query pivotObject];
    isValid = ([pivotObject conformsToType:kHGSTypeWebCalendar]);
  }
  return isValid;
}

- (HGSResult *)preFilterResult:(HGSResult *)result 
               matchesForQuery:(HGSQuery*)query
                  pivotObjects:(HGSResultArray *)pivotObjects {
  // Remove events that aren't from this calendar.
  HGSAssert([pivotObjects count] <= 1, @"%@", pivotObjects);
  HGSResult *pivotObject = [pivotObjects objectAtIndex:0];
  if ([pivotObject conformsToType:kHGSTypeWebCalendar]) {
    if ([result conformsToType:kHGSTypeWebCalendarEvent]) {
      NSString *eventCalendarID = [result valueForKey:kGoogleCalendarIDKey];
      NSString *calendarID = [pivotObject valueForKey:kGoogleCalendarIDKey];
      if (![eventCalendarID isEqualToString:calendarID]) {
        result = nil;
      }
    } else {
      result = nil;
    }
  }
  return result;
}

- (HGSScoredResult *)postFilterScoredResult:(HGSScoredResult *)result 
                            matchesForQuery:(HGSQuery *)query
                               pivotObjects:(HGSResultArray *)pivotObjects {
  // If we're pivoting on the calendar then score the result based on its
  // proximity to 'now'.
  HGSAssert([pivotObjects count] <= 1, @"%@", pivotObjects);
  HGSResult *pivotObject = [pivotObjects objectAtIndex:0];
  if ([pivotObject conformsToType:kHGSTypeWebCalendar]
      && [result conformsToType:kHGSTypeWebCalendarEvent]) {
    // We're pivoted but it's safe to assume that we're dealing with the
    // calendar associated with this event so proceed.
    CGFloat score = HGSCalibratedScore(kHGSCalibratedStrongScore);
    result = [HGSScoredResult resultWithResult:result
                                       score:score
                                  flagsToSet:eHGSSpecialUIRankFlag
                                flagsToClear:0
                                 matchedTerm:[result matchedTerm]
                              matchedIndexes:[result matchedIndexes]];
  }
  return result;
}

- (void)setUpPeriodicRefresh {
  [updateTimer_ invalidate];
  // We add a minutes worth of random jitter.
  NSTimeInterval jitter = arc4random() / (LONG_MAX / (NSTimeInterval)60.0);
  updateTimer_
    = [NSTimer scheduledTimerWithTimeInterval:kRefreshSeconds + jitter
                                       target:self
                                     selector:@selector(refreshCalendars:)
                                     userInfo:nil
                                      repeats:NO];
}

- (void)refreshCalendars:(NSTimer*)timer {
  updateTimer_ = nil;
  [self startAsyncCalendarsListFetch];
  [self setUpPeriodicRefresh];
}

- (void)loginCredentialsChanged:(NSNotification *)notification {
  HGSAssert([notification object] == account_, 
            @"Notification from unexpected account!");
  [self cancelAllTickets];
  // If the login changes, we should update immediately, and make sure the
  // periodic refresh is enabled (it would have been shut down if the previous
  // credentials were incorrect).
  [self startAsyncCalendarsListFetch];
  [self setUpPeriodicRefresh];
}

- (NSString *)accountCalendarURLString {
  // Determine if we are using a hosted account by looking at the name of the
  // account class -- do this so that we don't have to pull in
  // GoogleAccount.h.
  // The ultimate URL will be one of either:
  //   http://www.google.com/calendar/
  //   http://www.google.com/calendar/hosted/DOMAIN.COM/
  NSString *calendarURLString = @"http://www.google.com/calendar/";
  NSString *accountClass = [account_ className];
  if ([accountClass isEqualToString:kGoogleAppsAccountClassName]) {
    NSString *accountDomain = [account_ userName];
    NSRange domainRange = [accountDomain rangeOfString:@"@"];
    if (domainRange.location != NSNotFound) {
      accountDomain
        = [accountDomain substringFromIndex:domainRange.location + 1];
      calendarURLString
        = [calendarURLString stringByAppendingFormat:@"hosted/%@/",
           accountDomain];
    } else {
      HGSLog(@"Expected to find domain in user account '%@'.", accountDomain);
    }
  }
  return calendarURLString;
}

#pragma mark -
#pragma mark Calendar Fetching

- (void)startAsyncCalendarsListFetch {
  if (!service_) {
    HGSKeychainItem* keychainItem 
      = [HGSKeychainItem keychainItemForService:[account_ identifier]
                                       username:nil];
    NSString *username = [keychainItem username];
    NSString *password = [keychainItem password];
    if ([username length]) {
      service_ = [[GDataServiceGoogleCalendar alloc] init];
      [service_ setUserAgent:@"google-qsb-1.0"];
      // If there is no password then we will only fetch public albums.
      if ([password length]) {
        [service_ setUserCredentialsWithUsername:username
                                        password:password];
      }
      [service_ setServiceShouldFollowNextLinks:YES];
      [service_ setIsServiceRetryEnabled:YES];
    } else {
      [updateTimer_ invalidate];
      updateTimer_ = nil;
      return;
    }
  }
  @synchronized (self) {
    if ([activeTickets_ count] == 0) {
      HGSOperationQueue *opQueue = [HGSOperationQueue sharedOperationQueue];
      HGSInvocationOperation *op 
        = [HGSInvocationOperation memoryInvocationOperationWithTarget:self 
                                                             selector:@selector(asyncCalendarListFetchOperation:) 
                                                               object:service_];
      [opQueue addOperation:op];
    }
  }
}

- (void)asyncCalendarListFetchOperation:(GDataServiceGoogleCalendar*)service {
  GDataServiceTicket *calendarTicket
    = [service fetchFeedWithURL:[NSURL URLWithString:
                                 kGDataGoogleCalendarDefaultOwnCalendarsFeed]
                       delegate:self
              didFinishSelector:@selector(calendarFeedTicket:
                                          finishedWithFeed:
                                          error:)];
  @synchronized (self) {
    [activeTickets_ addObject:calendarTicket];
  }
  while (YES) {
    NSDate *date = [[NSDate alloc] initWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode 
                             beforeDate:date];
    [date release];
    @synchronized (self) {
      if ([activeTickets_ count] == 0) {
        break;
      }
    }
  }
}

- (void)calendarFeedTicket:(GDataServiceTicket *)ticket
          finishedWithFeed:(GDataFeedCalendar *)feed
                     error:(NSError *)error {
  @synchronized (self) {
    HGSCheckDebug([activeTickets_ containsObject:ticket], nil);
    [activeTickets_ removeObject:ticket];
  }
  if (!error) {
    NSArray *entries = [feed entries];
    for (GDataEntryCalendar *entry in entries) {
      [self indexCalendar:entry];
    }
  } else {
    NSString *fetchType = HGSLocalizedString(@"^calendar", 
                                             @"A label denoting a Google "
                                             @"Calendar.");
    NSError *fetchError = [error gcs_errorByAddingFetchType:fetchType];
    
    [self performSelectorOnMainThread:@selector(reportError:) 
                           withObject:fetchError 
                        waitUntilDone:NO];
  }
}

- (void)indexCalendar:(GDataEntryCalendar *)calendarEntry {
  NSString* calendarTitle = [[calendarEntry title] stringValue];
  NSString *calendarID = [calendarEntry identifier];
  NSMutableDictionary *attributes
    = [NSMutableDictionary dictionaryWithObject:calendarID
                                         forKey:kGoogleCalendarIDKey];
  
  // We can't get last-used, so just use last-modified.
  [attributes setObject:[[calendarEntry updatedDate] date]
                 forKey:kHGSObjectAttributeLastUsedDateKey];
  
  // Come up with a unique calendar URL.  Since an account may own multiple
  // calendars and since there is no URL for going directly to a specific
  // calendar we must create our own so that the mixer does not think that
  // calendars from the same account are duplicates. We uniquify the URL
  // for each calendar by adding parameters that will be ignored.
  // NOTE: All links will go to the currently signed-in account's calendar
  // web page.  This may be different from the account associated with
  // this calendar.
  NSString *googleCalendarTitle
    = HGSLocalizedString(@"^Google Calendar", 
                         @"A label denoting the Google Calendar service.");
  NSString *urlString = [self accountCalendarURLString];
  NSString *encodedAccountName
    = [[account_ userName]
       stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  NSString *encodedCalendarTitle
    = [calendarTitle
       stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  urlString
    = [urlString stringByAppendingFormat:@"?qsb-account=%@&qsb-calendar=%@",
       encodedAccountName, encodedCalendarTitle];
  NSURL *calendarURL = [NSURL URLWithString:urlString];

  // Compose the contents of the path control:
  // 'Google Calendar'/username/calendar name.
  NSArray *pathCellElements
    = [NSArray arrayWithObjects:
       [HGSPathCellElement elementWithTitle:googleCalendarTitle
                                        url:calendarURL],
       [HGSPathCellElement elementWithTitle:[service_ username]
                                        url:calendarURL],
       [HGSPathCellElement elementWithTitle:calendarTitle url:calendarURL],
       nil];
  NSArray *cellArray
    = [HGSPathCellElement pathCellArrayWithElements:pathCellElements];
  if (cellArray) {
    [attributes setObject:cellArray forKey:kQSBObjectAttributePathCellsKey]; 
  }

  [attributes setObject:calendarIcon_ forKey:kHGSObjectAttributeIconKey];
  
  // Don't site search our calendar.
  [attributes setObject:[NSNumber numberWithBool:YES] 
                 forKey:kHGSObjectAttributeHideGoogleSiteSearchResultsKey];
  
  // Add calendarEntry description and tags to enhance searching.
  NSString* calendarDescription = [[calendarEntry summary] stringValue];
  if (calendarDescription) {
    [attributes setObject:calendarDescription 
                   forKey:kHGSObjectAttributeSnippetKey];
  }
  NSString *calendarAccount = [calendarTitle stringByAppendingFormat:@" (%@)",
                               [account_ userName]];
  HGSUnscoredResult* result
    = [HGSUnscoredResult resultWithURL:calendarURL
                                  name:calendarTitle
                                  type:kHGSTypeWebCalendar
                                source:self
                            attributes:attributes];
  NSString *otherTerm = HGSLocalizedString(@"^calendar", 
                                           @"A label denoting a Google "
                                           @"Calendar.");
  [self indexResult:result
               name:calendarAccount
          otherTerm:otherTerm];
  
  // Now index today's events in the calendarEntry.
  // NOTE: This may pull all-day events from 'tomorrow' because of timezone
  // differences.
  NSURL* eventFeedURL = [[calendarEntry alternateLink] URL];
  if (eventFeedURL) {
    GDataDateTime *startOfToday
      = [GDataDateTime dateTimeForTodayAtHour:0 minute:0 second:0];
    GDataQueryCalendar *calendarQuery
      = [GDataQueryCalendar calendarQueryWithFeedURL:eventFeedURL];
    [calendarQuery setStartIndex:1];
    [calendarQuery setMaxResults:100];
    [calendarQuery setMinimumStartTime:startOfToday];
    [calendarQuery setShouldShowDeleted:NO];
    GDataServiceTicket *eventTicket
      = [service_ fetchFeedWithQuery:calendarQuery
                            delegate:self
                   didFinishSelector:@selector(eventsFetcher:
                                               finishedWithFeed:
                                               error:)];
    [calendarEntry setProperty:calendarURL forKey:kGoogleCalendarURLKey];
    [eventTicket setProperty:calendarEntry forKey:kGoogleCalendarEntryKey];
    @synchronized (self) {
      [activeTickets_ addObject:eventTicket];
    }
  }
}

#pragma mark -
#pragma mark Calendar Event Fetching

- (void)eventsFetcher:(GDataServiceTicket *)ticket
     finishedWithFeed:(GDataFeedCalendarEvent *)eventFeed
               error:(NSError *)error {
  @synchronized (self) {
    HGSCheckDebug([activeTickets_ containsObject:ticket], nil);
    [activeTickets_ removeObject:ticket];
  }
  if (!error) {
    NSArray *eventList = [eventFeed entries];
    for (GDataEntryCalendarEvent *eventEntry in eventList) {
      GDataEntryCalendar *calendarEntry
        = [ticket propertyForKey:kGoogleCalendarEntryKey];
      [self indexEvent:eventEntry withCalendar:calendarEntry];
    }
  } else {
    NSString *fetchType
      = HGSLocalizedString(@"^event", 
                           @"A label denoting a Google Calendar event");
    NSError *fetchError = [error gcs_errorByAddingFetchType:fetchType];
    
    [self performSelectorOnMainThread:@selector(reportError:) 
                           withObject:fetchError 
                        waitUntilDone:NO];
  }
}

- (void)indexEvent:(GDataEntryCalendarEvent *)eventEntry
      withCalendar:(GDataEntryCalendar *)calendarEntry {
  NSURL* eventURL = [[eventEntry HTMLLink] URL];
  GDataEventStatus *eventStatus = [eventEntry eventStatus];
  NSString *statusString = [eventStatus stringValue];
  if (eventURL && ![statusString isEqualToString:kGDataEventStatusCanceled]) {
    NSString *calendarID = [calendarEntry identifier];
    NSMutableDictionary *attributes
      = [NSMutableDictionary dictionaryWithObject:calendarID
                                           forKey:kGoogleCalendarIDKey];
    
    // Compose the contents of the path control:
    // 'Google Calendar'/username/calendar name/event title.
    // The first three links will go to the account's calendar web page.
    // The event cell will be linked to the cell details web page.
    NSURL *calendarURL = [calendarEntry propertyForKey:kGoogleCalendarURLKey];
    NSString *googleCalendarTitle
      = HGSLocalizedString(@"^Google Calendar", 
                           @"A label denoting the Google Calendar service.");
    NSString* calendarTitle = [[calendarEntry title] stringValue];
    NSString* eventTitle = [[eventEntry title] stringValue];
    NSArray *pathCellElements
      = [NSArray arrayWithObjects:
         [HGSPathCellElement elementWithTitle:googleCalendarTitle
                                          url:calendarURL],
         [HGSPathCellElement elementWithTitle:[service_ username]
                                          url:calendarURL],
         [HGSPathCellElement elementWithTitle:calendarTitle url:calendarURL],
         [HGSPathCellElement elementWithTitle:eventTitle url:eventURL],
         nil];
    NSArray *cellArray
      = [HGSPathCellElement pathCellArrayWithElements:pathCellElements];
    if (cellArray) {
      [attributes setObject:cellArray forKey:kQSBObjectAttributePathCellsKey]; 
    }
    
    // Add eventEntry description and tags to enhance searching.
    NSString* eventDescription = [[eventEntry content] stringValue];
    if ([eventDescription length] == 0) {
      eventDescription = eventTitle;
    }
    
    // Find the closest future (that is, from the start of the current
    // day) instance of the event. The event times are not sorted, so, if
    // it's an array of more than one time, scan the (unsorted) event dates
    // to find the best match.
    NSDate *startOfToday = [NSDate gcs_startOfToday];
    NSArray *whens = [eventEntry times];
    NSUInteger eventCount = 0;
    NSString *baseURLString = [eventURL absoluteString];
    for (GDataWhen *when in whens) {
      GDataDateTime *startDateTime = [when startTime];
      NSDate *whenDate = [startDateTime date];
      if ([whenDate gcs_isAtOrAfter:startOfToday]) {
        NSDate *startTime = whenDate;
        NSDate *endTime = [[when endTime] date];
        BOOL allDay = ![startDateTime hasTime];
        [attributes setObject:startTime forKey:kGoogleCalendarEventStartTimeKey];
        [attributes setObject:endTime forKey:kGoogleCalendarEventEndTimeKey];
        NSString *todayName = [startTime gcs_todayOrTomorrow];
        NSString *snippet = [self snippetForEvent:eventEntry
                                        startTime:startTime
                                          endTime:endTime
                                      weekdayName:todayName
                                           allDay:allDay];
        if ([snippet length]) {
          [attributes setObject:snippet forKey:kHGSObjectAttributeSnippetKey];
        }
        [attributes setObject:eventIcon_ forKey:kHGSObjectAttributeIconKey];
        
        // Invert date to set last used date
        NSTimeInterval interval = [startTime timeIntervalSinceNow];
        NSDate *lastUsed = [[NSDate date] addTimeInterval:-interval];
        [attributes setObject:lastUsed forKey:kHGSObjectAttributeLastUsedDateKey];
        
        NSString *dateString 
          = [shortDateNoTimeFormatter_ stringFromDate:startTime];
        // Uniquify the eventURL.
        NSString *eventURLString
          = [baseURLString stringByAppendingFormat:@"&qsb-event-index=%d",
             eventCount];
        HGSUnscoredResult* result
          = [HGSUnscoredResult resultWithURL:[NSURL URLWithString:eventURLString]
                                        name:eventTitle
                                        type:kHGSTypeWebCalendarEvent
                                      source:self
                                  attributes:attributes];
        
        NSMutableArray *otherStrings = [NSMutableArray arrayWithObjects:
                                        eventDescription,
                                        calendarTitle,
                                        eventDescription,
                                        dateString,
                                        nil];
        NSString *weekdayName = [startTime gcs_weekdayName];
        if (weekdayName) {
          [otherStrings addObject:weekdayName];
          if (![weekdayName isEqualToString:todayName]) {
            [otherStrings addObject:todayName];
          }
        } 
        [self indexResult:result
                     name:eventTitle
               otherTerms:otherStrings];
        ++eventCount;
      }
    }
  }
}

- (NSString *)snippetForEvent:(GDataEntryCalendarEvent *)eventEntry
                    startTime:(NSDate *)startTime
                      endTime:(NSDate *)endTime
                  weekdayName:(NSString *)weekdayName
                       allDay:(BOOL)allDay {
  // All-day is indicated by a start time with just a date (i.e. no time).
  // An 'instant' is indicated by no end time.
  NSString *snippet = weekdayName;
  NSDateFormatter *formatter = nil;
  if (snippet && !allDay) {
    formatter = noDateShortTimeFormatter_;
  } else if (!snippet && allDay) {
    formatter = shortDateNoTimeFormatter_;
  } else if (!snippet && !allDay) {
    formatter = shortDateShortTimeFormatter_;
  }
  NSString *startTimeString = [formatter stringFromDate:startTime];
  
  if (!allDay) {
    if (snippet) {
      snippet = [snippet stringByAppendingFormat:@", %@", startTimeString];
    } else {
      snippet = startTimeString;
    }
    if (endTime) {
      NSString *endTimeString = [noDateShortTimeFormatter_ stringFromDate:endTime];
      snippet = [snippet stringByAppendingFormat:@" — %@", endTimeString];
    }
  } else {
    NSString *allDayString
      = HGSLocalizedString(@"^All Day", @"The event will last all day.");
    if (!snippet) {
      snippet = startTimeString;
    }
    snippet = [snippet stringByAppendingFormat:@", %@", allDayString];
  }
  
  // Add location to the snippet.
  NSString *where = nil;
  NSArray *locations = [eventEntry locations];
  for (GDataWhere *location in locations) {
    NSString *stringLocation = [location stringValue];
    if ([stringLocation length]) {
      where = (where) ? [where stringByAppendingFormat:@"\r%@", stringLocation]
                      : stringLocation;
    }
  }
  if (where) {
    snippet = [snippet stringByAppendingFormat:@"\r%@", where];
  }
  return snippet;
}

- (void)reportError:(NSError *)error {
  GTMAssertRunningOnMainThread();
  NSInteger errorCode = [error code];
  // If nothing has changed since we last checked then don't have a cow,
  // and don't report not-connected-to-Internet errors.
  if (errorCode != kGDataHTTPFetcherStatusNotModified
      && errorCode != NSURLErrorNotConnectedToInternet) {
    if (errorCode == kGDataBadAuthentication) {
      // If the login credentials are bad, don't keep trying.
      [updateTimer_ invalidate];
      updateTimer_ = nil;
      // Tickle the account so that if the user happens to have the preference
      // window open showing either the account or the search source they
      // will immediately see that the account status has changed.
      [account_ authenticate];
    } else {
      NSTimeInterval currentTime = [[NSDate date] timeIntervalSinceReferenceDate];
      NSTimeInterval timeSinceLastErrorReport
        = currentTime - previousErrorReportingTime_;
      if (timeSinceLastErrorReport > kErrorReportingInterval) {
        previousErrorReportingTime_ = currentTime;
        NSString *errorString = nil;
        if (errorCode == 404) {
          errorString = @"might not be enabled";
        } else {
          errorString = @"fetch failed";
        }
        NSString *fetchType 
          = [[error userInfo] objectForKey:kGoogleCalendarFetchTypeErrorKey];
        HGSLog(@"GoogleCalendarsSource (%@InfoFetcher) %@ for account '%@': "
               @"error=%d '%@'.", fetchType, errorString,
               [account_ displayName], errorCode, [error localizedDescription]);
      }
    }
  }
}


#pragma mark -
#pragma mark HGSAccountClientProtocol Methods

- (BOOL)accountWillBeRemoved:(HGSAccount *)account {
  HGSAssert(account == account_, @"Notification from bad account!");
  [self cancelAllTickets];
  return YES;
}

@end


@implementation NSDate (GoogleCalendarsSource)

+ (NSDate *)gcs_startOfToday {
  NSCalendar *calendar
    = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar]
       autorelease];
  const NSUInteger kComponentBits = (NSYearCalendarUnit | NSMonthCalendarUnit
                                     | NSDayCalendarUnit | NSHourCalendarUnit
                                     | NSMinuteCalendarUnit
                                     | NSSecondCalendarUnit);
  NSDateComponents *dateComponents = [calendar components:kComponentBits
                                                 fromDate:[NSDate date]];
  [dateComponents setHour:0];
  [dateComponents setMinute:0];
  [dateComponents setSecond:0];
  NSDate *date = [calendar dateFromComponents:dateComponents];
  return date;
}

- (NSDate *)gcs_addDays:(NSInteger)days {
  NSCalendar *calendar
    = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar]
       autorelease];
  NSDateComponents *dateComponents
    = [[[NSDateComponents alloc] init] autorelease];
  [dateComponents setDay:days];
  NSDate *date
    = [calendar dateByAddingComponents:dateComponents toDate:self options:0];
  return date;
}

- (BOOL)gcs_isAtOrAfter:(NSDate *)otherTime {
  NSComparisonResult result = [self compare:otherTime];
  BOOL sameOrLater
    = result == NSOrderedSame || result == NSOrderedDescending;
  return sameOrLater;
}

- (NSString *)gcs_weekdayName {
  NSString *weekdayName = nil;
  NSDate *startOfToday = [NSDate gcs_startOfToday];
  NSDate *aWeekAway = [startOfToday gcs_addDays:7]; 
  if ([aWeekAway gcs_isAtOrAfter:self]) {
    NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
    [formatter setDateFormat:@"cccc"];
    weekdayName = [formatter stringFromDate:self];
  }
  return weekdayName;
}

- (NSString *)gcs_todayOrTomorrow {
  NSString *dayName = nil;
  NSDate *startOfToday = [NSDate gcs_startOfToday];
  NSDate *startOfTomorrow = [startOfToday gcs_addDays:1]; 
  NSDate *startOfDayAfterTomorrow = [startOfTomorrow gcs_addDays:1]; 
  if ([self gcs_isAtOrAfter:startOfToday]
      && [startOfTomorrow gcs_isAtOrAfter:self]) {
    dayName = HGSLocalizedString(@"^Today", 
                                 @"The event occurs today.");
  } else if ([startOfDayAfterTomorrow gcs_isAtOrAfter:self]) {
    dayName = HGSLocalizedString(@"^Tomorrow", 
                                 @"The event occurs tomorrow.");
  } else  {
    dayName = [self gcs_weekdayName];
  }
  return dayName;
}

@end


@implementation GDataDateTime (GoogleCalendarsSource)

+ (GDataDateTime *)dateTimeForTodayAtHour:(int)hour
                                   minute:(int)minute
                                   second:(int)second {
  const NSUInteger kComponentBits = (NSYearCalendarUnit | NSMonthCalendarUnit
                                     | NSDayCalendarUnit | NSHourCalendarUnit
                                     | NSMinuteCalendarUnit
                                     | NSSecondCalendarUnit);
  NSCalendar *cal
    = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar]
       autorelease];
  NSDate *today = [NSDate date];
  NSDateComponents *dateComponents = [cal components:kComponentBits
                                            fromDate:today];
  [dateComponents setHour:hour];
  [dateComponents setMinute:minute];
  [dateComponents setSecond:second];
  GDataDateTime *dateTime
    = [GDataDateTime dateTimeWithDate:today
                             timeZone:[NSTimeZone systemTimeZone]];
  [dateTime setDateComponents:dateComponents];
  return dateTime;
}

@end

@implementation NSError (GoogleCalendarsSource)

- (NSError *)gcs_errorByAddingFetchType:(NSString *)fetchType {
  NSMutableDictionary *userInfo 
    = [NSMutableDictionary dictionaryWithDictionary:[self userInfo]];
  [userInfo setObject:fetchType forKey:kGoogleCalendarFetchTypeErrorKey];
  return [NSError errorWithDomain:[self domain] 
                             code:[self code] 
                         userInfo:userInfo];
}

@end

