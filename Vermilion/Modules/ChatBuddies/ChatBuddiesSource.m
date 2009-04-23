//
//  ChatBuddiesSource.m
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

#import <Vermilion/Vermilion.h>
#import <InstantMessage/IMService.h>

#import "GTMGarbageCollection.h"
#import "GTMNSString+URLArguments.h"
#import "GTMMethodCheck.h"
#import "QSBHGSDelegate.h"

static NSString* const kChatBuddyAttributeInformationKey 
  = @"ChatBuddyAttributeInformationKey";

// TODO(alcor): rank buddies by frequency of use, consider "RecentChats" default

// Search our buddy list and return matches against screen name, first or
// last name, email address, status message and service name.
//
@interface ChatBuddiesSource : HGSMemorySearchSource {
 @private
  NSMutableSet *availableServices_;  // The names of my logged-in services.
  BOOL iWasOnline_;  // My last remembered I/M status.
  NSMutableArray *buddyResults_; // the list of results in the index
  BOOL rebuildIndex_;
  NSArray *imStatusStrings_;
  NSArray *serviceStatusStrings_;
  NSArray *buddyStatusStrings_;
}

@end

@interface ChatBuddiesSource (ChatBuddiesSourcePrivateMethods)

- (HGSResult *)contactResultFromIMBuddy:(NSDictionary *)buddy
                                service:(IMService *)service
                                 source:(HGSSearchSource *)source;

// Pushes everything in our buddyResults_ down into the memory source
- (void)updateIndex;

// Update our index in response to a change in a buddy's information.
- (void)infoChangedNotification:(NSNotification*)notification;

// Reconcile a change in a service's status.
- (void)serviceStatusChangedNotification:(NSNotification*)notification;

// Our status has changed.
- (void)myStatusChangedNotification:(NSNotification*)notification;

- (NSArray *)stringsFromBuddy:(HGSResult *)buddy forKeys:(NSArray *)keys;
- (NSString *)nameStringForBuddy:(HGSResult *)buddy;
- (NSArray *)otherTermStringsForBuddy:(HGSResult *)buddy;
@end


@implementation ChatBuddiesSource
GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    // Collect and cache information about our buddies and set of
    // logged-in services.
    availableServices_ = [[NSMutableSet alloc] init];
    buddyResults_ = [[NSMutableArray alloc] init];
    IMPersonStatus myStatus = [IMService myStatus];
    iWasOnline_ = (myStatus == IMPersonStatusIdle
                   || myStatus == IMPersonStatusAway
                   || myStatus == IMPersonStatusAvailable);
    NSArray *services = [IMService allServices];
    NSEnumerator *serviceEnum = [services objectEnumerator];
    IMService *service = nil;
    while ((service = [serviceEnum nextObject])) {
      if ([service status] == IMServiceStatusLoggedIn) {
        [availableServices_ addObject:[service name]];
      }
      NSArray *buddiesForService = [service infoForAllScreenNames];
      NSEnumerator *buddyEnum = [buddiesForService objectEnumerator];
      NSDictionary *buddy = nil;
      while ((buddy = [buddyEnum nextObject])) {
        HGSResult *newBuddy
          = [self contactResultFromIMBuddy:buddy
                                   service:service
                                    source:self];
        [buddyResults_ addObject:newBuddy];
      }
    }
    [self updateIndex];
  }

  // Register for notifications about changes to buddy information.
  NSNotificationCenter *nc = [IMService notificationCenter];
  [nc addObserver:self 
         selector:@selector(infoChangedNotification:) 
             name:IMPersonInfoChangedNotification 
           object:nil];
  [nc addObserver:self 
         selector:@selector(serviceStatusChangedNotification:) 
             name:IMServiceStatusChangedNotification 
           object:nil];
  [nc addObserver:self 
         selector:@selector(myStatusChangedNotification:) 
             name:IMMyStatusChangedNotification 
           object:nil];
  
  imStatusStrings_ = [[NSArray alloc] initWithObjects:
                      HGSLocalizedString(@"MyIMStatusUnknown", 
                                         @"MyIMStatusUnknown"),
                      HGSLocalizedString(@"MyIMStatusOffline", 
                                         @"MyIMStatusOffline"),
                      HGSLocalizedString(@"MyIMStatusIdle", 
                                         @"MyIMStatusIdle"),
                      HGSLocalizedString(@"MyIMStatusAway", 
                                         @"MyIMStatusAway"),
                      HGSLocalizedString(@"MyIMStatusAvailable", 
                                         @"MyIMStatusAvailable"),
                      HGSLocalizedString(@"MyIMStatusNoStatus", 
                                         @"MyIMStatusNoStatus"),
                      nil];
  
  serviceStatusStrings_ = [[NSArray alloc] initWithObjects:
                           HGSLocalizedString(@"ServiceStatusLoggedOut", 
                                              @"ServiceStatusLoggedOut"),
                           HGSLocalizedString(@"ServiceStatusDisconnected", 
                                              @"ServiceStatusDisconnected"),
                           HGSLocalizedString(@"ServiceStatusLoggingOut", 
                                              @"ServiceStatusLoggingOut"),
                           HGSLocalizedString(@"ServiceStatusLoggingIn", 
                                              @"ServiceStatusLoggingIn"),
                           HGSLocalizedString(@"ServiceStatusLoggedIn", 
                                              @"ServiceStatusLoggedIn"),
                           nil];
  
  buddyStatusStrings_ = [[NSArray alloc] initWithObjects:
                         HGSLocalizedString(@"BuddyStatusUnknown",
                                            @"BuddyStatusUnknown"),
                         HGSLocalizedString(@"BuddyStatusOffline", 
                                            @"BuddyStatusOffline"),
                         HGSLocalizedString(@"BuddyStatusIdle",
                                            @"BuddyStatusIdle"),
                         HGSLocalizedString(@"BuddyStatusAway",
                                            @"BuddyStatusAway"),
                         HGSLocalizedString(@"BuddyStatusAvailable",
                                            @"BuddyStatusAvailable"),
                         HGSLocalizedString(@"BuddyStatusNone",
                                            @"BuddyStatusNone"),
                         nil];
  
  return self;  
}

