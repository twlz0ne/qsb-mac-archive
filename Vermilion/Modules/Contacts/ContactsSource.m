//
//  HGSContactsSource.m
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

#import <Vermilion/Vermilion.h>
#import <AddressBook/AddressBook.h>
#import <AddressBook/ABAddressBookC.h>
#if !TARGET_OS_IPHONE
#import "GTMGarbageCollection.h"
#endif

#import "GTMGeometryUtils.h"
#import "GTMNSImage+Scaling.h"
#import "GTMNSBezierPath+CGPath.h"

static NSString *const kMetaDataFilePath
  = @"~/Library/Application Support/AddressBook/Metadata/%@.abcdp";
static NSString *const kHGSGenericContactIconName = @"HGSGenericContactImage";

#define kTypeContactAddressBook HGS_SUBTYPE(kHGSTypeContact, @"addressbook")

@interface HGSContactsSource : HGSMemorySearchSource <ABImageClient> {
 @private
  NSCondition *condition_;
  BOOL indexing_;
  NSMutableDictionary *imageLoadingTags_;
  NSArray *results_;
  NSImage *genericImage_;
}
- (void)loadAddressBookContactsOperation;
- (void)addressBookChanged:(NSNotification *)notification;

// Return an ABPerson for a given result
- (ABRecord *)personForResult:(HGSResult *)result;

// Take a phone number [(123)456-7890] and clean it to 1234567890
- (NSString *)cleanPhoneNumber:(NSString *)dirtyPhone;

// Clean up a URL. Currently just prepends http:// if it is missing
- (NSString *)cleanURL:(NSString *)dirtyURL;

// Given an ABPerson and a property name, creates an array of HGSObjects
// to match. You can specify the type of the HGSObjects, how to create the
// URL, and an appropriate cleaner method [(NSString *)cleaner:(NSString *)]
// to help create the URL.
- (NSArray *)objectsForMultiValueProperty:(NSString *)property 
                               fromPerson:(ABPerson *)person 
                                     type:(NSString *)type 
                                urlFormat:(NSString *)urlFormat 
                              cleanMethod:(SEL)cleaner;

// Given an HGSResult we "explode" it into it's internal HGSObjects
// i.e. phone numbers, addressess, email, etc.
- (NSArray *)explodeContactForSearchOperation:(HGSResult *)contact;
@end

@implementation HGSContactsSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    indexing_ = YES; // Hold queries until the first indexing run completes
    condition_ = [[NSCondition alloc] init];
    imageLoadingTags_ = [[NSMutableDictionary alloc] init];
    NSOperation *op = [[[NSInvocationOperation alloc]
                        initWithTarget:self
                              selector:@selector(loadAddressBookContactsOperation)
                                object:nil]
                       autorelease];
    [[HGSOperationQueue sharedOperationQueue] addOperation:op];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self 
           selector:@selector(addressBookChanged:) 
               name:kABDatabaseChangedExternallyNotification 
             object:nil];
  }
  return self;
}

- (NSImage *)genericContactImage {
  if (!genericImage_) {
    @synchronized(self) {
      genericImage_ = [NSImage imageNamed:@"blue-contact"];
      genericImage_
        = [HGSIconProvider imageWithRoundRectAndDropShadow:genericImage_];
      [genericImage_ retain];
    }
  }
  return genericImage_; 
}

