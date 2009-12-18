//
//  HGSResult.h
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
  @discussion HGSResult
*/

#import <Foundation/Foundation.h>

@class HGSSearchSource;

// Support the icon property: the phone needs to treat this as a different class
#if TARGET_OS_IPHONE
@class UIImage;
typedef UIImage NSImage;
#else
@class NSImage;
#endif

// public value keys
extern NSString* const kHGSObjectAttributeNameKey;  // NSString
extern NSString* const kHGSObjectAttributeURIKey;  // NSString
extern NSString* const kHGSObjectAttributeUniqueIdentifiersKey; // NSArray (of NSStrings)
extern NSString* const kHGSObjectAttributeTypeKey;  // NSString

// Last Used Date can be set using the key, but should be retrieved using
// the [HGSResult lastUsedDate] method. It will not be in the value dictionary.
extern NSString* const kHGSObjectAttributeLastUsedDateKey;  // NSDate
extern NSString* const kHGSObjectAttributeSnippetKey;  // NSString
extern NSString* const kHGSObjectAttributeSourceURLKey;  // NSString
// Icon Key returns the icon lazily (default for things in the table)
// Immediate Icon Key blocks the UI until we get an icon back
extern NSString* const kHGSObjectAttributeIconKey;  // NSImage
extern NSString* const kHGSObjectAttributeImmediateIconKey;  // NSImage
extern NSString* const kHGSObjectAttributeIconPreviewFileKey;  // NSString - either an URL or a filepath
extern NSString* const kHGSObjectAttributeCompoundIconPreviewFileKey;  // NSURL
extern NSString* const kHGSObjectAttributeFlagIconNameKey;  // NSString
extern NSString* const kHGSObjectAttributeAliasDataKey;  // NSData
extern NSString* const kHGSObjectAttributeIsSyntheticKey;  // NSNumber (BOOL)
extern NSString* const kHGSObjectAttributeIsContainerKey;  // NSNumber (BOOL)
extern NSString* const kHGSObjectAttributeDefaultActionKey;  // id<HGSAction>
extern NSString* const kHGSObjectAttributeContactEmailKey; // NSString - Primary email address
extern NSString* const kHGSObjectAttributeEmailAddressesKey; // NSArray of NSString - Related email addresses
extern NSString* const kHGSObjectAttributeContactsKey;  // NSArray of NSString - Names of related people
extern NSString* const kHGSObjectAttributeBundleIDKey;  // NSString - Bundle ID
extern NSString* const kHGSObjectAttributeAlternateActionURIKey; // NSURL - url to be opened for accessory cell in mobile

extern NSString* const kHGSObjectAttributeWebSearchDisplayStringKey; // Display string to replace "Search %@" when it doesn't make sense
extern NSString* const kHGSObjectAttributeWebSearchTemplateKey; // NSString
extern NSString* const kHGSObjectAttributeAllowSiteSearchKey; // NSNumber BOOL - Allow this item to be tabbed into
extern NSString* const kHGSObjectAttributeWebSuggestTemplateKey; // NSString - JSON suggest url (in google/opensearch format)
extern NSString* const kHGSObjectAttributeStringValueKey; // NSString
extern NSString* const kHGSObjectAttributePasteboardValueKey; // NSDictionary of types(NSString) to NSData

// Keys for attribute dictionaries. Use accesors to get values.
extern NSString* const kHGSObjectAttributeRankFlagsKey;  // NSNumber of HGSRankFlags
extern NSString* const kHGSObjectAttributeRankKey;  // NSNumber 0-10... (estimated number of uses in 7 days?)

extern NSString* const kHGSObjectAttributeAddressBookRecordIdentifierKey;  // NSValue (NSInteger)

