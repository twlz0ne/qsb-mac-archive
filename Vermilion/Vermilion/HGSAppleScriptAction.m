//
//  HGSAppleScriptAction.m
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

#import "HGSAppleScriptAction.h"
#import "HGSLog.h"
#import "HGSBundle.h"
#import "GTMNSAppleScript+Handler.h";
#import "HGSResult.h"
#import "GTMNSWorkspace+Running.h"
#import "GTMMethodCheck.h"
#import "GTMNSAppleEventDescriptor+Foundation.h"

NSString *const kHGSAppleScriptFileNameKey = @"HGSAppleScriptFileName";
NSString *const kHGSAppleScriptHandlerNameKey = @"HGSAppleScriptHandlerName";
NSString *const kHGSAppleScriptApplicationsKey = @"HGSAppleScriptApplications";
NSString *const kHGSAppleScriptBundleIDKey = @"HGSAppleScriptBundleID";
NSString *const kHGSAppleScriptMustBeRunningKey 
  = @"HGSAppleScriptMustBeRunning";
static NSString *const kHGSOpenDocAppleEvent = @"aevtodoc";

@interface HGSAppleScriptAction ()
- (BOOL)requiredAppsRunning:(HGSResultArray *)results;
@end

@implementation HGSAppleScriptAction
GTM_METHOD_CHECK(NSWorkspace, gtm_isAppWithIdentifierRunning:);
GTM_METHOD_CHECK(NSAppleScript, gtm_hasOpenDocumentsHandler);
GTM_METHOD_CHECK(NSAppleScript, gtm_executePositionalHandler:parameters:error:); 
GTM_METHOD_CHECK(NSAppleScript, gtm_executeAppleEvent:error:); 
GTM_METHOD_CHECK(NSAppleScript, gtm_appleEventDescriptor);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSString *fileName = [configuration objectForKey:kHGSAppleScriptFileNameKey];
    if (!fileName) {
      fileName = @"main";
    }
    NSBundle *bundle = [configuration objectForKey:kHGSExtensionBundleKey];
    NSString *scriptPath = [bundle pathForResource:fileName 
                                            ofType:@"scpt" 
                                       inDirectory:@"Scripts"];
    if (!scriptPath) {
      scriptPath = [bundle pathForResource:fileName 
                                    ofType:@"applescript" 
                               inDirectory:@"Scripts"];
    }
    NSDictionary *err = nil;
    if (scriptPath) {
      NSURL *url = [NSURL fileURLWithPath:scriptPath];
      
      script_ = [[NSAppleScript alloc] initWithContentsOfURL:url error:&err];
    }
    if (!script_) {
      [self release];
      self = nil;
      HGSLog(@"Unable to load script %@ (%@)", fileName, err);
    } else {
      handlerName_ = [configuration objectForKey:kHGSAppleScriptHandlerNameKey];
      if (!handlerName_ && [script_ gtm_hasOpenDocumentsHandler]) {
        handlerName_ = kHGSOpenDocAppleEvent;
      }
      [handlerName_ retain];
      requiredApplications_ 
        = [[configuration objectForKey:kHGSAppleScriptApplicationsKey] 
           retain];
    }
  }
  return self;
}

- (void)dealloc {
  [handlerName_ release];
  [requiredApplications_ release];
  [script_ release];
  [super dealloc];
}

- (BOOL)requiredAppsRunning:(HGSResultArray *)results {
  BOOL areRunning = YES;
  NSMutableArray *resultBundleIDs = nil;
  if (results) {
    NSInteger count = [results count];
    resultBundleIDs = [NSMutableArray arrayWithCapacity:count];
    for (HGSResult *result in  results) {
      NSString *bundleID = [result valueForKey:kHGSObjectAttributeBundleIDKey];
      if (bundleID) {
        [resultBundleIDs addObject:bundleID];
      }
    }
  }
  if (areRunning) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    for (NSDictionary *requiredApp in requiredApplications_) {
      NSString *bundleID 
        = [requiredApp objectForKey:kHGSAppleScriptBundleIDKey];
      if (resultBundleIDs) {
        areRunning = [resultBundleIDs containsObject:bundleID];
      }
      if (areRunning) {
        NSNumber *nsRunning 
          = [requiredApp objectForKey:kHGSAppleScriptMustBeRunningKey];
        if (nsRunning) {
          BOOL running = [nsRunning boolValue];
          if (running) {
            areRunning = [ws gtm_isAppWithIdentifierRunning:bundleID];
          }
        }
      }
      if (!areRunning) break;
    }
  }
  return areRunning;
}

- (BOOL)appliesToResults:(HGSResultArray *)results {
  BOOL doesApply = NO;
  if (requiredApplications_) {
    doesApply = [self requiredAppsRunning:results];
  } else {
    doesApply = [super appliesToResults:results];
  }
  return doesApply;
}

- (BOOL)showInGlobalSearchResults {
  BOOL showInResults = [super showInGlobalSearchResults];
  if (showInResults) {
    showInResults = [self requiredAppsRunning:nil];
  }
  return showInResults;
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  // If we have a handler we call it
  // if not and it supports open, we call that
  // otherwise we just run the script.
  BOOL wasGood = NO;
  NSDictionary *error = nil;
  if (handlerName_) {
    HGSResultArray *directObjects 
      = [info objectForKey:kHGSActionDirectObjectsKey];
    NSArray *urls = [directObjects urls];
    
    if ([handlerName_ isEqualToString:kHGSOpenDocAppleEvent]) {
      NSAppleEventDescriptor *target 
        = [[NSProcessInfo processInfo] gtm_appleEventDescriptor];
      NSAppleEventDescriptor *openDoc 
        = [NSAppleEventDescriptor appleEventWithEventClass:kCoreEventClass 
                                                   eventID:kAEOpenDocuments
                                          targetDescriptor:target 
                                                  returnID:kAutoGenerateReturnID 
                                             transactionID:kAnyTransactionID];
      [openDoc setParamDescriptor:[urls gtm_appleEventDescriptor]
                       forKeyword:keyDirectObject];
      [script_ gtm_executeAppleEvent:openDoc error:&error];
    } else {
      NSArray *params = [NSArray arrayWithObjects:urls, nil];
      
      [script_ gtm_executePositionalHandler:handlerName_ 
                                 parameters:params 
                                      error:&error];
    }
  } else {
    [script_ executeAndReturnError:&error];
  }
  if (!error) {
    wasGood = YES;
  } else {
    //TODO(dmaclach): Handle error logging to user better
    HGSLogDebug(@"Applescript Error: %@", error);
  }
  return wasGood;
}


@end
