//
//  HGSCodeSignature.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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

#import <uuid/uuid.h>
#import <openssl/hmac.h>
#import <openssl/sha.h>
#import <Vermilion/Vermilion.h>
#import "HGSCodeSignature.h"

// Definitions for the code signing framework SPIs
typedef struct __SecRequirementRef *SecRequirementRef;
typedef struct __SecCodeSigner *SecCodeSignerRef;
typedef struct __SecCode const *SecStaticCodeRef;
enum {
  kSecCSSigningInformation = 2,
  errSecCSUnsigned = -67062,
  errSecCSBadObjectFormat = -67049,
  kCodeSignatureDigestLength = 20 // 160 bits
};
extern const NSString *kSecCodeInfoCertificates;
extern const NSString *kSecCodeSignerDetached;
extern const NSString *kSecCodeSignerIdentity;
OSStatus SecStaticCodeCreateWithPath(CFURLRef path, uint32_t flags,
                                     SecStaticCodeRef *staticCodeRef);
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, uint32_t flags,
                                       CFDictionaryRef *information);
OSStatus SecStaticCodeCheckValidityWithErrors(SecStaticCodeRef staticCodeRef,
                                              uint32_t flags,
                                              SecRequirementRef requirementRef,
                                              CFErrorRef *errors);
OSStatus SecCodeSignerCreate(CFDictionaryRef parameters, uint32_t flags,
                             SecCodeSignerRef *signer);
OSStatus SecCodeSignerAddSignatureWithErrors(SecCodeSignerRef signer,
                                             SecStaticCodeRef code,
                                             uint32_t flags,
                                             CFErrorRef *errors);
OSStatus SecCodeSetDetachedSignature(SecStaticCodeRef codeRef,
                                     CFDataRef signature, uint32_t flags);

static NSString *kSignatureDataKey = @"SignatureDataKey";
static NSString *kCertificateDataKey = @"CertificateDataKey";
static NSString *kSignatureDateKey = @"SignatureDateKey";
static NSString *kDetachedSignatureTypeKey = @"DetachedSignatureTypeKey";
static NSString *kCodeSignatureDirectory = @"QSBCodeSignature";
static NSString *kCodeSignatureFile = @"QSBCodeSignature.plist";
static const int kSignatureTypeStandard = 1;
static const int kSignatureTypeResource = 2;

@interface HGSCodeSignature()
- (BOOL)digest:(unsigned char *)digest usingKey:(NSData *)key;
- (BOOL)digestDirectory:(NSString *)path
             shaContext:(SHA_CTX *)shaCtx
            hmacContext:(HMAC_CTX *)hmacCtx;
- (NSDictionary *)embeddedResourceSignature;
@end

@implementation HGSCodeSignature

+ (HGSCodeSignature *)codeSignatureForBundle:(NSBundle *)bundle {
  return [[[HGSCodeSignature alloc] initWithBundle:bundle] autorelease];
}

- (id)initWithBundle:(NSBundle *)bundle {
  self = [super init];
  if (self) {
    bundle_ = [bundle retain];
  }
  return self;
}

- (void)dealloc {
  [bundle_ release];
  [super dealloc];
}

- (SecCertificateRef)copySignerCertificate {
  SecCertificateRef result = NULL;
  
  CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[bundle_ bundlePath]];
  if (url) {
    SecStaticCodeRef codeRef;
    if (SecStaticCodeCreateWithPath(url, 0, &codeRef) == noErr) {
      if (SecStaticCodeCheckValidityWithErrors(codeRef, 0,
                                               NULL, NULL) == noErr) {
        CFDictionaryRef signingInfo;
        if (SecCodeCopySigningInformation(codeRef, kSecCSSigningInformation,
                                          &signingInfo) == noErr) {
          CFArrayRef certs = CFDictionaryGetValue(signingInfo,
                                                  kSecCodeInfoCertificates);
          if (certs && CFArrayGetCount(certs)) {
            SecCertificateRef cert;
            cert = (SecCertificateRef)CFArrayGetValueAtIndex(certs, 0);
            if (cert) {
              // Make a deep copy of the certificate so that callers can
              // retain it after releasing us (the code signing framework
              // does not like having its own SecCertificateRef retained
              // after the info dictionary is released);
              CSSM_DATA signerDer;
              if (SecCertificateGetData(cert, &signerDer) == noErr) {
                SecCertificateCreateFromData(&signerDer, CSSM_CERT_X_509v3,
                                             CSSM_CERT_ENCODING_DER,
                                             &result);
              }
            }
          }
        }
        CFRelease(signingInfo);
      }
      CFRelease(codeRef);
    }
  }
  
  if (!result) {
    NSDictionary *sigDict = [self embeddedResourceSignature];
    if (sigDict) {
      NSData *certificateData = [sigDict objectForKey:kCertificateDataKey];
      if (certificateData) {
        CSSM_DATA cssmData;
        cssmData.Length = [certificateData length];
        cssmData.Data = (void *)[certificateData bytes];
        SecCertificateCreateFromData(&cssmData, CSSM_CERT_X_509v3,
                                     CSSM_CERT_ENCODING_DER, &result);
      }
    }
  }
  
  return result;
}

