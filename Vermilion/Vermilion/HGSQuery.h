//
//  HGSQuery.h
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
//

#import <Foundation/Foundation.h>

@class HGSObject;
@class HGSAction;

//
// HGSQuery
//
// Represents a fully-parsed query string in a format that's easily digestable
// by those that need to perform searches.
//

//
// The query syntax is pretty simple, all terms are looked for (ie-logical AND),
// there is no phrase support at this time (the version of this in
// googlemac/Vermilion/Query supports phrases).  All terms are matched on word
// prefix, ie: "S P" matches "System Preferences".  TODO: does this open the
// door to invisible quotes for CJK to get good results?
//

enum {
  eHGSQueryShowAlternatesFlag = 1 << 0,
};

typedef NSUInteger HGSQueryFlags;

@interface HGSQuery : NSObject {
 @private
  NSString *rawQuery_;
  NSSet *uniqueWords_;
  HGSObject *pivotObject_;
  HGSQuery *parent_;
  NSInteger maxDesiredResults_;
  HGSQueryFlags flags_;
}

- (id)initWithString:(NSString*)query 
         pivotObject:(HGSObject *)pivotObject
          queryFlags:(HGSQueryFlags)flags;

// Returns a set of unique words found in the query string
// ie: query ::  "Foo Bar" baz "mumble foo"
//     returns a set w/ ::   ( "baz", "bar", "foo", "mumble" )
// NOTE: the strings are all forced to lower case, and diacriticals will have
// been removed.
- (NSSet *)uniqueWords;

// The query string un-processed.  Most things doing matches should really be
// using the uniqueWords api so they get consistent.
- (NSString *)rawQueryString;

// A pivot object in the context is any object currently set to filter search
// this could  a directory (filtering to its contents) or a website (searching
// data there) or many other types of searchable items.
- (HGSObject*)pivotObject;

// A "parent" is a query that has asked for this one to be created.  Usually
// to pick up an indirect object for an action.  This allows a SearchSource to
// walk to the parent and fetch it's direct object to return results specific to
// that object.
- (HGSQuery*)parent;
- (void)setParent:(HGSQuery*)parent;

// Maximum number of results that we are interested in receiving. -1 indicates
// no limit.
- (NSInteger)maxDesiredResults;
- (void)setMaxDesiredResults:(NSInteger)maxResults;

// Various flags that modify some queries
- (HGSQueryFlags)flags;
@end