- (void)loadAddressBookContactsOperation {
  [condition_ lock];
  indexing_ = YES;
  
  // clear the existing info
  [self clearResultIndex];
  NSMutableArray *newResults = [NSMutableArray array];
  
  ABAddressBook *sab = [ABAddressBook sharedAddressBook];
  for (ABPerson *person in [sab people]) {
    NSString *name = nil;
    NSString *firstName = [person valueForProperty:kABFirstNameProperty];
    NSString *lastName = [person valueForProperty:kABLastNameProperty];
    if (firstName && lastName) {
      if ([sab defaultNameOrdering] == kABFirstNameFirst) {
        name = [NSString stringWithFormat:@"%@ %@", firstName, lastName];
      } else {
        name = [NSString stringWithFormat:@"%@ %@", lastName, firstName];
      }
    } else if (lastName) {
      name = lastName;
    } else if (firstName) {
      name = firstName;
    } else {
      name = [person valueForProperty:kABOrganizationProperty];
    }
    if (name) {
      NSString *urlString = [NSString stringWithFormat:kMetaDataFilePath, [person uniqueId]];
      urlString = [urlString stringByExpandingTildeInPath];
      NSString *multiValueKeys[] = {
        kABEmailProperty,
        kABAIMInstantProperty,
        kABJabberInstantProperty,
        kABMSNInstantProperty,
        kABYahooInstantProperty,
        kABICQInstantProperty
      };
    
      NSMutableArray *otherTermStrings = [NSMutableArray array];
      for (unsigned i = 0; i < sizeof(multiValueKeys) / sizeof(NSString *); i++) {
        ABMultiValue *multiValues = [person valueForProperty:multiValueKeys[i]];
        NSInteger valueCount = [multiValues count];
        for (NSInteger idx = 0; idx < valueCount; idx++) {
          NSString *value = [multiValues valueAtIndex:idx];
          if (value) {
            [otherTermStrings addObject:value];
          }
        }
      }
      
      NSString *nickname = [person valueForProperty:kABNicknameProperty];
      if (nickname) {
        [otherTermStrings addObject:nickname];
      }
      
      NSString *companyName = [person valueForProperty:kABOrganizationProperty];
      if (companyName && ![companyName isEqualToString:name]) {
        [otherTermStrings addObject:companyName];
      }
      
      //TODO(dmaclach): remove this once real ranking is in
      NSNumber *rank = [NSNumber numberWithFloat:0.9f];
      NSDictionary *attributes
        = [NSDictionary dictionaryWithObjectsAndKeys:
           otherTermStrings, kHGSObjectAttributeUniqueIdentifiersKey,
           rank, kHGSObjectAttributeRankKey,
           nil];
      HGSResult* hgsResult 
        = [HGSResult resultWithURL:[NSURL fileURLWithPath:urlString]
                              name:name
                              type:kTypeContactAddressBook
                            source:self
                        attributes:attributes];
      [newResults addObject:hgsResult];
      [self indexResult:hgsResult
             nameString:name
      otherStringsArray:otherTermStrings];
    }
  }
  
  @synchronized(self) {
    [results_ release];
    results_ = [newResults retain];
  }
  
  indexing_ = NO;
  [condition_ signal];
  [condition_ unlock];
}

- (void)addressBookChanged:(NSNotification *)notification {
  NSOperation *op 
    = [[[NSInvocationOperation alloc] initWithTarget:self
                                            selector:@selector(loadAddressBookContactsOperation)
                                              object:nil] autorelease];
  [[HGSOperationQueue sharedOperationQueue] addOperation:op];
}

- (void)dealloc {
  [genericImage_ release];
  genericImage_ = nil;
  [condition_ release];
  [imageLoadingTags_ release];
  [results_ release];
  [super dealloc];
}

#pragma mark -

- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query {
  // if we had a pivot object, we filter the results w/ the pivot info
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject && ![pivotObject isOfType:kTypeContactAddressBook]) {
    // To suvive the pivot, the contact has to have our a matching email
    // address.

    NSArray *emailAddresses
      = [pivotObject valueForKey:kHGSObjectAttributeEmailAddressesKey];
    
    NSMutableIndexSet *indexesToRemove = [NSMutableIndexSet indexSet];
    
    NSUInteger resultCount = [results count];
    for (NSUInteger idx = 0; idx < resultCount ; ++idx) {

      HGSResult *hgsResult = [results objectAtIndex:idx];
      ABRecord *person = [self personForResult:hgsResult];
      if (!person) continue;
      BOOL isMatch = NO;
      
      // check for email match
      ABMultiValue *multiValues = [person valueForProperty:kABEmailProperty];
      NSUInteger valueCount = [multiValues count];
      for (NSUInteger idx2 = 0; idx2 < valueCount; idx2++) {
        NSString *value = [multiValues valueAtIndex:idx2];
        if ([value length]) {
          if ([emailAddresses containsObject:value]) {
            isMatch = YES;
            break;
          }
        }
      }
      if (isMatch) continue;
      
      // NOTE: it would be really nice to kHGSObjectAttributeContactsKey off the
      // pivot to turn authors into contacts, etc.  But, the format of that key
      // is a "name" so it could be "john doe", "doe, john", "john k. doe",
      // "doe, john k.".  So trying to build up the logic to do that match is
      // really ugly.  It might be doable if we can turn the list of names into
      // some sort for query w/ optional terms, or each set of terms together
      // incase there is >1 name in the list, etc.  But that's no trivial, and
      // the lower layers don't do that either, so...no support for now!  :)
      
      // not found, mark for remove
      [indexesToRemove addIndex:idx];
    }

    // remove the indexes that weren't matches
    [results removeObjectsAtIndexes:indexesToRemove];
    
  }
}

- (NSArray *)objectsForMultiValueProperty:(NSString *)property 
                               fromPerson:(ABPerson *)person 
                                     type:(NSString *)type 
                                urlFormat:(NSString *)urlFormat 
                              cleanMethod:(SEL)cleaner {
  NSMutableArray *results = [NSMutableArray array];
  NSString *localizedProperty
    = GTMCFAutorelease(ABCopyLocalizedPropertyOrLabel((CFStringRef)property));
  if (!localizedProperty) {
    localizedProperty = property;
  }
  ABMultiValue *multiValue = [person valueForProperty:property];
  if (multiValue) {
    NSString *primary = [multiValue primaryIdentifier];
    NSUInteger count = [multiValue count];
    // Iterate through the multivalue getting all the subvalues
    for (NSUInteger i = 0; i < count; ++i) {
      id value = [multiValue valueAtIndex:i];
      NSString *label = [multiValue labelAtIndex:i];
      NSString *identifier = [multiValue identifierAtIndex:i];
      if (label) {
        CFStringRef cfLabel = (CFStringRef)label;
        NSString *localizedLabel 
          = GTMCFAutorelease(ABCopyLocalizedPropertyOrLabel(cfLabel));
        if (!localizedLabel) {
          localizedLabel = label;
        }
        NSString *cleanValue;
        if (cleaner) {
          cleanValue = [self performSelector:cleaner withObject:value];
        } else {
          cleanValue = value;
        }
        NSString *urlString = [NSString stringWithFormat:urlFormat, cleanValue];
        
        NSURL *url = [NSURL URLWithString:urlString];
        // We rank the primary identifiers higher so they show up better
        CGFloat rank = [identifier isEqualToString:primary] ? 1.0 : 0.0;
        NSNumber *nsRank = [NSNumber numberWithFloat:rank];
        // Snippets look like phone: home
        NSString *snippet = [NSString stringWithFormat:@"%@: %@",
                             localizedProperty, localizedLabel];
        // Need to get some decent icons
        NSDictionary *attr = [NSDictionary dictionaryWithObjectsAndKeys:
                              snippet, kHGSObjectAttributeSnippetKey,
                              nsRank, kHGSObjectAttributeRankKey,
                              nil];
        HGSResult *result = [HGSResult resultWithURL:url
                                                name:value 
                                                type:type 
                                              source:self 
                                          attributes:attr];
        [results addObject:result];
      }
    }
  }
  return results;
}
    
