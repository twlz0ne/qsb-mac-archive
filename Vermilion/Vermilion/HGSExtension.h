//
//  HGSExtension.h
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
#import <AppKit/AppKit.h>

// Information about extensions that a UI can display.

@protocol HGSExtension <NSObject>

// Designated initializer.
- (id)initWithConfiguration:(NSDictionary *)configuration;

// Return the unique identifier for this extension (reverse DNS style)
- (NSString *)identifier;

// Return an icon that can be displayed 128x128.
- (NSImage *)icon;

// Return a display name for the extension.
- (NSString *)name;

// Return a copyright string for the extension.
- (NSString *)copyright;

// Return a description for the extension.
- (NSAttributedString *)extensionDescription;

// Return a version number for the extension.
- (NSString *)extensionVersion;

@optional
// Provide default name or icon if needed.
- (id)defaultObjectForKey:(NSString *)key;

@end

@interface HGSExtension : NSObject <HGSExtension> {
 @private
  NSString *name_;
  NSString *iconPath_;
  NSImage *icon_;
  NSString *identifier_;
}

// Return a copyright string for the extension.
// By default returns the "NSHumanReadableCopyright" value from
// the info.plist of the bundle of the class that this object is an instance of.
- (NSString *)copyright;

// Return an identifier for the extension.
// By default returns the kHGSExtensionIdentifierKey. Falls back on
// CFBundleIdentifier.
- (NSString *)identifier;

// Return a description for the extension.
// By default looks for a file named "Description.html", "Description.rtf", 
// and "Description.rtfd", in that order, in the bundleof the class that this 
// object is an instance of.
- (NSAttributedString *)extensionDescription;

// Return a version number for the extension.
// By default returns the "CFBundleVersion" value from
// the info.plist of the bundle of the class that this object is an instance of.
- (NSString *)extensionVersion;

// Return an objectForInfoDictionaryKey for this extension
- (id)objectForInfoDictionaryKey:(NSString *)key;

// Return a default object for the given key.  Overridding implementations
// should always call super if it cannot provide the default.
- (id)defaultObjectForKey:(NSString *)key;

@end

// Extension keys

// String which is the class of the extension
extern NSString *const kHGSExtensionClassKey;
// String giving the points to which to attach the extension
extern NSString *const kHGSExtensionPointKey;
// String which is the reverse DNS identifier of the extension
extern NSString *const kHGSExtensionIdentifierKey;
// String which is the user-visible name of the extension
extern NSString *const kHGSExtensionUserVisibleNameKey;
// Extension's icon image. This can be requested through defaultObjectForKey
// but cannot be set in the initial configuration, because we want to discourage
// loading icons at startup if at all possible. When you fulfill the request
// we expect a 128x128 image.
extern NSString *const kHGSExtensionIconImageKey;
// String which is the path to an icon image. The path can either just be a
// name, in which case it will be looked for in the extension bundle, or a full
// path.
extern NSString *const kHGSExtensionIconImagePathKey;
// NSNumber (BOOL) indicating if extension is enabled.
extern NSString *const kHGSExtensionEnabledKey;
// NSBundle bundle associated with the extension
extern NSString *const kHGSExtensionBundleKey;
// Type of accounts in which the extension is interested.
extern NSString *const kHGSExtensionDesiredAccountType;
// YES if the extension presented to the user in the preferences panel.
// If this is not present then YES is assumed.
extern NSString *const kHGSIsUserVisible;
// YES if the extension is to be enabled by default.  If this key is _not_
// present, YES is assumed, except for account-dependent sources, in which
// case NO is assumed.
extern NSString *const kHGSIsEnabledByDefault;
// Identifier of account assigned to the extension.
extern NSString *const kHGSExtensionAccountIdentifier;

