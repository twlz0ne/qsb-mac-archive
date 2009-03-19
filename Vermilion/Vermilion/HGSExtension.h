//
//  HGSExtension.h
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
#import <AppKit/AppKit.h>

/*!
  Information about extensions that a UI can display.
*/
@interface HGSExtension : NSObject {
 @private
  NSString *displayName_;
  NSString *iconPath_;
  NSImage *icon_;
  NSString *identifier_;
  NSBundle *bundle_;
}

/*!
 Return the bundle associated with this extension.
 */
@property (readonly, retain) NSBundle *bundle;
/*!
 Return an identifier for the extension (reverse DNS style).
 
 @result The default implementation returns the kHGSExtensionIdentifierKey value 
         from the configuration dictionary. Falls back on CFBundleIdentifier.
 */
@property (readonly, copy) NSString *identifier;
/*!
 Return an icon that can be displayed 128x128.
 
 @result The default implementation returns the image at the 
         kHGSExtensionIconImagePathKey value from the configuration dictionary. 
         Falls back on a default icon.
*/
@property (readonly, retain) NSImage *icon;
/*!
 Return a display name string for the extension.
 
 @result The default implementation returns the kHGSExtensionUserVisibleNameKey 
        value from the configuration dictionary. If that doesn't exist, it tries
        various fallbacks trying to get a decent name.
*/
@property (readonly, copy) NSString *displayName;
/*!
 Return a copyright string for the extension.
 
 @result The default implementation returns the NSHumanReadableCopyright value.
*/
@property (readonly, copy) NSString *copyright;
/*!
 Return a description for the extension.
 
 @result The default implementation looks for a file named "Description.html", 
         "Description.rtf", and "Description.rtfd", in that order, in the bundle 
         returned by bundle.
 */
@property (readonly, copy) NSAttributedString *extensionDescription;
/*!
 Return a version number for the extension.
 
 @result The default value is the "CFBundleVersion" value from the info.plist 
         of the bundle of the class that this object is an instance of.
*/
@property (readonly, copy) NSString *extensionVersion;
/*!
  Return a name for a default icon for this extension if another icon can't
  be found.
*/
@property (readonly, retain) NSString *defaultIconName;
/*!
 Designated initializer.
 */
- (id)initWithConfiguration:(NSDictionary *)configuration;

/*!
  Return an objectForInfoDictionaryKey for this extension
*/
- (id)objectForInfoDictionaryKey:(NSString *)key;

/*!
  Return a default object for the given key.  Overridding implementations
  should always call super if it cannot provide the default.
*/
- (id)defaultObjectForKey:(NSString *)key;

@end

#pragma mark Extension keys

/*!
  String which is the class of the extension. Required.
*/
extern NSString *const kHGSExtensionClassKey;
/*!
  String giving the points to which to attach the extension. Required.
*/
extern NSString *const kHGSExtensionPointKey;
/*!
  String which is the reverse DNS identifier of the extension. Required.
*/
extern NSString *const kHGSExtensionIdentifierKey;
/*!
  String which is the user-visible name of the extension. Optional.
  Will use plugin display name if not supplied.
*/
extern NSString *const kHGSExtensionUserVisibleNameKey;
/*!
  Extension's icon image. This can be requested through defaultObjectForKey but
  cannot be set in the initial configuration, because we want to discourage
  loading icons at startup if at all possible. When you fulfill the request we
  expect a 128x128 image.
*/
extern NSString *const kHGSExtensionIconImageKey;
/*!
  String which is the path to an icon image. The path can either just be a
  name, in which case it will be looked for in the extension bundle, or a full
  path.
*/
extern NSString *const kHGSExtensionIconImagePathKey;
/*!
  NSNumber (BOOL) indicating if extension is enabled. Optional. Defaults
  to YES.
*/
extern NSString *const kHGSExtensionEnabledKey;
/*!
  NSBundle bundle associated with the extension
*/
extern NSString *const kHGSExtensionBundleKey;
/*!
  Types of accounts in which the extension is interested.  This may be a
  single NSString specifying the account type, or an array of NSStrings.
*/
extern NSString *const kHGSExtensionDesiredAccountTypes;
/*!
  Type of accounts in which the extension is offering.
*/
extern NSString *const kHGSExtensionOfferedAccountType;
/*!
  YES if the extension presented to the user in the preferences panel.  If this
  is not present then YES is assumed.
*/
extern NSString *const kHGSExtensionIsUserVisible;
/*!
  YES if the extension is to be enabled by default.  If this key is _not_
  present, YES is assumed, except for account-dependent sources, in which case
  NO is assumed.
*/
extern NSString *const kHGSExtensionIsEnabledByDefault;
/*!
  Account assigned to the extension. (id<HGSAccount>)
*/
extern NSString *const kHGSExtensionAccount;

#pragma mark Notifications

/*!
  Posted by an extension for presenting a short informational message to the
  user about the success of failure of an operation that may not otherwise
  manifest itself to the user.  |userInfo| should be a dictionary containing at
  least one of kHGSPlainTextMessageKey or kHGSAttributedTextMessageKey.  Other
  items may also be specified, including those given in the next section.
  |object| should be the reporting extension.
*/
extern NSString *const kHGSUserMessageNotification;

// Extension message notification userinfo keys

/*!
  An NSString or NSAttributedString giving a very short message to be presented
  to the user.
*/
extern NSString *const kHGSSummaryMessageKey;
/*!
  An NSString or NSAttributedString giving a longer, descriptive message to be
  presented to the user.  This is most valuable for suggesting remedial actions
  that the user can take or for giving additional information about the
  message.
*/
extern NSString *const kHGSDescriptionMessageKey;
/*!
  An NSImage that can be used to give additional context to the message
  presentation.  This is typically an icon representing the service associated
  with the reporting extension.
*/
extern NSString *const kHGSImageMessageKey;
/*!
  An NSNumber containing a whole number giving a success code for the operation
  performed by the extension.  Non-negative numbers typically represent
  success, with negative numbers representing an error of some kind.  The
  client UI could, for example, apply a tag to the message image for error
  conditions.
*/
extern NSString *const kHGSSuccessCodeMessageKey;

/*!
  @enum HGSSuccessCode
  @constant kHGSSuccessCodeBadError Serious Error Occurred
  @constant kHGSSuccessCodeError Error Occurred
  @constant kHGSSuccessCodeSuccess Successful
  @discussion
  Success Codes for use with kHGSSuccessCodeMessageKey.  Use whatever codes you
  want but remember the following: 
  1 negative numbers mean 'error' while positive numbers mean 'success' 
  2 the more negative a number is the more serious the error 
  3 Growl uses success codes where positive means 'error'
  4 Growl uses a success code range of -2 to +2 
  5 when passing error codes to Growl we change the sign and clamp
*/
enum {
  kHGSSuccessCodeBadError = -2,
  kHGSSuccessCodeError = -1,
  kHGSSuccessCodeSuccess = 0,
};
