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

/*!
 @header
 @discussion
*/

#import <Foundation/Foundation.h>
#import "HGSExtension.h"

@class HGSResult;
@class HGSResultArray;

/*!
  @class HGSAction
  @coclass HGSActionOperation
  @discussion
  The base class for actions. Actions can exist in two different versions.  The
  first version is "noun verb" such as "file open". The second requires two
  objects, "noun verb noun" such as "file 'email to' hasselhoff" with the 2nd
  being the indirect object. An action can be asked if a given result is valid
  as an indirect object. Actions can also return a result so that they can be
  chained together.
*/
@interface HGSAction : HGSExtension {
 @private
  NSSet *directObjectTypes_;
  NSSet *indirectObjectTypes_;
  BOOL indirectObjectOptional_;
  BOOL showInGlobalSearchResults_;
  BOOL causesUIContextChange_;
}

/*!
  The types of direct objects that are valid for this action
  @result The value of "HGSActionDirectObjectTypes" from config dict.
*/
@property (readonly, retain) NSSet *directObjectTypes;
/*!
  The types of direct objects that are valid for this action
  @result The value of "HGSActionIndirectObjectTypes" from config dict.
*/
@property (readonly, retain) NSSet *indirectObjectTypes;
/*!
  Is the indirect object optional for this action.
  @result Defaults to NO or the value of "HGSActionIndirectObjectOptional" from 
          config dict.
*/ 
@property (readonly) BOOL indirectObjectOptional;
/*!
  Should this action appear in global search results list (ie-no pivot).
  @result NO or the value of "HGSActionShowActionInGlobalSearchResults" from
          config dict.
*/
@property (readonly) BOOL showInGlobalSearchResults;
/*!
  Does the action cause a UI Context change? In the case of QSB, should we hide
  the QSB before performing the action.
  @result YES or the value of "HGSActionDoesActionCauseUIContextChange" from
          config dict.
*/
@property (readonly) BOOL causesUIContextChange;

/*!
  Does the action apply to an individual result. The calling code will check
  that the results are all one of the types listed in directObjectTypes before
  calling this. Do not call this to check if an action is valid for a given
  result. Always turn the result into a result array and call
  appliesToResults:. This is only for subclassers to override.
  @result Defaults to YES
*/
- (BOOL)appliesToResult:(HGSResult *)result;

/*!
  Does the action apply to the array of results. Normally you want to override
  appliesToResult:, which appliesToResults: will call.
  @result YES if all the results in the array conform to 
          directObjectTypes and they each pass appliesToResult:
*/
- (BOOL)appliesToResults:(HGSResultArray *)results;

/*!
  returns the name to display in the UI for this action. May change based on
  the contents of |result|, but the base class ignores it.
  @result Defaults to displayName.

*/
- (NSString*)displayNameForResults:(HGSResultArray*)results;

/*!
  returns the icon to display in the UI for this action. May change based on
  the contents of |result|, but the base class ignores it.
  @result Defaults to generic action icon.
*/
- (id)displayIconForResults:(HGSResultArray*)results;

/*!
  Conformers override to perform the action. Actions can have either one or two
  objects. If only one is present, it should act as "noun verb" such as "file
  open". If there are two it should behave as "noun verb noun" such as "file
  'email to' hasselhoff" with the 2nd being the indirect object.
  
  *** NB *** 
  
  Do not call this method directly. Wrap your action up in an
  HGSActionOperation and use that instead.
  
  @param info keys: 
  1 kHGSActionDirectObjectsKey (HGSResultArray *) - the direct objects (reqd)  
  2 kHGSActionIndirectObjectsKey (HGSResultArray *) - the indirect objects (opt)
  
  @result YES if action performed.
*/
- (BOOL)performWithInfo:(NSDictionary*)info;

@end

/*!
  kHGSValidateActionBehaviorsPrefKey is a boolean preference that the engine
  can use to enable extra logging about Action behaviors to help developers
  make sure their Action is acting right.  The pref should be set before launch
  to ensure it is all possible checks are done.
*/
#define kHGSValidateActionBehaviorsPrefKey @"HGSValidateActionBehaviors"

/*!
  The key for the direct objects for to performWithInfo:. 
 
  Type is HGSResultsArray.
  @see //google_vermilion_ref/occ/instm/HGSAction/performWithInfo: performWithInfo:
*/
extern NSString* const kHGSActionDirectObjectsKey;

/*!
 The key for the indirect objects for to performWithInfo:.
 
 Type is HGSResultsArray.
 @see //google_vermilion_ref/occ/instm/HGSAction/performWithInfo: performWithInfo:
*/
extern NSString* const kHGSActionIndirectObjectsKey;
