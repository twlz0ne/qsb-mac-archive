//
//  Shortcuts.m
//
//  Copyright (c) 2007-2008 Google Inc. All rights reserved.
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

// Shortcuts stores things in our user defaults.
// The top level is a dictionary keyed by "shortcut" where a shortcut is the
// series of characters entered by the user for them to get a object (i.e. 
// 'ipho' could correspond to iPhoto. The value associated with the key is
// an array of object identifiers. These identifiers match an entry in
// a sqlite cache that holds the data needed to rebuild the object.
// When a user associates a object (ex 'ipho') with a object (ex 'iphoto') 
// and there is nothing else keyed to 'ipho' in the DB, the array for 'ipho'
// will have a single entry 'iphoto'. If the user then associates 'iphone' with
// 'ipho' the array for 'ipho' will have two objects (iphoto and iphone). If
// the user again associates ipho with iPhone then the array will change to
// (iPhone, iPhoto). If the user then associates ipho with iphonizer the array
// will change to (iphone, iponizer). Object for shortcut will always return the
// first element in the array for a given key.

#import <Vermilion/Vermilion.h>
#import "HGSSQLiteBackedCache.h"
#import "HGSStringUtil.h"

#if TARGET_OS_IPHONE
#import "GMOSourceConfigProvider.h"
#else
#import "GTMNSFileManager+Carbon.h"
#import "QSBSearchWindowController.h"
#import "QSBSearchViewController.h"
#import "QSBSearchController.h"
#import "QSBTableResult.h"
#endif
#import "GTMMethodCheck.h"
#import "GTMObjectSingleton.h"
#import "GTMExceptionalInlines.h"

static NSString *const kHGSShortcutsKey = @"kHGSShortcutsKey";
static NSString *const kHGSShortcutsArchiveKey = @"kHGSShortcutsArchiveKey";
static NSString *const kHGSShortcutsVersionStringKey 
  = @"kHGSShortcutsVersionStringKey";

static NSString *const kHGSShortcutsAliasKey = @"kHGSShortcutsAliasKey";

// The current version of the shortcuts DB. If you change how things are stored
// in the shortcuts DB, you will have to change this.
static NSString* const kHGSShortcutsVersion = @"0.92";

// Maximum number of entries per shortcut.
static const unsigned int kMaxEntriesPerShortcut = 3;

@interface ShortcutsSource : HGSCallbackSearchSource {
@private
  HGSSQLiteBackedCache *cache_;
}

// Tell the database that "object" was selected for shortcut, and let it do its
// magic internally to update itself.
- (BOOL)updateShortcutFromController:(QSBSearchController *)searchController 
                          withResult:(HGSResult *)result;
// Reads in our shortcut info, and/or creates a new DB for us.
- (NSMutableDictionary *)readShortcutData;

- (NSArray *)rankedIdentifiersForNormalizedShortcut:(NSString *)shortcut;
- (NSArray *)rankedObjectsForShortcut:(NSString *)shortcut;
@end

static inline int KeyLength(NSString *a, NSString *b, void *c) {
  int lengthA = [a length];
  int lengthB = [b length];
  if (lengthA < lengthB) {
    return NSOrderedAscending;
  } else if (lengthA > lengthB) {
    return NSOrderedDescending;
  }
  return NSOrderedSame;
}

@implementation ShortcutsSource
GTM_METHOD_CHECK(NSFileManager, gtm_aliasDataForPath:);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
#if TARGET_OS_IPHONE
    GMOSourceConfigProvider *provider = [GMOSourceConfigProvider defaultConfig];
    NSString* cachePath = [provider shortcutsCacheDbPath];
#else
    id<HGSDelegate> delegate = [[HGSPluginLoader sharedPluginLoader] delegate];
    NSString *appSupportPath = [delegate userApplicationSupportFolderForApp];
    NSString* cachePath
      = [appSupportPath stringByAppendingPathComponent:@"shortcuts.db"];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self 
           selector:@selector(qsbWillPivot:) 
               name:kQSBWillPivotNotification 
             object:nil];
    [nc addObserver:self
           selector:@selector(qsbWillPerformAction:)
               name:kQSBQueryControllerWillPerformActionNotification
             object:nil];
#endif
    cache_ = [[HGSSQLiteBackedCache alloc] initWithPath:cachePath 
                                                version:kHGSShortcutsVersion
                                            useArchiver:YES];
    if (!cache_) {
      HGSLogDebug(@"Unable to allocate cache in HGSShortcuts");
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void) dealloc{
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [cache_ release];
  [super dealloc];
}

