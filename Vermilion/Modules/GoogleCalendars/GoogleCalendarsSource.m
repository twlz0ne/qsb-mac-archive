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
#import "GoogleAccountsConstants.h"
#import "HGSKeychainItem.h"
#import "QSBHGSResultAttributeKeys.h"

static NSString *const kGoogleCalendarIDKey = @"GoogleCalendarIDKey";
static NSString *const kCalendarEntryKey = @"CalendarEntryKey";
static NSString *const kCalendarURLKey = @"CalendarURLKey";

static const NSTimeInterval kRefreshSeconds = 300.0;  // 5 minutes.
static const NSTimeInterval kErrorReportingInterval = 3600.0;  // 1 hour


@interface GoogleCalendarsSource : HGSMemorySearchSource <HGSAccountClientProtocol> {
 @private
  GDataServiceGoogleCalendar *service_;
  NSMutableSet *activeTickets_;
  __weak NSTimer *updateTimer_;
  HGSAccount *account_;
  NSTimeInterval previousErrorReportingTime_;
  NSImage *calendarIcon_;
  NSImage *eventIcon_;
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
- (NSString *)snippetForEvent:(GDataEntryCalendarEvent *)eventEntry;

// Compose an URL string which can be used to open the account's
// calendar view in a browser.
- (NSString *)accountCalendarURLString;

// Utility function for reporting fetch errors.
- (void)reportErrorForFetchType:(NSString *)fetchType
                          error:(NSError *)error;

@end


@interface GDataDateTime (GoogleCalendarsSource)

// Utility function to make a GDataDateTime object for sometime today
+ (GDataDateTime *)dateTimeForTodayAtHour:(int)hour
                                   minute:(int)minute
                                   second:(int)second;

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
  [activeTickets_ release];
  [service_ release];
  [updateTimer_ invalidate];
  [account_ release];
  [calendarIcon_ release];
  [eventIcon_ release];
  [super dealloc];
}

- (void)cancelAllTickets {
  [activeTickets_ makeObjectsPerformSelector:@selector(cancelTicket)];
  [activeTickets_ removeAllObjects];
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
  if ([activeTickets_ count] == 0) {
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
    
    GDataServiceTicket *calendarTicket
      = [service_ fetchFeedWithURL:[NSURL URLWithString:
                                    kGDataGoogleCalendarDefaultOwnCalendarsFeed]
                          delegate:self
                 didFinishSelector:@selector(calendarFeedTicket:
                                             finishedWithFeed:
                                             error:)];
    [activeTickets_ addObject:calendarTicket];
  }
}

