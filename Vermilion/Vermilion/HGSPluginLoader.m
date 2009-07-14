//
//  HGSPluginLoader.m
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
#import "GTMObjectSingleton.h"
#import "HGSDelegate.h"
#import "HGSCodeSignature.h"
#import "HGSPluginBlacklist.h"
#import "KeychainItem.h"
#import <openssl/aes.h>
#import <openssl/evp.h>
#import <openssl/x509.h>
#import <openssl/x509v3.h>

@interface HGSPluginLoader()
- (BOOL)isPluginBundleCertified:(NSBundle *)pluginBundle;
- (BOOL)pluginIsWhitelisted:(NSBundle *)pluginBundle
          withCodeSignature:(HGSCodeSignature *)pluginCodeSignature;
- (void)addPluginToWhitelist:(NSBundle *)pluginBundle
           withCodeSignature:(HGSCodeSignature *)pluginCodeSignature;
- (BOOL)retrieveEncryptionKey:(unsigned char *)key;
- (void)deleteEncryptionKey;
- (BOOL)generateRandomBytes:(unsigned char *)bytes count:(NSUInteger)count;
- (void)readPluginSignatureInfo;
- (void)writePluginSignatureInfo;
- (void)loadPluginsAtPath:(NSString*)pluginsPath errors:(NSArray **)errors;
@end

static NSString *kPluginPathKey = @"PluginPathKey";
static NSString *kPluginSignatureKey = @"PluginSignatureKey";
static NSString *kPluginWhitelistKey = @"PluginWhitelistKey";
static NSString *kKeychainName = @"Plugins";
static NSString *kWhitelistFileName = @"PluginInfo";
static const UInt32 kEncryptionKeyLength = 16; // bytes, i.e., 128 bits
static const UInt32 kEncryptionIvLength = 16;
static const long kTenYearsInSeconds = 60 * 60 * 24 * 365 * 10;

NSString *const kHGSPluginLoaderPluginPathKey
  = @"HGSPluginLoaderPluginPathKey";
NSString *const kHGSPluginLoaderPluginFailureKey
  = @"HGSPluginLoaderPluginFailureKey";
NSString *const kHGSPluginLoaderPluginFailedCertification
  = @"HGSPluginLoaderPluginFailedCertification";
NSString *const kHGSPluginLoaderPluginFailedAPICheck
  = @"HGSPluginLoaderPluginFailedAPICheck";
NSString *const kHGSPluginLoaderPluginFailedInstantiation
  = @"HGSPluginLoaderPluginFailedInstantiation";
NSString *const kHGSPluginLoaderPluginFailedUnknownPluginType 
  = @"HGSPluginLoaderPluginFailedUnknownPluginType";
NSString *const kHGSPluginLoaderWillLoadPluginsNotification
  = @"HGSPluginLoaderWillLoadPluginsNotification";
NSString *const kHGSPluginLoaderDidLoadPluginsNotification
  = @"HGSPluginLoaderDidLoadPluginsNotification";
NSString *const kHGSPluginLoaderWillLoadPluginNotification
  = @"HGSPluginLoaderWillLoadPluginNotification";
NSString *const kHGSPluginLoaderDidLoadPluginNotification
  = @"HGSPluginLoaderDidLoadPluginNotification";
NSString *const kHGSPluginLoaderPluginKey
  = @"HGSPluginLoaderPluginKey";
NSString *const kHGSPluginLoaderPluginNameKey
  = @"HGSPluginLoaderPluginNameKey";
NSString *const kHGSPluginLoaderErrorKey
  = @"HGSPluginLoaderErrorKey";
NSString *const kHGSPluginLoaderDidInitializePluginsNotification
  = @"HGSPluginLoaderDidInitializePluginsNotification";

@implementation HGSPluginLoader

GTMOBJECT_SINGLETON_BOILERPLATE(HGSPluginLoader, sharedPluginLoader);

@synthesize delegate = delegate_;
@synthesize plugins = plugins_;