/*!
  The "type" system used for results is based on string hierarchies (similar to
  reverse dns names).  The common bases are "contact", "file", "webpage", etc.
  A source can then refine them to be more specific: "contact.addressbook",
  "contact.google", "webpage.bookmark".  These strings are meant to be case
  sensitive (to allow for faster compares).  There are two helpers (isOfType:
  and conformsToType:) that allow the caller to check to see if a result is of
  a certain type or refinement of that type.  The HGS_SUBTYPE macro is to be
  used in the construction of string hierarchies with more than one segment.
  Types can be made up of multiple segments to refine them as specifically as
  needed.
*/
#define HGS_SUBTYPE(x,y) x @"." y
/*!
  Here are the current bases/common types. This DOES NOT mean that this is all 
  the possible valid base types.  New sources are free to add new types.
*/
#define kHGSTypeContact @"contact"
#define kHGSTypeFile    @"file"
#define kHGSTypeEmail   @"email"
#define kHGSTypeWebpage @"webpage"
#define kHGSTypeOnebox  @"onebox"
#define kHGSTypeAction  @"action"
#define kHGSTypeText    @"text"
#define kHGSTypeScript  @"script"
#define kHGSTypeDateTime @"datetime"
#define kHGSTypeGeolocation @"geolocation"
#define kHGSTypeSearch           HGS_SUBTYPE(kHGSTypeText, @"search")
#define kHGSTypeSuggest          HGS_SUBTYPE(kHGSTypeText, @"suggestion")
#define kHGSTypeDirectory        HGS_SUBTYPE(kHGSTypeFile, @"directory")
#define kHGSTypeTextFile         HGS_SUBTYPE(kHGSTypeFile, @"text")
#define kHGSTypeFileApplication  HGS_SUBTYPE(kHGSTypeFile, @"application")
#define kHGSTypeWebBookmark      HGS_SUBTYPE(kHGSTypeWebpage, @"bookmark")
#define kHGSTypeWebHistory       HGS_SUBTYPE(kHGSTypeWebpage, @"history")
#define kHGSTypeWebApplication   HGS_SUBTYPE(kHGSTypeWebpage, @"application")
#define kHGSTypeGoogleSuggest    HGS_SUBTYPE(kHGSTypeSuggest, @"googlesuggest")
#define kHGSTypeGoogleNavSuggest HGS_SUBTYPE(kHGSTypeWebpage, @"googlenavsuggest")
#define kHGSTypeGoogleSearch     HGS_SUBTYPE(kHGSTypeSearch,  @"googlesearch")
// Media splits into file. and webpage. because most actions will need to know
// how to act on them based on how they are fetched.
#define kHGSTypeFileMedia        HGS_SUBTYPE(kHGSTypeFile, @"media")
#define kHGSTypeFileMusic        HGS_SUBTYPE(kHGSTypeFileMedia, @"music")
#define kHGSTypeFileImage        HGS_SUBTYPE(kHGSTypeFileMedia, @"image")
#define kHGSTypeFileMovie        HGS_SUBTYPE(kHGSTypeFileMedia, @"movie")
#define kHGSTypeWebMedia         HGS_SUBTYPE(kHGSTypeWebpage, @"media")
#define kHGSTypeWebMusic         HGS_SUBTYPE(kHGSTypeWebMedia, @"music")
#define kHGSTypeWebImage         HGS_SUBTYPE(kHGSTypeWebMedia, @"image")
#define kHGSTypeWebMovie         HGS_SUBTYPE(kHGSTypeWebMedia, @"movie")
// TODO(dmaclach): should album inherit from image?
#define kHGSTypeFilePhotoAlbum   HGS_SUBTYPE(kHGSTypeFileImage,   @"album") 
#define kHGSTypeWebPhotoAlbum    HGS_SUBTYPE(kHGSTypeWebImage,   @"album") 
#define kHGSTypeTextUserInput    HGS_SUBTYPE(kHGSTypeText, @"userinput")
#define kHGSTypeTextPhoneNumber  HGS_SUBTYPE(kHGSTypeText, @"phonenumber")
#define kHGSTypeTextEmailAddress HGS_SUBTYPE(kHGSTypeText, @"emailaddress")
#define kHGSTypeTextInstantMessage HGS_SUBTYPE(kHGSTypeText, @"instantmessage")
#define kHGSTypeTextAddress      HGS_SUBTYPE(kHGSTypeText, @"address")

enum {
  eHGSNameMatchRankFlag = 1 << 0,
  eHGSUserPersistentPathRankFlag = 1 << 1,
  eHGSLaunchableRankFlag = 1 << 2,
  eHGSSpecialUIRankFlag = 1 << 3,
  eHGSUnderHomeRankFlag = 1 << 4,
  eHGSUnderDownloadsRankFlag = 1 << 5,
  eHGSUnderDesktopRankFlag = 1 << 6,
  eHGSSpamRankFlag = 1 << 7,
  eHGSHomeChildRankFlag = 1 << 8,
  eHGSBelowFoldRankFlag = 1 << 9,
};
typedef NSUInteger HGSRankFlags;

/*!
  Encapsulates a search result. May not directly contain all information about
  the result, but can use |source| to provide it lazily when needed for display
  or comparison purposes.
  
  The source may provide results lazily and will send notifications to anyone
  registered with KVO.  Consumers of the attributes shouldn't need to concern
  themselves with the details of pending loads or caching of results, but
  should call |-cancelAllPendingAttributeUpdates| when details of an object are
  no longer required (eg, the user has selected a different result or cleared
  the search).
*/
@interface HGSResult : NSObject <NSCopying, NSMutableCopying> {
 @public
  /*!
    This is accessed by the mixer for speed.
  */

  NSUInteger idHash_;  
 @protected
  /*!
    Used for global ranking, set by the Search Source that creates it.
  */
  HGSRankFlags rankFlags_;
  CGFloat rank_;
  NSString *uri_;
  NSString *displayName_;
  NSString *type_;
  HGSSearchSource *source_;
  NSDictionary *attributes_;  
  NSString *normalizedIdentifier_; // Only webpages have normalizedIdentifiers
  NSDate *lastUsedDate_;
  BOOL conformsToContact_;
}

/*!
 The display name for the result.
 */
@property (readonly) NSString *displayName;
/*!
 URI for the result.
 */
