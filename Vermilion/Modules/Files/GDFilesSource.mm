//
//  HGSFilesSource.m
//  Vermilion
//
//  Created by pinkerton on 3/5/08.
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
#import "GDFilesSource.h"
#import "NSWorkspace+Running.h"

#import "NSString+Path.h"
#import "NSString+UTI.h"
#import "GMGarbageCollection.h"

//NSString *const kPredicateString = @"(kMDItemTextContent = '*%@*'cd || kMDItemTitle = '*%@*'cd)";
NSString *const kPredicateString = @"(* = \"%@*\"cdw || kMDItemTextContent = \"%@*\"cdw)";

// a little stack-based class to turn off live updating of results while
// we take a snapshot
class StSpotlightQueryDisabler {
 private:
  NSMetadataQuery *query_;
 public:
  StSpotlightQueryDisabler(NSMetadataQuery *query) : query_(query) { 
    [query_ disableUpdates]; 
  }
  ~StSpotlightQueryDisabler() {
    [query_ enableUpdates];
  }
};

#pragma mark -

@interface HGSFileCreateContext : NSObject {
 @public
  HGSPredicate         *query_;
  NSString            *userHomePath_;
  int                  userHomePathLength_;
  NSString            *userDesktopPath_;
  int                  userDesktopPathLength_;
  NSString            *userDownloadsPath_;
  int                  userDownloadsPathLength_;
  NSSet               *userPersistentItemPaths_;
  NSSet               *launchableUTIs_;
  NSMutableIndexSet   *hiddenFolderCatalogIDs_;
  NSMutableIndexSet   *visibleFolderCatalogIDs_;
  
  id<HGSObjectHandler> resultHandler_;      // weak
  id<HGSActionProvider> actionProvider_;    // weak
  id<HGSPivotProvider> pivotProvider_;      // weak
  
  // TODO(pink) - HACK!
  CFIndex nextIndex_;
}
- (id)initWithPredicate:(HGSPredicate*)query
          resultHandler:(id<HGSObjectHandler>)handler
          actionProvider:(id<HGSActionProvider>)actionProvider
          pivotProvider:(id<HGSPivotProvider>)pivotProvider;
// No accessors, this is just a bag of data
@end

@implementation HGSFileCreateContext

- (id)initWithPredicate:(HGSPredicate*)query
          resultHandler:(id<HGSObjectHandler>)handler
          actionProvider:(id<HGSActionProvider>)actionProvider
          pivotProvider:(id<HGSPivotProvider>)pivotProvider {
  if (!query) return nil;
  
  self = [super init];
  if (!self) return nil;
  
  resultHandler_ = handler;
  actionProvider_ = actionProvider;
  pivotProvider_ = pivotProvider;
  
  // Cache query
  query_ = [query retain];
  
  // Home directories (standardized just in case its a symlink)
  userHomePath_ = [[NSHomeDirectory() stringByStandardizingPath] retain];
  userHomePathLength_ = [userHomePath_ length];
  userDesktopPath_ = [[userHomePath_ stringByAppendingPathComponent:@"Desktop"] retain];
  userDesktopPathLength_ = [userDesktopPath_ length];
  // TODO(aharper): Look up user's download folder preference
  userDownloadsPath_ = [[userHomePath_ stringByAppendingPathComponent:@"Downloads"] retain];
  userDownloadsPathLength_ = [userDownloadsPath_ length];
  
  // User persistent items
  userPersistentItemPaths_ = [[NSMutableSet set] retain];
  // Read the Dock prefs
  // TODO(aharper): This could probably be made more robust
  NSDictionary *dockPrefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.apple.dock"];
  NSArray *dockItems = [[dockPrefs objectForKey:@"persistent-apps"] arrayByAddingObjectsFromArray:[dockPrefs objectForKey:@"persistent-others"]];
  NSEnumerator *dockItemEnum = [dockItems objectEnumerator];
  NSDictionary *dockItem = nil;
  while ((dockItem = [dockItemEnum nextObject])) {
    NSData *aliasData = [[[dockItem objectForKey:@"tile-data"] objectForKey:@"file-data"] objectForKey:@"_CFURLAliasData"];
    if (aliasData) {
      NSString *dockItemPath = [[NSString pathWithAliasData:aliasData] stringByStandardizingPath];
      if (dockItemPath) [(NSMutableSet *)userPersistentItemPaths_ addObject:dockItemPath];
    }
  }
  // TODO(aharper): Read Finder.app sidebar info as persistent paths
  
  // Launchable UTIs
  NSArray *prefPaneChildren = [@"com.apple.systempreference.prefpane" utiTypeChildren];
  NSArray *applicationChildren = [(NSString *)kUTTypeApplication utiTypeChildren];
  if (prefPaneChildren && applicationChildren) {
    launchableUTIs_ = [[NSSet setWithArray:[prefPaneChildren arrayByAddingObjectsFromArray:applicationChildren]] retain];
  }
  
  // Index set for tracking hidden folders
  hiddenFolderCatalogIDs_ = [[NSMutableIndexSet indexSet] retain];
  visibleFolderCatalogIDs_ = [[NSMutableIndexSet indexSet] retain]; 
  
  // Sanity
  if (!userHomePath_ || !userDesktopPath_ || !userDownloadsPath_ ||
      !userPersistentItemPaths_ ||
      !launchableUTIs_ || !hiddenFolderCatalogIDs_ || !visibleFolderCatalogIDs_) {
    [self release];
    return nil;
  }
  
  return self;
} // init

