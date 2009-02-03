//
//  ApplescriptPluginsAction.m
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

#import "ApplescriptPluginsAction.h"
#import "GTMNSAppleEventDescriptor+Handler.h"
#import "GTMNSAppleEventDescriptor+Foundation.h"
#import "GTMNSAppleScript+Handler.h"

NSString *const kHGSAppleScriptPListVersionKey = @"HGSAppleScriptPListVersionKey";
NSInteger const kHGSAppleScriptCurrentVersion = 1;
NSString *const kHGSAppleScriptScriptsKey = @"HGSAppleScriptScriptsKey";
NSString *const kHGSAppleScriptDisplayNameKey = @"HGSAppleScriptDisplayNameKey";
NSString *const kHGSAppleScriptIconKey = @"HGSAppleScriptIconKey";
NSString *const kHGSAppleScriptDescriptionKey = @"HGSAppleScriptDescriptionKey";
NSString *const kHGSAppleScriptHandlerKey = @"HGSAppleScriptHandlerKey";
NSString *const kHGSAppleScriptDisplayInGlobalResultsKey = @"HGSAppleScriptDisplayInGlobalResultsKey";
NSString *const kHGSAppleScriptSupportedTypesKey = @"HGSAppleScriptSupportedTypesKey";
NSString *const kHGSAppleScriptRequiredRunningAppKey = @"HGSAppleScriptRequiredRunningAppKey";
NSString *const kHGSAppleScriptSwitchContextsKey = @"HGSAppleScriptSwitchContextsKey";

@interface NSObject (AppleScriptPluginsActionPrivate)
- (id)as_performSelectorOnMainThread:(SEL)selector withObject:(id)object;
@end

@interface AppleScriptPluginsAction (AppleScriptPluginsActionPrivate)
- (BOOL)requiredAppRunning;
@end

