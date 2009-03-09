//
//  FileSystemActions.m
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
#import "FilesystemActions.h"
#import "GTMMethodCheck.h"
#import "GTMNSAppleScript+Handler.h"
#import "GTMGarbageCollection.h"
#import "QLUIPrivate.h"

@interface FileSystemOpenAction : HGSAction
@end

@interface FileSystemOpenWithAction : FileSystemOpenAction
@end

@interface FileSystemQuickLookAction : HGSAction
@end

@interface FileSystemScriptAction : HGSAction
+ (NSAppleScript *)fileSystemActionScript;
- (NSString *)handlerName;
@end

@interface FileSystemShowInFinderAction : FileSystemScriptAction
@end

@interface FileSystemGetInfoAction : FileSystemScriptAction
@end


@interface FileSystemEjectAction : HGSAction
@end

@implementation FileSystemOpenWithAction

// TODO(alcor): for now this behaves as Open, support indirects.

@end

@implementation FileSystemOpenAction

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSImage *icon = [ws iconForFileType:@"rtf"];
    defaultObject = icon;
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
     = [info objectForKey:kHGSActionDirectObjectsKey];
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSArray *urls = [directObjects urls];
  BOOL wasGood = YES;
  for (NSURL *url in urls) {
    wasGood != [ws openURL:url];
  }
  return wasGood;
}

- (id)displayIconForResults:(HGSResultArray*)results {
  NSImage *icon = nil;
  if ([results count] > 1) {
    icon = [super displayIconForResults:results];
  } else {
    HGSResult *result = [results objectAtIndex:0];
    NSURL *url = [result url];
  
    BOOL isDirectory = NO;
    if ([url isFileURL]) {
      [[NSFileManager defaultManager] fileExistsAtPath:[url path]
                                           isDirectory:&isDirectory];
    }
    
    if (isDirectory) {
      NSWorkspace *ws = [NSWorkspace sharedWorkspace];
      NSString *finderPath
        = [ws absolutePathForAppBundleWithIdentifier:@"com.apple.finder"];
      icon = [ws iconForFile:finderPath];
    } else {
      CFURLRef appURL = NULL;
      if (url && noErr == LSGetApplicationForURL((CFURLRef)url,
                                                 kLSRolesViewer,
                                                 NULL, &appURL)) {
        GTMCFAutorelease(appURL);
        icon =  [[NSWorkspace sharedWorkspace] iconForFile:[(NSURL *)appURL path]];
      }
    }
  }
  return icon;
}

- (BOOL)appliesToResults:(HGSResultArray *)results {
  // If we have an icon, then we probably apply.
  return [self displayIconForResults:results] != nil;
}
@end

@implementation FileSystemScriptAction

+ (NSAppleScript *)fileSystemActionScript {
  static NSAppleScript *fileSystemActionScript = nil;
  if (!fileSystemActionScript) {
    NSBundle *bundle = HGSGetPluginBundle();
    NSString *path = [bundle pathForResource:@"FileSystemActions"
                                      ofType:@"scpt" 
                                 inDirectory:@"Scripts"];
    if (path) {
      NSURL *url = [NSURL fileURLWithPath:path];
      NSDictionary *error = nil;
      fileSystemActionScript 
        = [[NSAppleScript alloc] initWithContentsOfURL:url 
                                                 error:&error];
      if (error) {
        HGSLog(@"Unable to load %@. Error: %@", url, error);
      }
    } else {
      HGSLog(@"Unable to find script FileSystemActions.scpt");
    }
  }
  return fileSystemActionScript;
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
     = [info objectForKey:kHGSActionDirectObjectsKey];
  NSArray *args = [directObjects filePaths];
  NSDictionary *error = nil;
  NSAppleScript *script = [FileSystemScriptAction fileSystemActionScript];
  NSString *handlerName = [self handlerName];
  NSAppleEventDescriptor *answer
    = [script gtm_executePositionalHandler:handlerName
                                parameters:[NSArray arrayWithObject:args]
                                     error:&error];
  BOOL isGood = YES;
  if (!answer || error) {
    HGSLogDebug(@"Unable to execute handler %@: %@", error);
    isGood = NO;
  }
  return isGood;
}