- (void)dealloc {
  [query_ release];
  [userHomePath_ release];
  [userDesktopPath_ release];
  [userDownloadsPath_ release];
  [userPersistentItemPaths_ release];
  [launchableUTIs_ release];
  [hiddenFolderCatalogIDs_ release];
  [visibleFolderCatalogIDs_ release];
  [super dealloc];
} // dealloc

@end

#pragma mark -

static BOOL IsHidden(FSRef *thisRef,
                       NSMutableIndexSet *previousHiddenFolders,
                       NSMutableIndexSet *previousVisibleFolders) {
  // Sanity  
  if (!thisRef) return YES;
  
  // Get info and parent
  FSRef parentRef;
  FSCatalogInfo catInfo;
  OSStatus err = FSGetCatalogInfo(thisRef,
                                  kFSCatInfoNodeID |
                                  kFSCatInfoNodeFlags |
                                  kFSCatInfoParentDirID,
                                  &catInfo,
                                  NULL,
                                  NULL,
                                  &parentRef);
  if (err != noErr) return NO;  // Nothing sane
  
  // If the parent is the same as here we're at the top, all we care about
  // is ourself
  if (catInfo.parentDirID == 1) {
    // Is it visible at this level?
    LSItemInfoRecord lsInfo;
    err = LSCopyItemInfoForRef(thisRef, kLSRequestBasicFlagsOnly, &lsInfo);
    if (err != noErr) return NO;
    if (lsInfo.flags & kLSItemInfoIsInvisible) {
      // This invisible and if its a folder all of its children are invisible
      if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
        [previousHiddenFolders addIndex:catInfo.nodeID];
      }
      return YES;
    }
    if (lsInfo.flags & kLSItemInfoIsPackage) {
      // This not invisible but all of its children are invisible
      if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
        [previousHiddenFolders addIndex:catInfo.nodeID];
      }
      return NO;
    }
    // LSInfo says we're visible
    return NO;
  }
  
  // If we know the parent was invisible we can skip out now
  if ([previousHiddenFolders containsIndex:catInfo.parentDirID]) {
    // This item is hidden too
    if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
      [previousHiddenFolders addIndex:catInfo.nodeID];
    }
    return YES;
  }
  
  // If our parent was known to be visible we can also shortcut
  if ([previousVisibleFolders containsIndex:catInfo.parentDirID]) {
    // Is it visible at this level?
    LSItemInfoRecord lsInfo;
    err = LSCopyItemInfoForRef(thisRef, kLSRequestBasicFlagsOnly, &lsInfo);
    if (err != noErr) return NO;
    if (lsInfo.flags & kLSItemInfoIsInvisible) {
      // This invisible and if its a folder all of its children are invisible
      if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
        [previousHiddenFolders addIndex:catInfo.nodeID];
      }
      return YES;
    }
    if (lsInfo.flags & kLSItemInfoIsPackage) {
      // This not invisible but all of its children are invisible
      if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
        [previousHiddenFolders addIndex:catInfo.nodeID];
      }
      return NO;
    }
    // LSInfo says we're visible
    return NO;
  }
  
  // Recurse up
  BOOL parentHidden = IsHidden(&parentRef, previousHiddenFolders, previousVisibleFolders);
  if (parentHidden) {
    if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
      [previousHiddenFolders addIndex:catInfo.nodeID];
    }
    return YES;
  }
  
  // Now check on the parent
  LSItemInfoRecord lsInfo;
  err = LSCopyItemInfoForRef(&parentRef, kLSRequestBasicFlagsOnly, &lsInfo);
  if (err != noErr) return NO;
  if (lsInfo.flags & kLSItemInfoIsInvisible) {
    [previousHiddenFolders addIndex:catInfo.parentDirID];
    if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
      [previousHiddenFolders addIndex:catInfo.nodeID];
    }
    return YES;
  }
  if (lsInfo.flags & kLSItemInfoIsPackage) {
    if (catInfo.nodeFlags & kFSNodeIsDirectoryMask) {
      [previousHiddenFolders addIndex:catInfo.nodeID];
    }
    return YES;
  }
  
  // Fallthrough
  [previousVisibleFolders addIndex:catInfo.parentDirID];
  return NO;
  
}

