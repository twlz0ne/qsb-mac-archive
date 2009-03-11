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
enum {
  kSecCSSigningInformation = 2,
  errSecCSUnsigned = -67062,
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

@interface HGSCodeSignature()
- (void)verifySignature:(BOOL)adHocOK;
- (BOOL)digest:(unsigned char *)digest
     forBundle:(NSBundle *)bundle
      usingKey:(NSData *)key;
- (BOOL)digestDirectory:(NSString *)path
             shaContext:(SHA_CTX *)shaCtx
            hmacContext:(HMAC_CTX *)hmacCtx;
@end

@implementation HGSCodeSignature

+ (HGSCodeSignature *)codeSignatureForBundle:(NSBundle *)bundle {
  return [[[HGSCodeSignature alloc] initWithBundle:bundle] autorelease];
}

- (id)initWithBundle:(NSBundle *)bundle {
  self = [super init];
  if (self) {
    // Err on the side of caution
    status_ = eSignatureStatusInvalid;
    
    if (bundle) {
      CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:[bundle bundlePath]];
      if (url && SecStaticCodeCreateWithPath(url, 0, &staticCodeRef_) == noErr) {
        [self verifySignature:NO];
      }
    }
  }
  return self;
}

- (void)dealloc {
  if (signerCertificate_) {
    CFRelease(signerCertificate_);
  }
  if (signingInfo_) {
    CFRelease(signingInfo_);
  }
  if (staticCodeRef_) {
    CFRelease(staticCodeRef_);
  }
  [super dealloc];
}

- (void)verifySignature:(BOOL)adHocOK {
  status_ = eSignatureStatusInvalid;

  if (signerCertificate_) {
    CFRelease(signerCertificate_);
    signerCertificate_ = nil;
  }
  if (signingInfo_) {
    CFRelease(signingInfo_);
    signingInfo_ = nil;
  }
  
  OSStatus err = SecStaticCodeCheckValidityWithErrors(staticCodeRef_, 0,
                                                      NULL, NULL);
  switch (err) {
    case errSecCSUnsigned:
      status_ = eSignatureStatusUnsigned;
      break;
    case noErr:
      if (SecCodeCopySigningInformation(staticCodeRef_,
                                        kSecCSSigningInformation,
                                        &signingInfo_) == noErr) {
        CFArrayRef certs = CFDictionaryGetValue(signingInfo_,
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
                                           &signerCertificate_);
            }
          }
        }
        // If the signing info dictionary did not contain a signer
        // certificate, then the bundle has an ad-hoc signature, which
        // for our purposes is the same thing as being unsigned when
        // verifying an embedded signature (i.e., when we're not validating the
        // detached ad-hoc signature we generated and stored ourselves).
        if (signerCertificate_ || adHocOK) {
          status_ = eSignatureStatusOK;
        } else {
          status_ = eSignatureStatusUnsigned;
        } 
      }
      break;
  }
}

- (HGSSignatureStatus)signatureStatus {
  return status_;
}

- (SecCertificateRef)signerCertificate {
  return signerCertificate_;
}

- (BOOL)signerCertificateIsEqual:(SecCertificateRef)cert {
  BOOL result = NO;
  
  // Compare by doing a memcmp of the two certificates' DER encoding
  if (cert && signerCertificate_) {
    CSSM_DATA certDer, signerDer;
    if (SecCertificateGetData(cert, &certDer) == noErr &&
        SecCertificateGetData(signerCertificate_, &signerDer) == noErr &&
        certDer.Length == signerDer.Length &&
        memcmp(certDer.Data, signerDer.Data, certDer.Length) == 0) {
      result = YES;
    }
  }
  
  return result;
}

