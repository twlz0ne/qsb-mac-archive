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
#import "HGSModuleLoader.h"
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
NSString* const kHGSObjectAttributeIsSyntheticKey = @"kHGSObjectAttributeIsSynthetic";
NSString* const kHGSObjectAttributeIsCorrectionKey = @"kHGSObjectAttributeIsCorrection";
NSString* const kHGSObjectAttributeIsContainerKey = @"kHGSObjectAttributeIsContainer";
NSString* const kHGSObjectAttributeRankKey = @"kHGSObjectAttributeRank";  
NSString* const kHGSObjectAttributeDefaultActionKey = @"kHGSObjectAttributeDefaultActionKey";
// Path cell-related keys
NSString* const kHGSObjectAttributePathCellClickHandlerKey = @"kHGSObjectAttributePathCellClickHandler";
NSString* const kHGSObjectAttributePathCellsKey = @"kHGSObjectAttributePathCells";
NSString* const kHGSPathCellDisplayTitleKey = @"kHGSPathCellDisplayTitle";
NSString* const kHGSPathCellImageKey = @"kHGSPathCellImage";
NSString* const kHGSPathCellURLKey = @"kHGSPathCellURL";
NSString* const kHGSPathCellHiddenKey = @"kHGSPathCellHidden";

NSString* const kHGSObjectAttributeVisitedCountKey = @"kHGSObjectAttributeVisitedCount";

NSString* const kHGSObjectAttributeWebSearchDisplayStringKey = @"kHGSObjectAttributeWebSearchDisplayString";
NSString* const kHGSObjectAttributeWebSearchTemplateKey = @"kHGSObjectAttributeWebSearchTemplate";
NSString* const kHGSObjectAttributeAllowSiteSearchKey = @"kHGSObjectAttributeAllowSiteSearch";
NSString* const kHGSObjectAttributeWebSuggestTemplateKey = @"kHGSObjectAttributeWebSuggestTemplate";
NSString* const kHGSObjectAttributeStringValueKey = @"kHGSObjectAttributeStringValue";

NSString* const kHGSObjectAttributeRankFlagsKey = @"kHGSObjectAttributeRankFlags";

// Contact related keys
NSString* const kHGSObjectAttributeContactEmailKey = @"kHGSObjectAttributeContactEmail";  
NSString* const kHGSObjectAttributeEmailAddressesKey = @"kHGSObjectAttributeEmailAddressesKey";
NSString* const kHGSObjectAttributeContactsKey = @"kHGSObjectAttributeContactsKey";
NSString* const kHGSObjectAttributeAlternateActionURIKey = @"kHGSObjectAttributeAlternateActionURI";
NSString* const kHGSObjectAttributeAddressBookRecordIdentifierKey = @"kHGSObjectAttributeAddressBookRecordIdentifier";

// Chat Buddy-related keys
NSString* const kHGSObjectAttributeBuddyMatchingStringKey = @"kHGSObjectAttributeBuddyMatchingStringKey";
NSString* const kHGSIMBuddyInformationKey = @"kHGSIMBuddyInformationKey";

@interface HGSResult ()
+ (NSString *)hgsTypeForPath:(NSString*)path;
- (NSDictionary *)values;
- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result;
- (NSArray *)pathCellArrayForResult:(HGSResult *)result;
- (NSArray *)pathCellArrayForFileURL:(NSURL *)url;
- (NSArray *)pathCellArrayForNonFileURL:(NSURL *)url;
@end

@implementation HGSResult

GTM_METHOD_CHECK(NSString, readableURLString);

+ (void)initialize {
  [self setKeys:[NSArray arrayWithObject:kHGSObjectAttributeIconKey]  
triggerChangeNotificationsForDependentKey:kHGSObjectAttributeImmediateIconKey];
}

+ (BOOL)automaticallyNotifiesObserversForKey:(NSString *)key {
  return YES;  
}

+ (id)resultWithURL:(NSURL*)url
               name:(NSString *)name
               type:(NSString *)typeStr
             source:(id<HGSSearchSource>)source 
         attributes:(NSDictionary *)attributes {
  return [[[self alloc] initWithURL:url
                               name:name
                               type:typeStr
                             source:source
                         attributes:attributes] autorelease]; 
}

