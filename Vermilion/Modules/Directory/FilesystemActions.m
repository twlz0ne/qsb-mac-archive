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
#import "QSBApplicationDelegate.h"
#import "QSBSearchWindowController.h"

@interface FileSystemOpenAction : HGSAction
@end

@interface FileSystemShowInFinderAction : HGSAction
@end

@interface FileSystemQuickLookAction : HGSAction
@end

@interface FileSystemGetInfoAction : HGSAction {
@private
  NSAppleScript *script_;
}
@end

const OSType kToolbarAppsFolderIcon = 'tAps';
const OSType kToolbarInfoIcon = 'tbin';

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

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSURL *url = [object valueForKey:kHGSObjectAttributeURIKey];
  BOOL wasGood = [ws openURL:url];
  return wasGood;
}

- (id)displayIconForResult:(HGSObject*)result {
  CFURLRef url = (CFURLRef)[result valueForKey:kHGSObjectAttributeURIKey];
  CFURLRef appURL = NULL;
  if (url && noErr == LSGetApplicationForURL(url,
                                             kLSRolesViewer,
                                             NULL, &appURL)) {
    
    GTMCFAutorelease(appURL);
    return [[NSWorkspace sharedWorkspace] iconForFile:[(NSURL *)appURL path]];
  }
  return nil;
}

@end

@implementation FileSystemShowInFinderAction

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSString *finderPath
      = [ws absolutePathForAppBundleWithIdentifier:@"com.apple.finder"];
    NSImage *icon = [ws iconForFile:finderPath];
    defaultObject = icon;
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSURL *url = [object valueForKey:kHGSObjectAttributeURIKey];
  return [ws selectFile:[url path] inFileViewerRootedAtPath:@""];
}

@end


@implementation FileSystemQuickLookAction
  
- (BOOL)doesActionCauseUIContextChange {
  return NO;
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSURL *url = [object valueForKey:kHGSObjectAttributeURIKey];
  NSArray *urls = [NSArray arrayWithObject:url];
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

- (NSRect)previewPanel:(NSPanel*)panel frameForURL:(NSURL*)URL {
  QSBApplicationDelegate *delegate = [NSApp delegate];
  NSView *previewView = [[delegate searchWindowController] previewImageView];
  NSRect frame = [previewView bounds];
  frame.origin = [[previewView window] convertBaseToScreen:
                  [previewView convertPoint:NSZeroPoint toView:nil]];
  return  frame;
}

@end

@implementation FileSystemGetInfoAction

GTM_METHOD_CHECK(NSAppleScript, gtm_executePositionalHandler:parameters:error:);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSString *source = @"on getFileInfo(x)\r"
    @"tell application \"Finder\"\r"
    @"activate\r"
    @"set macpath to POSIX file x as text\r"
    @"open information window of item macpath\r"
    @"end tell\r"
    @"end getInfo\r";
    script_ = [[NSAppleScript alloc] initWithSource:source];
  }
  return self;
}

- (void)dealloc {
  [script_ release];
  [super dealloc];
}

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    NSImage *icon 
      = [ws iconForFileType:NSFileTypeForHFSTypeCode(kToolbarInfoIcon)];
    defaultObject = icon;
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSURL *url = [object valueForKey:kHGSObjectAttributeURIKey];
  HGSAssert([url isFileURL], @"Must be file URL");
  NSDictionary *dictionary = nil;
  NSAppleEventDescriptor *answer;
  NSArray *args = [NSArray arrayWithObject:[url path]];
  answer = [script_ gtm_executePositionalHandler:@"getFileInfo" 
                                      parameters:args
                                           error:&dictionary];
  if (!answer || dictionary) {
    HGSLogDebug(@"Unable to getInfo: %@", dictionary);
    return NO;
  }
  return YES;
}

@end
