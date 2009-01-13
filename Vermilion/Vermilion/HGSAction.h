//
//  HGSAction.h
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
#import "HGSExtension.h"

// kHGSValidateActionBehaviorsPrefKey is a boolean preference that the engine
// can use to enable extra logging about Action behaviors to help developers
// make sure their Action is acting right.  The pref should be set before launch
// to ensure it is all possible checks are done.
#define kHGSValidateActionBehaviorsPrefKey @"HGSValidateActionBehaviors"


@class HGSObject;

// keys to |-performActionWithInfo:|, see below for more details
extern NSString* const kHGSActionPrimaryObjectKey;
extern NSString* const kHGSActionIndirectObjectKey;

//
// HGSAction
//
// The base class for actions. Actions can exist in two different versions.
// The first version is "noun verb" such as "file open". The second requires two
// objects, "noun verb noun" such as "file 'email to' hasselhoff" with the 2nd
// being the indirect object. An action can be asked if a given result is
// valid as an indirect object. Actions can also return a result so that they
// can be chained together. 
//
 
@protocol HGSAction <HGSExtension>

// If this action can take a direct and/or indirect object, it must declare the
// types.  If the indirect object is optional, then use
// |isIndirectObjectOptional| to let the calling code know.  If any object type
// is valid for either direct or indirect objects, then return a set with the
// string "*".
- (NSSet*)directObjectTypes;
- (NSSet*)indirectObjectTypes;
- (BOOL)isIndirectObjectOptional;

// Does the action apply to the result.  The calling code will check that the
// result is of one of the types listed in directObjectTypes before calling
// this.
- (BOOL)doesActionApplyTo:(HGSObject*)result;

// Should this action appear in global search results list (ie-no pivot).
// HGSAction implementation returns NO.
- (BOOL)showActionInGlobalSearchResults;

// Does the action cause a UI Context change? In the case
// of QSB, should we hide the QSB before performing the action.
// HGSAction implementation returns YES.
- (BOOL)doesActionCauseUIContextChange;

// returns the name to display in the UI for this action. May change based
// on the contents of |result|, but the base class ignores it.
- (NSString*)displayNameForResult:(HGSObject*)result;

// returns the icon to display in the UI for this action. May change based
// on the contents of |result|, but the base class ignores it.
- (id)displayIconForResult:(HGSObject*)result;

// Conformers override to perform the action. Actions can have either one or two
// objects. If only one is present, it should act as "noun verb" such as "file
// open". If there are two it should behave as "noun verb noun" such as "file
// 'email to' hasselhoff" with the 2nd being the indirect object.
// Returns NO if action not performed. YES dictionary if performed.
// 
// *** NB ***
// Do not call this method directly. Wrap your action up in an
// HGSActionOperation and use that instead.
//
// |info| keys:
//   kHGSActionPrimaryObjectKey 
//     - HGSObject* - the direct object (reqd)
//   kHGSActionIndirectObjectKey 
//     - HGSObject* - the indirect object, there can be only one. (opt)
//
// Return YES on success.
//
- (BOOL)performActionWithInfo:(NSDictionary*)info;
@end

// The HGSAction class is provided as a convenience class for people doing
// simple actions. People may want to use the protocol if they prefer to reuse
// some exiting class without subclassing.

@interface HGSAction : HGSExtension <HGSAction> {
 @private
  NSSet *directObjectTypes_;
  NSSet *indirectObjectTypes_;
  BOOL indirectObjectOptional_;
  BOOL showActionInGlobalSearchResults_;
  BOOL doesActionCauseUIContextChange_;
}

// The defaults for the apis in the protocol are as follow:
//
//   -directObjectTypes
//      nil or the value of "HGSActionDirectObjectTypes" from config dict.
//   -indirectObjectTypes
//      nil or the value of "HGSActionIndirectObjectTypes" from config dict.
//   -isIndirectObjectOptional
//      NO or the value of "HGSActionIndirectObjectOptional" from config dict.
//   -doesActionApplyTo:
//      YES
//   -showActionInGlobalSearchResults
//      NO or the value of "HGSActionShowActionInGlobalSearchResults" from
//      config dict.
//   -doesActionCauseUIContextChange
//      YES or the value of "HGSActionDoesActionCauseUIContextChange" from
//      config dict.
//   -displayNameForResult:
//      the name of the action (-[HGSExtension name])
//   -displayIconForResult:
//      the name of the action (-[HGSExtension icon])
//

@end