+ (id)resultWithFilePath:(NSString *)path 
                  source:(id<HGSSearchSource>)source 
              attributes:(NSDictionary *)attributes {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *url = [NSURL fileURLWithPath:path];
  NSString *type = [self hgsTypeForPath:path];
  if (!type) {
    type = kHGSTypeFile;
  }
  
  return [self resultWithURL:url
                        name:[fm displayNameAtPath:path]
                        type:type
                      source:source
                  attributes:attributes];
}

+ (id)resultWithDictionary:(NSDictionary *)dictionary 
                    source:(id<HGSSearchSource>)source {
  return [[[self alloc] initWithDictionary:dictionary 
                                    source:source] autorelease];
}

- (id)initWithURL:(NSURL *)url
             name:(NSString *)name
             type:(NSString *)typeStr
           source:(id<HGSSearchSource>)source 
       attributes:(NSDictionary *)attributes {
  if ((self = [super init])) {
    if (!url || !name || !typeStr) {
      HGSLogDebug(@"Must have an url, name and typestr for %@ of %@ (%@)", 
                  name, source, url);
      [self release];
      return nil;
    }
    values_ = [[NSMutableDictionary alloc] initWithCapacity:4 ];
    
    url_ = [url retain];
    idHash_ = [url_ hash];
    name_ = [name retain];
    type_ = [typeStr retain];
    source_ = [source retain];
    conformsToContact_ = [self conformsToType:kHGSTypeContact];
    if ([self conformsToType:kHGSTypeWebpage]) {
      normalizedIdentifier_ = [[[url_ absoluteString] readableURLString] retain];
    }
    if (attributes) {
      [values_ addEntriesFromDictionary:attributes];
    }
    NSNumber *rank = [values_ objectForKey:kHGSObjectAttributeRankKey];
    if (rank) {
      rank_ = [rank floatValue];
      [values_ removeObjectForKey:kHGSObjectAttributeRankKey];
    }
    NSNumber *rankFlags = [values_ objectForKey:kHGSObjectAttributeRankFlagsKey];
    if (rankFlags) {
      rankFlags_ = [rankFlags unsignedIntValue];
      [values_ removeObjectForKey:kHGSObjectAttributeRankFlagsKey];
    }
    lastUsedDate_ = [values_ objectForKey:kHGSObjectAttributeLastUsedDateKey];
    if (lastUsedDate_) {
      [values_ removeObjectForKey:kHGSObjectAttributeLastUsedDateKey];
    } else {
      lastUsedDate_ = [NSDate distantPast];
    }
    [lastUsedDate_ retain];
  }
  return self;
}
  
- (id)initWithDictionary:(NSDictionary*)dict 
                  source:(id<HGSSearchSource>)source {
  NSMutableDictionary *attributes 
    = [NSMutableDictionary dictionaryWithDictionary:dict];
  NSURL *url = [attributes objectForKey:kHGSObjectAttributeURIKey];
  if ([url isKindOfClass:[NSString class]]) {
    url = [NSURL URLWithString:(NSString*)url];
  }
  

  if ([url isFileURL]) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:[url path]]) {
      [self release];
      return nil;
    }  
  }
  
  NSString *name = [attributes objectForKey:kHGSObjectAttributeNameKey];
  NSString *type = [attributes objectForKey:kHGSObjectAttributeTypeKey];
  [attributes removeObjectsForKeys:[NSArray arrayWithObjects:
                                    kHGSObjectAttributeURIKey, 
                                    kHGSObjectAttributeNameKey, 
                                    kHGSObjectAttributeTypeKey,
                                    nil]];
  return [self initWithURL:url
                      name:name 
                      type:type 
                    source:source
                attributes:attributes];
}

- (void)dealloc {
  [[HGSIconProvider sharedIconProvider] cancelOperationsForResult:self];
  [source_ release];
  [values_ release];
  [url_ release];
  [normalizedIdentifier_ release];
  [name_ release];
  [type_ release];
  [lastUsedDate_ release];
  [super dealloc];
}

- (id)copyOfClass:(Class)cls {
  // Split the alloc and the init up to minimize time spent in
  // synchronized block.
  HGSResult *newResult = [cls alloc];
  @synchronized(values_) {
    newResult = [newResult initWithURL:[self url]
                                  name:[self displayName]
                                  type:[self type]
                                source:source_
                            attributes:values_];
  }
  // now pull over the fields
  newResult->rank_ = rank_;
  newResult->rankFlags_ = rankFlags_;
  return newResult;
}

