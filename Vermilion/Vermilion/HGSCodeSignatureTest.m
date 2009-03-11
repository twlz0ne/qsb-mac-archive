//
//  HGSCodeSignatureTest.m
//  QSB
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

#import <Foundation/Foundation.h>
#import "GTMSenTestCase.h"
#import "HGSCodeSignature.h"


@interface HGSCodeSignatureTest : GTMTestCase
@end

static const unsigned char kAppSigningKey[16] = {
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
};
static NSString *kAppPath = @"/Applications/System Preferences.app";

@implementation HGSCodeSignatureTest

- (void)testKeyedSignature {
  NSBundle *appBundle
    = [NSBundle bundleWithPath:kAppPath];
  STAssertNotNil(appBundle, @"could not find System Preferences.app bundle");
  
  HGSCodeSignature *sig = [HGSCodeSignature codeSignatureForBundle:appBundle];
  STAssertNotNil(sig, @"failed to create code signature object");
  
  NSData *key = [NSData dataWithBytes:kAppSigningKey length:16];
  STAssertNotNil(key, @"failed to encode key data");
  
  HGSSignatureStatus status = [sig verifySignature:key
                                         forBundle:appBundle
                                          usingKey:key];
  STAssertEquals(status, eSignatureStatusInvalid, @"invalid signature accepted");
  
  NSData *sigData = [sig generateSignatureForBundle:appBundle
                                           usingKey:key];
  STAssertNotNil(sigData, @"failed to create signature");
                         
  status = [sig verifySignature:sigData
                      forBundle:appBundle
                       usingKey:key];
  STAssertEquals(status, eSignatureStatusOK, @"failed to validate signature");
}

- (void)testSignatureValid {
  NSBundle *appBundle
    = [NSBundle bundleWithPath:kAppPath];
  STAssertNotNil(appBundle, @"could not find System Preferences.app bundle");
  
  HGSCodeSignature *sig = [HGSCodeSignature codeSignatureForBundle:appBundle];
  STAssertNotNil(sig, @"failed to create code signature object");
  
  HGSSignatureStatus status = [sig signatureStatus];
  STAssertEquals(status, eSignatureStatusOK, @"invalid signature accepted");
}

- (void)testCertificates {
  NSBundle *appBundle
    = [NSBundle bundleWithPath:kAppPath];
  STAssertNotNil(appBundle, @"could not find System Preferences.app bundle");
  
  HGSCodeSignature *sig = [HGSCodeSignature codeSignatureForBundle:appBundle];
  STAssertNotNil(sig, @"failed to create code signature object");
  
  SecCertificateRef cert = [sig signerCertificate];
  STAssertTrue(cert != NULL, @"failed to extract certificate");
  
  STAssertTrue([sig signerCertificateIsEqual:cert], @"certificates incorrect");
}

@end
