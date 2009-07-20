//
//  HGSResult.m
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

#import "HGSResult.h"
#import "HGSExtensionPoint.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"
#import "HGSIconProvider.h"
#import "HGSSearchSource.h"
#import "NSString+ReadableURL.h"
#import "GTMMethodCheck.h"
#import "HGSPluginLoader.h"
#import "HGSDelegate.h"
#import "HGSBundle.h"

// storage and initialization for value names
NSString* const kHGSObjectAttributeNameKey = @"kHGSObjectAttributeName";
NSString* const kHGSObjectAttributeURIKey = @"kHGSObjectAttributeURI";
NSString* const kHGSObjectAttributeUniqueIdentifiersKey = @"kHGSObjectAttributeUniqueIdentifiers";  // NSString
NSString* const kHGSObjectAttributeTypeKey = @"kHGSObjectAttributeType";
NSString* const kHGSObjectAttributeLastUsedDateKey = @"kHGSObjectAttributeLastUsedDate";
NSString* const kHGSObjectAttributeSnippetKey = @"kHGSObjectAttributeSnippet";
NSString* const kHGSObjectAttributeSourceURLKey = @"kHGSObjectAttributeSourceURL";
NSString* const kHGSObjectAttributeIconKey = @"kHGSObjectAttributeIcon";
NSString* const kHGSObjectAttributeImmediateIconKey = @"kHGSObjectAttributeImmediateIconKey";
NSString* const kHGSObjectAttributeIconPreviewFileKey = @"kHGSObjectAttributeIconPreviewFileKey";
NSString *const kHGSObjectAttributeCompoundIconPreviewFileKey = @"kHGSObjectAttributeCompoundIconPreviewFileKey";
NSString* const kHGSObjectAttributeFlagIconNameKey = @"kHGSObjectAttributeFlagIconName";
NSString* const kHGSObjectAttributeAliasDataKey = @"kHGSObjectAttributeAliasData";
NSString* const kHGSObjectAttributeIsSyntheticKey = @"kHGSObjectAttributeIsSynthetic";
NSString* const kHGSObjectAttributeIsContainerKey = @"kHGSObjectAttributeIsContainer";
NSString* const kHGSObjectAttributeRankKey = @"kHGSObjectAttributeRank";
NSString* const kHGSObjectAttributeRankFlagsKey = @"kHGSObjectAttributeRankFlags";
NSString* const kHGSObjectAttributeDefaultActionKey = @"kHGSObjectAttributeDefaultActionKey";
NSString* const kHGSObjectAttributeBundleIDKey = @"kHGSObjectAttributeBundleID";
NSString* const kHGSObjectAttributeWebSearchDisplayStringKey = @"kHGSObjectAttributeWebSearchDisplayString";
NSString* const kHGSObjectAttributeWebSearchTemplateKey = @"kHGSObjectAttributeWebSearchTemplate";
NSString* const kHGSObjectAttributeAllowSiteSearchKey = @"kHGSObjectAttributeAllowSiteSearch";
NSString* const kHGSObjectAttributeWebSuggestTemplateKey = @"kHGSObjectAttributeWebSuggestTemplate";
NSString* const kHGSObjectAttributeStringValueKey = @"kHGSObjectAttributeStringValue";
NSString* const kHGSObjectAttributePasteboardValueKey = @"kHGSObjectAttributePasteboardValue";

// Contact related keys
NSString* const kHGSObjectAttributeContactEmailKey = @"kHGSObjectAttributeContactEmail";  
NSString* const kHGSObjectAttributeEmailAddressesKey = @"kHGSObjectAttributeEmailAddressesKey";
NSString* const kHGSObjectAttributeContactsKey = @"kHGSObjectAttributeContactsKey";
NSString* const kHGSObjectAttributeAlternateActionURIKey = @"kHGSObjectAttributeAlternateActionURI";
NSString* const kHGSObjectAttributeAddressBookRecordIdentifierKey = @"kHGSObjectAttributeAddressBookRecordIdentifier";

