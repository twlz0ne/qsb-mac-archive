//
//  MountSearchSource.m
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
#import <arpa/inet.h>
#import "GTMGarbageCollection.h"

static const NSTimeInterval kServiceResolutionTimeout = 5.0;

@interface MountSearchSource : HGSMemorySearchSource {
 @private
  NSMutableArray *services_;
  NSMutableDictionary *browsers_;
  NSDictionary *configuration_;
}
- (void)updateResultsIndex;
@end

@implementation MountSearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    configuration_ = [configuration objectForKey:@"MountSearchSourceServices"]; 
    browsers_ = [[NSMutableDictionary alloc] init];
    services_ = [[NSMutableArray alloc] init];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(willRemoveExtensionNotification:)
               name:kHGSExtensionPointWillRemoveExtensionNotification
             object:nil];
    
    for (NSString *key in configuration_) {
      NSNetServiceBrowser *browser
        = [[[NSNetServiceBrowser alloc] init] autorelease];
      [browser setDelegate:self];
      [browser searchForServicesOfType:key inDomain:@""];
      [browsers_ setObject:browser forKey:key];
    }
  }
  return self;
}

- (void)dealloc {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [browsers_ release];
  [configuration_ release];
  [services_ release];
  [super dealloc];
}

- (void)willRemoveExtensionNotification:(NSNotification *)notification {
  for (NSString *key in browsers_) {
    NSNetServiceBrowser *browser = [browsers_ objectForKey:key];
    [browser stop];
  }
  [browsers_ release];
  browsers_ = nil;
  for (NSNetService *service in services_) {
    [service setDelegate:nil];
  }
  [services_ release];
  services_ = nil;
}

- (void)updateResultsIndex {
  [self clearResultIndex];
  for (NSNetService *service in services_) {
    if (![service delegate]) {
      // If the delegate has not been set then it's new and we haven't started
      // resolving it. So set the delegate, and start resolving.
      [service setDelegate:self];
      [service resolveWithTimeout:kServiceResolutionTimeout];
    }
  }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict {
  HGSLogDebug(@"Mount did not search: %@",
              [errorDict objectForKey:NSNetServicesErrorCode]);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
  [services_ addObject:service];
  if (!moreComing) {
    [self updateResultsIndex];
  }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)service
               moreComing:(BOOL)moreComing {
  [services_ removeObject:service];
  if (!moreComing) {
    [self updateResultsIndex];
  }
}

- (void)netServiceDidResolveAddress:(NSNetService *)service {  
  struct sockaddr_in *inetAddress = NULL;
  for (NSData *addressBytes in [service addresses]) {
    inetAddress = (struct sockaddr_in *)[addressBytes bytes];
    if (inetAddress->sin_family == AF_INET ||
        inetAddress->sin_family == AF_INET6) {
      break;
    } else {
      inetAddress = NULL;
    }
  }
  if (inetAddress) {
    const char *ipCString = NULL;
    char ipStringBuffer[INET6_ADDRSTRLEN] = { 0 };
    NSString *ipString = nil;
    switch (inetAddress->sin_family) {
      case AF_INET:
        ipCString = inet_ntop(inetAddress->sin_family, &inetAddress->sin_addr,
                             ipStringBuffer, (socklen_t)sizeof(ipStringBuffer));
        ipString = [NSString stringWithUTF8String:ipCString];
        break;
      case AF_INET6:
        ipCString = inet_ntop(inetAddress->sin_family,
                             &((struct sockaddr_in6 *)inetAddress)->sin6_addr,
                            ipStringBuffer, (socklen_t)sizeof(ipStringBuffer));
        ipString = [NSString stringWithFormat:@"[%s]", ipCString];
        break;
    }
    if (ipString) {
      NSString *mount = HGSLocalizedString(@"mount", 
                                           @"A label for a result denoting a "
                                           @"network mount point");
      NSString *share = HGSLocalizedString(@"share", 
                                           @"A label for a result denoting a "
                                           @"network share point");    
      NSMutableArray *otherTerms = [NSMutableArray arrayWithObjects:
                                    mount, share, nil];
      NSString *urlString = nil, *type = nil, *scheme = nil;
      
      for (NSString *key in configuration_) {
        if ([[service type] hasPrefix:key]) {
          NSDictionary *dict = [configuration_ objectForKey:key];
          scheme = [dict objectForKey:@"scheme"];
          urlString = [NSString stringWithFormat:@"%@://%@/", scheme, ipString];
          type = [dict objectForKey:@"type"];
          [otherTerms addObject:scheme];
          break;
        } 
      }
      
      if (urlString && type) {
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                    urlString,
                                    kHGSObjectAttributeSourceURLKey,
                                    nil];
        NSString *name = [service name];
        NSString *displayName = [NSString stringWithFormat:@"%@ (%@)", 
                                 name, scheme];
        HGSUnscoredResult *hgsResult 
          = [HGSUnscoredResult resultWithURI:urlString
                                        name:displayName
                                        type:type
                                      source:self
                                  attributes:attributes];
        [self indexResult:hgsResult 
                     name:name 
               otherTerms:otherTerms];
      }
    }
  }
}

- (void)netService:(NSNetService *)sender
     didNotResolve:(NSDictionary *)errorDict {
  HGSLogDebug(@"Mount did not resolve: %@ (%@)", sender,
              [errorDict objectForKey:NSNetServicesErrorCode]);
}

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeIconKey]) {
    NSURL *appURL = nil;
    if (noErr == LSGetApplicationForURL((CFURLRef)[result url],
                                        kLSRolesViewer,
                                        NULL,
                                        (CFURLRef *)&appURL)) {
      // TODO(alcor): badge this with the bonjour icon
      // NSImage *bonjour = [NSImage imageNamed:NSImageNameBonjour];
      value = [[NSWorkspace sharedWorkspace] iconForFile:[appURL path]];
      GTMCFAutorelease(appURL);
    }
  
  }
  return value;
}
@end
