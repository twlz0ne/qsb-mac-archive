//
//  HGSActionArgument.h
//
//  Copyright (c) 2010 Google Inc. All rights reserved.
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
 @discussion HGSActionArgument
*/

#import <Foundation/Foundation.h>

@class HGSTypeFilter;

/*!
 @class HGSActionArgument
 @discussion
 Describes an argument that an action may have.
*/

@interface HGSActionArgument : NSObject {
 @private
  BOOL optional_;
  NSString *name_;
  NSString *localizedName_;
  HGSTypeFilter *typeFilter_;
  NSString *localizedDescription_;
  NSSet *localizedOtherTerms_;
}

/*! Is this argument an optional one. */
@property (readonly, nonatomic, assign, getter=isOptional) BOOL optional;

/*! 
 Name of the argument. Each argument for an action must have a unique
 name. This is not to be displayed to the user.
*/
@property (readonly, nonatomic, retain) NSString *name;

/*! 
 Localized name of the argument for user display.
*/
@property (readonly, nonatomic, retain) NSString *localizedName;

/*!
 Describes the valid types for the argument.
*/
@property (readonly, nonatomic, retain) HGSTypeFilter *typeFilter;

/*!
 A description for the argument that can be displayed.
*/

@property (readonly, nonatomic, retain) NSString *localizedDescription;

/*!
 Localized synonyms for the argument. Again these must be unique across
 all arguments for a given action.
*/
@property (readonly, nonatomic, retain) NSSet *localizedOtherTerms;

- (id)initWithConfiguration:(NSDictionary *)configuration;

@end

/*!
 Configuration key for the supported object types for the action argument.
 
 Type is NSString, NSArray or NSSet. '*' matches all types.
 */
extern NSString* const kHGSActionArgumentSupportedTypesKey;

/*!
 Configuration key for the unsupported object types for the action argument.
 Default is nil, which means that no filtering is performed.
 
 Type is NSString, NSArray or NSSet. '*' is not allowed.
*/
extern NSString* const kHGSActionArgumentUnsupportedTypesKey;

/*!
 Configuration key for whether the argument is optional.
 Default is NO.
 
 Type is Boolean.
 */
extern NSString* const kHGSActionArgumentOptionalKey;

/*!
 Configuration key for other terms that match for this action argument. 
 
 Type is NSString, or NSArray of NSString.
 */
extern NSString* const kHGSActionArgumentOtherTermsKey;

/*!
 Configuration key for the name of the argument.
 
 Type is String.
 */
extern NSString* const kHGSActionArgumentNameKey;

/*!
 Configuration key for the description of the argument. This will be used
 as a key to look up a localized version.
 Default is nil.
 
 Type is String.
 */
extern NSString* const kHGSActionArgumentDescriptionKey;