static NSString* const kHGSResultFileSchemePrefix = @"file://";

@interface HGSResult ()
@property (readonly) NSDictionary *attributes;
+ (NSString *)hgsTypeForPath:(NSString*)path;

@end

@implementation HGSResult

GTM_METHOD_CHECK(NSString, readableURLString);
@synthesize displayName = displayName_;
@synthesize type = type_;
@synthesize uri = uri_;
@synthesize lastUsedDate = lastUsedDate_;
@synthesize rank = rank_;
@synthesize rankFlags = rankFlags_;
@synthesize source = source_;
@synthesize attributes = attributes_;

+ (id)resultWithURL:(NSURL*)url
               name:(NSString *)name
               type:(NSString *)typeStr
             source:(HGSSearchSource *)source 
         attributes:(NSDictionary *)attributes {
  return [[[self alloc] initWithURI:[url absoluteString]
                               name:name
                               type:typeStr
                             source:source
                         attributes:attributes] autorelease]; 
}

+ (id)resultWithURI:(NSString*)uri
               name:(NSString *)name
               type:(NSString *)typeStr
             source:(HGSSearchSource *)source 
         attributes:(NSDictionary *)attributes {
  return [[[self alloc] initWithURI:uri
                               name:name
                               type:typeStr
                             source:source
                         attributes:attributes] autorelease]; 
}

+ (id)resultWithFilePath:(NSString *)path 
                  source:(HGSSearchSource *)source 
              attributes:(NSDictionary *)attributes {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *type = [self hgsTypeForPath:path];
  if (!type) {
    type = kHGSTypeFile;
  }
  NSString *uri 
    = [NSString stringWithFormat:@"%@%@", kHGSResultFileSchemePrefix, path];
  return [self resultWithURI:uri
                        name:[fm displayNameAtPath:path]
                        type:type
                      source:source
                  attributes:attributes];
}

+ (id)resultWithDictionary:(NSDictionary *)dictionary 
                    source:(HGSSearchSource *)source {
  return [[[self alloc] initWithDictionary:dictionary 
                                    source:source] autorelease];
}

- (id)initWithURI:(NSString *)uri
             name:(NSString *)name
             type:(NSString *)typeStr
           source:(HGSSearchSource *)source 
       attributes:(NSDictionary *)attributes {
  if ((self = [super init])) {
    if (!uri || !name || !typeStr) {
      HGSLogDebug(@"Must have an uri, name and typestr for %@ of %@ (%@)", 
                  name, source, uri);
      [self release];
      return nil;
    }
    NSMutableDictionary *abridgedAttrs 
      = [NSMutableDictionary dictionaryWithDictionary:attributes];
    [abridgedAttrs removeObjectsForKeys:[NSArray arrayWithObjects:
                                         kHGSObjectAttributeURIKey, 
                                         kHGSObjectAttributeNameKey, 
                                         kHGSObjectAttributeTypeKey,
                                         nil]];
    uri_ = [uri retain];
    idHash_ = [uri_ hash];
    displayName_ = [name retain];
    type_ = [typeStr retain];
    source_ = [source retain];
    conformsToContact_ = [self conformsToType:kHGSTypeContact];
    if ([self conformsToType:kHGSTypeWebpage]) {
      normalizedIdentifier_ 
        = [[uri_ readableURLString] retain];
    }
    NSNumber *rank 
      = [abridgedAttrs objectForKey:kHGSObjectAttributeRankKey];
    if (rank) {
      rank_ = [rank floatValue];
      [abridgedAttrs removeObjectForKey:kHGSObjectAttributeRankKey];
    }
    NSNumber *rankFlags 
      = [abridgedAttrs objectForKey:kHGSObjectAttributeRankFlagsKey];
    if (rankFlags) {
      rankFlags_ = [rankFlags unsignedIntValue];
      [abridgedAttrs removeObjectForKey:kHGSObjectAttributeRankFlagsKey];
    }
    lastUsedDate_ 
      = [abridgedAttrs objectForKey:kHGSObjectAttributeLastUsedDateKey];
    if (lastUsedDate_) {
      [abridgedAttrs removeObjectForKey:kHGSObjectAttributeLastUsedDateKey];
    } else {
      lastUsedDate_ = [NSDate distantPast];
    }
    
    // If we are supplied with an icon, apply it to both immediate
    // and non-immediate icon attributes.
    NSImage *image = [abridgedAttrs objectForKey:kHGSObjectAttributeIconKey];
    if (image) {
      if (![abridgedAttrs objectForKey:kHGSObjectAttributeImmediateIconKey]) {
        [abridgedAttrs setObject:image forKey:kHGSObjectAttributeImmediateIconKey];
      }
    } else {
      image = [abridgedAttrs objectForKey:kHGSObjectAttributeImmediateIconKey];
      if (image) {
        if (![abridgedAttrs objectForKey:kHGSObjectAttributeIconKey]) {
          [abridgedAttrs setObject:image forKey:kHGSObjectAttributeIconKey];
        }
      }
    }
      
    [lastUsedDate_ retain];
    attributes_ = [abridgedAttrs retain];
  }
  return self;
}
  