- (id)copyWithZone:(NSZone *)zone {
  return [self copyOfClass:[HGSResult class]];
}

- (id)mutableCopyWithZone:(NSZone *)zone {
  return [self copyOfClass:[HGSMutableResult class]];
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

- (void)setValue:(id)obj forKey:(NSString*)key {
  if (key) { // This allows nil to remove value
    @synchronized(values_) {
      id oldValue = [values_ objectForKey:key];
      // TODO(dmaclach): handle this better, hopefully by getting rid of
      // setValue:forKey:
      HGSAssert(![key isEqualToString:kHGSObjectAttributeRankFlagsKey], nil);
      HGSAssert(![key isEqualToString:kHGSObjectAttributeURIKey], nil);
      HGSAssert(![key isEqualToString:kHGSObjectAttributeRankKey], nil);
      HGSAssert(![key isEqualToString:kHGSObjectAttributeNameKey], nil);
      HGSAssert(![key isEqualToString:kHGSObjectAttributeTypeKey], nil);
      if (oldValue != obj && ![oldValue isEqual:obj]) {
        [self willChangeValueForKey:key];
        if (!obj) {
          [values_ removeObjectForKey:key];
        } else {
          [values_ setObject:obj forKey:key];
        }
        [self didChangeValueForKey:key];
      }
    }
  }
}

- (id)valueForUndefinedKey:(NSString *)key {
  return nil;
}

// if the value isn't present, ask the result source to satisfy the
// request. Also registers for notifications so that we can update the
// value cache. 
- (id)valueForKey:(NSString*)key {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeURIKey]) {
    value = [self url];
  } else if ([key isEqualToString:kHGSObjectAttributeNameKey]) {
    value = [self displayName];
  } else if ([key isEqualToString:kHGSObjectAttributeTypeKey]) {
    value = [self type];
  }
  if (!value) {
    @synchronized (values_) {
      value = [values_ objectForKey:key];
      if (!value) {
        if ([key isEqualToString:kHGSObjectAttributeImmediateIconKey]) {
          value = [values_ objectForKey:kHGSObjectAttributeIconKey];
        }
      }
      if (!value) {
        // request from the source. This may kick off a pending load. 
        value = [[self source] provideValueForKey:key result:self];
        if (!value) {
          value = [self provideValueForKey:key result:self];
        }
        if (value) {
          [self setValue:value forKey:key];
        }
      }
      if (!value) {
        value = [super valueForKey:key];
      }
    }
  }
  // Done for thread safety.
  return [[value retain] autorelease];
}

- (NSURL *)url {
  return [[url_ retain] autorelease];
}

- (NSString*)stringValue {
  return [self displayName];
}

- (NSString*)displayName {
  return [[name_ retain] autorelease];
}

- (NSImage *)displayIconWithLazyLoad:(BOOL)lazyLoad {
  NSString *key = lazyLoad ? kHGSObjectAttributeIconKey 
  : kHGSObjectAttributeImmediateIconKey;
  return [self valueForKey:key];
}

- (NSArray *)displayPath {
  // The path presentation shown in the search results window can be
  // built from one of the following (in order of preference):
  //   1. an array of cell descriptions
  //   2. a file path URL (from our |identifier|).
  //   3. a slash-delimeted string of cell titles
  // Only the first option guarantees that a cell is clickable, the
  // second option may but is not likely to support clicking, and the
  // third definitely not.  GDGeneralDataProvider will return a decent
  // cell array for regular URLs and file URLs and a mediocre one for
  // public.message results but you can compose and provide your own
  // in 1) your source's provideValueForKey: method or 2) an override
  // of displayPath in your custom HGSObect result class.
  return [self valueForKey:kHGSObjectAttributePathCellsKey];
}

- (NSString*)type {
  return type_;
}

- (BOOL)isOfType:(NSString *)typeStr {
  // Exact match
  BOOL result = [type_ isEqualToString:typeStr];
  return result;
}