- (NSArray *)explodeContactForSearchOperation:(HGSResult *)contact {
  struct ContactMap {
    NSString *property_;
    NSString *type_;
    NSString *urlFormat_;
    NSString *selName_;
  };
  
  struct ContactMap contactMap[] = {
    { kABPhoneProperty, kHGSTypeTextPhoneNumber, @"callto:+%@", @"cleanPhoneNumber:" },
    { kABEmailProperty, kHGSTypeTextEmailAddress, @"mailto:%@", nil },
    { kABJabberInstantProperty, kHGSTypeTextInstantMessage, @"xmpp:%@", nil },
    { kABAIMInstantProperty, kHGSTypeTextInstantMessage, @"aim:%@", nil },
    { kABICQInstantProperty, kHGSTypeTextInstantMessage, @"icq:%@", nil },
    { kABYahooInstantProperty, kHGSTypeTextInstantMessage, @"ymsgr:%@", nil },
    { kABMSNInstantProperty, kHGSTypeTextInstantMessage, @"msn:%@", nil },
    { kABURLsProperty, kHGSTypeWebpage, @"%@", @"cleanURL:" }
  };
    
  NSMutableArray *results = [NSMutableArray array];
  ABPerson *person = (ABPerson *)[self personForResult:contact];
  if (!person) return results;
  
  for (size_t i = 0; i < sizeof(contactMap) / sizeof(contactMap[0]); ++i) {
    SEL cleaner = NULL;
    if (contactMap[i].selName_) {
      cleaner = NSSelectorFromString(contactMap[i].selName_);
    }
    NSArray *objectResults 
      = [self objectsForMultiValueProperty:contactMap[i].property_
                                fromPerson:person 
                                      type:contactMap[i].type_
                                 urlFormat:contactMap[i].urlFormat_
                               cleanMethod:cleaner];
    [results addObjectsFromArray:objectResults];
  }
  return results;
}

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  HGSQuery *query = [operation query];
  HGSResult *pivotObject = [query pivotObject];
  if ([pivotObject conformsToType:kTypeContactAddressBook]) {
    NSArray *results = [self explodeContactForSearchOperation:pivotObject];
    NSString *queryString = [query rawQueryString];
    if ([queryString length]) {
      NSMutableArray *filteredResults = [NSMutableArray array];
      for (HGSResult *result in results) {
        NSString *stringValue = [result displayName];
        if ([stringValue hasPrefix:queryString]) {
          [filteredResults addObject:result];
        }
      }
      results = filteredResults;
    }
    [operation setResults:results];
  } else {
    // Put a hold on queries while indexing
    [condition_ lock];
    while (indexing_) {
      [condition_ wait];
    }
    [condition_ signal];
    [condition_ unlock];

    // now do the query
    [super performSearchOperation:operation];
  }
}


- (void)consumeImageData:(NSData *)data forTag:(NSInteger)tag {
  HGSResult *result = nil;
  NSNumber *tagNum = [NSNumber numberWithInteger:tag];
  @synchronized(imageLoadingTags_) {
    if (data) {
      // give it a retain since we're gonna remove it from the collection
      result = [[imageLoadingTags_ objectForKey:tagNum] retain];
    }
    [imageLoadingTags_ removeObjectForKey:tagNum]; 
  }
  if (result) {
    // balance our retain
    [result autorelease];

    // create an image out of the data and put it into the result
    NSImage *image = [[[NSImage alloc] initWithData:data] autorelease];
    image = [HGSIconProvider imageWithRoundRectAndDropShadow:image];
    if (image) {
      [result setValue:image forKey:kHGSObjectAttributeIconKey];
      
      NSString *idString = [[result url] absoluteString];
      [[HGSIconProvider sharedIconProvider] cacheIcon:image
                                               forKey:idString];
    }
  }
}

- (ABRecord *)personForResult:(HGSResult *)result {
  ABRecord *person = nil;
  if ([result conformsToType:kTypeContactAddressBook]) {
    NSString *uid = [[result url] path];
    uid = [uid lastPathComponent];
    uid = [uid stringByDeletingPathExtension];
    if (uid) {
      person = [[ABAddressBook sharedAddressBook] recordForUniqueId:uid];
    }
  }
  return person;
}