- (void)dealloc {
  [[IMService notificationCenter] removeObserver:self];
  [availableServices_ release];
  [buddyResults_ release];
  [imStatusStrings_ release];
  [serviceStatusStrings_ release];
  [buddyStatusStrings_ release];
  [super dealloc];
}

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  // TODO(mrossetti): break this method up. It's too complex.
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeIconKey]) {
    // Retrieve the info for this result.
    NSDictionary *imBuddyInfo 
      = [result valueForKey:kChatBuddyAttributeInformationKey];
    if ([imBuddyInfo count]) {
      NSString *serviceName = [imBuddyInfo objectForKey:IMPersonServiceNameKey];
      if ([serviceName length]) {
        IMService *service = [IMService serviceWithName:serviceName];
        NSString *screenName = [imBuddyInfo objectForKey:IMPersonScreenNameKey];
        NSDictionary *currentBuddyInfo = [service infoForScreenName:screenName];
        NSData *buddyPictureData 
          = [currentBuddyInfo objectForKey:IMPersonPictureDataKey];
        if (buddyPictureData) {
          NSImage *image = [[[NSImage alloc] initWithData:buddyPictureData]
                            autorelease];
          HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
          value = [provider imageWithRoundRectAndDropShadow:image];
        }
      }
    }
    if (!value) {
      value = [NSImage imageNamed:@"blue-user"];
    }
  } else if ([key isEqualToString:kHGSObjectAttributeSnippetKey]) {
    // Snippet: status, "status message"
    NSMutableString *snippet = [NSMutableString string];
    NSDictionary *imBuddyInfo 
      = [result valueForKey:kChatBuddyAttributeInformationKey];

    // Fetch their current status for up to date info
    NSString *serviceName = [imBuddyInfo objectForKey:IMPersonServiceNameKey];
    IMService *service = [IMService serviceWithName:serviceName];
    NSString *screenName = [imBuddyInfo objectForKey:IMPersonScreenNameKey];
    NSDictionary *currentBuddyInfo = [service infoForScreenName:screenName];    
    
    // Determine our status, the service status and finally the buddy's.
    NSString *statusString = nil;
    NSUInteger status = MIN([IMService myStatus], [imStatusStrings_ count]);
    if (status != IMPersonStatusIdle
        && status != IMPersonStatusAway
        && status != IMPersonStatusAvailable) {
      statusString = [imStatusStrings_ objectAtIndex:status];
    } else {
      status = MIN([service status], [serviceStatusStrings_ count]);
      if (status != IMServiceStatusLoggedIn) {
        statusString = [serviceStatusStrings_ objectAtIndex:status];
      } else {
        NSNumber *imStatus = [currentBuddyInfo objectForKey:IMPersonStatusKey];
        status = MIN([imStatus unsignedIntValue], [buddyStatusStrings_ count]);
        statusString = [buddyStatusStrings_ objectAtIndex:status];
      }
    }
    
    // Compose the snippet.
    NSString *statusMessage
      = [currentBuddyInfo objectForKey:IMPersonStatusMessageKey];

    if ([statusMessage length]) {
      [snippet appendString:statusMessage];
      if ([statusString length] 
          && ![statusString isEqualToString:statusMessage]) {
        [snippet appendFormat:@" (%@)", statusString];
      }
    } else if ([statusString length]) {
      [snippet appendString:statusString];
    }
    value = snippet;
  }
  else if ([key isEqualToString:kQSBObjectAttributePathCellsKey]) {
    // Build three cells, the first with 'iChat', the second with the
    // service name, and the third with the screen name.  Only the
    // third cell will respond to clicks.
    // TODO(mrossetti): Make the iChat cell clickable to activate iChat.
    NSURL *buddyURL = [result url];
    NSString *iChatName = @"iChat";
    NSURL *iChatURL = nil;
    CFURLRef iChatCFURL = nil;
    OSStatus osStatus = LSGetApplicationForURL((CFURLRef)buddyURL,
                                               kLSRolesViewer + kLSRolesEditor,
                                               nil,  // Ignore NSRef
                                               &iChatCFURL);
    if (osStatus == noErr && iChatCFURL) {
      iChatURL = GTMCFAutorelease(iChatCFURL);
      NSString *iChatPath = [iChatURL path];
      NSBundle *iChatBundle = [NSBundle bundleWithPath:iChatPath];
      NSString *iChatAppName = nil;
      if (iChatBundle) {
        iChatAppName = [iChatBundle objectForInfoDictionaryKey:@"CFBundleName"];
        if ([iChatAppName length]) {
          iChatName =  iChatAppName;
        }
      }
    } else if (iChatCFURL) {
      CFRelease(iChatCFURL);
    }
    
    NSDictionary *imBuddyInfo 
      = [result valueForKey:kChatBuddyAttributeInformationKey];
    NSString *serviceName = [imBuddyInfo objectForKey:IMPersonServiceNameKey];
    NSString *screenName = [imBuddyInfo objectForKey:IMPersonScreenNameKey];
    
    if ([serviceName length] && [screenName length]) {
      NSMutableDictionary *iChatCell 
        = [NSMutableDictionary dictionaryWithObjectsAndKeys:
           iChatName, kQSBPathCellDisplayTitleKey,
           nil];
      if (iChatURL) {
        [iChatCell setObject:iChatURL forKey:kQSBPathCellURLKey];
      }
      NSDictionary *serviceCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                   serviceName, kQSBPathCellDisplayTitleKey,
                                   nil];
      NSDictionary *buddyCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                 screenName, kQSBPathCellDisplayTitleKey,
                                 buddyURL, kQSBPathCellURLKey,
                                 nil];
      value = [NSArray arrayWithObjects:iChatCell, serviceCell, buddyCell, nil];
    }
  }
  if (!value) {
    value = [super provideValueForKey:key result:result];
  }
  
  return value;
}