static BOOL TypeConformsToType(NSString *type1, NSString *type2) {
  // Must have the exact prefix
  BOOL result = [type1 hasPrefix:type2];
  NSUInteger typeLen;
  if (result &&
      ([type1 length] > (typeLen = [type2 length]))) {
    // If it's not an exact match, it has to have a '.' after the base type (we
    // don't count "foobar" as of type "foo", only "foo.bar" matches).
    unichar nextChar = [type1 characterAtIndex:typeLen];
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

- (id<HGSSearchSource>)source {  
  return source_;
}

- (CGFloat)rank {
  return rank_;
}

- (HGSRankFlags)rankFlags {
  return rankFlags_;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"[%@ - %@ (%@ from %@)]", 
          [self displayName], [self type], [self class], source_];
}

// merge the attributes of |result| into this one. Single values that overlap
// are lost, arrays and dictionaries are merged together to form the union.
// TODO(dmaclach): currently this description is a lie. Arrays and dictionaries
// aren't merged.
- (void)mergeWith:(HGSResult*)result {
  BOOL dumpQueryProgress = [[NSUserDefaults standardUserDefaults]
                            boolForKey:@"reportQueryOperationsProgress"];
  if (dumpQueryProgress) {
    HGSLogDebug(@"merging %@ into %@", [result description], [self description]);
  }
  NSDictionary *resultValues = [result values];
  @synchronized(values_) {
    for (NSString *key in [resultValues allKeys]) {
      if ([values_ objectForKey:key]) continue;
      [values_ setValue:[result valueForKey:key] forKey:key];
    }
  }
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
    
    NSArray *identifiers = [self valueForKey:kHGSObjectAttributeUniqueIdentifiersKey];
    NSArray *identifiers2 = [compareTo valueForKey:kHGSObjectAttributeUniqueIdentifiersKey];
    
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
      intersects = [self->url_ isEqualTo:compareTo->url_];
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

- (NSDate *)lastUsedDate {
  return lastUsedDate_;
}

- (NSDictionary *)values {
  NSDictionary *dict;
  @synchronized (values_) {
    // We make a copy and autorelease to keep safe across threads.
    dict = [values_ copy];
  }
  return [dict autorelease];
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
  err = LSCopyItemAttribute(&ref, kLSRolesAll, kLSItemContentType, (CFTypeRef*)&cfUTType);
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

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeIconKey]
      || [key isEqualToString:kHGSObjectAttributeImmediateIconKey]) {  
    HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
    BOOL lazily = ![key isEqualToString:kHGSObjectAttributeImmediateIconKey];
    value = [provider provideIconForResult:result
                                loadLazily:lazily
                                  useCache:YES];
  } else if ([key isEqualToString:kHGSObjectAttributePathCellsKey]) {
    value = [self pathCellArrayForResult:result];
  } else if ([key isEqualToString:kHGSObjectAttributeDefaultActionKey]) {
    HGSExtensionPoint *actionPoint = [HGSExtensionPoint actionsPoint];
    HGSModuleLoader *sharedLoader = [HGSModuleLoader sharedModuleLoader];
    id<HGSDelegate> delegate = [sharedLoader delegate];
    NSString *actionID = [delegate defaultActionID];
    value = [actionPoint extensionWithIdentifier:actionID];
  } 
  return value;
}

- (NSArray *)pathCellArrayForResult:(HGSResult *)result {
  NSArray *cellArray = nil;
  NSURL *url = [result url];
  if ([url isFileURL]) {
    cellArray = [self pathCellArrayForFileURL:url];
  } else {
    cellArray = [self pathCellArrayForNonFileURL:url];
  }
  return cellArray;
}

