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
#import "GTMObjectSingleton.h"
#import "HGSDelegate.h"
#import "HGSCodeSignature.h"
#import <openssl/aes.h>
#import <openssl/evp.h>
#import <openssl/x509.h>
#import <openssl/x509v3.h>

@interface HGSModuleLoader()
- (BOOL)isPluginAtPathCertified:(NSString *)path;
- (BOOL)pluginIsWhitelisted:(NSBundle *)pluginBundle
          withCodeSignature:(HGSCodeSignature *)pluginCodeSignature;
- (void)addPluginToWhitelist:(NSBundle *)pluginBundle
           withCodeSignature:(HGSCodeSignature *)pluginCodeSignature;
- (BOOL)retrieveEncryptionKey:(unsigned char *)key;
- (void)deleteEncryptionKey;
- (BOOL)generateRandomBytes:(unsigned char *)bytes count:(NSUInteger)count;
- (void)readPluginSignatureInfo;
- (void)writePluginSignatureInfo;
@end

static NSString *kPluginPathKey = @"PluginPathKey";
static NSString *kPluginSignatureKey = @"PluginSignatureKey";
static NSString *kPluginWhitelistKey = @"PluginWhitelistKey";
static NSString *kKeychainName = @"Plugins";
static NSString *kWhitelistFileName = @"PluginInfo";
static const UInt32 kEncryptionKeyLength = 16; // bytes, i.e., 128 bits
static const UInt32 kEncryptionIvLength = 16;
static const long kTenYearsInSeconds = 60 * 60 * 24 * 365 * 10;

NSString *const kHGSModuleLoaderPluginPathKey
  = @"HGSModuleLoaderPluginPathKey";
NSString *const kHGSModuleLoaderPluginFailureKey
  = @"HGSModuleLoaderPluginFailureKey";
NSString *const kHGSModuleLoaderPluginFailedCertification
  = @"HGSModuleLoaderPluginFailedCertification";
NSString *const kHGSModuleLoaderPluginFailedAPICheck
  = @"HGSModuleLoaderPluginFailedAPICheck";
NSString *const kHGSModuleLoaderPluginFailedInstantiation
  = @"HGSModuleLoaderPluginFailedInstantiation";
NSString *const kHGSModuleLoaderPluginFailedUnknownPluginType 
  = @"HGSModuleLoaderPluginFailedUnknownPluginType";

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
    
    executableSignature_
      = [[HGSCodeSignature codeSignatureForBundle:[NSBundle mainBundle]]
         retain];
    if ([executableSignature_ verifySignature] == eSignatureStatusOK) {
      executableCertificate_ = [executableSignature_ copySignerCertificate];
    } else {
      [executableSignature_ release];
      executableSignature_ = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [extensionMap_ release];
  [executableSignature_ release];
  [pluginSignatureInfo_ release];
  if (executableCertificate_) {
    CFRelease(executableCertificate_);
  }
  [super dealloc];
}

- (void)loadPluginsAtPath:(NSString*)pluginPath errors:(NSArray **)errors {
  if (pluginPath) {
    NSMutableArray *ourErrors = [NSMutableArray array];
    NSDirectoryEnumerator* dirEnum
      = [[NSFileManager defaultManager] enumeratorAtPath:pluginPath];
    HGSExtensionPoint *pluginsPoint = [HGSExtensionPoint pluginsPoint];
    for (NSString *path in dirEnum) {
      NSString *errorType = nil;
      [dirEnum skipDescendents];
      NSString* fullPath = [pluginPath stringByAppendingPathComponent:path];
      NSString *extension = [fullPath pathExtension];
      Class pluginClass = [extensionMap_ objectForKey:extension];
      if (pluginClass) {
        if ([self isPluginAtPathCertified:fullPath]) {
          if ([pluginClass isPluginAtPathValidAPI:fullPath]) {
            HGSPlugin *plugin = [[[pluginClass alloc] initWithPath:fullPath]
                                 autorelease];
            if (plugin) {
              [pluginsPoint extendWithObject:plugin];
            } else {
              errorType = kHGSModuleLoaderPluginFailedInstantiation;
            }
          } else {
            errorType = kHGSModuleLoaderPluginFailedAPICheck;
          }
        } else {
          errorType = kHGSModuleLoaderPluginFailedCertification;
        }
      } else {
        errorType = kHGSModuleLoaderPluginFailedUnknownPluginType;
      }
      if (errorType) {
        NSDictionary *errorDictionary
          = [NSDictionary dictionaryWithObjectsAndKeys:
             errorType, kHGSModuleLoaderPluginFailureKey,
             fullPath, kHGSModuleLoaderPluginPathKey,
             nil];
        [ourErrors addObject:errorDictionary];
      }
    }
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

- (BOOL)isPluginAtPathCertified:(NSString *)path {
  if (!executableSignature_) {
    // If the host application is not signed, do not perform validation.
    return YES;
  }
  
  NSBundle *pluginBundle = [NSBundle bundleWithPath:path];
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
      shouldLoad = [HGSCodeSignature certificate:executableCertificate_
                                         isEqual:pluginCertificate];
      CFRelease(pluginCertificate);
    } else {
      shouldLoad = NO;
    }
  }
  
  // Plugin is either not signed, or signed with an unknown
  // certificate. Ask the user to approve the plugin.
  if (!shouldLoad) {
    switch ([delegate_ shouldLoadPluginAtPath:path
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
  if (SecKeychainFindGenericPassword(NULL,
                                     [appName length],
                                     [appName UTF8String],
                                     [kKeychainName length],
                                     [kKeychainName UTF8String],
                                     &keyMaterialLengthFromKeychain,
                                     &keyMaterialFromKeychain,
                                     NULL) == noErr) {
    if (keyMaterialLengthFromKeychain == kEncryptionKeyLength) {
      // Keychain has an existing key, return that
      memcpy(key, keyMaterialFromKeychain, kEncryptionKeyLength);
      gotKey = YES;
    }
    SecKeychainItemFreeContent(NULL, keyMaterialFromKeychain);
  }
  
  if (!gotKey) {
    // Key material unavailable, create a new keychain item
    [self deleteEncryptionKey];
    if ([self generateRandomBytes:key count:kEncryptionKeyLength]) {
      if (SecKeychainAddGenericPassword(NULL,
                                       [appName length],
                                       [appName UTF8String],
                                       [kKeychainName length],
                                       [kKeychainName UTF8String],
                                       kEncryptionKeyLength,
                                       key,
                                       NULL) == noErr) {
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
  if (SecKeychainFindGenericPassword(NULL,
                                     [appName length],
                                     [appName UTF8String],
                                     [kKeychainName length],
                                     [kKeychainName UTF8String],
                                     &keyMaterialLengthFromKeychain,
                                     &keyMaterialFromKeychain,
                                     &itemRef) == noErr) {
    SecKeychainItemFreeContent(NULL, keyMaterialFromKeychain);
    SecKeychainItemDelete(itemRef);
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