- (id)initWithDictionary:(NSDictionary*)attributes 
                  source:(HGSSearchSource *)source {
  NSString *uri = [attributes objectForKey:kHGSObjectAttributeURIKey];
  if ([uri isKindOfClass:[NSURL class]]) {
    uri = [((NSURL*)uri) absoluteString];
  }
  if ([uri hasPrefix:kHGSResultFileSchemePrefix]) {
    NSString *path = [uri substringFromIndex:[kHGSResultFileSchemePrefix length]];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
      [self release];
      return nil;
    }  
  }
  NSString *name = [attributes objectForKey:kHGSObjectAttributeNameKey];
  NSString *type = [attributes objectForKey:kHGSObjectAttributeTypeKey];
  self = [self initWithURI:uri
                      name:name 
                      type:type 
                    source:source
                attributes:attributes];
  return self;
}

- (void)dealloc {
  [[HGSIconProvider sharedIconProvider] cancelOperationsForResult:self];
  [source_ release];
  [attributes_ release];
  [uri_ release];
  [normalizedIdentifier_ release];
  [displayName_ release];
  [type_ release];
  [lastUsedDate_ release];
  [super dealloc];
}

- (id)copyOfClass:(Class)cls mergingAttributes:(NSDictionary *)attributes {
  if (attributes) {
    NSMutableDictionary *newAttributes 
      = [NSMutableDictionary dictionaryWithDictionary:attributes];
    [newAttributes addEntriesFromDictionary:[self attributes]];
    attributes = newAttributes;
  } else {
    attributes = [self attributes];
  }
  HGSResult *newResult = [[cls alloc] initWithURI:[self uri]
                                             name:[self displayName]
                                             type:[self type]
                                           source:source_
                                       attributes:attributes];
  newResult->rank_ = rank_;
  newResult->rankFlags_ = rankFlags_;
  return newResult;
}

- (id)copyWithZone:(NSZone *)zone {
  return [self copyOfClass:[HGSResult class] mergingAttributes:nil];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
  return [self copyOfClass:[HGSMutableResult class] mergingAttributes:nil];
}

- (NSUInteger)hash {
  return idHash_;
}

- (BOOL)isEqual:(id)object {
  BOOL equal = NO;
  if (idHash_ == [object hash] 
      &&[object isKindOfClass:[HGSResult class]]) {
    HGSResult *hgsResult = (HGSResult*)object;
    equal = [object isOfType:[self type]]
      && [[hgsResult url] isEqual:[self url]];
  }
  return equal;
}

- (id)valueForUndefinedKey:(NSString *)key {
  return nil;
}

