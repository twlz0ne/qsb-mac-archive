//
//  QSBCategory.m
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

#import "QSBCategory.h"
#import <Vermilion/Vermilion.h>
#import <GTM/GTMObjectSingleton.h>
#import "QSBCategories.h"

// Keys for the Categories.plist dictionaries
static NSString *const kQSBCategoryConformToTypesKey = @"conformToTypes";
static NSString *const kQSBCategoryDoesNotConformToTypesKey 
  = @"doesNotConformToTypes";

// Catch all type for types that don't fit elsewhere.
static NSString *const kQSBCategoryOthersType 
  = GTM_NSSTRINGIFY(QSB_CATEGORY_OTHERS_NAME); 

@interface QSBCategory ()

- (id)initWithName:(NSString *)name dictionary:(NSDictionary *)dictionary;

@end

@interface QSBOtherCategory : QSBCategory
@end

@implementation QSBCategory 

@synthesize conformTypes = conformTypes_;
@synthesize doesNotConformTypes = doesNotConformTypes_;
@synthesize name = name_;
@synthesize localizedName = localizedName_;
@synthesize localizedSingularName = localizedSingularName_;

- (id)initWithName:(NSString *)name dictionary:(NSDictionary *)dictionary {
  if ((self = [super init])) {
    if (dictionary) {
      NSArray *array = [dictionary objectForKey:kQSBCategoryConformToTypesKey];
      if ([array count]) {
        conformTypes_ = [[NSSet alloc] initWithArray:array];
      }
      array = [dictionary objectForKey:kQSBCategoryDoesNotConformToTypesKey];
      if ([array count]) {
        doesNotConformTypes_ = [[NSSet alloc] initWithArray:array];
      }
#if DEBUG
      // Debug runtime check to make sure our types are sane.
      if ([conformTypes_ count] && [doesNotConformTypes_ count]) {
        HGSAssert(![conformTypes_ intersectsSet:doesNotConformTypes_], nil);
      }
#endif  // DEBUG
    }
    name_ = [name copy];
    HGSAssert(name_, nil);
    NSBundle *bundle = [NSBundle mainBundle];
    localizedName_ = [[bundle localizedStringForKey:name 
                                              value:nil 
                                              table:nil] retain];
    HGSAssert(localizedName_, nil);
    localizedSingularName_ 
      = [[bundle localizedStringForKey:name 
                                 value:nil 
                                 table:@"CategorySingulars"] retain];
    HGSAssert(localizedSingularName_, nil);
  }
  return self;
}

- (void)dealloc {
  [name_ release];
  [conformTypes_ release];
  [doesNotConformTypes_ release];
  [localizedName_ release];
  [localizedSingularName_ release];
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone {
  return [self retain];
}

- (BOOL)isResultMember:(HGSResult *)result {
  return [result conformsToTypeSet:[self conformTypes]] 
    && [result doesNotConformToTypeSet:[self doesNotConformTypes]];
}

- (NSComparisonResult)compare:(QSBCategory *)category {
  return [[self localizedName] compare:[category localizedName]];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"<%@:%p %@>",
          [self class], self, [self localizedName]];
}

@end

@implementation QSBOtherCategory

- (BOOL)isResultMember:(HGSResult *)result {
  NSString *type = [result type];
  QSBCategoryManager *manager = [QSBCategoryManager sharedManager];
  QSBCategory *category = [manager categoryForType:type];
  return [[category class] isKindOfClass:[self class]];
}

@end


@implementation QSBCategoryManager
GTMOBJECT_SINGLETON_BOILERPLATE(QSBCategoryManager, sharedManager);

+ (void)load {
  // We force the creation and loading of the manager at startup to prevent
  // loading and parsing of the category file to screw up timings on first
  // searches.
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [self sharedManager];
  [pool release];
}

- (id)init {
  if ((self = [super init])) {
    NSMutableSet *othersDoesNotConformTo = [NSMutableSet set];
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:@"Categories" ofType:@"plist"];
    HGSAssert(path, @"Unable to find Categories.plist");
    NSDictionary *categories = [NSDictionary dictionaryWithContentsOfFile:path];
    NSMutableArray *tempCategories 
      = [NSMutableArray arrayWithCapacity:[categories count]];
    for (NSString *name in categories) {
      NSDictionary *definition = [categories objectForKey:name];
      QSBCategory *category 
        = [[[QSBCategory alloc] initWithName:name 
                                  dictionary:definition] autorelease];
      [tempCategories addObject:category];
      [othersDoesNotConformTo unionSet:[category conformTypes]];
    }
    NSDictionary *otherDict 
      = [NSDictionary dictionaryWithObject:[othersDoesNotConformTo allObjects]
                                    forKey:kQSBCategoryDoesNotConformToTypesKey];
    otherCategory_ = [[QSBCategory alloc] initWithName:kQSBCategoryOthersType
                                             dictionary:otherDict];
    [tempCategories addObject:otherCategory_];
    categories_ = [tempCategories retain];
  }
  return self;
}

- (void) dealloc {
  [categories_ release];
  [otherCategory_ release];
  [super dealloc];
}

- (QSBCategory *)categoryForType:(NSString *)type {
  QSBCategory *category = nil;
  for (category in categories_) {
    NSSet *conformTypes = [category conformTypes];
    if (HGSTypeConformsToTypeSet(type, conformTypes)) {
      NSSet *doesNotConformTypes = [category doesNotConformTypes];
      if (HGSTypeDoesNotConformToTypeSet(type, doesNotConformTypes)) {
        break;
      }
    }
  }
  if (!category) {
    category = otherCategory_;
  }
  return category;
}

- (NSArray *)categories {
  return categories_;
}

@end
