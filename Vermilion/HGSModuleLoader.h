//
//  HGSModuleLoader.h
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

#import <Foundation/Foundation.h>

//
// HGSModuleLoader
//
// Takes care of loading and registering modules that extend extensions points
// Fields requests for iterators and actions for a given type via 
// the associated protocols.

// Extensions can be defined in two ways:
// the easy way is to add a 
// 'HGSExtensions' key to your plist which is an array of dictionaries.
// Each dictionary contains two keys:
// 'HGSExtensionClass' which is the class to be instantiated
// 'HGSExtensionPoint' which is a string naming the point to be extended.
//
// Common points are:
//   HGSActionsExtensionPoint
//   HGSSourcesExtensionPoint;
// 
// <array>
//   <dict>
//     <key>HGSExtensionClass</key>
//     <string>HGSActionSource</string>
//     <key>HGSExtensionPoint</key>
//     <string>HGSSourcesExtensionPoint</string>
//   </dict>
// </array>
//
// OR
// 
// Create a class that conforms to the HGSModule Protocol and set it as
// the principal class for your bundle.
//
// Example:
// <key>NSPrincipalClass</key>
// <string>HGSApplicationsModule</string>
//
// We prefer the former, and only support the latter for very complex extensions
// or dynamic extensions.

@protocol HGSExtension;
@protocol HGSDelegate;

@interface HGSModuleLoader : NSObject {
 @private
  __weak id<HGSDelegate> delegate_;
  
  // Extension map maps a particular extension (.hgs) to a type of plugin
  // to instantiate. This allows us to extend Vermiliion to accept other
  // types of plugins like (.py) or (.scpt) and have those act
  // as real plugins.
  NSMutableDictionary *extensionMap_;  
}

// Return the shared module Loader.
+ (HGSModuleLoader*)sharedModuleLoader;

// Registers a plugin class for a given set of extensions.
- (void)registerClass:(Class)cls forExtensions:(NSArray *)extensions;

// Given a path to a folder where modules may live, identify all modules and
// their sources and actions, and return them as mutable plugins.
- (NSArray *)loadPluginsAtPath:(NSString*)pluginsPath;
- (BOOL)extendPoint:(NSString *)extensionPointID
         withObject:(id<HGSExtension>)extension;

- (id<HGSDelegate>)delegate;
- (void)setDelegate:(id<HGSDelegate>)delegate;

@end