- (NSImage *)loadImageForObject:(HGSResult *)result immediately:(BOOL)immediately {
  NSImage *image = [[HGSIconProvider sharedIconProvider] 
                    cachedIconForKey:[[result url] absoluteString]];
  
  if (!image) {
    ABPerson *person = (ABPerson *)[self personForResult:result];
    if (!immediately) {
      NSInteger tag = [person beginLoadingImageDataForClient:self];
      NSNumber *tagNumber = [NSNumber numberWithInteger:tag];
      @synchronized(imageLoadingTags_) {
        [imageLoadingTags_ setObject:result forKey:tagNumber];
      }
      image = [self genericContactImage];
    } else {
      NSData *data = [person imageData];
      if (data) {
        image = [[[NSImage alloc] initWithData:data] autorelease];
        image = [HGSIconProvider imageWithRoundRectAndDropShadow:image];
        if (image) {
          NSString *idString = [[result url] absoluteString];
          [[HGSIconProvider sharedIconProvider] cacheIcon:image
                                                   forKey:idString];
        }
      } else {
        image = [self genericContactImage];
      }
    }
  }
  return image;    
}

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeAddressBookRecordIdentifierKey]) {
    ABRecord *person = [self personForResult:result];
    value = [person uniqueId];
  } else if ([key isEqualToString:kHGSObjectAttributeContactEmailKey]) {
    ABRecord *person = [self personForResult:result];
    ABMultiValue *emails = [person valueForProperty:kABEmailProperty];
    if ([emails count]) {
      NSString *primaryID = [emails primaryIdentifier];
      NSUInteger primaryIndex = [emails indexForIdentifier:primaryID];
      value = [emails valueAtIndex:primaryIndex];
    }
  } else if ([key isEqualToString:kHGSObjectAttributeIconKey]) {
    value = [self loadImageForObject:result immediately:NO];
  } else if ([key isEqualToString:kHGSObjectAttributeImmediateIconKey]) {
    value = [self loadImageForObject:result immediately:YES];
  } else if ([key isEqualToString:kHGSObjectAttributeSnippetKey]) {
    ABRecord *person = [self personForResult:result];
    
    NSMutableArray *snippetArray = [NSMutableArray array];
    NSString * const propertiesToCheck[] = {
      kABEmailProperty,
      kABPhoneProperty,
      kABJabberInstantProperty,
      kABAIMInstantProperty,
      kABICQInstantProperty,
      kABYahooInstantProperty,
      kABMSNInstantProperty,
      kABURLsProperty
    };
    for (size_t i = 0; i < sizeof(propertiesToCheck) / sizeof(NSString *); i++) {
      ABMultiValue *snippetValue = [person valueForProperty:propertiesToCheck[i]];
      if (snippetValue) {
        // We intentionally only grab primaries for the snippet just because
        // we want to give the viewer a decent snippet with as much info
        // as possible that they may recognize to choose between two otherwise
        // similar results. If they have 6 "John Smiths" in their contacts
        // we hope that these John Smiths have different email addresses and
        // phone numbers. We don't grab multiple email addresses and phone
        // numbers because we decided that having more different information
        // (email/phone/im) was easier to differentiate between people than
        // having more similar info (home phone/work phone).
        // We anticipate that the "primary" result is the one that the 
        // "searcher" uses the most often, therefore will be the most
        // recognizable.
        NSString *primaryID = [snippetValue primaryIdentifier];
        NSUInteger primaryIndex = [snippetValue indexForIdentifier:primaryID];
        id snippet = [snippetValue valueAtIndex:primaryIndex];
        if (snippet) {
          [snippetArray addObject:snippet];
        }
      }
    }
     
    value = [snippetArray componentsJoinedByString:@", "];
  }
