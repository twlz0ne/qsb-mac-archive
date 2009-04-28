//
//  ApplicationsActions.m
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

#import <Vermilion/Vermilion.h>
#import "GTMNSWorkspace+Running.h"
#import "GTMMethodCheck.h"

@interface ApplicationsQuitAction : HGSAction
- (BOOL)performWithInfo:(NSDictionary*)info;
@end

@implementation ApplicationsQuitAction
GTM_METHOD_CHECK(NSWorkspace, gtm_launchedApplications);

- (BOOL)appliesToResult:(HGSResult *)result {
  NSArray *apps = [[NSWorkspace sharedWorkspace] gtm_launchedApplications];
  for (NSDictionary *app in apps) {
    NSString *path = [app objectForKey:@"NSApplicationPath"];
    NSURL *url = [result url];
    if (path && [url isFileURL] && [path isEqual:[url path]]) {
      return YES;
    }
  }
  return NO;
}

- (BOOL)performWithInfo:(NSDictionary *)info {
  BOOL quit = NO;
  
  HGSResultArray *directObjects
    = [info objectForKey:kHGSActionDirectObjectsKey];
  for (HGSResult *result in directObjects) {
    NSString *path = [[result url] path];
    NSString *bundleID = [[NSBundle bundleWithPath:path] bundleIdentifier];
    const char *bundleIDUTF8 = [bundleID UTF8String];
    if (bundleIDUTF8) {
      AppleEvent event;
      if (AEBuildAppleEvent(kCoreEventClass, kAEQuitApplication,
                            typeApplicationBundleID, bundleIDUTF8,
                            strlen(bundleIDUTF8), kAutoGenerateReturnID,
                            kAnyTransactionID, &event, NULL, "") == noErr) {
        AppleEvent reply;
        if (AESendMessage(&event, &reply, kAENoReply,
                          kAEDefaultTimeout) == noErr) {
          quit = YES;
        }
        AEDisposeDesc(&event);
      }
    }
  }
  
  return quit;
}

@end