- (NSData *)generateExternalAdHocSignature {
  NSData *result = nil;
  
  uuid_t uuid;
  uuid_generate(uuid);
  char uuidString[sizeof(uuid_t) + 1];
  uuid_unparse(uuid, uuidString);
  NSString *detachedFilePath
    = [NSTemporaryDirectory() stringByAppendingPathComponent:
       [NSString stringWithUTF8String:uuidString]];

  NSDictionary *parameters = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSURL fileURLWithPath:detachedFilePath],
                              kSecCodeSignerDetached,
                              kCFNull, kSecCodeSignerIdentity,
                              nil];
  
  SecCodeSignerRef signer;
  if (SecCodeSignerCreate((CFDictionaryRef)parameters, 0, &signer) == noErr) {
    CFErrorRef errors = NULL;
    if (staticCodeRef_ && SecCodeSignerAddSignatureWithErrors(signer,
                                            staticCodeRef_, 0,
                                            &errors) == noErr) {
      // TODO(hawk): There is a race condition at this point. An attacker
      // could conceivably write a different signature to our temp file
      // before we read it, causing us to trust the signature on their
      // malicious plugin. Figure out something to avoid this.
      result = [NSData dataWithContentsOfFile:detachedFilePath];
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
  
  return result;
}

- (HGSSignatureStatus)verifyExternalAdHocSignature:(NSData *)signatureData {
  status_ = eSignatureStatusInvalid;
  if (staticCodeRef_ && [signatureData length]) {
    if (SecCodeSetDetachedSignature(staticCodeRef_,
                                    (CFDataRef)signatureData, 0) == noErr) {
      [self verifySignature:YES];
    }
  }
  return status_;
}


- (HGSSignatureStatus)verifySignature:(NSData *)signature
                            forBundle:(NSBundle *)bundle
                     usingCertificate:(SecCertificateRef)certificateRef {
  HGSSignatureStatus result = eSignatureStatusInvalid;
  
  if (![signature length]) {
    return eSignatureStatusUnsigned;
  }
  
  if (!certificateRef || !bundle) {
    return eSignatureStatusInvalid;
  }
  
  unsigned char digest[kCodeSignatureDigestLength];
  if (![self digest:digest forBundle:bundle usingKey:nil]) {
    return eSignatureStatusInvalid;
  }
  
  SecKeyRef publicKey;
  if (SecCertificateCopyPublicKey(certificateRef, &publicKey) == noErr) {
    CSSM_CSP_HANDLE csp;
    if (SecKeyGetCSPHandle(publicKey, &csp) == noErr) {
      const CSSM_KEY *cssmKey;
      if (SecKeyGetCSSMKey(publicKey, &cssmKey) == noErr) {
        CSSM_CC_HANDLE sigCtx;
        if (CSSM_CSP_CreateSignatureContext(csp, CSSM_ALGID_SHA1WithRSA, NULL,
                                            cssmKey, &sigCtx) == noErr) {
            CSSM_DATA digestData, signatureData;
            digestData.Length = kCodeSignatureDigestLength;
            digestData.Data = digest;
            signatureData.Length = [signature length];
            signatureData.Data = (void *)[signature bytes];
          if (CSSM_VerifyData(sigCtx, &digestData, 1, CSSM_ALGID_SHA1,
                              &signatureData) == noErr) {
            result = eSignatureStatusOK;
          }
          CSSM_DeleteContext(sigCtx);
        }
      }
    }
    CFRelease(publicKey);
  }
  
  return result;
}

- (HGSSignatureStatus)verifySignature:(NSData *)signature
                            forBundle:(NSBundle *)bundle
                             usingKey:(NSData *)key {
  HGSSignatureStatus result = eSignatureStatusInvalid;
  
  if (![signature length] || ![key length]) {
    return eSignatureStatusUnsigned;
  }
  
  if ([signature length] != kCodeSignatureDigestLength) {
    return eSignatureStatusInvalid;
  }
  
  unsigned char digest[kCodeSignatureDigestLength];
  if ([self digest:digest forBundle:bundle usingKey:key]) {
    if (memcmp(digest, [signature bytes], kCodeSignatureDigestLength) == 0) {
      result = eSignatureStatusOK;
    }
  }
  
  return result;
}

- (NSData *)generateSignatureForBundle:(NSBundle *)bundle
                         usingIdentity:(SecIdentityRef)identity {
  NSData *result = nil;
  
  unsigned char digest[kCodeSignatureDigestLength];
  if (![self digest:digest forBundle:bundle usingKey:nil]) {
    return nil;
  }
  
  SecKeyRef privateKey;
  if (SecIdentityCopyPrivateKey(identity, &privateKey) == noErr) {
    CSSM_CSP_HANDLE csp;
    if (SecKeyGetCSPHandle(privateKey, &csp) == noErr) {
      const CSSM_KEY *cssmKey;
      if (SecKeyGetCSSMKey(privateKey, &cssmKey) == noErr) {
        const CSSM_ACCESS_CREDENTIALS *cred;
        if (SecKeyGetCredentials(privateKey, CSSM_ACL_AUTHORIZATION_SIGN,
                                 kSecCredentialTypeDefault, &cred) == noErr) {
          CSSM_CC_HANDLE sigCtx;
          if (CSSM_CSP_CreateSignatureContext(csp, CSSM_ALGID_SHA1WithRSA, cred,
                                              cssmKey, &sigCtx) == noErr) {
            CSSM_DATA input, output;
            input.Length = kCodeSignatureDigestLength;
            input.Data = digest;
            if (CSSM_SignData(sigCtx, &input, 1, CSSM_ALGID_SHA1,
                              &output) == noErr) {
              result = [NSData dataWithBytes:output.Data length:output.Length];
            }
            CSSM_DeleteContext(sigCtx);
          }
        }
      }
    }
    CFRelease(privateKey);
  }

  return result;
}

- (NSData *)generateSignatureForBundle:(NSBundle *)bundle
                              usingKey:(NSData *)key {
  NSData *result = nil;
  if ([key length]) {
    unsigned char digest[kCodeSignatureDigestLength];
    if ([self digest:digest forBundle:bundle usingKey:key]) {
      result = [NSData dataWithBytes:digest length:kCodeSignatureDigestLength];
    }
  }
  
  return result;
}

- (BOOL)digest:(unsigned char *)digest
     forBundle:(NSBundle *)bundle
      usingKey:(NSData *)key {
  BOOL result = NO;
  
  // Hash the Info.plist
  NSString *plistPath
    = [[[bundle bundlePath] stringByAppendingPathComponent:@"Contents"]
       stringByAppendingPathComponent:@"Info.plist"];
  NSData *contents = [NSData dataWithContentsOfFile:plistPath];
  if ([contents length]) {
    if (![key length]) {
      SHA_CTX ctx;
      if (SHA1_Init(&ctx)) {
        if (SHA1_Update(&ctx, [contents bytes], [contents length])) {
          if ([self digestDirectory:[bundle resourcePath]
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
      if ([self digestDirectory:[bundle resourcePath]
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