- (id)init {
  if ((self = [super init])) {
    extensionMap_ = [[NSMutableDictionary alloc] init];
    NSBundle *bnd = [NSBundle bundleForClass:[self class]];
    NSString *currentFrameworkPath
      = [[bnd bundlePath] stringByAppendingPathComponent:@"Versions/A"];
    bnd = [NSBundle bundleWithPath:currentFrameworkPath];
    frameworkSignature_
      = [[HGSCodeSignature codeSignatureForBundle:bnd] retain];
    executableSignature_
      = [[HGSCodeSignature codeSignatureForBundle:[NSBundle mainBundle]]
         retain];
    if ([frameworkSignature_ verifySignature] == eSignatureStatusOK &&
        [executableSignature_ verifySignature] == eSignatureStatusOK) {
      frameworkCertificate_ = [frameworkSignature_ copySignerCertificate];
    } else {
      [frameworkSignature_ release];
      frameworkSignature_ = nil;
      [executableSignature_ release];
      executableSignature_ = nil;
    }
  }
  return self;
}

// COV_NF_START
// Singleton, so never called.
- (void)dealloc {
  [extensionMap_ release];
  [executableSignature_ release];
  [frameworkSignature_ release];
  [pluginSignatureInfo_ release];
  [plugins_ release];
  if (frameworkCertificate_) {
    CFRelease(frameworkCertificate_);
  }
  [super dealloc];
}
// COV_NF_END

- (void)loadPluginsWithErrors:(NSArray **)errors {
  NSArray *pluginPaths = [[self delegate] pluginFolders];
  NSMutableArray *allErrors = [NSMutableArray array];
  for (NSString *pluginPath in pluginPaths) {
    NSArray *pluginErrors = nil;
    [self loadPluginsAtPath:pluginPath errors:&pluginErrors];
    if (pluginErrors) {
      [allErrors addObjectsFromArray:pluginErrors];
    }
  }
  if (errors) {
    *errors = allErrors;
  }
  HGSExtensionPoint *pluginsPoint = [HGSExtensionPoint pluginsPoint];
  NSArray *factorablePlugins = [pluginsPoint extensions];
  
  // Installing extensions is done in this order:
  //   1. Install account type extensions.
  //   2. Install previously setup accounts from our preferences.  This 
  //      step relies on the account types having been installed in Step 1.
  //      This needs to be done before you call.
  //      -installAndEnablePluginsBasedOnPluginsState
  //   3. Factor all factorable extensions.  This step relies on accounts
  //      having been reconstituted in Step 2.
  //   4. Install all non-account type extensions.
  
  // Step 1: Install the account type extensions.
  [factorablePlugins makeObjectsPerformSelector:@selector(installAccountTypes)];
  
  [self setPlugins:factorablePlugins];
}

- (void)installAndEnablePluginsBasedOnPluginsState:(NSArray *)state {
  NSArray *plugins = [self plugins];
  
  // Step 3: Factor the new extensions now that we know all available accounts.
  [plugins makeObjectsPerformSelector:@selector(factorProtoExtensions)];
  
  // Step 4: Go through our plugins and set enabled states based on what
  // the user has saved off in their prefs.
  for (HGSPlugin *plugin in plugins) {
    NSString *pluginIdentifier = [plugin identifier];
    NSDictionary *oldPluginDict = nil;
    for (oldPluginDict in state) {
      NSString *oldID = [oldPluginDict objectForKey:kHGSBundleIdentifierKey];
      if ([oldID isEqualToString:pluginIdentifier]) {
        break;
      }
    }
    // If a user has turned off a plugin, then all extensions associated
    // with that plugin are turned off. New plugins are on by default.
    BOOL pluginEnabled = YES;
    if (oldPluginDict) {
      pluginEnabled 
        = [[oldPluginDict objectForKey:kHGSPluginEnabledKey] boolValue];
    }
    [plugin setEnabled:pluginEnabled];
    
    // Now run through all the extensions in the plugin. Due to us moving
    // code around an extension may have moved from one plugin to another.
    // So even though we found a matching plugin above, we will search
    // through all the plugins looking for a match.
    NSArray *protoExtensions = [plugin protoExtensions];
    for (HGSProtoExtension *protoExtension in protoExtensions) {
      BOOL protoExtensionEnabled = YES;
      NSString *protoExtensionID = [protoExtension identifier];
      NSDictionary *oldExtensionDict = nil;
      for (oldPluginDict in state) {
        NSArray *oldExtensionDicts 
          = [oldPluginDict objectForKey:kHGSPluginExtensionsDicts];
        for (oldExtensionDict in oldExtensionDicts) {
          NSString *oldID 
            = [oldExtensionDict objectForKey:kHGSExtensionIdentifierKey];
          if ([oldID isEqualToString:protoExtensionID]) {
            protoExtensionEnabled 
               = [[oldExtensionDict objectForKey:kHGSExtensionEnabledKey] boolValue];
            break;
          }
        }
        if (oldExtensionDict) break;
      }
      // Due to us moving code around, an extension may have moved from one
      // plugin to another
      if (oldExtensionDict) {
        [protoExtension setEnabled:protoExtensionEnabled];
      }
    }
    if ([plugin isEnabled]) {
      [plugin install];
    }
  }
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kHGSPluginLoaderDidInitializePluginsNotification 
                    object:self];
}

