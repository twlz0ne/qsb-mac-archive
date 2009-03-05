//
//  HGSExtensionPoint.m
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

#import "HGSExtensionPoint.h"
#import "HGSExtension.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"

NSString* const kHGSExtensionPointDidAddExtensionNotification
  = @"HGSExtensionPointDidAddExtensionNotification";
NSString* const kHGSExtensionPointWillRemoveExtensionNotification
  = @"HGSExtensionPointWillRemoveExtensionNotification";
NSString* const kHGSExtensionPointDidRemoveExtensionNotification
  = @"HGSExtensionPointDidRemoveExtensionNotification";
NSString *const kHGSExtensionKey = @"HGSExtension";

static NSMutableDictionary *sHGSExtensionPoints = nil;

@interface HGSExtensionPoint ()
- (BOOL)verifyExtension:(id<HGSExtension>)extension;
@end

@implementation HGSExtensionPoint
+ (void)initialize {
  if (!sHGSExtensionPoints) {
    sHGSExtensionPoints = [[NSMutableDictionary alloc] init];
  }
}

// Returns the global extension point with a given identifier
+ (HGSExtensionPoint*)pointWithIdentifier:(NSString*)identifier {
  HGSExtensionPoint* point;
  @synchronized(sHGSExtensionPoints) {
    point = [sHGSExtensionPoints objectForKey:identifier];
    if (!point) {
      point = [[[self alloc] init] autorelease];
      [sHGSExtensionPoints setObject:point forKey:identifier];
    }
  }
  return point;
}

- (id)init {
  self = [super init];
  if (self != nil) {
    extensions_ = [[NSMutableDictionary alloc] init];
  }
  return self;
}

// COV_NF_START
- (void)dealloc {
  // Since these get stored away in a static dictionary
  // we never get released.
  [extensions_ release];
  [super dealloc];
}
// COV_NF_END


- (BOOL)verifyExtension:(id<HGSExtension>)extension {
  return extension && (!protocol_ || [extension conformsToProtocol:protocol_]);
}

- (void)setProtocol:(Protocol *)protocol {
  protocol_ = protocol;

  NSMutableArray *extensionsToRemove = [NSMutableArray array];
  NSArray *allValues = nil;
  @synchronized(extensions_) {
    allValues = [extensions_ allValues];
  }
  for (id extension in allValues) {
    if (![self verifyExtension:extension]) {
      [extensionsToRemove addObject:extension];
    }
  }
  for (id extension in extensionsToRemove) {
    [self removeExtension:extension];
  }
}

- (BOOL)extendWithObject:(id<HGSExtension>)extension {
  BOOL wasGood = YES;
  NSString *identifier = [extension identifier];
  if (![identifier length]) {
    HGSLog(@"Extension %@ has bad identifier", extension);
    wasGood = NO;
  }
  if (![self verifyExtension:extension]) {
    HGSLog(@"Extension %@ does not conform to protocol", identifier);
    wasGood = NO;
  }
  if (wasGood) {
    @synchronized(extensions_) {
      // Make sure it isn't in use and we don't already have this extension
      // used for a different key
      if ([extensions_ objectForKey:identifier]) {
        HGSLog(@"Extension %@ with identifier '%@' already exists in %@",
               extension, identifier, self);
        wasGood = NO;
      } else {
        [extensions_ setObject:extension forKey:identifier];
        wasGood = YES;
      }
    }
  }
  if (wasGood) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSDictionary *userInfo 
      = [NSDictionary dictionaryWithObject:extension forKey:kHGSExtensionKey];
    [nc postNotificationName:kHGSExtensionPointDidAddExtensionNotification 
                      object:self 
                    userInfo:userInfo];
    
  }
  return wasGood;
}

- (NSString *)description {
  NSString *result = [NSString stringWithFormat:@"%@ <%@> - Extensions: %@",
                      [self class], NSStringFromProtocol(protocol_), 
                      [self extensions]];
  return result;
}

#pragma mark Access

- (id)extensionWithIdentifier:(NSString *)identifier {
  id result;
  @synchronized(extensions_) {
    result = [extensions_ objectForKey:identifier];
  }
  return result;
}

- (NSArray *)extensions {
  NSArray *result;
  @synchronized(extensions_) {
    // This yields a temp array safe to iterate if our data gets changed.
    result = [extensions_ allValues];
  }
  return result;
}

- (NSArray *)allExtensionIdentifiers {
  NSArray *result;
  @synchronized(extensions_) {
    // This yields a temp array safe to iterate if our data gets changed.
    result = [extensions_ allKeys];
  }
  return result;
}

#pragma mark Removal

- (void)removeExtensionWithIdentifier:(NSString *)identifier {
  id extension = [self extensionWithIdentifier:identifier];
  if (!extension) {
    HGSLogDebug(@"No such extension with id: %@", identifier);
    return;
  }
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSDictionary *userInfo = [NSDictionary dictionaryWithObject:extension
                                                       forKey:kHGSExtensionKey];
  [nc postNotificationName:kHGSExtensionPointWillRemoveExtensionNotification 
                    object:self 
                  userInfo:userInfo];
  @synchronized(extensions_) {
    [extensions_ removeObjectForKey:identifier];
  }
  [nc postNotificationName:kHGSExtensionPointDidRemoveExtensionNotification 
                    object:self 
                  userInfo:userInfo];
}

- (void)removeExtension:(id<HGSExtension>)extension {
  [self removeExtensionWithIdentifier:[extension identifier]];
}

@end