- (NSArray *)pathCellArrayForFileURL:(NSURL *)url {
  NSMutableArray *cellArray = nil;
  
  // Provide a cellArray for the path control assuming that we are
  // a file and our identifier is a file URL.
  if (url) {
    // Generate a list of display components and then walk backwards
    // through it generating URLs for each component.
    NSString *targetPath = [url path];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *displayComponents = [fm componentsToDisplayForPath:targetPath];
    if (displayComponents) {
      cellArray = [NSMutableArray arrayWithCapacity:[displayComponents count]];
      NSEnumerator *reverseEnum = [displayComponents reverseObjectEnumerator];
      NSString *component;
      NSString *subPath = targetPath;
      while ((component = [reverseEnum nextObject])) {
        NSURL *subUrl = [NSURL fileURLWithPath:subPath];
        NSDictionary *cellDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  component, kHGSPathCellDisplayTitleKey,
                                  subUrl, kHGSPathCellURLKey,
                                  nil];
        [cellArray insertObject:cellDict atIndex:0];
        subPath = [subPath stringByDeletingLastPathComponent];
      }
      // Determine if we can abbreviate the path presentation.
      
      // First, see if this is in the user's home directory structure
      // and, if so, abbreviated it with 'Home'.  If not, then check
      // to see if we're on the root volume and if so, don't show
      // the volume name.
      NSString *homeDirectory = NSHomeDirectory();
      NSString *homeDisplay = [fm displayNameAtPath:homeDirectory];
      NSUInteger compCount = 0;
      NSDictionary *componentToAdd = nil;
      NSDictionary *firstCell = [cellArray objectAtIndex:0];
      NSString *firstCellTitle = [firstCell objectForKey:kHGSPathCellDisplayTitleKey];
      if ([firstCellTitle isEqualToString:homeDisplay]) {
        compCount = 1;
        componentToAdd = [NSDictionary dictionaryWithObjectsAndKeys:
                          HGSLocalizedString(@"Home", nil), kHGSPathCellDisplayTitleKey,
                          [NSURL fileURLWithPath:homeDirectory], kHGSPathCellURLKey,
                          nil];
      } else {
        NSString *rootDisplay = [fm displayNameAtPath:@"/"];
        if ([firstCellTitle isEqualToString:rootDisplay]) {
          compCount = 1;
        }
      }
      if (compCount) {
        [cellArray removeObjectsInRange:NSMakeRange(0, compCount)];
      }
      if (componentToAdd) {
        [cellArray insertObject:componentToAdd atIndex:0];
      }
    } else {
      HGSLogDebug(@"Unable to get path components for path '%@'.", targetPath);
    }
  }
  
  return cellArray;
}

- (NSArray *)pathCellArrayForNonFileURL:(NSURL *)url {
  NSMutableArray *cellArray = nil;
  
  // See if we have a regular URL.
  NSString *absolutePath = [url absoluteString];
  if (absolutePath) {
    // Build up two path cells, one with the domain, and the second
    // with the location within the domain.  Do this by finding the
    // first and second occurrence of the slash separator.
    NSString *hostString = [url host];
    if ([hostString length]) {
      cellArray = [NSMutableArray arrayWithCapacity:2];
      NSURL *pathURL = [NSURL URLWithString:absolutePath];
      NSString *pathString = [url path];
      
      if ([pathString length] == 0 || [pathString isEqualToString:@"/"]) {
        // We just have a host cell.
        NSDictionary *hostCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                  hostString, kHGSPathCellDisplayTitleKey,
                                  pathURL, kHGSPathCellURLKey,
                                  nil];
        [cellArray addObject: hostCell];
      } else {          
        // NOTE: Attempts to use -[NSURL initWithScheme:host:path:] were unsuccessful
        //       using (nil|@""|@"/") for the path.  Each fails to produce an
        //       acceptable URL or throws an exception.
        // NSURL *hostURL = [[[NSURL alloc] initWithScheme:[url scheme]
        //                                            host:hostString
        //                                            path:???] autorelease];
        NSURL *hostURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/",
                                               [url scheme], hostString]];
        NSDictionary *hostCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                  hostString, kHGSPathCellDisplayTitleKey,
                                  hostURL, kHGSPathCellURLKey,
                                  nil];
        [cellArray addObject: hostCell];
        NSDictionary *pathCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                  pathString, kHGSPathCellDisplayTitleKey,
                                  pathURL, kHGSPathCellURLKey,
                                  nil];
        [cellArray addObject: pathCell];
      }
    }
  }
  return cellArray;
}

@end

@implementation HGSMutableResult

- (void)setRankFlags:(HGSRankFlags)flags {
  rankFlags_ = flags;
}

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

- (NSArray *)results {
  return [[results_ retain] autorelease];
}

- (NSString*)displayName {
  NSString *displayName = nil;
  if ([results_ count] == 1) {
    HGSResult *result = [results_ objectAtIndex:0];
    displayName = [result displayName];
  } else {
    // TODO(alcor): make this nicer
    displayName = @"Multiple Items";
  }
  return displayName;
}

- (NSImage*)displayIconWithLazyLoad:(BOOL)lazyLoad {
  NSImage *displayImage = nil;
  if ([results_ count] == 1) {
    HGSResult *result = [results_ objectAtIndex:0];
    displayImage = [result displayIconWithLazyLoad:lazyLoad];
  } else {
    HGSIconProvider *provider = [HGSIconProvider sharedIconProvider];
    displayImage = [provider compoundPlaceHolderIcon];
  }
  return displayImage;
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
@end
