//
//  HGSProtoExtension.h
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


@class HGSPlugin;
@class HGSExtension;
@protocol HGSAccount;

// An HGSProtoExtension manages an HGSExtension.  Typically, a list of
// these protoExtensions is presented to the user in a table allowing
// the user to choose which are to be enabled for actual use.  When a
// protoExtension is enabled, either automatically at application launch
// or manually by the user, an instance of HGSExtension is created and
// made available for subsequent searches and actions.  Correspondingly,
// when a protoExtension is disabled the associated HGSExtension is
// turned off and removed.
// 
// An HGSProtoExtension can be 'factored'.  This means that the prototype
// extension can specify interest in certain external 'factors' such as
// an online account (which is the only type of factor currently
// supported).  Upon the availability of a 'factor' of the desired type,
// the protoExtension is replicated (by HGSPlugin calling the
// -[HGSProtoExtension factor] or -[HGSProtoExtension factorForAccount:]
// member function) and added to the list of available sources (usually
// presented to the user in a table).
// 
// To specify an extension's interest in being factored by whatever
// HGSGoogleAccounts are available|, provide the
// HGSExtensionDesiredAccountType| key in your bundle's plist with a
// value of |Google|.
// 
// It is likely that this implementation will change somewhat as new
// types of factors are introduced in the future.
//
@interface HGSProtoExtension : NSObject {
 @private
  HGSPlugin *plugin_;  // The plugin to which we belong.
  HGSExtension *extension_; // Installed extension.
  NSString *className_;  // The name of the extension class.
  NSString *moduleName_;  // Module name if python extension.
  NSString *displayName_;
  NSString *extensionPointKey_;  // Typically, 'source' or 'action'.
  NSString *protoIdentifier_;  // Cached, and initialized from extension.
  NSDictionary *extensionDict_;  // The dict from w/in the info.plist.  We don't
                                 // want to store this, we want the "current"
                                 // info from the plugin's info.plist each run.
  BOOL isEnabled_;
  BOOL isOld_;  // YES for old until we inventory an extension that matches.
  BOOL isNew_;  // YES for new until matched with an old extension.
}

@property (nonatomic, retain) HGSPlugin *plugin;
@property (nonatomic, retain, readonly) HGSExtension *extension;
@property (nonatomic, copy, readonly) NSString *className;
@property (nonatomic, copy, readonly) NSString *moduleName;
@property (nonatomic, copy, readonly) NSString *displayName;
@property (nonatomic, copy, readonly) NSString *extensionPointKey;
@property (nonatomic, copy, readonly) NSString *protoIdentifier;
@property (nonatomic, copy, readonly) NSDictionary *extensionDictionary;
@property (nonatomic) BOOL isEnabled;
@property (nonatomic) BOOL isOld;
@property (nonatomic) BOOL isNew;

// Initialize a prototype extension given a dictionary.
- (id)initWithBundleExtension:(NSDictionary *)bundleExtension
                       plugin:(HGSPlugin *)plugin;

// Initialize a prototype extension given a dictionary from preferences.
- (id)initWithPreferenceDictionary:(NSDictionary *)bundleExtension;

// Provide an archivable dictionary for the extension.
- (NSDictionary *)dictionaryValue;

// Return YES if this protoExtension is factorable.  Sources are currently
// only factorable by instances of HGSAccount.
- (BOOL)isFactorable;

// Return zero or more protoExtensions by factoring based on desired accounts.
// If this protoExtension is not factorable then return an empty array.
- (NSArray *)factor;

// Return a new protoExtension by factoring on the account.  If this
// protoExtension is not factorable on account then return nil.
// TODO(mrossetti): Generalize this when additional factor types are introduced.
- (HGSProtoExtension *)factorForAccount:(id<HGSAccount>)account;

// Return a description for the extension.
// By default looks for a file named "Description.html", "Description.rtf", 
// and "Description.rtfd", in that order, in the bundleof the class that this 
// object is an instance of.
- (NSAttributedString *)extensionDescription;

// Return a version number for the extension.
// By default returns the "CFBundleVersion" value from
// the info.plist of the bundle of the class that this object is an instance of.
- (NSString *)extensionVersion;

// Helper functions for filtering out plugins we previously knew about but
// which have now gone missing, and vice versa.
- (BOOL)notIsNew;
- (BOOL)notIsOld;

// Set isEnabled for the extension based on its HGSIsEnabledByDefault setting
// and its desire for an account.  Return YES if the extension was disabled.
- (BOOL)autoSetIsEnabled;

// Returns if the extension has been installed.
- (BOOL)isInstalled;

// Install or uninstall an extension.
- (void)install;
- (void)uninstall;

// Compare the names of the extensions.
- (NSComparisonResult)compare:(HGSProtoExtension *)extensionB;

// Return an objectForInfoDictionaryKey for this extension
- (id)objectForInfoDictionaryKey:(NSString *)key;

// Returns YES if the extension's extension point is of the type specified
// and for which the HGSIsUserVisible flas is not set to NO.
- (BOOL)isUserVisibleAndExtendsExtensionPoint:(NSString *)extensionPoint;

// Convenience methods for setting a factor.
- (void)setExtensionDictionaryObject:(id)factor forKey:(NSString *)key;

@end


// Notification sent when extension has been enabled/disabled.  The 
// notification's |object| will contain the HGSProtoExtension reporting
// the change.  There will be no |userInfo|.
extern NSString *const kHGSExtensionDidChangeEnabledNotification;
