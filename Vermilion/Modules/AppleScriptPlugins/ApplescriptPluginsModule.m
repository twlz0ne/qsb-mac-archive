//
//  AppleScriptPluginsModule.m
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
#import "AppleScriptPluginsAction.h"

@interface AppleScriptPluginsModule : HGSExtension
@end

@implementation AppleScriptPluginsModule
- (void)registerAppleScript:(NSAppleScript*)script
                 withLoader:(HGSPluginLoader *)loader
                       path:(NSString*)path {  
  NSArray *scripts = nil;
  if ([[path pathExtension] caseInsensitiveCompare:@"scptd"] == NSOrderedSame) {
    NSBundle *scriptBundle = [NSBundle bundleWithPath:path];
    NSString *plistPath 
      = [scriptBundle pathForResource:@"QSBPlugin" ofType:@"plist"];
    NSDictionary *plistDict 
      = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSNumber *version = [plistDict objectForKey:kHGSAppleScriptPListVersionKey];
    if ([version intValue] != kHGSAppleScriptCurrentVersion) return;
    scripts = [plistDict objectForKey:kHGSAppleScriptScriptsKey];
  } else {
    scripts = [NSArray arrayWithObject:[NSDictionary dictionary]];
  }
  for (NSDictionary *scriptDefn in scripts) {
    AppleScriptPluginsAction *actionObj 
      = [[[AppleScriptPluginsAction alloc] initWithScript:script
                                                     path:path
                                               attributes:scriptDefn]
       autorelease];
    HGSExtensionPoint *actionPoint = [HGSExtensionPoint actionsPoint];
    [actionPoint extendWithObject:actionObj];
  }
}

- (void)registerAppleScript:(NSString*)scriptPath
                 withLoader:(HGSPluginLoader *)loader {
  NSURL *url = [NSURL fileURLWithPath:scriptPath];
  NSDictionary *error = nil;
  NSAppleScript *script = [[[NSAppleScript alloc] initWithContentsOfURL:url
                                                                  error:&error] 
                           autorelease];
  if (!script) {
    HGSLogDebug(@"Couldn't load script at %@ (%@)", scriptPath, error);
  } else {
    [self registerAppleScript:script 
                   withLoader:loader 
                         path:scriptPath];
  }
}

- (void)registerAppleScripts:(NSArray*)scripts 
                  withLoader:(HGSPluginLoader *)loader {
  NSEnumerator *enumerator = [scripts objectEnumerator];
  NSString *path;
  while ((path = [enumerator nextObject])) {
    [self registerAppleScript:path withLoader:loader];
  }
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    HGSPluginLoader *loader = [HGSPluginLoader sharedPluginLoader];
    id<HGSDelegate> delegate = [loader delegate];
    NSArray *pluginFolders = [delegate pluginFolders];
    for (NSString *path in pluginFolders) {
      NSArray *scptPlugins = [NSBundle pathsForResourcesOfType:@"scpt"
                                                   inDirectory:path];
      NSArray *appleScriptPlugins
      = [NSBundle pathsForResourcesOfType:@"applescript"
                              inDirectory:path];
      NSArray *scptdPlugins = [NSBundle pathsForResourcesOfType:@"scptd"
                                                    inDirectory:path];
      
      [self registerAppleScripts:scptPlugins withLoader:loader];
      [self registerAppleScripts:appleScriptPlugins withLoader:loader];
      [self registerAppleScripts:scptdPlugins withLoader:loader];
    }
  }
  return self;
}

@end
