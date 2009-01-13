//
//  HGSPlugin.m
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

#import "HGSPlugin.h"
#import "GTMMethodCheck.h"
#import "GTMNSArray+Merge.h"
#import "GTMNSEnumerator+Filter.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"
#import "HGSModule.h"
#import "HGSModuleLoader.h"
#import "HGSProtoExtension.h"

// Array of Cocoa extension descriptions.
static NSString *const kHGSExtensionsKey = @"HGSExtensions";
// NSNumber (BOOL) indicating if plugin is enabled (master switch).
static NSString *const kHGSPluginEnabledKey = @"HGSPluginEnabled";
// String containing the path at which the plugin bundle was last found.
static NSString *const kHGSPluginBundlePathKey = @"HGSPluginBundlePath";
// String giving the name of the bundle.
static NSString *const kHGSPluginBundleNameKey = @"HGSPluginBundleName";
// String containing the identifier (in reverse DNS) of the plugin.
static NSString *const kHGSBundleIdentifierKey = @"HGSBundleIdentifier";
// String giving the name of the plugin.
static NSString *const kHGSPluginDisplayNameKey = @"HGSPluginDisplayName";
// Array containing dictionaries describing the extensions of this plugin.
static NSString *const kHGSPluginExtensionsDicts = @"HGSPluginExtensionsDicts";



@interface HGSPlugin (HGSPluginPrivateMethods)

- (BOOL)isValid;
- (BOOL)extensionIsEnabled:(HGSProtoExtension *)extension;

// Private property setters.
- (void)setBundle:(NSBundle *)bundle;
- (void)setBundlePath:(NSString *)bundlePath;
- (void)setBundleName:(NSString *)bundleName;
- (void)setBundleIdentifier:(NSString *)bundleIdentifier;
- (void)setDisplayName:(NSString *)displayName;
- (void)setProtoExtensions:(NSArray *)protoExtensions;
- (void)setIsOld:(BOOL)isOld;
- (void)setIsNew:(BOOL)isNew;
- (void)setSourceCount:(NSUInteger)sourceCount;
- (void)setActionCount:(NSUInteger)actionCount;

@end


@implementation HGSPlugin

GTM_METHOD_CHECK(NSArray, gtm_mergeArray:mergeSelector:);
GTM_METHOD_CHECK(NSEnumerator,
                 gtm_filteredEnumeratorByTarget:performOnEachSelector:)
GTM_METHOD_CHECK(NSEnumerator, 
                 gtm_filteredEnumeratorByMakingEachObjectPerformSelector:withObject:);

@synthesize bundle = bundle_;
@synthesize bundlePath = bundlePath_;
@synthesize bundleName = bundleName_;
@synthesize bundleIdentifier = bundleIdentifier_;
@synthesize displayName = displayName_;
@synthesize protoExtensions = protoExtensions_;
@synthesize isEnabled = isEnabled_;
@synthesize isOld = isOld_;
@synthesize isNew = isNew_;
@synthesize sourceCount = sourceCount_;
@synthesize actionCount = actionCount_;

static BOOL gValidatingPlugins = NO;

+ (void)initialize {
  if (self == [HGSPlugin class]) {
    #if DEBUG
    gValidatingPlugins = YES;
    #else  // DEBUG
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    gValidatingPlugins = [ud boolForKey:@"HGSValidatePlugins"];
    #endif  // DEBUG
  }
}

+ (BOOL)validatePlugins {
  return gValidatingPlugins;
}