- (void)setValue:(id)value forKey:(NSString *)key {
  // TODO(dmaclach): remove this soon. Here right now in case I missed 
  // some setValue:forKey: calls on HGSResult.
  HGSAssert(NO, @"setValue:(%@) forKey:(%@)", value, key);
  exit(-1);
}

// if the value isn't present, ask the result source to satisfy the
// request.
- (id)valueForKey:(NSString*)key {
  id value = [attributes_ objectForKey:key];
  if (!value) {
    if ([key isEqualToString:kHGSObjectAttributeURIKey]) {
      value = [self uri];
    } else if ([key isEqualToString:kHGSObjectAttributeNameKey]) {
      value = [self displayName];
    } else if ([key isEqualToString:kHGSObjectAttributeTypeKey]) {
      value = [self type];
    } else if ([key isEqualToString:kHGSObjectAttributeIconKey]
        || [key isEqualToString:kHGSObjectAttributeImmediateIconKey]) {
      HGSSearchSource *source = [self source];
      if ([source providesIconsForResults]) {
        value = [source provideValueForKey:key result:self];
      } else {
        HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
        BOOL skip = [key isEqualToString:kHGSObjectAttributeImmediateIconKey];
        value = [provider provideIconForResult:self
                               skipPlaceholder:skip];
      }
    }  
    if (!value) {
      // If we haven't provided a value, ask our source for a value.
      value = [[self source] provideValueForKey:key result:self];
    }
    if (!value) {
      // If neither self or source provides a value, ask our HGSDelegate.
      HGSPluginLoader *loader = [HGSPluginLoader sharedPluginLoader];
      id <HGSDelegate> delegate = [loader delegate];
      value = [delegate provideValueForKey:key result:self];
    }
  }
  if (!value) {
    value = [super valueForKey:key];
  }
  // Done for thread safety.
  return [[value retain] autorelease];
}

- (NSString*)stringValue {
  return [self displayName];
}

- (BOOL)isOfType:(NSString *)typeStr {
  // Exact match
  BOOL result = [type_ isEqualToString:typeStr];
  return result;
}

- (BOOL)localFile {
  return [uri_ hasPrefix:kHGSResultFileSchemePrefix];
}

- (NSString *)filePath {
  NSString *path = nil;
  if ([self localFile]) {
    path = [uri_ substringFromIndex:[kHGSResultFileSchemePrefix length]];
  }
  return path;
}

- (NSURL *)url {
  return [NSURL URLWithString:uri_];
}

static BOOL TypeConformsToType(NSString *type1, NSString *type2) {
  // Must have the exact prefix
  NSUInteger type2Len = [type2 length];
  BOOL result = type2Len > 0 && [type1 hasPrefix:type2];
  if (result &&
      ([type1 length] > type2Len)) {
    // If it's not an exact match, it has to have a '.' after the base type (we
    // don't count "foobar" as of type "foo", only "foo.bar" matches).
    unichar nextChar = [type1 characterAtIndex:type2Len];
    result = (nextChar == '.');
  }
  return result;
}

- (BOOL)conformsToType:(NSString *)typeStr {
  NSString *myType = [self type];
  return TypeConformsToType(myType, typeStr);
}

- (BOOL)conformsToTypeSet:(NSSet *)typeSet {
  NSString *myType = [self type];
  for (NSString *aType in typeSet) {
    if (TypeConformsToType(myType, aType)) {
      return YES;
    }
  }
  return NO;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@:%p> [%@ - %@ (%@ from %@)]", 
          [self class], self, [self displayName], [self type], [self class],
          source_];
}

// merge the attributes of |result| into this one. Single values that overlap
// are lost.
- (HGSResult *)mergeWith:(HGSResult*)result {
  Class cls = [self class];
  NSDictionary *attributes = [result attributes];
  HGSResult *newResult = [self copyOfClass:cls mergingAttributes:attributes];
  return [newResult autorelease];
}

