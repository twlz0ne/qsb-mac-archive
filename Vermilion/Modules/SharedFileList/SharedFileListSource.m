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

static NSString* const kObjectAttributeSharedFileListItem = 
  @"ObjectAttributeSharedFileListItem";

@interface SharedFileListSource : HGSMemorySearchSource
- (void)loadFileLists;
@end

@implementation SharedFileListSource
- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    [self loadFileLists];
   }
  return self;
}

- (NSArray *)activeLists {
  return [NSArray arrayWithObjects:
          (id)kLSSharedFileListFavoriteVolumes,
          (id)kLSSharedFileListFavoriteItems,
          (id)kLSSharedFileListRecentApplicationItems,
          (id)kLSSharedFileListRecentDocumentItems,
          (id)kLSSharedFileListRecentServerItems,
          nil];
}

- (NSArray *)indexObjectsForList:(NSString *)listName {
  
  LSSharedFileListRef list =
    LSSharedFileListCreate(NULL, (CFStringRef) listName, NULL);
  
  if (!list) return nil;
  
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
    IconRef iconRef = LSSharedFileListItemCopyIconRef(itemRef);
    
    NSImage *image = nil;
    if (iconRef) {
      [[[NSImage alloc] initWithIconRef:iconRef] autorelease];
      ReleaseIconRef(iconRef);
    }
    
    NSString *name = 
      (NSString *)GTMCFAutorelease(LSSharedFileListItemCopyDisplayName(itemRef));
    
    // TODO(alcor): kObjectAttributeSharedFileListItem is not used. it 
    // should be used for demand loading of results.
    
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                                item, kObjectAttributeSharedFileListItem,
                                image, kHGSObjectAttributeIconKey,
                                nil];
    
    HGSObject *object = [HGSObject objectWithFilePath:[url path]
                                               source:self
                                           attributes:attributes];
    [self indexResult:object
           nameString:name
          otherString:nil];
  }
  
  CFRelease(list);
  return nil;
}

- (void)loadFileLists {
  NSArray *lists = [self activeLists];
  
  for (id list in lists) {
    
    // TODO(alcor): watch for notifications and recache
    //
    //LSSharedFileListAddObserver(list,
    //                            [[NSRunLoop mainRunLoop] getCFRunLoop],
    //                            kCFRunLoopDefaultMode,
    //                            listChanged, 
    //                            self);
    //
    //LSSharedFileListRemoveObserver(list,
    //                               [[NSRunLoop mainRunLoop] getCFRunLoop],
    //                               kCFRunLoopDefaultMode, 
    //                               listChanged,
    //                               self);
    //
    
    [self indexObjectsForList:list];
  }
}

//- (void)listChanged:(LSSharedFileListRef)list {
//  UInt32 seed;
//  NSArray *items = (NSArray *)LSSharedFileListCopySnapshot(list, &seed);
//  [items release];
//}
//
//static void listChanged(LSSharedFileListRef list, void *context) {
//  [(id)context listChanged:list];
//}

@end
