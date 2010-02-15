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

/*!
 @header
 @discussion HGSQuery
*/

#import <Foundation/Foundation.h>

@class HGSResult;
@class HGSResultArray;
@class HGSTokenizedString;

typedef enum {
  eHGSQueryShowAlternatesFlag = 1 << 0,
} HGSQueryFlags;

/*!
 Represents a fully-parsed query string in a format that's easily digestable
 by those that need to perform searches.
 
 The query syntax is pretty simple, all terms are looked for (ie-logical AND),
 there is no phrase support at this time.  All terms are matched on word
 prefix, ie: "S P" matches "System Preferences".
 
 TODO: does this open the door to invisible quotes for CJK to get good results?
 */
@interface HGSQuery : NSObject {
 @private
  HGSTokenizedString *tokenizedQueryString_;
  HGSResultArray *pivotObjects_;
  HGSQuery *parent_;
  HGSQueryFlags flags_;
}

/*! 
  A pivot object in the context is any result currently set to filter search
  this could  a directory (filtering to its contents) or a website (searching
  data there) or many other types of searchable items.
*/
@property (readonly, retain) HGSResultArray *pivotObjects;

/*!
 pivotObject will return the first value of pivotObjects if and only if
 [pivotObjects count] == 1. Otherwise it will return nil.
*/
@property (readonly, retain) HGSResult *pivotObject;

/*!
  The query string in it's original and tokenized forms.
*/
@property (readonly, retain) HGSTokenizedString *tokenizedQueryString;

/*!
  A "parent" is a query that has asked for this one to be created.  Usually to
  pick up an indirect object for an action.  This allows a SearchSource to walk
  to the parent and fetch it's direct object to return results specific to that
  object.
*/
@property (readwrite, retain) HGSQuery *parent;

/*! 
  Various flags that modify some queries.
*/
@property (readonly, assign) HGSQueryFlags flags;

/*! 
 Designated Initializer.
*/
- (id)initWithTokenizedString:(HGSTokenizedString *)query 
                 pivotObjects:(HGSResultArray *)pivots
                   queryFlags:(HGSQueryFlags)flags;

- (id)initWithString:(NSString *)query 
        pivotObjects:(HGSResultArray *)pivots
          queryFlags:(HGSQueryFlags)flags;
@end