#if !TARGET_OS_IPHONE
  else if ([key isEqualToString:kHGSObjectAttributePathCellsKey]) {
    // Build two cells, the first with Address Book or Google Contacts,
    // the second with the contact entry.
    // TODO(mrossetti): Accommodate Google Contacts when available.
    NSString *serviceName = HGSLocalizedString(@"Contact", nil);
    NSURL *serviceURL = nil;
    NSString *contactName = [result valueForKey:kHGSObjectAttributeNameKey];
    NSURL *contactURL = [result url];
    if ([contactURL isFileURL]) {
      CFURLRef appURL = NULL;
      OSStatus osStatus = LSGetApplicationForURL((CFURLRef)contactURL,
                                                 kLSRolesViewer + kLSRolesEditor,
                                                 NULL,  // Ignore FSRef
                                                 &appURL);
      if (osStatus == noErr && appURL) {
        serviceURL = GTMCFAutorelease(appURL);
        NSString *servicePath = [serviceURL path];
        NSBundle *serviceBundle = [NSBundle bundleWithPath:servicePath];
        if (serviceBundle) {
          serviceName = [serviceBundle objectForInfoDictionaryKey:@"CFBundleName"];
        }
      }
    }
    
    NSMutableDictionary *baseCell = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     serviceName, kHGSPathCellDisplayTitleKey,
                                     nil];
    if (serviceURL) {
      [baseCell setObject:serviceURL forKey:kHGSPathCellURLKey];
    }
    NSDictionary *contactCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                 contactName, kHGSPathCellDisplayTitleKey,
                                 contactURL, kHGSPathCellURLKey,
                                 nil];
    value = [NSArray arrayWithObjects:baseCell, contactCell, nil];
  }
#endif
  if (!value) {
    value = [super provideValueForKey:key result:result];
  }
  
  return value;
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValidSource = [super isValidSourceForQuery:query];
  // Limit the pivot support to just things w/ an email address.  We do this in
  // isValidSourceForQuery instead of processMatchingResults:forQuery:
  // because we want to avoid the extra work when this attribute isn't present
  // at all.
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    // Default to not handling the search when pivoting
    isValidSource = NO;
    if ([pivotObject valueForKey:kHGSObjectAttributeEmailAddressesKey]) {
      isValidSource = YES;
    } else if ([pivotObject isOfType:kTypeContactAddressBook]) {
      isValidSource = YES;
    }
  }
  return isValidSource;
}

- (NSMutableDictionary *)archiveRepresentationForResult:(HGSResult*)result {
  // For address book contacts, we only need to store the Person's unique id
  // to be able to rebuild the result.
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  NSString *uniqID
    = [result valueForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  if (uniqID) {
    [dict setObject:uniqID
             forKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  }
  return dict;
}

- (HGSResult *)resultWithArchivedRepresentation:(NSDictionary *)representation {
  HGSResult *result = nil;
  NSString *uniqID
    = [representation objectForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  if (uniqID) {
    @synchronized(self) {
      // Find the result w/ that ID.
      for (HGSResult *hgsResult in results_) {
        NSString *testUniqID
          = [hgsResult valueForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
        if ([testUniqID isEqualToString:uniqID]) {
          // make sure it lives on the calling thread's pool
          result = [[hgsResult retain] autorelease];
          break;
        }
      }
    }
  }

  return result;
}

- (NSString *)cleanPhoneNumber:(NSString *)dirtyPhone {
  NSMutableString *cleanPhone = [NSMutableString string];
  NSUInteger length = [dirtyPhone length];
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  
  for (NSUInteger i = 0; i < length; ++i) {
    unichar digit = [dirtyPhone characterAtIndex:i];
    if ([digits characterIsMember:digit]) {
      [cleanPhone appendFormat:@"%C", digit];
    }
  }
  return cleanPhone;
}
  
- (NSString *)cleanURL:(NSString *)dirtyURL {
  NSString *cleanURL = dirtyURL;
  NSString *lowerDirty = [dirtyURL lowercaseString];
  if (![lowerDirty hasPrefix:@"http"]) {
    cleanURL = [NSString stringWithFormat:@"http://%@", dirtyURL];
  }
  return cleanURL;
}
@end