@implementation AppleScriptPluginsAction
- (id)initWithScript:(NSAppleScript *)script 
                path:(NSString *)path
          attributes:(NSDictionary *)attributes {
  NSString *handlerName = [attributes objectForKey:kHGSAppleScriptHandlerKey];
  NSString *name = [[path lastPathComponent] stringByDeletingPathExtension];
  NSString *displayName 
    = [attributes objectForKey:kHGSAppleScriptDisplayNameKey];
  if (!displayName) {
    displayName = name;
  }
  NSString *iconPath = [attributes objectForKey:kHGSAppleScriptIconKey];
  NSImage *icon = nil;
  if (iconPath) {
    if (![iconPath isAbsolutePath]) {
      NSBundle *iconBundle = [NSBundle bundleWithPath:path];
      NSString *bundlePath = [iconBundle resourcePath];
      if (bundlePath) {
        iconPath = [bundlePath stringByAppendingPathComponent:iconPath];
      }
    }
    if (iconPath) {
      icon = [[[NSImage alloc] initByReferencingFile:iconPath] autorelease];
    }
  }
  if (!icon) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    icon = [ws iconForFile:path];
  }
  NSString *description 
    = [attributes objectForKey:kHGSAppleScriptDescriptionKey];
  BOOL displayInGlobalResults
    = [[attributes objectForKey:kHGSAppleScriptDisplayInGlobalResultsKey] boolValue];
  if (!displayInGlobalResults && !handlerName) {
    // if we don't have a handler
    displayInGlobalResults = ![script gtm_hasOpenDocumentsHandler];
  }
  NSString *requiredAppID 
    = [attributes objectForKey:kHGSAppleScriptRequiredRunningAppKey];
  NSArray *supportedTypesArray
    = [attributes objectForKey:kHGSAppleScriptSupportedTypesKey];
  if ([supportedTypesArray isKindOfClass:[NSString string]]) {
    supportedTypesArray = [NSArray arrayWithObject:supportedTypesArray];
  }
  NSNumber *switchContext 
    = [attributes objectForKey:kHGSAppleScriptSwitchContextsKey];
  
  // TODO(dmaclach): fix this jury rigged AppleScript support ASAP
  static int count = 0;
  NSString *identifier 
    = [NSString stringWithFormat:@"com.google.qsb.applescript.action.%d", 
       count++];
  NSDictionary *configuration = [NSDictionary dictionaryWithObjectsAndKeys:
                                 identifier, kHGSExtensionIdentifierKey,
                                 name, kHGSExtensionUserVisibleNameKey,
                                 icon, kHGSExtensionIconImageKey,
                                 nil];
  if ((self = [super initWithConfiguration:configuration])) {
    if (script) {
      script_ = [script retain];
      displayName_ = [displayName retain];
      description_ = [description retain];
      handler_ = [handlerName retain];
      requiredRunningAppBundleID_ = [requiredAppID retain];
      if ([supportedTypesArray count] > 0) {
        supportedTypes_ = [[NSSet alloc] initWithArray:supportedTypesArray];
      }
      displayInGlobalResults_ = displayInGlobalResults;
      switchContexts_ = switchContext ? [switchContext boolValue] : YES;
    } else {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [script_ release];
  [displayName_ release];
  [description_ release];
  [handler_ release];
  [requiredRunningAppBundleID_ release];
  [supportedTypes_ release];
  [super dealloc];
}

- (NSNumber*)performActionWithInfoInternal:(NSDictionary*)info {
  // If we have a handler we call it
  // if not and it supports open, we call that
  // otherwise we just run the script.
  BOOL wasGood = NO;
  NSString *handler = handler_;
  if (!handler) {
    if ([script_ gtm_hasOpenDocumentsHandler]) {
      handler = @"aevtodoc";
    }
  }
  NSDictionary *error = nil;
  if (handler) {
    HGSObject *object = [info objectForKey:kHGSActionPrimaryObjectKey];
    NSURL *uri = [object identifier];
    NSString *uriString = [uri isFileURL] ? [uri path] : [uri absoluteString];
    NSArray *params = [NSArray arrayWithObjects:uriString, nil];
    
    [script_ gtm_executePositionalHandler:handler 
                               parameters:params 
                                    error:&error];
  } else {
    [script_ executeAndReturnError:&error];
  }
  if (!error) {
    wasGood = YES;
  } else {
    //TODO(dmaclach): Handle error logging to user better
    HGSLogDebug(@"Applescript Error: %@", error);
  }
  return [NSNumber numberWithBool:wasGood];
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  NSNumber *val 
    = [self as_performSelectorOnMainThread:@selector(performActionWithInfoInternal:) 
                                withObject:info];
  return [val boolValue];
}  

- (NSString*)displayNameForResult:(HGSObject*)result {
  NSString *resultName = [result displayName]; 
  return [NSString stringWithFormat:displayName_, resultName];
}

- (NSSet*)directObjectTypes {
  return supportedTypes_;
}

- (BOOL)doesActionApplyTo:(HGSObject*)object {
  BOOL applies = [self requiredAppRunning];
  return applies;
}
 
- (BOOL)doesActionCauseUIContextChange {
  return switchContexts_;
}

- (BOOL)showActionInGlobalSearchResults {
  return displayInGlobalResults_ && [self requiredAppRunning];
}

- (BOOL)requiredAppRunning {
  BOOL running = NO;
  if (requiredRunningAppBundleID_) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSArray *apps = [ws launchedApplications];
    NSArray *bundleIDs = [apps valueForKey:@"NSApplicationBundleIdentifier"];
    for (NSString *bundleID in bundleIDs) {
      if ([bundleID caseInsensitiveCompare:requiredRunningAppBundleID_] == NSOrderedSame) {
        running = YES;
        break;
      }
    }
  } else {
    running = YES;
  }
  return running;
}
@end

@implementation NSObject (HGSApplescriptPluginsActionPrivate)
- (void)as_selectorPerformer:(NSMutableDictionary *)dict {
  SEL selector = NSSelectorFromString([dict objectForKey:@"Selector"]);
  id ret = [self performSelector:selector 
                      withObject:[dict objectForKey:@"Arg"]];
  if (ret) {
    [dict setObject:ret forKey:@"Return"];
  }
}

- (id)as_performSelectorOnMainThread:(SEL)selector withObject:(id)object {
  NSMutableDictionary *dict 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       NSStringFromSelector(selector), @"Selector",
       object, @"Arg", nil];
  [self performSelectorOnMainThread:@selector(as_selectorPerformer:) 
                         withObject:dict 
                      waitUntilDone:YES];
  return [dict objectForKey:@"Return"];
}
@end