+ (BOOL)certificate:(SecCertificateRef)cert1
            isEqual:(SecCertificateRef)cert2 {
  BOOL result = NO;
  
  if (cert1 && cert2) {
    if (cert1 == cert2) {
      result = YES;
    } else {
      // Compare by doing a memcmp of the two certificates' DER encoding
      CSSM_DATA certDer, signerDer;
      if (SecCertificateGetData(cert1, &certDer) == noErr &&
          SecCertificateGetData(cert2, &signerDer) == noErr &&
          certDer.Length == signerDer.Length &&
          memcmp(certDer.Data, signerDer.Data, certDer.Length) == 0) {
        result = YES;
      }
    }
  }
  
  return result;
}

- (BOOL)generateSignatureUsingIdentity:(SecIdentityRef)identity {
  BOOL result = NO;
  
  if (!bundle_ || !identity) {
    return NO;
  }
  
  // Start by trying to create a standard Mac OS X code signature on the
  // bundle. This works only with bundles containing a Mac executable.
  OSStatus err = fnfErr;
  CFTypeRef keys[] = { kSecCodeSignerIdentity };
  CFTypeRef values[] = { identity };
  CFDictionaryRef parameters
    = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
                         &kCFTypeDictionaryKeyCallBacks,
                         &kCFTypeDictionaryValueCallBacks);
  if (parameters) {
    NSURL *url = [NSURL fileURLWithPath:[bundle_ bundlePath]];
    if (url) {
      SecStaticCodeRef codeRef;
      if ((err = SecStaticCodeCreateWithPath((CFURLRef)url, 0,
                                             &codeRef)) == noErr) {
        SecCodeSignerRef signer;
        if (SecCodeSignerCreate(parameters, 0, &signer) == noErr) {
          CFErrorRef errors = NULL;
          err = SecCodeSignerAddSignatureWithErrors(signer, codeRef, 0,
                                                    &errors);
          CFRelease(signer);
        }
        CFRelease(codeRef);
      }
    }
    CFRelease(parameters);
  }
  
  if (err == noErr) {
    // Standard code signing succeeded
    result = YES;
  } else if (err == errSecCSBadObjectFormat) {
    // Code signing failed due to a lack of a Mach executable,
    // perform our built-in code signing instead.
    NSData *sigData = nil;
    // Digest the the files
    unsigned char digest[kCodeSignatureDigestLength];
    if ([self digest:digest usingKey:nil]) {
      SecKeyRef privateKey;
      // Sign the digest
      if (SecIdentityCopyPrivateKey(identity, &privateKey) == noErr) {
        CSSM_CSP_HANDLE csp;
        if (SecKeyGetCSPHandle(privateKey, &csp) == noErr) {
          const CSSM_KEY *cssmKey;
          if (SecKeyGetCSSMKey(privateKey, &cssmKey) == noErr) {
            const CSSM_ACCESS_CREDENTIALS *cred;
            if (SecKeyGetCredentials(privateKey, CSSM_ACL_AUTHORIZATION_SIGN,
                                     kSecCredentialTypeDefault,
                                     &cred) == noErr) {
              CSSM_CC_HANDLE sigCtx;
              if (CSSM_CSP_CreateSignatureContext(csp, CSSM_ALGID_SHA1WithRSA,
                                                  cred, cssmKey,
                                                  &sigCtx) == noErr) {
                CSSM_DATA input, output = { 0, NULL };
                input.Length = kCodeSignatureDigestLength;
                input.Data = digest;
                if (CSSM_SignData(sigCtx, &input, 1, CSSM_ALGID_SHA1,
                                  &output) == noErr) {
                  sigData = [NSData dataWithBytes:output.Data
                                           length:output.Length];
                }
                CSSM_DeleteContext(sigCtx);
              }
            }
          }
        }
        CFRelease(privateKey);
      }
      NSData *certData = nil;
      if (sigData) {
        // Copy the certificate
        SecCertificateRef certificateRef = NULL;
        if (SecIdentityCopyCertificate(identity, &certificateRef) == noErr) {
          CSSM_DATA cssmData;
          if (SecCertificateGetData(certificateRef, &cssmData) == noErr) {
            certData
              = [NSData dataWithBytes:cssmData.Data length:cssmData.Length];
          }
          CFRelease(certificateRef);
        }
      }
      if (sigData && certData) {
        // Create and write the dictionary file with the signature,
        // certificate, and date/time
        NSDictionary *sigDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                 sigData, kSignatureDataKey,
                                 certData, kCertificateDataKey,
                                 [NSDate date], kSignatureDateKey,
                                 nil];
        NSString *dirPath
          = [[[bundle_ bundlePath] stringByAppendingPathComponent:@"Contents"]
             stringByAppendingPathComponent:kCodeSignatureDirectory];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDirectory;
        if (![fm fileExistsAtPath:dirPath isDirectory:&isDirectory]) {
          // Create the directory
          [fm createDirectoryAtPath:dirPath attributes:nil];
        }
        NSString *sigPath
          = [dirPath stringByAppendingPathComponent:kCodeSignatureFile];
        result = [sigDict writeToFile:sigPath atomically:YES];
      }
    }
  }
  
  return result;
}