@property (readonly) NSString *uri;
/*!
 Is it a local file
*/
@property (readonly, getter=isFileResult) BOOL fileResult;
/*!
 Filepath for the result
*/
@property (readonly) NSString *filePath;
/*!
 URL for the result.
*/
@property (readonly) NSURL *url;
/*!
  Type of the result. See kHGSType constants.
*/
@property (readonly) NSString *type;
/*!
  Last time this result was used (if known)
*/
@property (readonly) NSDate *lastUsedDate;
/*!
  The relative rank of an item (from 0.0 to 1.0)
*/
@property (readonly) CGFloat rank;
/*!
  Information about the item that may change it's overall ranking
*/
@property (readonly) HGSRankFlags rankFlags;
/*!
  The source which supplied this result.
*/
@property (readonly) HGSSearchSource *source;

/*!
  Convenience methods
*/
+ (id)resultWithURL:(NSURL *)url
               name:(NSString *)name
               type:(NSString *)typeStr
             source:(HGSSearchSource *)source
         attributes:(NSDictionary *)attributes;

+ (id)resultWithFilePath:(NSString *)path 
                  source:(HGSSearchSource *)source 
              attributes:(NSDictionary *)attributes;

+ (id)resultWithURI:(NSString *)uri
               name:(NSString *)name
               type:(NSString *)type
             source:(HGSSearchSource *)source
         attributes:(NSDictionary *)attributes;

/*!
  Create an result based on a dictionary of keys. 
*/
+ (id)resultWithDictionary:(NSDictionary *)dictionary 
                    source:(HGSSearchSource *)source;

- (id)initWithURI:(NSString *)uri
             name:(NSString *)name
             type:(NSString *)typeStr
           source:(HGSSearchSource *)source
       attributes:(NSDictionary *)attributes;

- (id)initWithDictionary:(NSDictionary*)dict
                  source:(HGSSearchSource *)source;

/*!
  Return a new result by adding attributes to an old result.
*/
- (HGSResult *)resultByAddingAttributes:(NSDictionary *)attributes;

/*!
  Get an attribute by name. |-valueForKey:| may return a placeholder value that
  is to be updated later via KVO.
*/
- (id)valueForKey:(NSString*)key;

/*!
  Merge the attributes of |result| with this one, and return a new object.
  Single values that overlap are lost.
*/
- (HGSResult *)mergeWith:(HGSResult*)result;

/*!
  Is this result a "duplicate" of |compareTo|? Not using |-isEqual:| because
  that impacts how the object gets put into collections.
*/
- (BOOL)isDuplicate:(HGSResult*)compareTo;

/*!
  Some helpers to check if this result is of a given type.  |isOfType| checks
  for an exact match of the type.  |conformsToType{Set}| checks to see if this
  object is of the specific type{s} or a refinement of it/them.
*/
- (BOOL)isOfType:(NSString *)typeStr;
- (BOOL)conformsToType:(NSString *)typeStr;
- (BOOL)conformsToTypeSet:(NSSet *)typeSet;
/*!
 Mark this result as having been of interest to the user.
 Base implementation sends a promoteResult message to the result's source,
 and sends out a "kHGSResultDidPromoteNotification".
 */
- (void)promote;

/*!
 Given a path to a file, returns it's HGSType.
*/
+ (NSString *)hgsTypeForPath:(NSString*)path;

@end

@interface HGSMutableResult : HGSResult
- (void)addRankFlags:(HGSRankFlags)flags;
- (void)removeRankFlags:(HGSRankFlags)flags;
- (void)setRank:(CGFloat)rank;
@end

/*!
 A collection of HGSResults that acts very similar to NSArray.
*/
@interface HGSResultArray : NSObject <NSFastEnumeration> {
  NSArray *results_;
}
/*!
 The display name for the results combined.
 */
@property (readonly) NSString *displayName;

+ (id)arrayWithResult:(HGSResult *)result;
+ (id)arrayWithResults:(NSArray *)results;
+ (id)arrayWithFilePaths:(NSArray *)filePaths;
- (id)initWithResults:(NSArray *)results;
- (id)initWithFilePaths:(NSArray *)filePaths;
- (NSArray *)urls;
- (NSUInteger)count;
- (HGSResult *)objectAtIndex:(NSUInteger)ind;
- (HGSResult *)lastObject;
/*!
  Will return nil if any of the results does not have a valid file path
*/
- (NSArray *)filePaths;
- (NSImage *)icon;
/*!
  Some helpers to check if this result is of a given type.  |isOfType| checks
  for an exact match of the type.  |conformsToType{Set}| checks to see if this
  object is of the specific type{s} or a refinement of it/them.
*/
- (BOOL)isOfType:(NSString *)typeStr;
- (BOOL)conformsToType:(NSString *)typeStr;
- (BOOL)conformsToTypeSet:(NSSet *)typeSet;
- (BOOL)doesNotConformToTypeSet:(NSSet *)typeSet;
/*!
 Mark these results as having been of interest to the user.
 Base implementation sends a promoteResult message to the result's source.
*/
- (void)promote;

@end

/*!
 Notification sent when a result is promoted.
 Object is the result.
*/
extern NSString *const kHGSResultDidPromoteNotification;