- (NSString *)handlerName {
  HGSAssert(@"handlerName must be overridden by subclasses", nil);
  return nil;
}
@end

@implementation FileSystemShowInFinderAction

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    defaultObject = [NSImage imageNamed:NSImageNameRevealFreestandingTemplate];
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (NSString *)handlerName {
  return @"showInFinder";
}

@end

@implementation FileSystemQuickLookAction
  
- (BOOL)causesUIContextChange {
  return NO;
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
    = [info objectForKey:kHGSActionDirectObjectsKey];
  NSArray *urls = [directObjects urls];
  QLPreviewPanel *panel = [QLPreviewPanel sharedPreviewPanel];
  [panel setHidesOnDeactivate:NO];
  BOOL changed = ![urls isEqualToArray:[panel URLs]];
  [panel setURLs:urls currentIndex:0 preservingDisplayState:YES];
  if (![panel isVisible] || changed) {
    [NSApp activateIgnoringOtherApps:YES];
    [[panel windowController] setDelegate:self];
    [panel makeKeyAndOrderFrontWithEffect:QLZoomEffect];
  } else {
    [panel closeWithEffect:QLZoomEffect]; 
  }
  return YES;
}

@end

@implementation FileSystemGetInfoAction

GTM_METHOD_CHECK(NSAppleScript, gtm_executePositionalHandler:parameters:error:);

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    defaultObject = [NSImage imageNamed:NSImageNameInfo];
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (NSString *)handlerName {
  return @"getInfo";
}

@end

@implementation FileSystemEjectAction

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    
    IconRef iconRef = NULL;
    GetIconRef(kOnSystemDisk,
               kSystemIconsCreator,
               kEjectMediaIcon, 
               &iconRef);
    
    NSImage *image = nil;
    if (iconRef) {
      image = [[[NSImage alloc] initWithIconRef:iconRef] autorelease];
      ReleaseIconRef(iconRef);
    } 
    
    defaultObject = image;
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
     = [info objectForKey:kHGSActionDirectObjectsKey];
  
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSArray *filePaths = [directObjects filePaths];
  
  BOOL success = YES;
  for (NSString *path in filePaths) {
    // if workspace can't do it, try the finder.
    if (![workspace unmountAndEjectDeviceAtPath:path]){
      NSString *displayName
        = [[NSFileManager defaultManager] displayNameAtPath:path];
      NSString *source = [NSString stringWithFormat:
        @"tell application \"Finder\" to eject disk \"%@\"",displayName];
      NSAppleScript *ejectScript
        = [[[NSAppleScript alloc] initWithSource:source] autorelease]; 
      NSDictionary *errorDict = nil;
      [ejectScript executeAndReturnError:&errorDict];
      if (errorDict) {
        NSString *error
        = [errorDict objectForKey:NSAppleScriptErrorBriefMessage];
        HGSLog(@"Error ejecting disk %@: %@", path, error);
        NSBeep();
        success = NO;
      }
    }
  }
  return success;
}

- (BOOL)appliesToResults:(HGSResultArray *)results {
  BOOL doesApply = [super appliesToResults:results];
  if (doesApply) {
    NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
    NSArray *filePaths = [results filePaths];
    if (filePaths) {
      NSArray *volumes = [workspace mountedLocalVolumePaths];
      NSSet *volumesSet = [NSSet setWithArray:volumes];
      NSSet *pathsSet = [NSSet setWithArray:filePaths];
      doesApply = [pathsSet intersectsSet:volumesSet];
    } else {
      doesApply = NO;
    }
  }
  return doesApply;
}


@end