- (HGSSignatureStatus)verifySignature {
  HGSSignatureStatus result = eSignatureStatusInvalid;

  // Try validating the Mac OS X code signature first
  OSStatus err = fnfErr;
  CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[bundle_ bundlePath]];
  if (url) {
    SecStaticCodeRef codeRef;
    if ((err = SecStaticCodeCreateWithPath(url, 0, &codeRef)) == noErr) {
      err = SecStaticCodeCheckValidityWithErrors(codeRef, 0, NULL, NULL);
      CFDictionaryRef signingInfo;
      switch (err) {
        case errSecCSUnsigned:
          result = eSignatureStatusUnsigned;
          break;
        case noErr:
          if (SecCodeCopySigningInformation(codeRef, kSecCSSigningInformation,
                                            &signingInfo) == noErr) {
            CFArrayRef certs = CFDictionaryGetValue(signingInfo,
                                                    kSecCodeInfoCertificates);
            if (certs && CFArrayGetCount(certs)) {
              SecCertificateRef cert;
              cert = (SecCertificateRef)CFArrayGetValueAtIndex(certs, 0);
              if (cert) {
                // Require a certificate, since our trust model relies on
                // matching certificates between the app and plugins
                result = eSignatureStatusOK;
              }
            }
            CFRelease(signingInfo);
          }
          break;
      }
      CFRelease(codeRef);
    }
  }
  
  if (err == errSecCSBadObjectFormat) {
    // There is no Mac OS X code signature, check for a resource code signature 
    NSDictionary *sigDict = [self embeddedResourceSignature];
    if (sigDict) {
      NSData *certificateData = [sigDict objectForKey:kCertificateDataKey];
      if (certificateData) {
        SecCertificateRef certificateRef;
        CSSM_DATA cssmData;
        cssmData.Length = [certificateData length];
        cssmData.Data = (void *)[certificateData bytes];
        if (SecCertificateCreateFromData(&cssmData, CSSM_CERT_X_509v3,
                                         CSSM_CERT_ENCODING_DER,
                                         &certificateRef) == noErr) {
          NSData *sigData = [sigDict objectForKey:kSignatureDataKey];
          unsigned char digest[kCodeSignatureDigestLength];
          if (sigData && [self digest:digest usingKey:nil]) {          
            SecKeyRef publicKey;
            if (SecCertificateCopyPublicKey(certificateRef,
                                            &publicKey) == noErr) {
              CSSM_CSP_HANDLE csp;
              if (SecKeyGetCSPHandle(publicKey, &csp) == noErr) {
                const CSSM_KEY *cssmKey;
                if (SecKeyGetCSSMKey(publicKey, &cssmKey) == noErr) {
                  CSSM_CC_HANDLE sigCtx;
                  if (CSSM_CSP_CreateSignatureContext(csp, CSSM_ALGID_SHA1WithRSA,
                                                      NULL, cssmKey,
                                                      &sigCtx) == noErr) {
                    CSSM_DATA cssmDigestData, cssmSigData;
                    cssmDigestData.Length = kCodeSignatureDigestLength;
                    cssmDigestData.Data = digest;
                    cssmSigData.Length = [sigData length];
                    cssmSigData.Data = (void *)[sigData bytes];
                    if (CSSM_VerifyData(sigCtx, &cssmDigestData, 1,
                                        CSSM_ALGID_SHA1,
                                        &cssmSigData) == noErr) {
                      result = eSignatureStatusOK;
                    }
                    CSSM_DeleteContext(sigCtx);
                  }
                }
              }
              CFRelease(publicKey);
            }
          }
          CFRelease(certificateRef);
        }
      }
    }
  }
  
  return result;
}