- (NSArray *)pluginsState {
  // Save these plugins in preferences. All we care about at this point is
  // the enabled state of the plugin and it's extensions.
  NSArray *plugins = [self plugins];
  NSUInteger count = [plugins count];
  NSMutableArray *archivablePlugins = [NSMutableArray arrayWithCapacity:count];
  for (HGSPlugin *plugin in plugins) {
    NSArray *protoExtensions = [plugin protoExtensions];
    count = [protoExtensions count];
    NSMutableArray *archivableExtensions = [NSMutableArray arrayWithCapacity:count];
    for (HGSProtoExtension *protoExtension in protoExtensions) {
      NSNumber *isEnabled = [NSNumber numberWithBool:[protoExtension isEnabled]];
      NSString *identifier = [protoExtension identifier];
      NSDictionary *protoValues = [NSDictionary dictionaryWithObjectsAndKeys:
                                   identifier, kHGSExtensionIdentifierKey,
                                   isEnabled, kHGSExtensionEnabledKey,
                                   nil];
      [archivableExtensions addObject:protoValues];
    }
    NSNumber *isEnabled = [NSNumber numberWithBool:[plugin isEnabled]];
    NSString *identifier = [plugin identifier];
    NSDictionary *archiveValues
      = [NSDictionary dictionaryWithObjectsAndKeys:
         identifier, kHGSBundleIdentifierKey,
         isEnabled, kHGSPluginEnabledKey,
         archivableExtensions, kHGSPluginExtensionsDicts,
         nil];
    [archivablePlugins addObject:archiveValues];
  }
  return archivablePlugins;
}

