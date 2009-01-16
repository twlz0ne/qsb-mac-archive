//
//  HGSModuleLoader.m
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
#import "HGSModuleLoader.h"
#import "HGSPlugin.h"
#import "GTMObjectSingleton.h"

@implementation HGSModuleLoader

GTMOBJECT_SINGLETON_BOILERPLATE(HGSModuleLoader, sharedModuleLoader);

- (id)init {
  if ((self = [super init])) {
    extensionMap_ = [[NSMutableDictionary alloc] init];
    if (!extensionMap_) {
      HGSLog(@"Unable to create extensionMap_");
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [extensionMap_ release];
  [super dealloc];
}

- (NSArray *)loadPluginsAtPath:(NSString*)pluginPath {
  NSMutableArray *plugins = nil;
  if (pluginPath) {
    NSDirectoryEnumerator* dirEnum
      = [[NSFileManager defaultManager] enumeratorAtPath:pluginPath];
    NSString* path = nil;
    while ((path = [dirEnum nextObject])) {
      [dirEnum skipDescendents];
      NSString* fullPath = [pluginPath stringByAppendingPathComponent:path];
      NSString *extension = [fullPath pathExtension];
      Class pluginClass = [extensionMap_ objectForKey:extension];
      if (pluginClass) {
        HGSPlugin *plugin = [[[pluginClass alloc] initWithPath:fullPath]
                             autorelease];
        if (plugin) {
          if (!plugins) {
            plugins = [NSMutableArray arrayWithObject:plugin];
          } else {
            [plugins addObject:plugin];
          }
        }
      }
    }
  }
  return plugins;
}

- (void)registerClass:(Class)cls forExtensions:(NSArray *)extensions {
  for (id extension in extensions) {
    #if DEBUG
    Class oldCls = [extensionMap_ objectForKey:extension];
    if (oldCls) {
      HGSLogDebug(@"Replacing %@ with %@ for extension %@", 
                  NSStringFromClass(oldCls), NSStringFromClass(cls), extension);
    }
    #endif
    [extensionMap_ setObject:cls forKey:extension];
  }
}

#pragma mark -

- (BOOL)extendPoint:(NSString *)extensionPointID
         withObject:(id<HGSExtension>)extension {
  HGSExtensionPoint *point = [HGSExtensionPoint pointWithIdentifier:extensionPointID];
  return [point extendWithObject:extension];
}

- (id<HGSDelegate>)delegate {
  return delegate_;
}

- (void)setDelegate:(id<HGSDelegate>)delegate {
  delegate_ = delegate;
}

@end