- (NSData *)generateDetachedSignature {
  NSData *sigData = nil;
  NSNumber *sigType = nil;
  
  uuid_t uuid;
  uuid_generate(uuid);
  char uuidString[37];
  uuid_unparse(uuid, uuidString);
  NSString *detachedFilePath
    = [NSTemporaryDirectory() stringByAppendingPathComponent:
       [NSString stringWithUTF8String:uuidString]];
  NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSURL fileURLWithPath:detachedFilePath],
                              kSecCodeSignerDetached,
                              kCFNull, kSecCodeSignerIdentity,
                              nil];
  
  OSStatus err = fnfErr;
  CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[bundle_ bundlePath]];
  if (url) {
    SecStaticCodeRef codeRef;
    if ((err = SecStaticCodeCreateWithPath(url, 0, &codeRef)) == noErr) {
      SecCodeSignerRef signer;
      if (SecCodeSignerCreate((CFDictionaryRef)parameters, 0,
                              &signer) == noErr) {
        CFErrorRef errors = NULL;
        if (SecCodeSignerAddSignatureWithErrors(signer, codeRef, 0,
                                                &errors) == noErr) {
          // TODO(hawk): There is a race condition at this point. An attacker
          // could conceivably write a different signature to our temp file
          // before we read it, causing us to trust the signature on their
          // malicious plugin. Figure out something to avoid this.
          sigData = [NSData dataWithContentsOfFile:detachedFilePath];
          sigType = [NSNumber numberWithInt:kSignatureTypeStandard];
        } else {
          if (errors) {
            CFStringRef desc = CFErrorCopyDescription(errors);
            if (desc) {
              HGSLog(@"Failed to generate code signature: %@", desc);
              CFRelease(desc);
            }
            CFRelease(errors);
          }
        }
        CFRelease(signer);
      }
      CFRelease(codeRef);
    }
  }
  
  if (err == errSecCSBadObjectFormat) {
    // No Mach executable available for standard Mac OS X code signing,
    // generate a resource code signature
    unsigned char digest[kCodeSignatureDigestLength];
    if ([self digest:digest usingKey:nil]) {
      sigData = [NSData dataWithBytes:digest
                               length:kCodeSignatureDigestLength];
      sigType = [NSNumber numberWithInt:kSignatureTypeResource];
    }
  }
  
  NSData *result = nil;
  if (sigData && sigType) {
    NSDictionary *sigDict = [NSDictionary dictionaryWithObjectsAndKeys:
                             sigData, kSignatureDataKey,
                             sigType, kDetachedSignatureTypeKey,
                             [NSDate date], kSignatureDateKey,
                             nil];
    result = [NSKeyedArchiver archivedDataWithRootObject:sigDict];
  }
  
  return result;
}

- (HGSSignatureStatus)verifyDetachedSignature:(NSData *)signature {
  HGSSignatureStatus result = eSignatureStatusInvalid;
  
  NSDictionary *sigDict;
  @try {
    sigDict = [NSKeyedUnarchiver unarchiveObjectWithData:signature];
  }
  @catch (NSException *e) {
   sigDict = nil;
  }
  
  NSData *sigData = [sigDict objectForKey:kSignatureDataKey];
  if (!sigData) {
    return eSignatureStatusInvalid;
  }
  
  int sigType = [[sigDict objectForKey:kDetachedSignatureTypeKey] intValue];
  if (sigType == kSignatureTypeStandard) {
    OSStatus err = fnfErr;
    CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[bundle_ bundlePath]];
    if (url) {
      SecStaticCodeRef codeRef;
      if ((err = SecStaticCodeCreateWithPath(url, 0, &codeRef)) == noErr) {
        if (SecCodeSetDetachedSignature(codeRef,
                                        (CFDataRef)sigData, 0) == noErr) {
          if (SecStaticCodeCheckValidityWithErrors(codeRef, 0, NULL,
                                                   NULL) == noErr) {
            result = eSignatureStatusOK;
          }
        }
        CFRelease(codeRef);
      }
    }
  } else if (sigType == kSignatureTypeResource) {
    unsigned char digest[kCodeSignatureDigestLength];
    if ([self digest:digest usingKey:nil]) {
      if ([sigData length] == kCodeSignatureDigestLength &&
          !memcmp(digest, [sigData bytes], kCodeSignatureDigestLength)) {
        result = eSignatureStatusOK;
      }
    }
  }
  
  return result;
}