- (id)defaultObjectForKey:(NSString *)key {
  id defaultObject = nil;
  if ([key isEqualToString:kHGSExtensionUserVisibleNameKey]) {
    defaultObject = HGSLocalizedString(@"Shortcuts", nil);
  }
  if (!defaultObject) {
    defaultObject = [super defaultObjectForKey:key];
  }
  return defaultObject;
}

- (HGSSQLiteBackedCache *)cache {
  return cache_;
}

- (HGSResult *)unarchiveResultForIdentifier:(NSString *)identifier {
  id object = [[self cache] valueForKey:identifier];
  
  // Make sure we get out dictionary we expect of source name and object
  if ([object isKindOfClass:[NSDictionary class]] &&
      ([object count] == 1)) {
    NSDictionary *archiveDict = object;
    NSString *sourceName = [[archiveDict allKeys] lastObject];
    NSDictionary *archivedRep = [archiveDict objectForKey:sourceName];
    if ([archivedRep isKindOfClass:[NSDictionary class]]) {
      HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
      HGSSearchSource *source = [sourcesPoint extensionWithIdentifier:sourceName];
      HGSResult *result = [source resultWithArchivedRepresentation:archivedRep];
      return result;
    } else {
      HGSLogDebug(@"didn't have a dictionary for the hgsobject's archived rep");
    }
  }
  return nil;
}

// TODO(alcor): move storage of shortcuts to a sqlite db
- (void)setArray:(NSArray *)array forShortcut:(NSString *)key {
  NSMutableDictionary *shortcutDB = [self readShortcutData];
  [shortcutDB setObject:array forKey:key];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:shortcutDB forKey:kHGSShortcutsKey];
  [defaults synchronize];
}

- (NSMutableArray *)arrayForShortcut:(NSString *)key {
  NSMutableDictionary *shortcutDB = [self readShortcutData];
  NSMutableArray *valueArray = [shortcutDB objectForKey:key];
  return valueArray;
}

- (BOOL)updateShortcutFromController:(QSBSearchController *)searchController  
                          withResult:(HGSResult *)result {
  // Check to see if the args we got are reasonable
  if (!searchController || !result) {
    HGSLogDebug(@"Bad Args");
    return NO;
  }
  
  // right now we only store shortcuts at the top level
  if ([searchController parentSearchController]) {
    return NO;
  }
  
  NSString *shortcut = [searchController queryString];
  if (![shortcut length]) {
    return NO;
  }

  NSString *normalizeShortcut
    = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:shortcut];
  if ([normalizeShortcut length] == 0) {
    return NO;
  }
  
  NSURL *identifier = [result url];
  if (!identifier) {
    HGSLogDebug(@"HGSResult had no identifier (%@)", result);
    return NO;
  }
  
  HGSSearchSource *source = [result source];
  NSMutableDictionary *archiveDict = [source archiveRepresentationForResult:result];
  if (!archiveDict || [archiveDict count] == 0) {
    return NO;
  }
  
  NSMutableArray *valueArray = [self arrayForShortcut:normalizeShortcut];
  // see if we have an array for the given shortcut
  
  NSString *idString = [identifier absoluteString];
  
  @synchronized ([self class]) {

    int currentIndex = [valueArray indexOfObject:idString];
    
    // The only way to be inserted at 0 is if you are in 2nd place, 
    // otherwise insert at 1
    int newIndex = (currentIndex <= 1) ? 0 : 1;
    
    // Only perform the insertion/update if the current index changed
    // or if the array doesn't exist yet.
    
    if (!valueArray || newIndex != currentIndex) {
      if (!valueArray) {
        valueArray = [NSMutableArray array]; 
      } else {
        valueArray = [[valueArray mutableCopy] autorelease];
      }

      [valueArray removeObject:idString];
      [valueArray insertObject:idString atIndex:newIndex];
    }
    
    // Clamp the number of shortcuts to kMaxEntriesPerShortcut.
    if ([valueArray count] > kMaxEntriesPerShortcut) {
      NSRange toRemove 
        = GTMNSMakeRange(kMaxEntriesPerShortcut,
                         [valueArray count] - kMaxEntriesPerShortcut);
      [valueArray removeObjectsInRange:toRemove];
    }
    
    [self setArray:valueArray forShortcut:normalizeShortcut];
    NSString *srcId = [source identifier];
    NSDictionary *archiveData = [NSDictionary dictionaryWithObject:archiveDict 
                                                            forKey:srcId];
    [[self cache] setValue:archiveData forKey:idString];
    HGSLogDebug(@"Shortcut recorded: %@ = %@", shortcut, result);
  }
  return YES;
}  // updateShortcutFromController:withObject:

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  // shortcuts start w/ the raw query so anything can get remembered.
  HGSQuery *query = [operation query];
  NSString *queryString = [query rawQueryString];
  NSArray *results = [self rankedObjectsForShortcut:queryString];
  NSMutableArray *rankedResults 
    = [NSMutableArray arrayWithCapacity:[results count]];
  NSEnumerator *enumerator = [results objectEnumerator];
  HGSResult *result;
  for (NSUInteger i = 0; (result = [enumerator nextObject]); ++i) {
    // Decrease the score for each
    HGSMutableResult *mutableResult = [[result mutableCopy] autorelease];
    [mutableResult setRank:1000 - i];
    [rankedResults addObject:mutableResult];
  }
  [operation setResults:rankedResults];
}

