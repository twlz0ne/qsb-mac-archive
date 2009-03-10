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

#define kResultTypeShare @"share"
static NSString *kResultTypeAfpShare = HGS_SUBTYPE(kResultTypeShare, @"afp");
static NSString *kResultTypeSmbShare = HGS_SUBTYPE(kResultTypeShare, @"smb");
static const NSTimeInterval kServiceResolutionTimeout = 5.0;

@interface MountSearchSource : HGSMemorySearchSource {
 @private
  NSNetServiceBrowser *afpServiceBrowser_;
  NSNetServiceBrowser *smbServiceBrowser_;
  NSMutableArray *services_;
}
- (void)updateResultsIndex;
@end

@implementation MountSearchSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    services_ = [[NSMutableArray alloc] init];
    afpServiceBrowser_ = [[NSNetServiceBrowser alloc] init];
    [afpServiceBrowser_ setDelegate:self];
    [afpServiceBrowser_ searchForServicesOfType:@"_afpovertcp._tcp" inDomain:@""];
    smbServiceBrowser_ = [[NSNetServiceBrowser alloc] init];
    [smbServiceBrowser_ setDelegate:self];
    [smbServiceBrowser_ searchForServicesOfType:@"_smb._tcp" inDomain:@""];
  }
  return self;
}

- (void) dealloc {
  [afpServiceBrowser_ stop];
  [afpServiceBrowser_ release];
  [smbServiceBrowser_ stop];
  [smbServiceBrowser_ release];
  [services_ release];
  [super dealloc];
}

- (void)updateResultsIndex {
  [self clearResultIndex];
  for (NSNetService *service in services_) {
    [service setDelegate:self];
    [service resolveWithTimeout:kServiceResolutionTimeout];
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
    const char *ipString = NULL;
    char ipStringBuffer[INET6_ADDRSTRLEN] = { 0 };
    switch (inetAddress->sin_family) {
      case AF_INET:
        ipString = inet_ntop(inetAddress->sin_family, &inetAddress->sin_addr,
                             ipStringBuffer, sizeof(ipStringBuffer));
        break;
      case AF_INET6:
        ipString = inet_ntop(inetAddress->sin_family,
                             &((struct sockaddr_in6 *)inetAddress)->sin6_addr,
                            ipStringBuffer, sizeof(ipStringBuffer));
        break;
    }
    if (ipString) {
      NSMutableArray *otherTerms = [NSMutableArray arrayWithObjects:
                                    HGSLocalizedString(@"mount", @"mount"),
                                    HGSLocalizedString(@"shares", @"shares"),
                                    nil];
      NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSImage imageNamed:NSImageNameBonjour],
                                  kHGSObjectAttributeIconKey,
                                  nil];
      NSString *url = nil, *type = nil;
      if ([[service type] hasPrefix:@"_afpovertcp._tcp"]) {
        url = [NSString stringWithFormat:@"afp://%s/", ipString];
        type = kResultTypeAfpShare;
        [otherTerms addObject:@"afp"];
      } else if ([[service type] hasPrefix:@"_smb._tcp"]) {
        url = [NSString stringWithFormat:@"smb://%s/", ipString];
        type = kResultTypeSmbShare;
        [otherTerms addObject:@"smb"];
      }
      if (url && type) {
        HGSResult *hgsResult 
          = [HGSResult resultWithURL:[NSURL URLWithString:url]
                                name:[service name]
                                type:type
                              source:self
                          attributes:attributes];
        [self indexResult:hgsResult
               nameString:[service name]
        otherStringsArray:otherTerms];
      }
    }
  }
}

- (void)netService:(NSNetService *)sender
     didNotResolve:(NSDictionary *)errorDict {
  HGSLogDebug(@"Mount did not resolve: %@",
              [errorDict objectForKey:NSNetServicesErrorCode]);
}

@end
