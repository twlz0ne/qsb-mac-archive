//
//  HGSPluginBlacklist.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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

#import "HGSPluginBlacklist.h"
#import "HGSPluginLoader.h"
#import "HGSDelegate.h"
#import "HGSLog.h"
#import "GTMObjectSingleton.h"
#import <GData/GDataHTTPFetcher.h>
#import <stdlib.h>

static NSString* const kHGSPluginBlacklistFile = @"PluginBlacklist";
static NSString* const kHGSPluginBlacklistVersionKey = @"HGSPBVersion";
static NSString* const kHGSPluginBlacklistEntriesKey = @"HGSPBEntries";
static NSString* const kHGSPluginBlacklistLastUpdateKey = @"HGSPBLastUpdate";
static NSString* const kHGSPluginBlacklistVersion = @"1";
static const NSTimeInterval kHGSPluginBlacklistUpdateInterval = 86400; // 1 day
static const NSTimeInterval kHGSPluginBlacklistJitterRange = 3600; // 1 hour
static NSString* const kHGSPluginBlacklistURL
  = @"https://dl.google.com/mac/data/qsb/blacklist.xml";
NSString* kHGSBlacklistUpdatedNotification = @"HGSBlacklistUpdatedNotification";

@interface HGSPluginBlacklist()
- (NSTimeInterval)jitter;
@end

@implementation HGSPluginBlacklist

GTMOBJECT_SINGLETON_BOILERPLATE(HGSPluginBlacklist, sharedPluginBlacklist);

@synthesize blacklistPath = blacklistPath_;

- (id)init {
  self = [super init];
  if (self) {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    srand((int)now);
    id<HGSDelegate> delegate = [[HGSPluginLoader sharedPluginLoader] delegate];
    NSString *appSupportPath = [delegate userCacheFolderForApp];
    blacklistPath_
      = [[appSupportPath
         stringByAppendingPathComponent:kHGSPluginBlacklistFile] retain];
    NSTimeInterval lastUpdate = 0;
    if (blacklistPath_) {
      @try {
        NSDictionary *blacklist
          = [NSDictionary dictionaryWithContentsOfFile:blacklistPath_];
        if (blacklist) {
          NSString *version
            = [blacklist objectForKey:kHGSPluginBlacklistVersionKey];
          if ([version isEqualToString:kHGSPluginBlacklistVersion]) {
            blacklistedBundleIDs_
              = [[blacklist objectForKey:kHGSPluginBlacklistEntriesKey] retain];
            lastUpdate
              = [[blacklist objectForKey:kHGSPluginBlacklistLastUpdateKey]
                 doubleValue];
          }
        }
      }
      @catch(NSException *e) {
        HGSLog(@"Unable to load blacklist for %@ (%@)", self, e);
      }
    }
    if (lastUpdate < now - (int)kHGSPluginBlacklistUpdateInterval) {
      [self updateBlacklist:self];
    } else {
      NSTimeInterval interval
        = kHGSPluginBlacklistUpdateInterval + [self jitter];
      updateTimer_
        = [NSTimer scheduledTimerWithTimeInterval:interval
                                           target:self
                                         selector:@selector(updateBlacklist:)
                                         userInfo:nil
                                          repeats:NO];
    }
  }
  return self;
}

// COV_NF_START
// Singleton, so this is never called.
- (void)dealloc {
  if ([updateTimer_ isValid]) {
    [updateTimer_ invalidate];
  }
  [blacklistPath_ release];
  [blacklistedBundleIDs_ release];
  [super dealloc];
}
// COV_NF_END

- (BOOL)bundleIsBlacklisted:(NSBundle *)pluginBundle {
  return [self bundleIDIsBlacklisted:[pluginBundle bundleIdentifier]];
}

- (BOOL)bundleIDIsBlacklisted:(NSString *)bundleID {
  BOOL isBlacklisted;
  bundleID = [bundleID lowercaseString];
  @synchronized(self) {
    isBlacklisted = [blacklistedBundleIDs_ containsObject:bundleID];
  }
  return isBlacklisted;
}

-(void)updateBlacklist:(id)sender {
  NSURL *url = [NSURL URLWithString:kHGSPluginBlacklistURL];
  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  GDataHTTPFetcher *fetcher
    = [GDataHTTPFetcher httpFetcherWithRequest:request];
  [fetcher setIsRetryEnabled:YES];
  [fetcher beginFetchWithDelegate:self
                didFinishSelector:@selector(blacklistFetcher:
                                            finishedWithData:)
                  didFailSelector:@selector(blacklistFetcher:
                                            failedWithError:)];
  if ([updateTimer_ isValid]) {
    [updateTimer_ invalidate];
  }
  NSTimeInterval interval = kHGSPluginBlacklistUpdateInterval + [self jitter];
  updateTimer_
    = [NSTimer scheduledTimerWithTimeInterval:interval
                                       target:self
                                     selector:@selector(updateBlacklist:)
                                     userInfo:nil
                                      repeats:NO];
}

- (NSTimeInterval)jitter {
  return (NSTimeInterval)(rand() % (int)kHGSPluginBlacklistJitterRange);
}

- (void)blacklistFetcher:(GDataHTTPFetcher *)fetcher
        finishedWithData:(NSData *)data {
  NSInteger statusCode = [fetcher statusCode];
  if (statusCode == 200) {
    [self updateBlacklistWithData:data];
  } else {
    HGSLog(@"Unable to refresh blacklist for %@ (%i)", self, statusCode);
  }
}

- (void)updateBlacklistWithData:(NSData *)data {
  NSError *error;
  NSXMLDocument *doc
    = [[[NSXMLDocument alloc] initWithData:data
                                    options:0
                                      error:&error] autorelease];
  if (doc) {
    NSMutableArray *newBlacklist = [NSMutableArray array];
    NSArray *guids = [doc nodesForXPath:@"//guid" error:nil];
    for (NSXMLNode *guid in guids) {
      [newBlacklist addObject:[[guid stringValue] lowercaseString]];
    }
    [blacklistedBundleIDs_ release];
    @synchronized(self) {
      blacklistedBundleIDs_ = [newBlacklist retain];
      NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
      NSDictionary *cacheDict =
        [NSDictionary dictionaryWithObjectsAndKeys:
         kHGSPluginBlacklistVersion, kHGSPluginBlacklistVersionKey,
         blacklistedBundleIDs_, kHGSPluginBlacklistEntriesKey,
         [NSNumber numberWithDouble:now], kHGSPluginBlacklistLastUpdateKey,
         nil];
      if (![cacheDict writeToFile:blacklistPath_ atomically:YES]) {
        HGSLogDebug(@"Unable to save blacklist to %@", blacklistPath_);
      }
    }
  } else {
    HGSLog(@"Unable to refresh blacklist for %@ (%@)", self, error);
  }
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSBlacklistUpdatedNotification object:self];
}

- (void)blacklistFetcher:(GDataHTTPFetcher *)fetcher
         failedWithError:(NSError *)error {
  HGSLog(@"Unable to refresh blacklist for %@ (%@)", self, error);
}

@end
