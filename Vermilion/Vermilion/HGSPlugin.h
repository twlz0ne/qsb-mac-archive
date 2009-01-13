//
//  HGSPlugin.h
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

// kHGSPluginConfigurationVersionKey is a key into the archived dictionary
// describing a plugin giving the version of the dictionary when that
// plugin was most recently archived.
#define kHGSPluginConfigurationVersionKey @"kHGSPluginConfigurationVersionKey"

// kHGSPluginConfigurationVersion gives the current version with which
// a plugin configuration dictionary will be archived.
#define kHGSPluginConfigurationVersion 1


// A class that represents an object containing source and action
// extensions along with location, type, enablement, etc.  Objects
// of this class are usually reconstituted from plugin bundles or
// from preferences.
// 
@interface HGSPlugin : NSObject {
 @private
  NSBundle *bundle_;
  NSString *bundlePath_;  // Original location of plugin bundle.
  NSString *bundleName_;
  NSString *bundleIdentifier_;
  NSString *displayName_;  // Human-readable plugin name.
  
  NSArray *protoExtensions_;  // ProtoExtensions of this plugin.
  
  BOOL isOld_;  // YES for old until we find an installed plugin that matches.
  BOOL isNew_;  // YES for new until matched with an existing plugin. 
  BOOL isEnabled_;  // Plugin master swtich.

  NSUInteger sourceCount_;  // Cached
  NSUInteger actionCount_;  // Cached
}

@property (nonatomic, retain, readonly) NSBundle *bundle;
@property (nonatomic, copy, readonly) NSString *bundlePath;
@property (nonatomic, copy, readonly) NSString *bundleName;
@property (nonatomic, copy, readonly) NSString *bundleIdentifier;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, retain, readonly) NSArray *protoExtensions;
@property (nonatomic) BOOL isEnabled;
@property (nonatomic, readonly) BOOL isOld;
@property (nonatomic, readonly) BOOL isNew;
@property (nonatomic, readonly) NSUInteger sourceCount;
@property (nonatomic, readonly) NSUInteger actionCount;

// Reconstitute a plugin from a bundle.
- (id)initWithBundleAtPath:(NSString *)bundlePath;

// Reconstitute a plugin from a dictionary, usually from preferences, marking
// all plugins and extensions as 'old'.
- (id)initWithDictionary:(NSDictionary *)pluginDict;

// Provide an archivable dictionary for a plugin.
- (NSDictionary *)dictionaryValue;

// Compare the identifier and path of each plugin.
- (NSComparisonResult)compare:(HGSPlugin *)pluginB;

// Merge |pluginB| into self.
- (HGSPlugin *)merge:(HGSPlugin *)pluginB;

// Install/uninstall extensions.
- (void)installExtensions;
- (void)uninstallExtensions;

// Remove all old extensions for which there was no new extension.
- (void)stripOldUnmergedExtensions;

// Automatically set up the enabled-ness of new extensions.
- (void)autoSetEnabledForNewExtensions;

// Helper functions for filtering out plugins we previously knew about but
// which have now gone missing and vice versa.
- (BOOL)notIsOld;
- (BOOL)notIsNew;

// Return a copyright string for the extension.
// By default returns the "NSHumanReadableCopyright" value from
// the info.plist of the bundle of the class that this object is an instance of.
- (NSString *)copyright;

// For debugging purposes. Allows you to log any problems in plugin loading.
// HGSValidatePlugins is a boolean preference that the
// engine can use to enable extra logging while managing plugins
// and extensions to assist developers in making sure their plugins
// and extensions are configured properly.  The pref should be set
// before launch to ensure it is all possible checks are done.
// defaults write com.google.qsb HGSValidatePlugins 1
+ (BOOL)validatePlugins;
@end

// Notification sent when plugin has been enabled/disabled.  The 
// notification's |object| will contain the HGSPlugin reporting
// the change.  There will be no |userInfo|.
extern NSString *const kHGSPluginDidChangeEnabledNotification;