- (void)loadPluginsAtPath:(NSString*)pluginPath errors:(NSArray **)errors {
  if (pluginPath) {
    NSMutableArray *ourErrors = [NSMutableArray array];
    NSDirectoryEnumerator* dirEnum
      = [[NSFileManager defaultManager] enumeratorAtPath:pluginPath];
    HGSExtensionPoint *pluginsPoint = [HGSExtensionPoint pluginsPoint];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc postNotificationName:kHGSPluginLoaderWillLoadPluginsNotification 
                      object:self 
                    userInfo:nil];
    for (NSString *path in dirEnum) {
      NSString *errorType = nil;
      [dirEnum skipDescendents];
      NSString* fullPath = [pluginPath stringByAppendingPathComponent:path];
      NSString *extension = [fullPath pathExtension];
      Class pluginClass = [extensionMap_ objectForKey:extension];
      NSString *pluginName = [fullPath lastPathComponent];
      HGSPlugin *plugin = nil;
      if (pluginClass) {
        NSBundle *pluginBundle = [NSBundle bundleWithPath:fullPath];
        NSString *betterPluginName 
          = [pluginBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if (!betterPluginName) {
          betterPluginName 
            = [pluginBundle objectForInfoDictionaryKey:@"CFBundleName"];
        }
        if (betterPluginName) {
          pluginName = betterPluginName;
        }
        NSDictionary *willLoadUserInfo 
          = [NSDictionary dictionaryWithObject:pluginName 
                                        forKey:kHGSPluginLoaderPluginNameKey];
        [nc postNotificationName:kHGSPluginLoaderWillLoadPluginNotification
                          object:self 
                        userInfo:willLoadUserInfo];
        if ([self isPluginBundleCertified:pluginBundle]) {
          if ([pluginClass isPluginBundleValidAPI:pluginBundle]) {
            plugin 
              = [[[pluginClass alloc] initWithBundle:pluginBundle] autorelease];
            if (plugin) {
              [pluginsPoint extendWithObject:plugin];
            } else {
              errorType = kHGSPluginLoaderPluginFailedInstantiation;
            }
          } else {
            errorType = kHGSPluginLoaderPluginFailedAPICheck;
          }
        } else {
          errorType = kHGSPluginLoaderPluginFailedCertification;
        }
      } else {
        errorType = kHGSPluginLoaderPluginFailedUnknownPluginType;
      }
      NSDictionary *errorDictionary = nil;
      if (errorType) {
        errorDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
                           errorType, kHGSPluginLoaderPluginFailureKey,
                           fullPath, kHGSPluginLoaderPluginPathKey,
                           nil];
        [ourErrors addObject:errorDictionary];
      }
      NSMutableDictionary *didLoadUserInfo 
        = [NSMutableDictionary dictionaryWithObject:pluginName
                                             forKey:kHGSPluginLoaderPluginNameKey];
      if (plugin) {
        [didLoadUserInfo setObject:plugin forKey:kHGSPluginLoaderPluginKey];
      }
      if (errorDictionary) {
        [didLoadUserInfo setObject:errorDictionary 
                            forKey:kHGSPluginLoaderErrorKey];
      }
      [nc postNotificationName:kHGSPluginLoaderDidLoadPluginNotification 
                        object:self 
                      userInfo:didLoadUserInfo];
    }
    NSDictionary *didLoadsUserInfo = nil;
    if ([ourErrors count]) {
      didLoadsUserInfo 
        = [NSDictionary dictionaryWithObject:ourErrors 
                                      forKey:kHGSPluginLoaderErrorKey];
    }
    [nc postNotificationName:kHGSPluginLoaderDidLoadPluginsNotification 
                      object:self 
                    userInfo:didLoadsUserInfo];
    
    if (errors) {
      *errors = [ourErrors count] ? ourErrors : nil;
    }  
  }
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

- (BOOL)isPluginBundleCertified:(NSBundle *)pluginBundle {
  // Blacklisted plugins are never certified
  HGSPluginBlacklist *bl = [HGSPluginBlacklist sharedPluginBlacklist];
  if ([bl bundleIsBlacklisted:pluginBundle]) {
    HGSLog(@"Blocked loading of blacklisted bundle %@", pluginBundle);
    return NO;
  }
  
  if (!executableSignature_ || !frameworkSignature_) {
    // If the host application is not signed, do not perform validation.
    return YES;
  }
  
  HGSCodeSignature *signature
    = [HGSCodeSignature codeSignatureForBundle:pluginBundle];
  
  if ([self pluginIsWhitelisted:pluginBundle withCodeSignature:signature]) {
    // User has previously approved the plugin.
    return YES;
  }
  
  // Plugin must have a valid signature
  BOOL shouldLoad = ([signature verifySignature] == eSignatureStatusOK);
  // Plugin must have been signed by the same identity that signed
  // the application
  if (shouldLoad) {
    SecCertificateRef pluginCertificate = [signature copySignerCertificate];
    if (pluginCertificate) {
      shouldLoad = [HGSCodeSignature certificate:frameworkCertificate_
                                         isEqual:pluginCertificate];
      CFRelease(pluginCertificate);
    } else {
      shouldLoad = NO;
    }
  }
  
  // Plugin is either not signed, or signed with an unknown
  // certificate. Ask the user to approve the plugin.
  if (!shouldLoad) {
    switch ([delegate_ shouldLoadPluginAtPath:[pluginBundle bundlePath]
                                withSignature:signature]) {
      case eHGSAllowAlways:
        [self addPluginToWhitelist:pluginBundle
                 withCodeSignature:signature];
        shouldLoad = YES;
        break;
      case eHGSAllowOnce:
        shouldLoad = YES;
        break;
      default:
        shouldLoad = NO;
        break;
    }
  }
  
  return shouldLoad;
}