- (id)initWithBundleAtPath:(NSString *)bundlePath {
  if ((self = [super init])) {
    BOOL debugPlugins = [HGSPlugin validatePlugins];

    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (bundle) {
      [self setBundle:bundle];
      [self setBundlePath:[bundlePath stringByStandardizingPath]];
      NSString *bundleName
        = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
      if (!bundleName) {
        bundleName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
        if (!bundleName) {
          bundleName = [bundle objectForInfoDictionaryKey:@"CFBundleExecutable"];
          if (!bundleName) {
            if (debugPlugins) {
              HGSLog(@"Unable to get a bundle name for %@", self);
            }
            bundleName = @"Unnamed Bundle";
          }
        }
      }
      [self setBundleName:bundleName];
      [self setBundleIdentifier:[bundle bundleIdentifier]];
      NSString *displayName
        = [bundle objectForInfoDictionaryKey:kHGSPluginDisplayNameKey];
      if (!displayName) {
        displayName = bundleName;
      }
      [self setDisplayName:displayName];

      NSMutableArray *protoExtensions = [NSMutableArray array];
      
      // Discover all plist based extensions
      NSArray *standardExtensions
        = [bundle objectForInfoDictionaryKey:kHGSExtensionsKey];
      if (standardExtensions) {
        for (NSDictionary *bundleExtension in standardExtensions) {
          HGSProtoExtension *extension
            = [[[HGSProtoExtension alloc] initWithBundleExtension:bundleExtension
                                                           plugin:self]
               autorelease];
          if (extension) {
            NSArray *factoredExtensions = [extension factor];
            [protoExtensions addObjectsFromArray:factoredExtensions];
          }
        } 
      }
      
      if ([protoExtensions count]) {
        [self setProtoExtensions:protoExtensions];
      } else {
        // TODO(mrossetti): Move this back into the module loader.
        if (debugPlugins) {
          HGSLog(@"No extensions found in plugin at path %@. "
                 @"Directly loading. NOTE: This is not necessarily an error.",
                 bundlePath);
        }
        Class principal = [bundle principalClass];
        if (principal) {
          if ([principal conformsToProtocol:@protocol(HGSModule)]) {
            id module = [[[principal alloc] init] autorelease];
            if (module) {
              [module registerModuleWithLoader:[HGSModuleLoader
                                                sharedModuleLoader]];
            } else {
              if (debugPlugins) {
                HGSLog(@"Unable to instantiate principal class: %@ for bundle %@:",
                       module, bundle);
              }
              [self release];
              self = nil;
            }
          }
        }
      }
      
      // TODO(mrossetti): Reconsider this policy.
      // Automatically enable newly discovered plugins.
      isEnabled_ = YES;  // Do not use the setter.
      
      // Validate the plugin.
      if (![self isValid]) {
        [self release];
        self = nil;
      }
    } else {
      if (debugPlugins) {
        HGSLog(@"Unable to get bundle for path %@", bundlePath);
      }
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary *)pluginDict {
  // This will reconstitute a plugin from a dictionary created
  // using -[dictionaryValue], below.
  // TODO(mrossetti): Review and decide when this should fail and return nil.
  if ((self = [super init])) {
    BOOL debugPlugins = [HGSPlugin validatePlugins];

    BOOL isEnabled = [[pluginDict objectForKey:kHGSPluginEnabledKey] boolValue];
    // Set isEnabled_ directly: do not use the mutator because we do not
    // want the side-effects of installing/uninstalling and saving prefs.
    isEnabled_ = isEnabled;
    
    NSString *bundlePath
      = [pluginDict objectForKey:kHGSPluginBundlePathKey];
    [self setBundlePath:bundlePath];
    if (!bundlePath && debugPlugins) {
      HGSLog(@"Plugin is missing bundlePath.");
    }

    NSString *bundleName = [pluginDict objectForKey:kHGSPluginBundleNameKey];
    [self setBundleName:bundleName];
    if (!bundleName && debugPlugins) {
      HGSLog(@"Plugin is missing bundleName.");
    }    

    NSString *displayName = [pluginDict objectForKey:kHGSPluginDisplayNameKey];
    if (!displayName) {
      if (debugPlugins) {
        HGSLog(@"Plugin is missing displayName.");
      }
      displayName = bundleName;
    }
    [self setDisplayName:displayName];
    
    NSString *bundleIdentifier
      = [pluginDict objectForKey:kHGSBundleIdentifierKey];
    if (!bundleIdentifier) {
      if (debugPlugins) {
        HGSLog(@"Plugin is missing bundleIdentifier.");
      }
      bundleIdentifier = bundleName;
    }
    [self setBundleIdentifier:bundleIdentifier];
    
    NSArray *extensionsDicts
      = [pluginDict objectForKey:kHGSPluginExtensionsDicts];
    NSMutableArray *protoExtensions
      = [NSMutableArray arrayWithCapacity:[extensionsDicts count]];
    for (NSDictionary *extDict in extensionsDicts) {
      HGSProtoExtension *extension
        = [[[HGSProtoExtension alloc] initWithPreferenceDictionary:extDict]
           autorelease];
      if (extension) {
        [protoExtensions addObject:extension];
      } else if (debugPlugins) {
        HGSLog(@"Failed to reanimate protoExtension from dict: %@",
               extDict);
      }
    }
    [self setProtoExtensions:protoExtensions];
    [self setIsOld:YES];
    
    // Validate the plugin.
    if (![self isValid]) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)copyWithZone:(NSZone *)zone {
  HGSPlugin* copiedPlugin = [[HGSPlugin allocWithZone:zone] init];
  if (copiedPlugin) {
    [copiedPlugin setBundle:[self bundle]];
    [copiedPlugin setBundlePath:[self bundlePath]];
    [copiedPlugin setBundleName:[self bundleName]];
    [copiedPlugin setBundleIdentifier:[self bundleIdentifier]];
    [copiedPlugin setDisplayName:[self displayName]];
    
    NSArray *copiedExtensions
      = [[[NSArray allocWithZone:zone] initWithArray:protoExtensions_
                                           copyItems:YES]
         autorelease];
    [copiedPlugin setProtoExtensions:copiedExtensions];
    
    [copiedPlugin setIsOld:[self isOld]];
    [copiedPlugin setIsNew:[self isNew]];
    copiedPlugin->isEnabled_ = isEnabled_;  // Do not use setter.
     if (![copiedPlugin isValid]) {
      [copiedPlugin release];
      copiedPlugin = nil;
    }
  }
  return copiedPlugin;
}

- (void)dealloc {
  [bundlePath_ release];
  [bundleName_ release];
  [bundleIdentifier_ release];
  [displayName_ release];
  [protoExtensions_ release];
  [bundle_ release];
  
  [super dealloc];
}

- (NSDictionary *)dictionaryValue {
  // This will create a dictionary that can be used to reconstitute
  // a plugin using -[initWithDictionary:], above.
  NSNumber *isEnabled = [NSNumber numberWithBool:[self isEnabled]];
  NSNumber *archiveVersion
    = [NSNumber numberWithUnsignedInt:kHGSPluginConfigurationVersion];
  NSArray *extensionsDicts = [protoExtensions_ valueForKey:@"dictionaryValue"];
  NSDictionary *pluginDict = [NSDictionary dictionaryWithObjectsAndKeys:
                              [self bundlePath], kHGSPluginBundlePathKey,
                              [self bundleName], kHGSPluginBundleNameKey,
                              [self bundleIdentifier], kHGSBundleIdentifierKey,
                              [self displayName], kHGSPluginDisplayNameKey,
                              isEnabled, kHGSPluginEnabledKey,
                              archiveVersion, kHGSPluginConfigurationVersionKey,
                              extensionsDicts, kHGSPluginExtensionsDicts,
                              nil];
  return pluginDict;
}

- (void)setIsEnabled:(BOOL)isEnabled {
  if ([self isEnabled] != isEnabled) {
    isEnabled_ = isEnabled;
    
    // Install/enable or disable the plugin.
    if (isEnabled) {
      [self installExtensions];
    } else {
      [self uninstallExtensions];
    }
    
    // Signal that the plugin's enabling setting has changed.
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSNotification *notification
      = [NSNotification notificationWithName:kHGSPluginDidChangeEnabledNotification
                                      object:self];
    [center postNotification:notification];
  }
}

- (NSComparisonResult)compare:(HGSPlugin *)pluginB {
  NSString *identifierA = [self bundleIdentifier];
  NSString *identifierb = [pluginB bundleIdentifier];
  NSComparisonResult result = [identifierA compare:identifierb];
  
  if (result == NSOrderedSame) {
    NSString *pathA = [self bundlePath];
    NSString *pathB = [pluginB bundlePath];
    result = [pathA compare:pathB];
  }
  
  return result;
}

- (HGSPlugin *)merge:(HGSPlugin *)pluginB {
  HGSPlugin *mergedPlugin = [[self copy] autorelease];
  // Indicate that we are no longer pending.
  [mergedPlugin setIsNew:NO];
  [mergedPlugin setIsOld:NO];
  
  // TODO(mrossetti): Compare bundle name and path to guarantee that we're
  // talking about the very same plugin.
  
  // Remember the bundle.
  if (![mergedPlugin bundle]) {
    [mergedPlugin setBundle:[pluginB bundle]];
  }
  
  // Reconcile the extensions.
  NSArray *oldProtoExtensions = [mergedPlugin protoExtensions];
  NSArray *newProtoExtensions = [pluginB protoExtensions];
  NSArray *mergedProtoExtensions
    = [oldProtoExtensions gtm_mergeArray:newProtoExtensions
                           mergeSelector:@selector(replaceWithProtoExtension:)];
  [mergedPlugin setProtoExtensions:mergedProtoExtensions];
  return mergedPlugin;
}

- (void)installExtensions {
  // Lock and load all enable-able sources and actions.
  NSEnumerator *protoExtensionsEnum = [[self protoExtensions] objectEnumerator];
  NSEnumerator *protoExtensionsToInstallEnum
    = [protoExtensionsEnum gtm_filteredEnumeratorByTarget:self
                              performOnEachSelector:@selector(extensionIsEnabled:)];
  NSArray *extensionsToInstall = [protoExtensionsToInstallEnum allObjects];
  [extensionsToInstall makeObjectsPerformSelector:@selector(install)];
}

- (void)uninstallExtensions {
  // Lock and load all enable-able sources and actions.
  NSEnumerator *protoExtensionsEnum = [[self protoExtensions] objectEnumerator];
  NSEnumerator *protoExtensionsToUninstallEnum
    = [protoExtensionsEnum
       gtm_filteredEnumeratorByMakingEachObjectPerformSelector:@selector(isInstalled)
                                                    withObject:nil];
  NSArray *extensionsToUninstall = [protoExtensionsToUninstallEnum allObjects];
  [extensionsToUninstall makeObjectsPerformSelector:@selector(uninstall)];
}

- (void)stripOldUnmergedExtensions {
  // This will not uninstall extensions because none should have been
  // installed at this point.
  NSEnumerator *protoExtensionsEnum = [[self protoExtensions] objectEnumerator];
  NSEnumerator *mergedProtoExtensionsEnum
    = [protoExtensionsEnum
       gtm_filteredEnumeratorByMakingEachObjectPerformSelector:@selector(notIsOld)
                                                    withObject:nil];
  NSArray *strippedExtensions = [mergedProtoExtensionsEnum allObjects];
  [self setProtoExtensions:strippedExtensions];
}

- (void)autoSetEnabledForNewExtensions {
  NSArray *allProtoExtensions = [self protoExtensions];
  [allProtoExtensions makeObjectsPerformSelector:
                                          @selector(autoSetIsEnabled)
                                      withObject:nil];
}

- (BOOL)notIsOld {
  return ![self isOld];
}

- (BOOL)notIsNew {
  return ![self isNew];
}

- (NSString *)copyright {
  return [[self bundle] objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@:%p displayName='%@', isEnabled=%d, "
          @"isOld=%d, isNew=%d, \n protoExtensions={%@} bundleIdentifier='%@', "
          @"bundlePath='%@', bundleName='%@', bundle=%@>",
          [self class], self, displayName_, isEnabled_, isOld_, isNew_,
          protoExtensions_, bundleIdentifier_, bundlePath_, bundleName_,
          bundle_];
}

@end


@implementation HGSPlugin (HGSPluginPrivateMethods)

- (BOOL)isValid {
  // Validate the plugin.
  BOOL isValid = [self bundlePath]
                 && [self bundleName]
                 && [self bundleIdentifier]
                 && [self displayName];
  if (!isValid) {
    if ([HGSPlugin validatePlugins]) {
      HGSLog(@"Plugin failed to validate.");
    }
  }
  return isValid;
}

- (BOOL)extensionIsEnabled:(HGSProtoExtension *)protoExtension {
  // Determine if a protoExtension is enabled.  Action extensions are
  // _always_ considered enabled at this time.
  BOOL isEnabled = [protoExtension isEnabled];
  if (!isEnabled) {
    // See if this extension is an action and, if so, then consider it enabled.
    NSString *extensionPointKey = [protoExtension extensionPointKey];
    isEnabled = ([extensionPointKey isEqualToString:kHGSActionsExtensionPoint]);
  }
  return isEnabled;
}

#pragma mark Private Property Setters

- (void)setBundle:(NSBundle *)bundle {
  [bundle_  autorelease];
  bundle_ = [bundle retain];
}

- (void)setBundlePath:(NSString *)bundlePath {
  [bundlePath_  release];
  bundlePath_ = [bundlePath copy];
}

- (void)setBundleName:(NSString *)bundleName {
  [bundleName_  release];
  bundleName_ = [bundleName copy];
}

- (void)setBundleIdentifier:(NSString *)bundleIdentifier {
  [bundleIdentifier_  release];
  bundleIdentifier_ = [bundleIdentifier copy];
}

- (void)setDisplayName:(NSString *)displayName {
  [displayName_  release];
  displayName_ = [displayName copy];
}

- (void)setProtoExtensions:(NSArray *)protoExtensions {
  [protoExtensions_ autorelease];
  protoExtensions_ = [protoExtensions retain];
  
  // Calculate the source and action count.  Also, set the plugin for
  // each extension to be myself.
  NSUInteger sourceCount = 0;
  NSUInteger actionCount = 0;
  for (HGSProtoExtension *extension in protoExtensions) {
    [extension setPlugin:self];
    NSString *extensionPointKey = [extension extensionPointKey];
    if (extensionPointKey) {
      if ([extensionPointKey isEqualToString:kHGSSourcesExtensionPoint]) {
        ++sourceCount;
      } else if ([extensionPointKey isEqualToString:kHGSActionsExtensionPoint]) {
        ++actionCount;
      } else if ([extensionPointKey isEqualToString:kHGSServicesExtensionPoint]) {
        // TODO(mrossetti): Do we want to count services?
      } else {
        if ([HGSPlugin validatePlugins]) {
          HGSLog(@"Unrecognized extension point '%@' for extension %@",
                 extensionPointKey, extension);
        }
      }
    }
  }
  [self setSourceCount:sourceCount];
  [self setActionCount:actionCount];
}

- (void)setIsOld:(BOOL)isOld {
  isOld_ = isOld;
}

- (void)setIsNew:(BOOL)isNew {
  isNew_ = isNew;
}

- (void)setSourceCount:(NSUInteger)sourceCount {
  sourceCount_ = sourceCount;
}

- (void)setActionCount:(NSUInteger)actionCount {
  actionCount_ = actionCount;
}

@end

// Notification sent when extension has been enabled/disabled.
NSString *const kHGSPluginDidChangeEnabledNotification
  = @"HGSPluginDidChangeEnabledNotification";