// this is result a "duplicate" of |compareTo|? The default implementation 
// checks |kHGSObjectAttributeURIKey| for equality, but subclasses may want
// something more sophisticated. Not using |-isEqual:| because that
// impacts how the object gets put into collections.
- (BOOL)isDuplicate:(HGSResult*)compareTo {
  // TODO: does [self class] come into play here?  can two different types ever
  // be equal at a base impl layer.
  BOOL intersects = NO;
  
  if (self->conformsToContact_ 
      && compareTo->conformsToContact_) {
    
    // Running through the identifers ourself is faster than creating two
    // NSSets and calling intersectsSet on them.
    NSArray *identifiers 
      = [self valueForKey:kHGSObjectAttributeUniqueIdentifiersKey];
    NSArray *identifiers2 
      = [compareTo valueForKey:kHGSObjectAttributeUniqueIdentifiersKey];
    
    for (id a in identifiers) {
      for (id b in identifiers2) {
        if ([a isEqual:b]) {
          intersects = YES;
          break;
        }
      }
      if (intersects) {
        break;
      }
    }
  } else {
    if (self->idHash_ == compareTo->idHash_) {
      intersects = [self->uri_ isEqualTo:compareTo->uri_];
    }
  }
  if (!intersects) {
    // URL get special checks to enable matches to reduce duplicates, we remove
    // some things that tend to be "optional" to get a "normalized" url, and
    // compare those.
    
    NSString *myNormURLString = self->normalizedIdentifier_;
    NSString *compareNormURLString = compareTo->normalizedIdentifier_;
    
    // if we got strings, compare
    if (myNormURLString && compareNormURLString) {
      intersects = [myNormURLString isEqualToString:compareNormURLString];
    }
  }
  return intersects;
}

- (void)promote {
  [[self source] promoteResult:self];
}

+ (NSString *)hgsTypeForPath:(NSString*)path {
  // TODO(dmaclach): probably need some way for third parties to muscle their
  // way in here and improve this map for their types.
  // TODO(dmaclach): combine this code with the SLFilesSource code so we
  // are only doing this in one place.
  FSRef ref;
  Boolean isDir = FALSE;
  OSStatus err = FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation],
                               &ref, 
                               &isDir);
  if (err != noErr) return nil;
  CFStringRef cfUTType = NULL;
  err = LSCopyItemAttribute(&ref, kLSRolesAll, 
                            kLSItemContentType, (CFTypeRef*)&cfUTType);
  if (err != noErr || !cfUTType) return nil;
  NSString *outType = nil;
  // Order of the map below is important as it's most specific first.
  // We don't want things matching to directories when they are packaged docs.
  struct {
    CFStringRef uttype;
    NSString *hgstype;
  } typeMap[] = {
    { kUTTypeContact, kHGSTypeContact },
    { kUTTypeMessage, kHGSTypeEmail },
    { kUTTypeHTML, kHGSTypeWebpage },
    { kUTTypeApplication, kHGSTypeFileApplication },
    { kUTTypeAudio, kHGSTypeFileMusic },
    { kUTTypeImage, kHGSTypeFileImage },
    { kUTTypeMovie, kHGSTypeFileMovie },
    { kUTTypePlainText, kHGSTypeTextFile },
    { kUTTypePackage, kHGSTypeFile },
    { kUTTypeDirectory, kHGSTypeDirectory },
    { kUTTypeItem, kHGSTypeFile }
  };
  for (size_t i = 0; i < sizeof(typeMap) / sizeof(typeMap[0]); ++i) {
    if (UTTypeConformsTo(cfUTType, typeMap[i].uttype)) {
      outType = typeMap[i].hgstype;
      break;
    }
  }
  CFRelease(cfUTType);
  return outType;
}

@end

@implementation HGSMutableResult

- (void)addRankFlags:(HGSRankFlags)flags {
  rankFlags_ |= flags;
}

- (void)removeRankFlags:(HGSRankFlags)flags {
  rankFlags_ &= ~flags;
}