// This source also provides results for ichat
- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValid = [super isValidSourceForQuery:query];
  HGSResult *pivot = [query pivotObject];
  if (isValid && [query pivotObject]) {
    NSString *path = [[pivot url] absoluteString];
    isValid = [path hasSuffix:@"/iChat.app"];
  }
  return isValid;
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  // We use a bool to keep track of when we need to update the index so we don't
  // spend lots of time doing this as buddies come and go.  This is needed
  // because when the im service goes online/offline, it sends a notification
  // for every buddy in the list.  If the index ever gets an api were we can
  // remove individual objects, then we might not need to do this batching.
  if (rebuildIndex_) {
    [self updateIndex];
  }
  [super performSearchOperation:operation];
}

- (NSMutableDictionary *)archiveRepresentationForResult:(HGSResult*)result {
  // Don't want chat buddy results remembered in shortcuts
  // TODO: revisit when we don't use a subclass and see if we can save a few
  // things to rebuild the real result.
  return nil;
}

- (HGSResult *)resultWithArchivedRepresentation:(NSDictionary *)representation {
  // Don't want chat buddy results remembered in shortcuts
  // TODO: revisit when we don't use a subclass and see if we can save a few
  // things to rebuild the real result.
  return nil;
}

@end


@implementation ChatBuddiesSource (ChatBuddiesSourcePrivateMethods)

