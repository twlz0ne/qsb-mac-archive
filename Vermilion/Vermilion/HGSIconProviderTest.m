//
//  HGSIconProviderTest.m
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


#import "GTMSenTestCase.h"
#import "HGSIconProvider.h"
#import <OCMock/OCMock.h>
#import "HGSResult.h"
#import "HGSSearchSource.h"
#import "GTMNSObject+UnitTesting.h"
#import "GTMAppKit+UnitTesting.h"
#import "GTMGarbageCollection.h"

@interface HGSIconProviderTest : GTMTestCase 
@end

@interface HGSIconOperation
+ (HGSIconOperation *)iconOperationForResult:(HGSResult*)result;
- (NSUInteger)hash;
@end

@implementation HGSIconProviderTest
- (void)testProvideIconForResult {  
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSString *path
    = [ws absolutePathForAppBundleWithIdentifier:@"com.apple.finder"];
  STAssertNotNil(path, nil);
  id searchSourceMock = [OCMockObject mockForClass:[HGSSearchSource class]];
  HGSUnscoredResult *result 
    = [HGSUnscoredResult resultWithFilePath:path
                                     source:searchSourceMock
                                 attributes:nil];
  STAssertNotNil(result, nil);
  HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
  [[[searchSourceMock stub] 
    andReturn:nil]
   provideValueForKey:kHGSObjectAttributeIconPreviewFileKey result:result];
  [[[searchSourceMock stub] 
    andReturn:nil]
   provideValueForKey:kHGSObjectAttributeImmediateIconKey result:result];
  NSImage *icon = [provider provideIconForResult:result 
                                 skipPlaceholder:YES];
  // Not using GTMAssertObjectImageEqualToImageNamed because it appears there
  // is an issue with the OS returning icons to us that aren't really
  // of generic color space. 
  // TODO(dmaclach): dig into this and file a radar.
  STAssertNotNil(icon, nil);
}

- (void)testRoundRectAndDropShadow {
  HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
  NSSize size = [provider preferredIconSize];
  STAssertEquals(size.height, (CGFloat)96.0, nil);
  STAssertEquals(size.width, (CGFloat)96.0, nil);
  // Create up NSImage using CG calls because doing it using lockFocus and
  // friends causes a weird mixup of calibrated and direct colorspaces.
  CGColorSpaceRef cspace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
  GTMCFAutorelease(cspace);
  CGContextRef context 
    = CGBitmapContextCreate(NULL, 
                            size.width, 
                            size.height, 
                            8, 
                            32 * size.width, 
                            cspace, 
                            kCGBitmapByteOrder32Host 
                            | kCGImageAlphaPremultipliedLast);
  GTMCFAutorelease(context);
  STAssertNotNULL(context, nil);
  CGColorRef color = CGColorCreateGenericRGB(0, 0, 1, 1);
  GTMCFAutorelease(color);
  CGContextSetFillColorWithColor(context, color);
  CGContextMoveToPoint(context, 16, 16);
  CGContextAddLineToPoint(context, 80, 16);
  CGContextAddLineToPoint(context, 48, 80);
  CGContextFillPath(context);
  CGImageRef cgImage = CGBitmapContextCreateImage(context);
  GTMCFAutorelease(cgImage);
  NSBitmapImageRep *bitmap 
    = [[[NSBitmapImageRep alloc] initWithCGImage:cgImage] autorelease];
  NSImage *image = [[[NSImage alloc] initWithSize:size] autorelease];
  [image addRepresentation:bitmap];
  image = [provider imageWithRoundRectAndDropShadow:image];
  GTMAssertObjectImageEqualToImageNamed(image, @"RoundRectAndDropShadow", nil);
}

- (void)testIconOperationHash {
  NSMutableSet *iconOperations = [NSMutableSet setWithCapacity:2];
  id searchSourceMock = [OCMockObject mockForClass:[HGSSearchSource class]];

  NSMutableDictionary* infoA = [NSMutableDictionary dictionary];
  NSString* pathA = @"file:///etc/";
  [infoA setObject:pathA forKey:kHGSObjectAttributeURIKey];
  [infoA setObject:@"fooA" forKey:kHGSObjectAttributeNameKey];
  [infoA setObject:@"barA" forKey:kHGSObjectAttributeTypeKey];
  HGSUnscoredResult* resultA 
    = [HGSUnscoredResult resultWithDictionary:infoA
                                       source:searchSourceMock];
  NSUInteger expectedHashA = [resultA hash];
  HGSIconOperation *operationA
    = [HGSIconOperation iconOperationForResult:resultA];
  [iconOperations addObject:operationA];
  NSUInteger hashA = [operationA hash];
  STAssertEquals(expectedHashA, hashA, nil);

  NSMutableDictionary* infoB = [NSMutableDictionary dictionary];
  NSString* pathB = @"file:///bin/";
  [infoB setObject:pathB forKey:kHGSObjectAttributeURIKey];
  [infoB setObject:@"fooB" forKey:kHGSObjectAttributeNameKey];
  [infoB setObject:@"barB" forKey:kHGSObjectAttributeTypeKey];
  HGSUnscoredResult* resultB 
    = [HGSUnscoredResult resultWithDictionary:infoB
                                       source:searchSourceMock];
  NSUInteger expectedHashB = [resultB hash];
  HGSIconOperation *operationB
    = [HGSIconOperation iconOperationForResult:resultB];
  [iconOperations addObject:operationB];
  NSUInteger hashB = [operationB hash];
  STAssertEquals(hashB, expectedHashB, nil);
  
  STAssertNotEquals(hashA, hashB, nil);
  
  [iconOperations removeObject:operationA];
  id objectA = [iconOperations member:operationA];
  STAssertNil(objectA, nil);
  id objectB = [iconOperations member:operationB];
  STAssertNotNil(objectB, nil);
}
  
@end
