//
//  HGSProtoExtension.m
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

#import "HGSProtoExtension.h"
#import "HGSAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSExtension.h"
#import "HGSLog.h"
#import "HGSPlugin.h"
#import "HGSPythonAction.h"
#import "HGSPythonSource.h"

@interface HGSProtoExtension (HGSProtoExtensionPrivateMethods)

// TODO(mrossetti): There will be other types of factors in the future so
// will need to introduce an HGSFactor protocol that supports -[identifier]
// at a minimum.
- (id)copyWithFactor:(id<HGSAccount>)factor
              forKey:(NSString *)key;

- (BOOL)isValid;

// Private setters.
- (void)setExtension:(HGSExtension *)extension;
- (void)setClassName:(NSString *)className;
- (void)setModuleName:(NSString *)moduleName;
- (void)setDisplayName:(NSString *)displayName;
- (void)setExtensionPointKey:(NSString *)extensionPointKey;
- (void)setProtoIdentifier:(NSString *)protoIdentifier;
- (void)setExtensionDictionary:(NSDictionary *)extensionDict;

// Respond to the pending removal of an account by shutting down our
// extension, if any, and removing ourself from the list of sources.
- (void)willRemoveAccount:(NSNotification *)notification;

@end


@implementation HGSProtoExtension

// TODO(mrossetti): we shouldn't require all these instance variables. We
// should be able to store most of this in a single dictionary instead of
// deconstructing it initially and reconstructing it later.
@synthesize plugin = plugin_;
@synthesize extension = extension_;
@synthesize className = className_;
@synthesize moduleName = moduleName_;
@synthesize displayName = displayName_;
@synthesize extensionPointKey = extensionPointKey_;
@synthesize protoIdentifier = protoIdentifier_;
@synthesize extensionDictionary = extensionDict_;
@synthesize isEnabled = isEnabled_;
@synthesize isOld = isOld_;
@synthesize isNew = isNew_;

+ (NSSet *)keyPathsForValuesAffectingKeyInstalled {
  NSSet *affectingKeys = [NSSet setWithObject:@"extension"];
  return affectingKeys;
}