- (NSArray *)stringsFromBuddy:(HGSResult *)buddy 
                      forKeys:(NSArray *)keys {
  NSMutableArray *strings = [NSMutableArray array];
  NSDictionary *imBuddyInfo 
    = [buddy valueForKey:kChatBuddyAttributeInformationKey];
  for (NSString *key in keys) {
    NSString *aStr = [imBuddyInfo objectForKey:key];
    if (aStr) {
      [strings addObject:aStr];
    }
  }
  return strings;
}

- (NSString *)nameStringForBuddy:(HGSResult *)buddy {
  // This is a list of the attributes that we will use
  // to compose the name-related string.
  // (can only be keys listed in init as going into the info dictionary)
  NSArray *imNameTermKeys = [NSArray arrayWithObjects:
                             IMPersonScreenNameKey,
                             IMPersonFirstNameKey,
                             IMPersonLastNameKey,
                             nil];
  NSArray *nameStrings = [self stringsFromBuddy:buddy forKeys:imNameTermKeys];
  return [nameStrings componentsJoinedByString:@" "];
}

- (NSArray *)otherTermStringsForBuddy:(HGSResult *)buddy {
  // This is a list of the attributes that we will use
  // to compose the non-name-related string array.
  // (can only be keys listed in init as going into the info dictionary)
  NSArray *imOtherTermKeys = [NSArray arrayWithObject:IMPersonEmailKey];
  return [self stringsFromBuddy:buddy
                        forKeys:imOtherTermKeys];
}

- (void)updateIndex {
  rebuildIndex_ = NO;
  [self clearResultIndex];

  @synchronized(buddyResults_) {
    for (HGSResult *buddyResult in buddyResults_) {
      NSString *name = [self nameStringForBuddy:buddyResult];
      NSArray *otherStrings = [self otherTermStringsForBuddy:buddyResult];
      [self indexResult:buddyResult
                   name:name
             otherTerms:otherStrings];
    }
  }
}

- (void)infoChangedNotification:(NSNotification*)notification {
  IMService *service = [notification object];
  // TODO(mrossetti): what happen if someone gets removed from the buddy list?
  // does that come via an info notice or a status notice (which we don't
  // listen too anymore)?  We'd need to remove the item from our cached list
  // or rebuild the full list if we can't tell who left.
  if (service) {
    NSDictionary *userInfo = [notification userInfo];
    NSString *serviceName = [service name];
    NSString *screenName = [userInfo objectForKey:IMPersonScreenNameKey];
    if ([screenName length]) {
      // See if we already know about this buddy.
      @synchronized(buddyResults_) {
        HGSResult *buddyResult = nil;
        for (buddyResult in buddyResults_) {
          NSDictionary *imBuddyInfo 
            = [buddyResult valueForKey:kChatBuddyAttributeInformationKey];
          NSString *buddyService 
            = [imBuddyInfo objectForKey:IMPersonServiceNameKey];
          if ([buddyService isEqualToString:serviceName]) {
            NSString *buddyName 
              = [imBuddyInfo objectForKey:IMPersonScreenNameKey];
            BOOL sameName = (buddyName != nil)
              && [buddyName caseInsensitiveCompare:screenName] == NSOrderedSame;
            if (sameName) {
              break;
            }
          }
        }
        if (buddyResult) {
          // Remove the results and add it new to pick up the changes
          [buddyResults_ removeObjectIdenticalTo:buddyResult];
          HGSResult *newBuddy
            = [self contactResultFromIMBuddy:userInfo
                                     service:service
                                      source:self];
          [buddyResults_ addObject:newBuddy];
          // Next search will rebuild the index (since it doesn't support remove)
          rebuildIndex_ = YES;
        } else {
          // This must be a new buddy but if it's a |statusChange| do nothing.
          HGSResult *newBuddy = [self contactResultFromIMBuddy:userInfo
                                                       service:service
                                                        source:self];
          [buddyResults_ addObject:newBuddy];
          // Add it to the index
          NSString *name = [self nameStringForBuddy:newBuddy];
          NSArray *terms = [self otherTermStringsForBuddy:newBuddy];
          [self indexResult:newBuddy
                       name:name
                 otherTerms:terms];
        }
      }  // @syncronized(buddyResults_)
    } else {
      HGSLogDebug(@"IMService notification missing screen name.");
    }
  } else {
    HGSLogDebug(@"IMService notification missing service name.");
  }
}

