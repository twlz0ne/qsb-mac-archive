//
//  EmailURLAction.m
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
#import "GTMGarbageCollection.h"
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "HGSAction.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"
#import "HGSObject.h"
#import "HGSBundle.h"

// An action which will email an URL.
//
@interface EmailURLAction : HGSAction
@end

@implementation EmailURLAction

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionIconImageKey]) {
    NSImage *icon = nil;
    CFURLRef url = (CFURLRef)[NSURL URLWithString:@"mailto:"];
    CFURLRef appURL = NULL;
    if (noErr == LSGetApplicationForURL(url,
                                        kLSRolesViewer,
                                        NULL, &appURL)) {
      GTMCFAutorelease(appURL);
      icon = [[NSWorkspace sharedWorkspace] iconForFile:[(NSURL *)appURL path]];
    } else {
      NSBundle *bundle = HGSGetPluginBundle();
      NSString *path = [bundle pathForResource:@"emailURL" ofType:@"icns"];
      icon = [[[NSImage alloc] initWithContentsOfFile:path] autorelease]; 
      if (!icon) {
        HGSLogDebug(@"Icon for EmailURL is missing from the EmailActions "
                    @"module bundle.");
      }
    }
    defaultObject = icon;
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

#pragma mark HGSAction Protocol Methods

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  // TODO(mrossetti): Rework this to accommodate different email products.
  BOOL wasGood = NO;
  HGSObject *objectWithURL = [info objectForKey:kHGSActionPrimaryObjectKey];
  NSURL *urlToSend = [objectWithURL valueForKey:kHGSObjectAttributeURIKey];
  NSString *urlString = [urlToSend absoluteString];
  urlString = [urlString gtm_stringByEscapingForURLArgument];
  urlString = [NSString stringWithFormat:@"mailto:?body=%@", urlString];
  NSURL *emailURL = [NSURL URLWithString:urlString];
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  wasGood = [ws openURL:emailURL];
  return wasGood;
}

- (BOOL)doesActionApplyTo:(HGSObject*)result {
  // We don't want to sent fileURLs
  BOOL isGood = NO;
  NSURL *urlToSend = [result valueForKey:kHGSObjectAttributeURIKey];
  if (urlToSend) {
    isGood = [urlToSend isFileURL] ? NO : YES;
  }
  return isGood;
}

@end