- (id)initWithBundleExtension:(NSDictionary *)bundleExtension
                       plugin:(HGSPlugin *)plugin {
  if ((self = [super init])) {
    BOOL debugPlugins = [HGSPlugin validatePlugins];
    NSString *className = [bundleExtension objectForKey:kHGSExtensionClassKey];
    [self setClassName:className];
    
    NSString *displayName
      = [bundleExtension objectForKey:kHGSExtensionUserVisibleNameKey];
    if (!displayName) {
      displayName = [plugin bundleName];
      if (!displayName) {
        if (debugPlugins) {
          HGSLog(@"Unable to get a displayName for %@", self);
        }
        displayName = @"Unnamed Extension";
      }
    }
    [self setDisplayName:displayName];
    
    NSString *protoIdentifier
      = [bundleExtension objectForKey:kHGSExtensionIdentifierKey];
    if (!protoIdentifier && debugPlugins) {
      HGSLog(@"Extension '%@' has no identifier.", [self displayName]);
    }
    [self setProtoIdentifier:protoIdentifier];
    
    NSString *extensionPointKey 
      = [bundleExtension objectForKey:kHGSExtensionPointKey];
    if (!extensionPointKey && debugPlugins) {
        HGSLog(@"Extension '%@' has no extension point.", [self displayName]);
      }
    [self setExtensionPointKey:extensionPointKey];
    
    // Save off the config info so we can pass it when creating the extension
    [self setExtensionDictionary:bundleExtension];

    // TODO(mrossetti): Review this policy in light of accounts and net access.
    // Always enable new extensions.
    // TODO(mrossetti): Eliminate this once we switch to actually removing
    // and installing extensions.
    // Do not use mutator since we do not want the side-effects.
    isEnabled_ = YES;
    [self setIsNew:YES];
    
    // Validate the extension.
    if (![self isValid]) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)initWithPreferenceDictionary:(NSDictionary *)prefDict {
  if ((self = [super init])) {
    NSString *className = [prefDict objectForKey:kHGSExtensionClassKey];
    [self setClassName:className];

    NSString *displayName = [prefDict objectForKey:kHGSExtensionUserVisibleNameKey];
    [self setDisplayName:displayName];
    
    NSString *protoIdentifier = [prefDict objectForKey:kHGSExtensionIdentifierKey];
    [self setProtoIdentifier:protoIdentifier];
    
    // TODO(mrossetti): Handle icon.

    NSString *extensionPointKey = [prefDict objectForKey:kHGSExtensionPointKey];
    [self setExtensionPointKey:extensionPointKey];

    BOOL isEnabled = [[prefDict objectForKey:kHGSExtensionEnabledKey] boolValue];
    isEnabled_ = isEnabled;  // Don't use setter -- we don't want side effects.
    
    [self setIsOld:YES];
    
    // Validate the extension.
    if (![self isValid]) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [plugin_ release];
  [extension_ release];
  [className_ release];
  [moduleName_ release];
  [displayName_ release];
  [extensionPointKey_ release];
  [protoIdentifier_ release];
  [extensionDict_ release];
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
  HGSProtoExtension* copiedExtension
    = [[HGSProtoExtension allocWithZone:zone] init];
  if (copiedExtension) {
    [copiedExtension setExtension:[self extension]];
    [copiedExtension setClassName:[self className]];
    [copiedExtension setModuleName:[self moduleName]];
    [copiedExtension setDisplayName:[self displayName]];
    [copiedExtension setExtensionPointKey:[self extensionPointKey]];
    [copiedExtension setProtoIdentifier:[self protoIdentifier]];
    // Do not use setter--Don't want side-effects.
    copiedExtension->isEnabled_ = [self isEnabled];
    [copiedExtension setIsOld:[self isOld]];
    [copiedExtension setIsNew:[self isNew]];
    [copiedExtension setExtensionDictionary:[self extensionDictionary]];
    
    if (![copiedExtension isValid]) {
      [copiedExtension release];
      copiedExtension = nil;
    }
  }
  return copiedExtension;
}

- (NSDictionary *)dictionaryValue {
  // This will create a dictionary that can be used to reconstitute
  // a protoExtension using -[initWithDictionary:], above.
  NSNumber *isEnabled = [NSNumber numberWithBool:[self isEnabled]];
  NSMutableDictionary *extDict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                  [self className], kHGSExtensionClassKey,
                                  [self displayName], kHGSExtensionUserVisibleNameKey,
                                  [self protoIdentifier], kHGSExtensionIdentifierKey,
                                  isEnabled, kHGSExtensionEnabledKey,
                                  // extensionPointKey can be nil so put it last.
                                  [self extensionPointKey], kHGSExtensionPointKey,
                                 nil];
  return extDict;
}

- (NSArray *)factor {
  // Determine if this protoExtension should be factored and, if so,
  // create one or more factored protoextensions, otherwise just return
  // this proto extension.
  NSArray *factors = nil;
  NSString *desiredAccountType
    = [[self extensionDictionary] objectForKey:kHGSExtensionDesiredAccountType];
  if (desiredAccountType) {
    NSMutableArray *factoredExtensions = [NSMutableArray array];
    // Create a copy of self for each account that's available.
    HGSAccountsExtensionPoint *aep
      = [HGSAccountsExtensionPoint accountsExtensionPoint];
    NSEnumerator *accountEnum = [aep accountsEnumForType:desiredAccountType];
    id<HGSAccount> account = nil;
    while ((account = [accountEnum nextObject])) {
      HGSProtoExtension *factoredExtension
        = [[self copyWithFactor:account
                         forKey:kHGSExtensionAccountIdentifier] autorelease];
      [factoredExtensions addObject:factoredExtension];
      
      // Register this protoExtension to receive notifications of pending
      // removal of the account so that the removal can be propogated to 
      // the extension.
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:factoredExtension
             selector:@selector(willRemoveAccount:)
                 name:kHGSWillRemoveAccountNotification
               object:nil];
    }
    factors = factoredExtensions;
  } else {
    factors = [NSArray arrayWithObject:self];
  }
  return factors;
}