- (void)serviceStatusChangedNotification:(NSNotification*)notification {
  IMService *service = [notification object];
  NSString *serviceName = [service name];
  // Determine if the service's status has changed.
  BOOL serviceWasOnline = [availableServices_ containsObject:serviceName];
  BOOL serviceIsOnline = ([service status] == IMServiceStatusLoggedIn);
  if (serviceWasOnline != serviceIsOnline) {
    if (serviceWasOnline) {
      [availableServices_ addObject:serviceName];
    } else {
      [availableServices_ removeObject:serviceName];
    }
  }
}

- (void)myStatusChangedNotification:(NSNotification*)notification {
  IMPersonStatus myStatus = [IMService myStatus];
  BOOL iAmOnline = (myStatus == IMPersonStatusIdle
                            || myStatus == IMPersonStatusAway
                            || myStatus == IMPersonStatusAvailable);
  if (iAmOnline != iWasOnline_) {
    iWasOnline_ = iAmOnline;
  }
}

- (HGSResult *)contactResultFromIMBuddy:(NSDictionary *)imBuddy
                                service:(IMService *)service
                                 source:(HGSSearchSource *)source {
  // Both a screen name and service name are required.
  NSString *screenName = imBuddy ? [imBuddy objectForKey:IMPersonScreenNameKey]
    : nil;
  // Note: The service name is taken from the service rather than
  // from the buddy since for Bonjour the service renders 'Bonjour'
  // while the buddy renders 'SubNet'.
  NSString *serviceName = [service name];
  
  if ([screenName length] == 0 || [serviceName length] == 0) {
    return nil;
  }
  
  NSString *identifier
    = [NSString stringWithFormat:@"ichat:compose?service=%@&id=%@&style=im",
       [serviceName gtm_stringByEscapingForURLArgument],
       [screenName gtm_stringByEscapingForURLArgument]];
  NSURL *url = [NSURL URLWithString:identifier];
  NSMutableString *displayName = [NSMutableString string];
  
  // NOTE: It's possible that the IMBuddy will provide an NSNull for the
  // first and/or last name so we must insure that we detect such case.
  NSString *firstName = [imBuddy objectForKey:IMPersonFirstNameKey];
  if ([firstName isKindOfClass:[NSString class]] && [firstName length]) {
    [displayName appendString:firstName];
  }
  NSString *lastName = [imBuddy objectForKey:IMPersonLastNameKey];
  if ([lastName isKindOfClass:[NSString class]] && [lastName length]) {
    if ([displayName length]) {
      [displayName appendString:@" "];
    }
    [displayName appendString:lastName];
  }
  
  if ([displayName length]) [displayName appendString:@" "];
  [displayName appendFormat:@"(%@: %@)", serviceName, screenName];
  
  // This is a list of the attributes that we will retain
  // from the buddy's information dictionary before composing
  // the cached result.
  NSString *imAttributeKeys[] = {
    IMPersonScreenNameKey,
    IMPersonFirstNameKey,
    IMPersonLastNameKey,
    IMPersonEmailKey,
  };
  size_t count = sizeof(imAttributeKeys) / sizeof(NSString*);
  NSMutableDictionary *imBuddyInfo
    = [NSMutableDictionary dictionaryWithCapacity:count];
  for (size_t i = 0; i < count; ++i) {
    NSString *imKey = imAttributeKeys[i];
    id itemToRetain = [imBuddy objectForKey:imKey];
    if (itemToRetain) {
      [imBuddyInfo setObject:itemToRetain forKey:imKey];
    }
  }
  // Set serviceName from service, not from buddy.
  [imBuddyInfo setObject:serviceName forKey:IMPersonServiceNameKey];
  
  NSArray *uniqueIdentifiers = [NSArray arrayWithObject:screenName];
  NSDictionary *attributes
    = [NSDictionary dictionaryWithObjectsAndKeys:
       uniqueIdentifiers, kHGSObjectAttributeUniqueIdentifiersKey,
       imBuddyInfo, kChatBuddyAttributeInformationKey,
       nil];
  return [HGSResult resultWithURL:url
                             name:displayName
                             type:HGS_SUBTYPE(kHGSTypeContact, @"ichat")
                           source:source
                       attributes:attributes];
}

@end
