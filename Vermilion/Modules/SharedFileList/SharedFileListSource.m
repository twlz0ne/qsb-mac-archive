//
//  SharedFileListSource.m
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
#import "GTMGarbageCollection.h"

// This is the LSSharedFileListItemRef for the item. Allows us to get at
// the icon and other properties as needed.
static NSString* const kObjectAttributeSharedFileListItem = 
  @"ObjectAttributeSharedFileListItem";

@interface SharedFileListSource : HGSMemorySearchSource {
@private
  NSArray *fileLists_;
}
- (void)loadFileLists;
- (void)observeFileLists:(BOOL)doObserve;
- (void)listChanged:(LSSharedFileListRef)list;
- (void)indexObjectsForList:(LSSharedFileListRef)list;
@end

static void ListChanged(LSSharedFileListRef inList, void *context);

@implementation SharedFileListSource
- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    CFStringRef ourLists[] = {
      kLSSharedFileListFavoriteVolumes,
      kLSSharedFileListFavoriteItems,
      kLSSharedFileListRecentApplicationItems,
      kLSSharedFileListRecentDocumentItems
    };
    NSMutableArray *monitoredLists = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(ourLists) / sizeof(ourLists[0]); ++i) {
      LSSharedFileListRef list = LSSharedFileListCreate(NULL, 
                                                        ourLists[i], 
                                                        NULL);
      if (!list) continue;
      [monitoredLists addObject:GTMCFAutorelease(list)];
    }
    fileLists_ = [monitoredLists retain];
    [self loadFileLists];
    [self observeFileLists:YES];
  }
  return self;
}

- (void)dealloc {
  [self observeFileLists:NO];
  [fileLists_ release];
  [super dealloc];
}

- (void)observeFileLists:(BOOL)doObserve {
  CFRunLoopRef mainLoop = CFRunLoopGetMain();
  for (id list in fileLists_) {
    LSSharedFileListRef listRef = (LSSharedFileListRef)list;
    if (doObserve) {
      LSSharedFileListAddObserver(listRef,
                                  mainLoop,
                                  kCFRunLoopDefaultMode,
                                  ListChanged,
                                  self);
    } else {
      LSSharedFileListRemoveObserver(listRef,
                                     mainLoop,
                                     kCFRunLoopDefaultMode,
                                     ListChanged,
                                     self);
    }      
  }
}

- (void)indexObjectsForList:(LSSharedFileListRef)list {
  UInt32 seed;
  NSArray *items =
    (NSArray *)GTMCFAutorelease(LSSharedFileListCopySnapshot(list, &seed));
  
  for (id item in items) {
    LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)item;
    OSStatus err = noErr;
    CFURLRef cfURL = NULL;
    err = LSSharedFileListItemResolve(itemRef, 
                                      kLSSharedFileListNoUserInteraction
                                      | kLSSharedFileListDoNotMountVolumes, 
                                      &cfURL, NULL);
    
    if (err) continue;
    NSURL *url = GTMCFAutorelease(cfURL);

    
    NSString *name = 
      (NSString *)GTMCFAutorelease(LSSharedFileListItemCopyDisplayName(itemRef));
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                item, kObjectAttributeSharedFileListItem,
                                nil];
    
    HGSObject *object = [HGSObject objectWithFilePath:[url path]
                                               source:self
                                           attributes:attributes];
    [self indexResult:object
           nameString:name
          otherString:nil];
  }
}

- (id)provideValueForKey:(NSString *)key result:(HGSObject *)result {
  id value = nil;
  if ([key isEqualToString:kHGSObjectAttributeIconKey] 
      || [key isEqualToString:kHGSObjectAttributeImmediateIconKey]) {
    id item = [result valueForKey:kObjectAttributeSharedFileListItem];
    if (item) {
      LSSharedFileListItemRef itemRef = (LSSharedFileListItemRef)item;
      IconRef iconRef = LSSharedFileListItemCopyIconRef(itemRef);
      if (iconRef) {
        value = [[[NSImage alloc] initWithIconRef:iconRef] autorelease];
        ReleaseIconRef(iconRef);
      }
    }
  }
  return value;
}
    
- (void)loadFileLists {  
  [self clearResultIndex];
  for (id list in fileLists_) {
    LSSharedFileListRef listRef = (LSSharedFileListRef)list;
    [self indexObjectsForList:listRef];
  }
}

- (void)listChanged:(LSSharedFileListRef)list {
  [self loadFileLists];
}

static void ListChanged(LSSharedFileListRef inList, void *context) {
  SharedFileListSource *object = (SharedFileListSource *)context;
  [object listChanged:inList];
}

@end