- (BOOL)pluginIsWhitelisted:(NSBundle *)pluginBundle
          withCodeSignature:(HGSCodeSignature *)pluginCodeSignature {
  BOOL isWhitelisted = NO;
  
  if (!pluginSignatureInfo_) {
    [self readPluginSignatureInfo];
  }
  
  NSString *path = [pluginBundle bundlePath];
  NSMutableArray *whitelist
    = [pluginSignatureInfo_ objectForKey:kPluginWhitelistKey];
  for (NSDictionary *whitelisted in whitelist) {
    if ([[whitelisted objectForKey:kPluginPathKey] isEqual:path]) {
      NSData *signatureData = [whitelisted objectForKey:kPluginSignatureKey];
      if (signatureData &&
          [pluginCodeSignature verifyDetachedSignature:signatureData]) {
        isWhitelisted = YES;
      }
    }
  }
  
  return isWhitelisted;
}

- (void)addPluginToWhitelist:(NSBundle *)pluginBundle
           withCodeSignature:(HGSCodeSignature *)pluginCodeSignature {
  if ([self pluginIsWhitelisted:pluginBundle
              withCodeSignature:pluginCodeSignature]) {
    return;
  }
  
  NSData *signatureData = [pluginCodeSignature generateDetachedSignature];
  if (signatureData) {
    NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
                           [pluginBundle bundlePath], kPluginPathKey,
                           signatureData, kPluginSignatureKey, nil];
    NSMutableArray *whitelist
      = [pluginSignatureInfo_ objectForKey:kPluginWhitelistKey];
    if (!whitelist) {
      whitelist = [NSMutableArray array];
    }
    [whitelist addObject:entry];
    [pluginSignatureInfo_ setObject:whitelist forKey:kPluginWhitelistKey];
    [self writePluginSignatureInfo];
  }
}

- (BOOL)retrieveEncryptionKey:(unsigned char *)key {
  BOOL gotKey = NO;
  
  NSString *appName = [[NSBundle mainBundle]
                       objectForInfoDictionaryKey:@"CFBundleDisplayName"];

  UInt32 keyMaterialLengthFromKeychain;
  void *keyMaterialFromKeychain;
  OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                   [appName length],
                                                   [appName UTF8String],
                                                   [kKeychainName length],
                                                   [kKeychainName UTF8String],
                                                   &keyMaterialLengthFromKeychain,
                                                   &keyMaterialFromKeychain,
                                                   NULL);
  if (!reportIfKeychainError(status)) {
    if (keyMaterialLengthFromKeychain == kEncryptionKeyLength) {
      // Keychain has an existing key, return that
      memcpy(key, keyMaterialFromKeychain, kEncryptionKeyLength);
      gotKey = YES;
    }
    reportIfKeychainError(SecKeychainItemFreeContent(NULL,
                                                     keyMaterialFromKeychain));
  }
  
  if (!gotKey) {
    // Key material unavailable, create a new keychain item
    [self deleteEncryptionKey];
    if ([self generateRandomBytes:key count:kEncryptionKeyLength]) {
      status = SecKeychainAddGenericPassword(NULL,
                                             [appName length],
                                             [appName UTF8String],
                                             [kKeychainName length],
                                             [kKeychainName UTF8String],
                                             kEncryptionKeyLength,
                                             key,
                                             NULL);
      if (!reportIfKeychainError(status)) {
        gotKey = YES;
      }
    }
  }
  
  return gotKey;
}

- (void)deleteEncryptionKey {
  NSString *appName = [[NSBundle mainBundle]
                       objectForInfoDictionaryKey:@"CFBundleDisplayName"];
  SecKeychainItemRef itemRef;
  UInt32 keyMaterialLengthFromKeychain;
  void *keyMaterialFromKeychain;
  OSStatus status = SecKeychainFindGenericPassword(NULL,
                                                   [appName length],
                                                   [appName UTF8String],
                                                   [kKeychainName length],
                                                   [kKeychainName UTF8String],
                                                   &keyMaterialLengthFromKeychain,
                                                   &keyMaterialFromKeychain,
                                                   &itemRef);
  if (!reportIfKeychainError(status)) {
    reportIfKeychainError(SecKeychainItemFreeContent(NULL,
                                                     keyMaterialFromKeychain));
    reportIfKeychainError(SecKeychainItemDelete(itemRef));
    CFRelease(itemRef);
  }
}
   
