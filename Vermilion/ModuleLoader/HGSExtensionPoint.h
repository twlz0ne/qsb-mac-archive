//
//  HGSExtensionPoint.h
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

// HGSExtensionPoint objects are a place that plugins can register new
// functionality. Each extension point contains a list of all registered
// extensions as well as a protocol to verify their interface.
// Extensions can be registered at any time, and the way they are used depends
// only on the requestor.

// This class is threadsafe.

@protocol HGSExtension;

@interface HGSExtensionPoint : NSObject {
 @private
  NSMutableDictionary* extensions_;
  Protocol* protocol_;
}

// Returns the global extension point with a given identifier
+ (HGSExtensionPoint*)pointWithIdentifier:(NSString*)identifer;

// Sets a protocol for all extensions to conform to. Extensions are verified on
// add. If extensions have already been registered with this point, they will be
// verified immediately. If they fail, an error will be logged to the console
// and they will be removed/ignored

- (void)setProtocol:(Protocol*)protocol;

// Add an extension to this point.
// Returns NO if the extension could not be registered or if the object does
// not conform to the protocol
- (BOOL)extendWithObject:(id<HGSExtension>)extension;

#pragma mark Access

// Returns the extension with the given identifier.
- (id)extensionWithIdentifier:(NSString *)identifier;

// Returns all the extensions
- (NSArray *)extensions;

// Returns an array of identifiers for all registered extensions (unordered)
- (NSArray *)allExtensionIdentifiers;

#pragma mark Removal

// Remove an extension with an identifier.
- (void)removeExtensionWithIdentifier:(NSString *)identifier;

// Remove a given extension
- (void)removeExtension:(id<HGSExtension>)extension;

@end


// This notification is sent by an extension point when extensions are added.
// Object is the extension point being modified
// Dictionary contains kHGSExtensionKey.
extern NSString* const kHGSExtensionPointDidAddExtensionNotification;

// These notifications are sent by an extension point when extensions are removed.
extern NSString* const kHGSExtensionPointWillRemoveExtensionNotification;
extern NSString* const kHGSExtensionPointDidRemoveExtensionNotification;

// Key for the notification dictionary. Represents the extension being added
// or removed.
extern NSString *const kHGSExtensionKey;