- (void)calendarFeedTicket:(GDataServiceTicket *)ticket
          finishedWithFeed:(GDataFeedCalendar *)feed
                     error:(NSError *)error {
  HGSCheckDebug([activeTickets_ containsObject:ticket], nil);
  [activeTickets_ removeObject:ticket];
  if (!error) {
    NSArray *entries = [feed entries];
    for (GDataEntryCalendar *entry in entries) {
      [self indexCalendar:entry];
    }
  } else {
    NSString *fetchType = HGSLocalizedString(@"calendar", 
                                             @"A label denoting a Google "
                                             @"Calendar.");
    [self reportErrorForFetchType:fetchType error:error];
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
    = HGSLocalizedString(@"Google Calendar", 
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
       [HGSPathCellElement elementWithTitle:googleCalendarTitle url:calendarURL],
       [HGSPathCellElement elementWithTitle:[service_ username] url:calendarURL],
       [HGSPathCellElement elementWithTitle:calendarTitle url:calendarURL],
       nil];
  NSArray *cellArray
    = [HGSPathCellElement pathCellArrayWithElements:pathCellElements];
  if (cellArray) {
    [attributes setObject:cellArray forKey:kQSBObjectAttributePathCellsKey]; 
  }

  [attributes setObject:calendarIcon_ forKey:kHGSObjectAttributeIconKey];
  
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
  NSString *otherTerm = HGSLocalizedString(@"calendar", 
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
    GDataDateTime *startOfDay
      = [GDataDateTime dateTimeForTodayAtHour:0 minute:0 second:0];
    GDataDateTime *endOfDay
      = [GDataDateTime dateTimeForTodayAtHour:23 minute:59 second:59];
    GDataQueryCalendar *calendarQuery
      = [GDataQueryCalendar calendarQueryWithFeedURL:eventFeedURL];
    [calendarQuery setStartIndex:1];
    [calendarQuery setMaxResults:100];
    [calendarQuery setMinimumStartTime:startOfDay];
    [calendarQuery setMaximumStartTime:endOfDay];
    [calendarQuery setShouldShowDeleted:NO];
    GDataServiceTicket *eventTicket
      = [service_ fetchFeedWithQuery:calendarQuery
                            delegate:self
                   didFinishSelector:@selector(eventsFetcher:
                                               finishedWithFeed:
                                               error:)];
    [calendarEntry setProperty:calendarURL forKey:kCalendarURLKey];
    [eventTicket setProperty:calendarEntry forKey:kCalendarEntryKey];
    [activeTickets_ addObject:eventTicket];
  }
}

#pragma mark -
#pragma mark Calendar Event Fetching

- (void)eventsFetcher:(GDataServiceTicket *)ticket
     finishedWithFeed:(GDataFeedCalendarEvent *)eventFeed
               error:(NSError *)error {
  HGSCheckDebug([activeTickets_ containsObject:ticket], nil);
  [activeTickets_ removeObject:ticket];
  if (!error) {
    NSArray *eventList = [eventFeed entries];
    for (GDataEntryCalendarEvent *eventEntry in eventList) {
      GDataEntryCalendar *calendarEntry = [ticket propertyForKey:kCalendarEntryKey];
      [self indexEvent:eventEntry withCalendar:calendarEntry];
    }
  } else {
    NSString *fetchType = HGSLocalizedString(@"event", 
                                             @"A label denoting a Google "
                                             @"Calendar event");
    [self reportErrorForFetchType:fetchType error:error];
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
    NSURL *calendarURL = [calendarEntry propertyForKey:kCalendarURLKey];
    NSString *googleCalendarTitle
      = HGSLocalizedString(@"Google Calendar", 
                           @"A label denoting the Google Calendar service.");
    NSString* calendarTitle = [[calendarEntry title] stringValue];
    NSString* eventTitle = [[eventEntry title] stringValue];
    NSArray *pathCellElements
      = [NSArray arrayWithObjects:
         [HGSPathCellElement elementWithTitle:googleCalendarTitle url:calendarURL],
         [HGSPathCellElement elementWithTitle:[service_ username] url:calendarURL],
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
    
    NSString *snippet = [self snippetForEvent:eventEntry];
    if ([snippet length]) {
      [attributes setObject:snippet forKey:kHGSObjectAttributeSnippetKey];
    }
    [attributes setObject:eventIcon_ forKey:kHGSObjectAttributeIconKey];
    HGSUnscoredResult* result
      = [HGSUnscoredResult resultWithURL:eventURL
                                    name:eventTitle
                                    type:kHGSTypeWebCalendarEvent
                                  source:self
                              attributes:attributes];
    
    NSMutableArray *otherStrings = [NSMutableArray arrayWithObjects:
                                    eventDescription,
                                    calendarTitle,
                                    eventDescription,
                                    nil];
    [self indexResult:result
                 name:eventTitle
           otherTerms:otherStrings];
  }
}

- (NSString *)snippetForEvent:(GDataEntryCalendarEvent *)eventEntry {
  // All-day is indicated by a start time with just a date (i.e. no time).
  // An 'instant' is indicated by no end time.
  NSString *snippet = nil;
  GDataDateTime *startTime = nil;
  GDataDateTime *endTime = nil;
  NSArray *times = [eventEntry times];
  GDataWhen *when = nil;
  if ([times count] > 0) {
    when = [times objectAtIndex:0];
    startTime = [when startTime];
    endTime = [when endTime];
  }
  if ([startTime hasTime]) {
    NSDateFormatter *timeFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [timeFormatter setDateStyle:NSDateFormatterNoStyle];
    [timeFormatter setTimeStyle:NSDateFormatterShortStyle];
    snippet = [timeFormatter stringFromDate:[startTime date]];
    if (endTime) {
      NSString *endTimeString = [timeFormatter stringFromDate:[endTime date]];
      snippet = [snippet stringByAppendingFormat:@" — %@", endTimeString];
    }
  } else {
    snippet = HGSLocalizedString(@"All Day", 
                                 @"The event will last all day.");
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

- (void)reportErrorForFetchType:(NSString *)fetchType
                          error:(NSError *)error {
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


@implementation GDataDateTime (GoogleCalendarsSource)

+ (GDataDateTime *)dateTimeForTodayAtHour:(int)hour
                                   minute:(int)minute
                                   second:(int)second {
  int const kComponentBits = (NSYearCalendarUnit | NSMonthCalendarUnit
                              | NSDayCalendarUnit | NSHourCalendarUnit
                              | NSMinuteCalendarUnit | NSSecondCalendarUnit);
  NSCalendar *cal
    = [[[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar]
       autorelease];
  NSDateComponents *dateComponents = [cal components:kComponentBits
                                            fromDate:[NSDate date]];
  [dateComponents setHour:hour];
  [dateComponents setMinute:minute];
  [dateComponents setSecond:second];
  GDataDateTime *dateTime
    = [GDataDateTime dateTimeWithDate:[NSDate date]
                             timeZone:[NSTimeZone systemTimeZone]];
  [dateTime setDateComponents:dateComponents];
  return dateTime;
}

@end