- (NSDictionary *)embeddedResourceSignature {
  NSDictionary *result = nil;
  NSString *sigPath
    = [[[[bundle_ bundlePath] stringByAppendingPathComponent:@"Contents"]
       stringByAppendingPathComponent:kCodeSignatureDirectory]
       stringByAppendingPathComponent:kCodeSignatureFile];
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDirectory;
  if ([fm fileExistsAtPath:sigPath isDirectory:&isDirectory]) {
    result = [NSDictionary dictionaryWithContentsOfFile:sigPath];
  }
  return result;
}

- (BOOL)digest:(unsigned char *)digest usingKey:(NSData *)key {
  BOOL result = NO;
  
  // Hash the Info.plist
  NSString *plistPath
    = [[[bundle_ bundlePath] stringByAppendingPathComponent:@"Contents"]
       stringByAppendingPathComponent:@"Info.plist"];
  NSData *contents = [NSData dataWithContentsOfFile:plistPath];
  if ([contents length]) {
    if (![key length]) {
      SHA_CTX ctx;
      if (SHA1_Init(&ctx)) {
        if (SHA1_Update(&ctx, [contents bytes], [contents length])) {
          if ([self digestDirectory:[bundle_ resourcePath]
                         shaContext:&ctx
                        hmacContext:nil]) {
            if (SHA1_Final(digest, &ctx)) {
              result = YES;
            }
          }
        }
      }
    } else {
      HMAC_CTX ctx;
      HMAC_Init(&ctx, [key bytes], [key length], EVP_sha1());
      if ([self digestDirectory:[bundle_ resourcePath]
                     shaContext:nil
                    hmacContext:&ctx]) {
        unsigned int length = kCodeSignatureDigestLength;
        HMAC_Final(&ctx, digest, &length);
        result = YES;
      }
    }
  }
  
  return result;
}

- (BOOL)digestDirectory:(NSString *)path
             shaContext:(SHA_CTX *)shaCtx
            hmacContext:(HMAC_CTX *)hmacCtx {
  BOOL result = YES;
  
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *dirEnum = [fm enumeratorAtPath:path];
  if (!dirEnum) {
    return NO;
  }
  NSString *filePath;
  while (result && (filePath = [dirEnum nextObject])) {
    filePath = [path stringByAppendingPathComponent:filePath];
    BOOL isDirectory, succeeded = NO;
    // Should always return YES
    if ([fm fileExistsAtPath:filePath isDirectory:&isDirectory]) {
      if (!isDirectory) {
        // Must be digestable
        if ([fm isReadableFileAtPath:filePath]) {
          // Must be able to get file attributes
          NSDictionary *attrs = [fm fileAttributesAtPath:path traverseLink:YES];
          if (attrs) {
            NSNumber *size = [attrs objectForKey:NSFileSize];
            if (size && [size unsignedLongLongValue] <= 0xFFFFFFFFLL) {
              // SHA1_Update() takes the length as an unsigned long
              if (result && [size unsignedLongLongValue] > 0) {
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                NSData *contents = [NSData dataWithContentsOfFile:filePath];
                if (contents) {
                  if (shaCtx) {
                    if (SHA1_Update(shaCtx, [contents bytes],
                                    [contents length])) {
                      succeeded = YES;
                    }
                  } else if (hmacCtx) {
                    HMAC_Update(hmacCtx, [contents bytes], [contents length]);
                    succeeded = YES;
                  }
                }
                [pool release];
              }
            }
          }
        }
      } else {
        // Recurse into the directory
        succeeded = [self digestDirectory:filePath
                               shaContext:shaCtx
                              hmacContext:hmacCtx];
      }
    }
    result = succeeded;
  }
  
  return result;
}


@end