static CFComparisonResult CompareRelevance(const void *ptr1, const void *ptr2, void *context) {
  // Sanity
  if (!(ptr1 && ptr2 && context)) return kCFCompareEqualTo;  // Nothing sane to do

  // Save some typing and cast
  HGSObject *item1 = (HGSObject *)ptr1;
  HGSObject *item2 = (HGSObject *)ptr2;
  
  // Final result
  CFComparisonResult compareResult = kCFCompareEqualTo;

  ////////////////////////////////////////////////////////////
  //  Penalize hidden items
  ////////////////////////////////////////////////////////////
  
  if (item1->isHidden_) {
    if (!item2->isHidden_) {
      compareResult = kCFCompareGreaterThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isHidden_) {
    compareResult = kCFCompareLessThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  ////////////////////////////////////////////////////////////
  //  Penalize spam
  ////////////////////////////////////////////////////////////
  
  if (item1->isSpam_) {
    if (!item2->isSpam_) {
      compareResult = kCFCompareGreaterThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isSpam_) {
    compareResult = kCFCompareLessThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  ////////////////////////////////////////////////////////////
  //  Penalize raw plists
  ////////////////////////////////////////////////////////////

  if (item1->isPlist_) {
    if (!item2->isPlist_) {
      compareResult = kCFCompareGreaterThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isPlist_) {
    compareResult = kCFCompareLessThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  ////////////////////////////////////////////////////////////
  //  Penalize areas in Library directory
  ////////////////////////////////////////////////////////////
  
  if (item1->isLibraryBadFile_) {
    if (!item2->isLibraryBadFile_) {
      compareResult = kCFCompareGreaterThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isLibraryBadFile_) {
    compareResult = kCFCompareLessThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Contacts
  ////////////////////////////////////////////////////////////
  
  if (item1->isContact_) {
    if (item2->isContact_) {
      // Between contacts just sort on last used
      goto HGSRelevanceSpotlightQueryRelevanceCompareLastUsed;
    } else {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
  } else if (item2->isContact_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  ////////////////////////////////////////////////////////////
  //  "Persistent" items (Dock, Finder sidebar, etc.)
  ////////////////////////////////////////////////////////////
  
  if (item1->isUserPersistentPath_) {
    if (!item2->isUserPersistentPath_) {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through to further comparisons
  } else if (item2->isUserPersistentPath_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  "Launchable" (Applications, Pref panes, etc.)
  ////////////////////////////////////////////////////////////
  
  if (item1->isLaunchable_ && item1->isNameMatch_) {
    if (!(item2->isLaunchable_ && item2->isNameMatch_)) {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isLaunchable_ && item2->isNameMatch_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  ////////////////////////////////////////////////////////////
  //  Special UI objects
  ////////////////////////////////////////////////////////////

  if (item1->isSpecialUIObject_) {
    if (!item2->isSpecialUIObject_) {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through to further comparisons
  } else if (item2->isSpecialUIObject_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Home folder check
  ////////////////////////////////////////////////////////////
  
  // Special home folder places
  if (item1->isHomeChild_ || item1->isUnderDownloads_ || item1->isUnderDesktop_) {
    if (!(item2->isHomeChild_ || item2->isUnderDownloads_ || item2->isUnderDesktop_)) {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isHomeChild_ || item2->isUnderDownloads_ || item2->isUnderDesktop_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  // Just under home in general is more relevant
  if (item1->isUnderHome_) {
    if (!item2->isUnderHome_) {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isUnderHome_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }

  ////////////////////////////////////////////////////////////
  //  Name matches are preferred even over recent usage
  ////////////////////////////////////////////////////////////
  if (item1->isNameMatch_) {
    if (!item2->isNameMatch_) {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
    // Fall through
  } else if (item2->isNameMatch_) {
    compareResult = kCFCompareGreaterThan;
    goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
  }
  
  ////////////////////////////////////////////////////////////
  //  Nearby calendars are relevant, other calendar is
  //  less relevant
  ////////////////////////////////////////////////////////////
  if (item1->isCalendar_) {
    if (item2->isCalendar_) {
      // Both are calendar, are both nearby?
      if (item1->isNearbyCalendar_) {
        if (item2->isNearbyCalendar_) {
          // Both are nearby calendars
          // TODO(aharper): Sort two nearbys on event date
          compareResult = kCFCompareEqualTo;
          goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
        } else {
          compareResult = kCFCompareLessThan;
          goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
        }
      } else if (item2->isNearbyCalendar_) { 
        compareResult = kCFCompareGreaterThan;
        goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
      }
    } else {
      if (item1->isNearbyCalendar_) {
        compareResult = kCFCompareLessThan;
        goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
      } else {
        compareResult = kCFCompareGreaterThan;
        goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
      }
    }
  } else if (item2->isCalendar_) {
    if (item2->isNearbyCalendar_) {
      compareResult = kCFCompareGreaterThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    } else {
      compareResult = kCFCompareLessThan;
      goto HGSRelevanceSpotlightQueryRelevanceCompareComplete;
    }
  }
  
  ////////////////////////////////////////////////////////////
  //  Last used date
  ////////////////////////////////////////////////////////////
HGSRelevanceSpotlightQueryRelevanceCompareLastUsed:
  // Barring any better information, sort by last used date
  // Set sort so that more recent wins, we can do this in one step by inverting
  // the comparison order (we want newer things to be less than)
  compareResult = CFDateCompare((CFDateRef)[item2 valueForKey:(NSString *)kHGSObjectAttributeLastUsedDateKey], 
                                (CFDateRef)[item1 valueForKey:(NSString *)kHGSObjectAttributeLastUsedDateKey], 
                                NULL);


  // Finished, all comparisons done
HGSRelevanceSpotlightQueryRelevanceCompareComplete:
  // Return the final result
  return compareResult;
                                                                    
}                                                           

static const void* CreateResult(MDQueryRef query, MDItemRef item, void *voidContext) {
  HGSFileCreateContext* context = (HGSFileCreateContext*)voidContext;
  if (!context) return NULL;

  CFIndex currentIndex = MDQueryGetResultCount(query) - 1;  // Safe because query is not sorted

  HGSObject* result = NULL;

  // Path is used a lot but can't be obtained from the query
  NSString *path = (NSString*)MDItemCopyAttribute(item, kMDItemPath);
  unsigned int pathLength = [path length];
  NSURL *uri = [NSURL fileURLWithPath:path];

  CFStringRef contentType = (CFStringRef)MDQueryGetAttributeValueOfResultAtIndex(query, kMDItemContentType, currentIndex);
  if (contentType && uri) {
    result = [[HGSMediaResult alloc] initWithIdentifier:uri
                                                   name:nil
                                                   type:contentType
                                                handler:context->resultHandler_];
   
  } else {
    NSString *description = [GMNSMakeCollectable(CFCopyDescription(item)) autorelease];
    NSLog(@"%@ tossing result, no content type", description);
    return NULL;
  }
  
  // Cache values the query has already copied
  NSDate *lastUsedDate = (NSDate*)MDQueryGetAttributeValueOfResultAtIndex(query, kMDItemLastUsedDate, currentIndex);
  if (lastUsedDate) [result setValue:lastUsedDate forKey:(NSString *)kHGSObjectAttributeLastUsedDateKey];
  NSString *title = (NSString*)MDQueryGetAttributeValueOfResultAtIndex(query, kMDItemTitle, currentIndex);
  if (title) [result setValue:title forKey:(NSString *)kHGSObjectAttributeNameKey];

  NSString *displayName = (NSString*)MDQueryGetAttributeValueOfResultAtIndex(query, kMDItemDisplayName, currentIndex);
//  if (displayName) [result setValue:displayName forKey:(NSString *)kMDItemDisplayName];
  NSString *fsName = (NSString*)MDQueryGetAttributeValueOfResultAtIndex(query, kMDItemFSName, currentIndex);
//  if (fsName) [result setValue:fsName forKey:(NSString *)kMDItemFSName];
  
  
#if 0
  // For many types we want name matches only
  for (NSInteger i = 0; i < sortContext->queryTermsCount_; i++) {
    NSString *term = [sortContext->queryTerms_ objectAtIndex:i];
    if (term) {
      // TODO(aharper): Make sure matches are on word boundaries
      // Not that validating the field != nil is neccessary. If string is nil
      // the NSNotFound will be true (because of return value of [nil rangeOfString:...])
      if ((displayName && ([displayName rangeOfString:term].location != NSNotFound)) ||
          (fsName && ([fsName rangeOfString:term].location != NSNotFound)) ||
          (title && ([title rangeOfString:term].location != NSNotFound))) {
        isNameMatch_ = YES;
        break;
      }    
    }
  }
#endif

  // check for a name match
  NSString* term = [context->query_ query];
  if ((displayName && ([displayName rangeOfString:term].location != NSNotFound)) ||
      (fsName && ([fsName rangeOfString:term].location != NSNotFound)) ||
      (title && ([title rangeOfString:term].location != NSNotFound)))
    result->isNameMatch_ = YES;

  // Persistent user paths (Dock, Finder sidebar, etc.)
  result->isUserPersistentPath_ = [context->userPersistentItemPaths_ containsObject:path];
  
  // Launchables
  result->isLaunchable_ = [context->launchableUTIs_ containsObject:(NSString*)contentType];
  
  // Special UI objects (Home, disks, printers etc.)
  // String comparison safe here because we've already standardized or 
  // normalized all paths.
  // Printer proxies are apps and therefore will already have hit the launchable
  // test
  result->isSpecialUIObject_ = [path isEqualToString:context->userHomePath_] ||
                       UTTypeEqual((CFStringRef)contentType, kUTTypeVolume);

  // Under home directory, again string comparisons safe because we've pre-normalized
  result->isUnderHome_ = [path hasPrefix:context->userHomePath_] &&
                  // Direct equality test here to make sure range check doesn't
                  // walk off string end
                  ![path isEqualToString:context->userHomePath_] &&
                   ([path characterAtIndex:context->userHomePathLength_] == '/');
  // Other home special paths
  if (result->isUnderHome_) {
    // Direct child of home?
    if ([path rangeOfString:@"/" options:NSLiteralSearch 
                      range:NSMakeRange(context->userHomePathLength_ + 1, pathLength - context->userHomePathLength_ - 1)].location == NSNotFound) {
      result->isHomeChild_ = YES;
    }
    // Direct child of downloads or desktop
    if ([path hasPrefix:context->userDownloadsPath_] &&
        [path rangeOfString:@"/" options:NSLiteralSearch 
                      range:NSMakeRange(context->userDownloadsPathLength_ + 1, pathLength - context->userDownloadsPathLength_ - 1)].location == NSNotFound) {
      result->isUnderDownloads_ = YES;
    }
    if ([path hasPrefix:context->userDesktopPath_] &&
        [path rangeOfString:@"/" options:NSLiteralSearch 
                      range:NSMakeRange(context->userDesktopPathLength_ + 1, pathLength - context->userDesktopPathLength_ - 1)].location == NSNotFound) {
      result->isUnderDesktop_ = YES;
    }
  }                      

  // Hidden
  FSRef itemRef;
  if (![path hasFSRef:&itemRef]) {
    [result release];
    return nil;
  }
  result->isHidden_ = IsHidden(&itemRef, context->hiddenFolderCatalogIDs_, context->visibleFolderCatalogIDs_);
  
  // Spam
  if (UTTypeEqual((CFStringRef)contentType, CFSTR("com.apple.mail.emlx")) &&
      (([path rangeOfString:@"/Spam.imapmbox/"].location != NSNotFound) ||
       ([path rangeOfString:@"/Junk.imapmbox/"].location != NSNotFound))) {
    // TODO(aharper): What about POP spam?   
    result->isSpam_ = YES;
  }

  // Plist
  result->isPlist_ = [path hasSuffix:@".plist"];

  // Areas of Library directory we want to largely ignore
  if ([path rangeOfString:@"/Library/Preferences/"].location != NSNotFound) {
    result->isLibraryBadFile_ = YES;
  }
  if (([path rangeOfString:@"/Library/Caches/"].location != NSNotFound) && 
      ([path rangeOfString:@"/metadata/" options:NSCaseInsensitiveSearch].location == NSNotFound)) {
    result->isLibraryBadFile_ = YES;
  }
  if (([path rangeOfString:@"/Library/Application Support/"].location != NSNotFound) && 
      ([path rangeOfString:@"/metadata/" options:NSCaseInsensitiveSearch].location == NSNotFound)) {
    result->isLibraryBadFile_ = YES;
  }
  
  return result;
}

#pragma mark -

@implementation HGSFilesSource

- (id)initWithName:(NSString*)name
      actionProvider:(id<HGSActionProvider>)actionProvider
      pivotProvider:(id<HGSPivotProvider>)pivotProvider
      errorDelegate:(id<HGSSearchSourceErrorDelegate>)errorDelegate {
  if ((self = [super initWithName:name 
                   actionProvider:actionProvider
                    pivotProvider:pivotProvider
                    errorDelegate:errorDelegate])) {
    results_ = [[NSMutableArray alloc] init];}
  return self;  
}

// called on the main thread, flip a bit that allows the thread to continue
// processing. The bulk of the work will continue on the thread.
- (void)queryNotification:(NSNotification*)notification {
  NSString *name = [notification name];
  if ([name isEqualToString:(NSString *)kMDQueryDidUpdateNotification]) {

    // TODO(pink) - handle deletes and updates...
    BOOL rescrapeAllResults = NO;
    
    // With deletes and updates done, its time to go looking for new results
    NSMutableSet *newResults = [NSMutableSet set];
    CFIndex currentCount = MDQueryGetResultCount(mdQuery_);
    if (rescrapeAllResults) {
#if 0
      // Must start from zero again
      for (CFIndex i = 0; i < currentCount; i++) {
        HGSObject *result = (HGSObject *)MDQueryGetResultAtIndex(mdQuery_, i);
        if (result && ![relevanceResults_ containsObject:result]) {
          [newResults addObject:result];
        }
      }
#endif
    } else {
      // No rescrape needed so we can do the fast thing
      for (CFIndex i = nextQueryItemIndex_; i < currentCount; i++) {
        HGSObject *result = (HGSObject *)MDQueryGetResultAtIndex(mdQuery_, i);
        if (result) {
          [newResults addObject:result];
        }
      }
    }

    // Next time around we can start from the current result count
    nextQueryItemIndex_ = currentCount;
    // Insert
    NSEnumerator *newResultsEnum = [newResults objectEnumerator];
    HGSObject *newResult = nil;
    while ((newResult = [newResultsEnum nextObject])) {
      // Find insert position
      CFIndex newIndex = CFArrayBSearchValues((CFArrayRef)results_,
                                              CFRangeMake(0, [results_ count]),
                                              newResult,
                                              &CompareRelevance,
                                              nil);
      if (newIndex < 0) newIndex = 0;
      [results_ insertObject:newResult atIndex:newIndex];
    }
  } else if ([name isEqualToString:(NSString*)kMDQueryDidFinishNotification]) {
    queryComplete_ = YES;
  }
}

// run through the list of applications looking for the ones that match
// somewhere in the title. When we find them, apply a local boost if possible.
// When we're done, sort based on ranking. 
- (NSArray*)performQuery:(HGSPredicate*)predicate 
                 context:(NSDictionary*)context
                observer:(id<HGSSearchSourceObserver>)observer {
  
  // TODO: (dmaclach) fix this when queries are fast enough
  return nil;
  NSString* predicateString = [NSString stringWithFormat:kPredicateString,
                                                            [predicate query],
                                                            [predicate query]];
  NSArray *attributeNames = [NSArray arrayWithObjects:
                             (NSString*)kMDItemTitle,
                             (NSString*)kMDItemDisplayName,
                             (NSString *)kMDItemFSName,
                             (NSString*)kMDItemPath,
                             (NSString*)kMDItemLastUsedDate,
                             (NSString*)kMDItemContentType,
                             nil];
  // Build the query
  mdQuery_ = MDQueryCreate(kCFAllocatorDefault,
                           (CFStringRef)predicateString,
                           (CFArrayRef)attributeNames,
                           // We must not sort here because it means that the
                           // result indexing will be stable (we leverage this
                           // behavior elsewhere)
                           NULL);
  if (!mdQuery_) return nil;
  [[NSNotificationCenter defaultCenter] addObserver:self 
                                           selector:@selector(queryNotification:) 
                                               name:(NSString *)kMDQueryDidFinishNotification 
                                             object:(id)mdQuery_];
  [[NSNotificationCenter defaultCenter] addObserver:self 
                                           selector:@selector(queryNotification:) 
                                               name:(NSString *)kMDQueryDidUpdateNotification 
                                             object:(id)mdQuery_];
  
  // Use our replacer
  [context_ autorelease];
  context_ = [[HGSFileCreateContext alloc] initWithPredicate:predicate
                                              resultHandler:self
                                              actionProvider:actionProvider_
                                              pivotProvider:pivotProvider_];
  MDQuerySetCreateResultFunction(mdQuery_, 
                                 &CreateResult,
                                 context_, 
                                 &kCFTypeArrayCallBacks);

  // Run
  if (!MDQueryExecute(mdQuery_, kMDQueryWantsUpdates)) {
    CFRelease(mdQuery_);
    mdQuery_ = NULL;
    return NO;
  }
  NSLog(@"started spotlight query with |%@|", predicateString);
  
  // block until this query is done to make it appear synchronous. sleep for a
  // second and then check again. |queryComplete_| is set on
  // the main thread which is fine since we're not writing to it here.
  NSRunLoop* loop = [NSRunLoop currentRunLoop];
  while (!queryComplete_ && [loop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]])
    ;
  
  // get results and create HGSObject objects from the spotlight results.
  [results_ removeAllObjects];
  CFIndex resultCount = MDQueryGetResultCount(mdQuery_);
  NSLog(@"... Spotlight complete got %d file results", resultCount);

  for (int i = 0; i < resultCount; i++) {
    HGSObject *result = (HGSObject*)MDQueryGetResultAtIndex(mdQuery_, i);
    if (result) {
      [results_ addObject:result];
    }
  }

  // remove objects that don't match the type of the pending action (if any)
  [self filterResults:results_ basedOnAction:[predicate pendingAction]];

  return results_;
}

- (void)dealloc {
  if (mdQuery_) CFRelease(mdQuery_);
  [context_ release];
  [results_ release];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

#pragma mark -

- (BOOL)provideValueForKey:(NSString*)key result:(HGSObject*)result {
  return NO;
}

- (BOOL)isContainer:(HGSObject*)result {
  return NO;
}

- (CGImageRef)thumbnail:(HGSObject*)result {
  //TODO(pinkerton)
  return nil;
}

- (CGImageRef)preview:(HGSObject*)result {
  //TODO(pinkerton)
  return nil;
}

- (NSString*)displayName:(HGSObject*)result {
  NSString* prefix = @"File";
  NSString* contentType = [result type];
  if (UTTypeConformsTo((CFStringRef)contentType, kUTTypeAudiovisualContent)) {
    prefix = @"Media";
  } else if (UTTypeConformsTo((CFStringRef)contentType, kUTTypeMessage)) {
    prefix = @"Email";
  }
  return [NSString stringWithFormat:@"%@: %@", prefix, 
      [result valueForKey:kHGSObjectAttributeNameKey]];
}
  
// loads everything necessary for display, can be finer-grained if necessary
- (void)loadDisplayDetails:(HGSObject*)result {

}

// cancels all pending requests to load value for |result|. 
- (void)cancelAllPendingAttributeUpdatesForResult:(HGSObject*)result {

}

@end
