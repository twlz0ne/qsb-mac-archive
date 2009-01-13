//
//  Shortcuts.h
//
//  Copyright (c) 2007-2008 Google Inc. All rights reserved.
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


// Shortcuts stores things in our user defaults.
// The top level is a dictionary keyed by "shortcut" where a shortcut is the
// series of characters entered by the user for them to get a object (i.e. 
// 'ipho' could correspond to iPhoto. The value associated with the key is
// an array of object identifiers. These identifiers match an entry in
// a sqlite cache that holds the data needed to rebuild the object.
// When a user associates a object (ex 'ipho') with a object (ex 'iphoto') 
// and there is nothing else keyed to 'ipho' in the DB, the array for 'ipho'
// will have a single entry 'iphoto'. If the user then associates 'iphone' with
// 'ipho' the array for 'ipho' will have two objects (iphoto and iphone). If
// the user again associates ipho with iPhone then the array will change to
// (iPhone, iPhoto). If the user then associates ipho with iphonizer the array
// will change to (iphone, iponizer). Object for shortcut will always return the
// first element in the array for a given key.

#import <Vermilion/Vermilion.h>

@class HGSSQLiteBackedCache;

@interface ShortcutsSource : HGSCallbackSearchSource {
 @private
  HGSSQLiteBackedCache *cache_;
}

// Tell the database that "object" was selected for shortcut, and let it do its
// magic internally to update itself.
- (BOOL)updateShortcut:(NSString*)shortcut 
            withObject:(HGSObject *)object;
@end

extern NSString *const kShortcutsSourceExtensionIdentifier;