- (BOOL)generateRandomBytes:(unsigned char *)bytes count:(NSUInteger)count {
  NSUInteger pos = 0;
  
  int devRandFD = open("/dev/urandom", O_RDONLY | O_NONBLOCK);
  if (devRandFD > 0) {
    do {
      int amountRead = read(devRandFD, bytes + pos, count - pos);
      if (amountRead <= 0) {
        if (errno == EAGAIN || errno == EINTR) {
          continue;
        }
        break;
      }
      pos += (NSUInteger)amountRead;
    } while (pos < count);
    close(devRandFD);
  }

  return (pos == count);
}

- (void)readPluginSignatureInfo {
  NSData *decryptedData = nil;
  NSString *whitelistPath
    = [[delegate_ userApplicationSupportFolderForApp]
       stringByAppendingPathComponent:kWhitelistFileName];
  NSData *encryptedData = [NSData dataWithContentsOfFile:whitelistPath];
  if ([encryptedData length] > kEncryptionIvLength) {
    unsigned char encKey[16];
    if ([self retrieveEncryptionKey:encKey]) {
      unsigned char *plaintext = malloc([encryptedData length]);
      if (plaintext) {
        NSUInteger encLength = [encryptedData length] - kEncryptionIvLength;
        [encryptedData getBytes:plaintext];
        int cfbNum = 0;
        AES_KEY aesKey;
        AES_set_encrypt_key(encKey, kEncryptionKeyLength * 8, &aesKey);
        AES_cfb8_encrypt(plaintext + kEncryptionIvLength,
                         plaintext + kEncryptionIvLength,
                         encLength,
                         &aesKey,
                         plaintext,
                         &cfbNum,
                         AES_DECRYPT);
        decryptedData = [NSData dataWithBytes:plaintext + kEncryptionIvLength
                                       length:encLength];
        free(plaintext);
      }
    }
  }
  
  if (decryptedData) {
    [pluginSignatureInfo_ release];
    pluginSignatureInfo_ = nil;
    @try {
      pluginSignatureInfo_
        = [NSKeyedUnarchiver unarchiveObjectWithData:decryptedData];
    }
    @catch (NSException *e) {
      // Just to be safe, in case the file was corrupted. The
      // unarchiveObjectWithData: method is documented to return nil if the
      // the input cannot be decoded, but it throws more often than not.
      HGSLog(@"Unable to unarchive plugin info (%@)", e);
    }
  }
  if (!pluginSignatureInfo_) {
    pluginSignatureInfo_ = [[NSMutableDictionary alloc] init];
  }
}

- (void)writePluginSignatureInfo {
  NSData *data;
  data = [NSKeyedArchiver archivedDataWithRootObject:pluginSignatureInfo_];
  NSString *whitelistPath
    = [[delegate_ userApplicationSupportFolderForApp]
       stringByAppendingPathComponent:kWhitelistFileName];
  
  // Data is AES encrypted in CFB mode, stored with the 16 byte IV prepended
  unsigned char key[16];
  if ([self retrieveEncryptionKey:key]) {
    NSUInteger totalLength = [data length] + kEncryptionIvLength;
    unsigned char *encData = malloc(totalLength);
    if (encData) {
      unsigned char iv[16];
      if ([self generateRandomBytes:iv count:kEncryptionIvLength]) {
        memcpy(encData, iv, kEncryptionIvLength);
        [data getBytes:encData + kEncryptionIvLength];
        
        int cfbNum = 0;
        AES_KEY aesKey;
        AES_set_encrypt_key(key, kEncryptionKeyLength * 8, &aesKey);
        AES_cfb8_encrypt(encData + kEncryptionIvLength,
                         encData + kEncryptionIvLength,
                         [data length],
                         &aesKey,
                         iv,
                         &cfbNum,
                         AES_ENCRYPT);
        [[NSData dataWithBytes:encData length:totalLength]
         writeToFile:whitelistPath atomically:YES];
        free(encData);
      }
    }
  }
}

@end