- (void)setRank:(CGFloat)rank {
  rank_ = rank;
}

@end

@implementation HGSResultArray

+ (id)arrayWithResult:(HGSResult *)result {
  id resultsArray = nil;
  if (result) {
    NSArray *array = [NSArray arrayWithObject:result];
    resultsArray = [self arrayWithResults:array];
  }
  return resultsArray;
}

+ (id)arrayWithResults:(NSArray *)results {
  return [[[self alloc] initWithResults:results] autorelease];
}

+ (id)arrayWithFilePaths:(NSArray *)filePaths {
  return [[[self alloc] initWithFilePaths:filePaths] autorelease];
}

- (id)initWithResults:(NSArray *)results {
  if ((self = [super init])) {
    results_ = [results copy];
  }
  return self;
}

- (id)initWithFilePaths:(NSArray *)filePaths {
  NSMutableArray *results 
    = [NSMutableArray arrayWithCapacity:[filePaths count]];
  for (NSString *path in filePaths) {
    HGSResult *result = [HGSResult resultWithFilePath:path
                                               source:nil 
                                           attributes:nil];
    HGSAssert(result, @"Unable to create result from %@", path);
    if (result) {
      [results addObject:result];
    }
  }
  return [self initWithResults:results];
}


- (void)dealloc {
  [results_ release];
  [super dealloc];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state 
                                  objects:(id *)stackbuf 
                                    count:(NSUInteger)len {
  return [results_ countByEnumeratingWithState:state 
                                       objects:stackbuf 
                                         count:len];
}

- (NSString*)displayName {
  NSString *displayName = nil;
  if ([results_ count] == 1) {
    HGSResult *result = [results_ objectAtIndex:0];
    displayName = [result displayName];
  } else {
    // TODO(alcor): make this nicer
    displayName = HGSLocalizedString(@"Multiple Items",
                                     @"A label denoting that this result "
                                     @"represents multiple items");
  }
  return displayName;
}

- (BOOL)isOfType:(NSString *)typeStr {
  BOOL isOfType = YES;
  for (HGSResult *result in self) {
    isOfType = [result isOfType:typeStr];
    if (!isOfType) break;
  }
  return isOfType;
}

- (BOOL)conformsToType:(NSString *)typeStr {
  BOOL isOfType = YES;
  for (HGSResult *result in self) {
    isOfType = [result conformsToType:typeStr];
    if (!isOfType) break;
  }
  return isOfType;
}

- (BOOL)conformsToTypeSet:(NSSet *)typeSet {
  BOOL isOfType = YES;
  for (HGSResult *result in self) {
    isOfType = [result conformsToTypeSet:typeSet];
    if (!isOfType) break;
  }
  return isOfType;
}

- (void)promote {
  [results_ makeObjectsPerformSelector:@selector(promote)];
}

- (NSArray *)urls {
  return [results_ valueForKey:@"url"];
}

- (NSArray *)filePaths {
  NSMutableArray *paths = [NSMutableArray arrayWithCapacity:[results_ count]];
  for (HGSResult *result in self) {
    NSURL *url = [result url];
    if ([url isFileURL]) {
      [paths addObject:[url path]];
    } else {
      paths = nil;
      break;
    }
  }
  return paths;
}

- (NSUInteger)count {
  return [results_ count];
}

- (HGSResult *)objectAtIndex:(NSUInteger)ind {
  return [results_ objectAtIndex:ind];
}

- (HGSResult *)lastObject {
  return [results_ lastObject];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@ results:\r%@", [self class], results_];
}

- (NSImage*)icon {
  NSImage *displayImage = nil;
  if ([results_ count] == 1) {
    HGSResult *result = [results_ objectAtIndex:0];
    displayImage = [result valueForKey:kHGSObjectAttributeIconKey];
  } else {
    HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
    displayImage = [provider compoundPlaceHolderIcon];
  }
  return displayImage;
}

@end