- (NSArray *)rankedIdentifiersForNormalizedShortcut:(NSString *)normalizeShortcut {
  
  NSMutableArray *valueArray = [NSMutableArray array];
  NSDictionary *shortcutDB = [self readShortcutData];
  NSArray *keyArray = [[shortcutDB allKeys] sortedArrayUsingFunction:KeyLength
                                                             context:NULL];
  
  NSMutableSet *identifierSet = [NSMutableSet set];
  NSEnumerator *keys = [keyArray objectEnumerator];
  NSString *key;
  while ((key = [keys nextObject])) {
    if ([key hasPrefix:normalizeShortcut]) {
      NSString *identifier;
      NSEnumerator *idEnumerator 
        = [[shortcutDB objectForKey:key] objectEnumerator];
      while ((identifier = [idEnumerator nextObject])) {
        // Filter out duplicates
        if (![identifierSet containsObject:identifier]) {
          [identifierSet addObject:identifier];
          [valueArray addObject:identifier];
        }
      }
    }
  }
  return valueArray;
}

- (NSArray *)rankedObjectsForShortcut:(NSString *)shortcut {
  NSString *normalizeShortcut
    = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:shortcut];
  NSArray *identifiers 
    = [self rankedIdentifiersForNormalizedShortcut:normalizeShortcut];
  
  NSMutableArray *results = [NSMutableArray array];
  
  NSEnumerator *idEnumerator = [identifiers objectEnumerator];
  NSString *identifier = nil;
  while ((identifier = [idEnumerator nextObject])) {
    
    HGSResult *result = [self unarchiveResultForIdentifier:identifier];
    if (result) {
      [results addObject:result];
    }
  }
  return results;
}  

- (NSMutableDictionary *)readShortcutData {
  NSMutableDictionary *shortcutData = nil;
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString* version = [defaults objectForKey:kHGSShortcutsVersionStringKey];
  @synchronized ([self class]) {
    if ([version isEqualToString:kHGSShortcutsVersion]) {
      NSDictionary *shortCuts = [defaults dictionaryForKey:kHGSShortcutsKey];
      shortcutData = [NSMutableDictionary dictionaryWithDictionary:shortCuts];
    }
    if (!shortcutData) {
      shortcutData = [NSMutableDictionary dictionary];
      [defaults setObject:kHGSShortcutsVersion 
                   forKey:kHGSShortcutsVersionStringKey];
      [defaults setObject:shortcutData 
                   forKey:kHGSShortcutsKey];
      [defaults synchronize];
    }
  }
  return shortcutData;
}  // readShortcutData

#if TARGET_OS_IPHONE
- (void)resetHistoryAndCache {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults removeObjectForKey:kHGSShortcutsVersionKey];
  [defaults removeObjectForKey:kHGSShortcutsKey];
  [defaults synchronize];
  
  [[self cache] removeAllObjects];
}

#else 

- (void)qsbWillPivot:(NSNotification *)notification {
  NSDictionary *userDict = [notification userInfo];
  QSBSearchController *searchController 
    = [userDict objectForKey:kQSBNotificationSearchControllerKey];
  id result = [notification object];
  if ([result respondsToSelector:@selector(representedResult)]) {
    HGSResult *hgsResult = [result representedResult];
    if ([hgsResult isKindOfClass:[HGSResult class]]) {
      [self updateShortcutFromController:searchController withResult:hgsResult];
    }
  }  
}

- (void)qsbWillPerformAction:(NSNotification *)notification {
  NSDictionary *userDict = [notification userInfo];
  QSBSearchController *searchController 
    = [userDict objectForKey:kQSBNotificationSearchControllerKey];
  HGSResultArray *directObjects 
    = [userDict objectForKey:kQSBNotificationDirectObjectsKey];
  if ([directObjects count] == 1) {
    HGSResult *directObject = [directObjects objectAtIndex:0];
    [self updateShortcutFromController:searchController 
                            withResult:directObject];
  }
}

#endif
@end