- (NSAttributedString *)extensionDescription {
  NSBundle *bundle = [[self plugin] bundle];
  NSAttributedString *description = nil;
  if (bundle) {
    NSString *extensions[] = {
      @"html",
      @"rtf",
      @"rtfd"
    };
    for (size_t i = 0; i < sizeof(extensions) / sizeof(NSString *); ++i) {
      NSString *path = [bundle pathForResource:@"Description"
                                        ofType:extensions[i]];
      if (path) {
        description 
          = [[[NSAttributedString alloc] initWithPath:path
                                   documentAttributes:nil] autorelease];
        if (description) {
          break;
        }
      }
    }
  }
  return description;
}

- (NSString *)extensionVersion {
  return [self objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (BOOL)notIsOld {
  return ![self isOld];
}

- (BOOL)notIsNew {
  return ![self isNew];
}

- (BOOL)autoSetIsEnabled {
  // This function is only called during plugin loading and only for
  // new extensions.
  // Set isEnabled_ for an extension according to the setting for
  // HGSIsEnabledByDefault, if there is one.  Otherwise, set to NO if
  // an account is desired.  Otherwise set to YES.
  // NOTE: Do not use the 'setIsEnabled' setter in this function
  // as we don't want the side effects.
  BOOL wasDisabled = NO;
  if ([self isNew]) {
    isEnabled_ = YES;  // Default setting.
    NSNumber *isEnabledByDefaultValue = [[self extensionDictionary]
                                         objectForKey:kHGSIsEnabledByDefault];
    if (isEnabledByDefaultValue) {
      BOOL doEnable = [isEnabledByDefaultValue boolValue];
      if (!doEnable) {
        isEnabled_ = NO;
        wasDisabled = YES;
      }
    } else {
      NSString *desiredAccountType
        = [[self extensionDictionary] 
           objectForKey:kHGSExtensionDesiredAccountType];
      if (desiredAccountType != nil) {
        // Do not use the setter as we don't want the side effects.
        isEnabled_ = NO;
        wasDisabled = YES;
      }
    }
  }
  return wasDisabled;
}

- (NSComparisonResult)compare:(HGSProtoExtension *)extensionB {
  NSString *aIdentifier = [self protoIdentifier];
  NSString *bIdentifier = [extensionB protoIdentifier];
  NSComparisonResult result = [aIdentifier compare:bIdentifier];
  
  if (result == NSOrderedSame) {
    NSString *extensionPointKeyA = [self extensionPointKey];
    NSString *extensionPointKeyB = [extensionB extensionPointKey];
    if (extensionPointKeyA && extensionPointKeyB) {
      result = [extensionPointKeyA compare:extensionPointKeyB];
    } else if (extensionPointKeyA) {
      result = NSOrderedDescending;
    } else {
      result = NSOrderedAscending;
    }
  }
  
  return result;
}

- (HGSProtoExtension *)replaceWithProtoExtension:(HGSProtoExtension *)newExtension {
  [newExtension setIsNew:NO];
  [newExtension setIsOld:NO];
  // Don't use setter since we don't want the side-effect.
  // TODO(mrossetti): Oh heavens, fix this.  Just post a notification from
  // the spots where the prefs should be updated.
  newExtension->isEnabled_ = [self isEnabled];
  return newExtension;
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
  id value = nil;
  NSBundle *bundle = [[self plugin] bundle];
  if (bundle) {
    value = [bundle objectForInfoDictionaryKey:key];
  }
  return value;
}

- (void)setExtensionDictionaryObject:(id)factor forKey:(NSString *)key {
  NSMutableDictionary *extensionFactors
    = [[[self extensionDictionary] mutableCopy] autorelease];
  if (!extensionFactors) {
    extensionFactors = [NSMutableDictionary dictionaryWithObject:factor
                                                          forKey:key];
  } else {
    [extensionFactors setObject:factor forKey:key];
  }
  [self setExtensionDictionary:extensionFactors];
}

- (void)install {
  HGSPlugin *plugin = [self plugin];
  NSBundle *bundle = [plugin bundle];
  BOOL debugPlugins = [HGSPlugin validatePlugins];
  id<HGSExtension> extension = nil;

  NSMutableDictionary *configuration
    = [NSMutableDictionary dictionaryWithDictionary:[self extensionDictionary]];

  // TODO(mikro): why do we need to set class name back in?
  NSString *className = [self className];
  [configuration setObject:className forKey:kHGSExtensionClassKey];
  
  // Ensure it's got a user visible name set in it (since we default it if the
  // key wasn't in the config dict).
  NSString *displayName = [self displayName];
  [configuration setObject:displayName forKey:kHGSExtensionUserVisibleNameKey];

  if (bundle) {
    // TODO(mikro): should we ever have an extension without a bundle?
    [configuration setObject:bundle forKey:kHGSExtensionBundleKey];
  }
  
  // Ensure the bundle is loaded
  if (![bundle isLoaded]) {
    // TODO(dmaclach): if we move stats, python, etc. from the current extension
    // loading, we can make all plugin's not get loaded until here, so we don't
    // may costs during startup for loading and never load a code bundle if it
    // has no active sources/actions.
    if (![bundle load] && debugPlugins) {
      HGSLog(@"Unable to load bundle %@", bundle);
    }
  }
  // Create it now
  Class extensionPointClass = NSClassFromString(className);
  if (extensionPointClass 
      && [extensionPointClass
          instancesRespondToSelector:@selector(initWithConfiguration:)]) {
    @try {
      // We have a try block here as this is a common fail place for extensions
      // and we don't want a failure to take out installing all the other
      // extensions. Since we are calling 3rd party code, we can't be sure
      // they will be kind to us.
      extension
        = [[[extensionPointClass alloc] initWithConfiguration:configuration] 
           autorelease];
    }
    @catch (NSException *e) {
      HGSLog(@"Unable to init extension %@", extension);
    }
  }
  if (extension) {
    NSString *extensionPointKey = [self extensionPointKey];
    if (extensionPointKey) {
      HGSExtensionPoint *point
        = [HGSExtensionPoint pointWithIdentifier:extensionPointKey];
      if ([point extendWithObject:extension]) {
        [self setExtension:extension];
        // TODO(mrossetti): Make sure we should change the proto identifier
        // here rather than just set the extension's identifier above.
        [self setProtoIdentifier:[extension identifier]];
      } else {
        if (debugPlugins) {
          HGSLog(@"Unable to extend %@ with %@ in %@",
                 point, extension, bundle);
        }
      }
    }
  } else {
    if (debugPlugins) {
      HGSLog(@"Unable to instantiate extension %@ in %@",
             className, bundle);
    }
  }
}

- (void)uninstall {
  if ([self isInstalled]) {
    NSString *extensionPointKey = [self extensionPointKey];
    HGSExtensionPoint *point
      = [HGSExtensionPoint pointWithIdentifier:extensionPointKey];
    [point removeExtension:extension_];
    [self setExtension:nil];
  }
}

- (BOOL)isInstalled {
  return ([self extension] != nil);
}

- (void)setIsEnabled:(BOOL)isEnabled {
  if (isEnabled_ != isEnabled) {
    BOOL notify = YES;
    isEnabled_ = isEnabled;
    if (isEnabled) {
      [self install];
    } else if ([self isInstalled]) {
      [self uninstall];
    } else {
      // Don't signal if we aren't installed to prevent a flood of
      // notifications at startup.
      notify = NO;
    }

    // Signal that the plugin's enabling setting has changed.
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    NSNotification *notification
      = [NSNotification notificationWithName:kHGSExtensionDidChangeEnabledNotification
                                      object:self];
    [center postNotification:notification];
  }
}

- (BOOL)isUserVisibleAndExtendsExtensionPoint:(NSString *)extensionPoint {
  BOOL doesExtend = [[self extensionPointKey] isEqualToString:extensionPoint];
  if (doesExtend) {
    NSNumber *isUserVisibleValue = [[self extensionDictionary]
                                    objectForKey:kHGSIsUserVisible];
    if (isUserVisibleValue) {
      doesExtend = [isUserVisibleValue boolValue];
    }
  }
  return doesExtend;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@:%p displayName='%@', class='%@', module='%@', "
          @"extensionPoint='%@', protoIdentifier='%@', "
          @"isEnabled=%d, isOld=%d, isNew=%d, plugin=%p\nextensionDict: %@>",
          [self class], self, displayName_, className_, moduleName_, 
          extensionPointKey_, protoIdentifier_, isEnabled_, 
          isOld_, isNew_, plugin_, extensionDict_];
}

@end


@implementation HGSProtoExtension (HGSProtoExtensionPrivateMethods)

- (id)copyWithFactor:(id<HGSAccount>)factor
              forKey:(NSString *)key {
  HGSProtoExtension *protoCopy = [self copyWithZone:[self zone]];
  [protoCopy setExtensionDictionaryObject:factor forKey:key];
  
  NSString *factorIdentifier = [factor identifier];
  
  // Recalculate the proto extension identifier.
  NSString *protoIdentifier
    = [[self protoIdentifier] stringByAppendingFormat:@".%@",
       factorIdentifier];
  [protoCopy setProtoIdentifier:protoIdentifier];
  
  // Update the extension identifier.
  NSString *extensionIdentifier = [[self extensionDictionary]
                                  objectForKey:kHGSExtensionIdentifierKey];
  if ([extensionIdentifier length]) {
    extensionIdentifier
      = [extensionIdentifier stringByAppendingFormat:@".%@", factorIdentifier];
  } else {
    extensionIdentifier = protoIdentifier;
  }
  [protoCopy setExtensionDictionaryObject:extensionIdentifier
                                   forKey:kHGSExtensionIdentifierKey];
  
  // Enhance the displayName.
  // TODO(mrossetti): This will get fancier and allow clicking on account
  // name in order to go to the account in the account list.
  NSString *newDisplayName = [[self displayName] stringByAppendingFormat:@" (%@)",
                              [factor accountName]];
  [protoCopy setDisplayName:newDisplayName];
  
  return protoCopy;
}

- (BOOL)isValid {
  BOOL isValid = ([self className]
                  && [self displayName]
                  && [self protoIdentifier]);
  if (!isValid) {
    if ([HGSPlugin validatePlugins]) {
      HGSLog(@"Extension failed to validate.");
    }
  }
  return isValid;
}

- (void)setExtension:(HGSExtension *)extension {
  [extension_ autorelease];
  extension_ = [extension retain];
}

- (void)setClassName:(NSString *)className {
  [className_ release];
  className_ = [className copy];
}

- (void)setModuleName:(NSString *)moduleName {
  [moduleName_ release];
  moduleName_ = [moduleName copy];
}

- (void)setDisplayName:(NSString *)displayName {
  [displayName_ release];
  displayName_ = [displayName copy];
}

- (void)setExtensionPointKey:(NSString *)extensionPointKey {
  [extensionPointKey_ release];
  extensionPointKey_ = [extensionPointKey copy];
}

- (void)setProtoIdentifier:(NSString *)protoIdentifier {
  [protoIdentifier_ release];
  protoIdentifier_ = [protoIdentifier copy];
}

- (void)setExtensionDictionary:(NSDictionary *)extensionDict {
  [extensionDict_ release];
  extensionDict_ = [extensionDict copy];
}

#pragma mark Notification Handling

- (void)willRemoveAccount:(NSNotification *)notification {
  BOOL alsoRemoveClient = YES;  // Remove ourself unless our installed
  // extension tells us otherwise.
  if ([self isInstalled]) {
    // Inform our extension that the account is going away.
    HGSExtension *extension = [self extension];
    if ([extension conformsToProtocol:@protocol(HGSAccountClientProtocol)]) {
      id<HGSAccountClientProtocol> accountClient
      = (id<HGSAccountClientProtocol>)extension;
      HGSAccount *account = [notification object];
      alsoRemoveClient = [accountClient accountWillBeRemoved:account];
      if (alsoRemoveClient) {
        HGSPlugin *plugin = [self plugin];
        [plugin removeExtension:self];
      }
    } else {
      HGSLogDebug(@"Attempt to remove an account for an extension that "
                  @"does not support the HGSAccountClientProtocol. "
                  @"Extension identifier: '%@'", 
                  [self protoIdentifier]);
    }
  }
  if (alsoRemoveClient) {
    HGSPlugin *plugin = [self plugin];
    [plugin removeExtension:self]; 
  }
}

@end

// Notification sent when extension has been enabled/disabled.
NSString *const kHGSExtensionDidChangeEnabledNotification
   =@"HGSExtensionDidChangeEnabledNotification";

