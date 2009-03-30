//
//  ApplicationUISource.m
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
#import "ApplicationUISource.h"
#import "GTMAXUIElement.h"
#import "ApplicationUIAction.h"

NSString *const kAppUISourceAttributeElementKey 
  = @"kHGSAppUISourceAttributeElementKey";

@interface ApplicationUISource : HGSCallbackSearchSource {
 @private
  NSImage *windowIcon_;
  NSImage *menuIcon_;
  NSImage *menuItemIcon_;
  NSImage *viewIcon_;
}
@end

@implementation ApplicationUISource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSBundle *bundle = HGSGetPluginBundle();
    NSString *path = [bundle pathForResource:@"window" ofType:@"icns"];
    HGSAssert(path, @"Icons for 'window' are missing from the "
              @"ApplicationUISource bundle.");
    windowIcon_ = [[NSImage alloc] initByReferencingFile:path];
    path = [bundle pathForResource:@"menu" ofType:@"icns"];
    HGSAssert(path, @"Icons for 'menu' are missing from the "
              @"ApplicationUISource bundle.");
    menuIcon_ = [[NSImage alloc] initByReferencingFile:path];
    path = [bundle pathForResource:@"menuitem" ofType:@"icns"];
    HGSAssert(path, @"Icons for 'menuitem' are missing from the "
              @"ApplicationUISource bundle.");
    menuItemIcon_ = [[NSImage alloc] initByReferencingFile:path];
    path = [bundle pathForResource:@"view" ofType:@"icns"];
    HGSAssert(path, @"Icons for 'view' are missing from the "
              @"ApplicationUISource bundle.");
    viewIcon_ = [[NSImage alloc] initByReferencingFile:path];
    if (!(windowIcon_ && menuIcon_ && menuItemIcon_ && viewIcon_)) {
      HGSLogDebug(@"Unable to get icons for %@", [self class]);
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [windowIcon_ release];
  [menuIcon_ release];
  [menuItemIcon_ release];
  [viewIcon_ release];
  [super dealloc];
}
    
- (NSDictionary*)getAppInfoFromResult:(HGSResult *)result {
  NSDictionary *appInfo = nil;
  if (result && [result isOfType:kHGSTypeFileApplication]) {
    NSURL *appURL = [result valueForKey:kHGSObjectAttributeURIKey];
    if ([appURL isFileURL]) {
      NSString *path = [appURL path];
      NSWorkspace *ws = [NSWorkspace sharedWorkspace];
      NSArray *runningApps = [ws launchedApplications];
      NSPredicate *pred 
        = [NSPredicate predicateWithFormat:@"SELF.NSApplicationPath == %@", 
           path];
      NSArray *results = [runningApps filteredArrayUsingPredicate:pred];
      if ([results count] > 0) {
        appInfo = [results objectAtIndex:0];
      }
    }
  }
  return appInfo;
}

- (void)addResultsFromElement:(GTMAXUIElement*)element 
                      toArray:(NSMutableArray*)array
                     matching:(NSString *)rawString {
  if (element) {
    NSArray *children 
      = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
    NSArray *placeHolderRoles = [NSArray arrayWithObjects:
                                 (NSString *)NSAccessibilityMenuRole, 
                                 (NSString *)kAXMenuBarRole,
                                 nil];
    for (GTMAXUIElement *child in children) {
      NSString *role 
        = [child stringValueForAttribute:NSAccessibilityRoleAttribute];
      if ([placeHolderRoles containsObject:role]) {
        [self addResultsFromElement:child toArray:array matching:rawString];
      } else {
        NSNumber *enabled 
          = [child accessibilityAttributeValue:NSAccessibilityEnabledAttribute];
        if (enabled && [enabled boolValue] == NO) continue;
        NSString *name 
          = [child stringValueForAttribute:NSAccessibilityTitleAttribute];
        if (!name) {
          name = [child stringValueForAttribute:NSAccessibilityRoleDescriptionAttribute];
        }
        if ([name length] == 0) continue;
        
        // Filter out the ones we don't want.
        NSString *compareName 
          = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:name];
        
        if ([rawString length] && ![compareName hasPrefix:rawString]) {
          continue;
        }
        // TODO(dmaclach): deal with lower level UI elements such as 
        // buttons, splitters etc.
        
        NSString *nameString 
          = [name stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *uriString 
          = [NSString stringWithFormat:@"AppUISource://%@/%p", 
             nameString, child];
        NSURL *uri = [NSURL URLWithString:uriString];
        NSImage *icon = nil;
        if ([role isEqualToString:NSAccessibilityWindowRole]) {
          icon = windowIcon_;
        } else if ([role isEqualToString:NSAccessibilityMenuRole] 
                   || [role isEqualToString:(NSString*)kAXMenuBarItemRole]
                   || [role isEqualToString:(NSString*)kAXMenuBarRole]) {
          icon = menuIcon_;
        } else if ([role isEqualToString:NSAccessibilityMenuItemRole]) {
          icon = menuItemIcon_;
        } else {
          icon = viewIcon_;
        }
        NSMutableDictionary *attributes
          = [NSMutableDictionary dictionaryWithObjectsAndKeys:
             child, kAppUISourceAttributeElementKey,
             icon, kHGSObjectAttributeIconKey,
             nil];
        HGSAction *defaultAction 
          = [ApplicationUIAction defaultActionForElement:child];
        if (defaultAction) {
          [attributes setObject:defaultAction 
                         forKey:kHGSObjectAttributeDefaultActionKey];
        }
        // TODO(dmaclach): Build up the path cells for the element
        HGSResult *result 
          = [HGSResult resultWithURL:uri
                                name:name
                                type:kHGSTypeAppUIItem
                              source:self
                          attributes:attributes];
        [array addObject:result];
      }
    }
  }
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  if ([GTMAXUIElement isAccessibilityEnabled]) {
    HGSResult *pivotObject = [[operation query] pivotObject];
    GTMAXUIElement *element 
      = [pivotObject valueForKey:kAppUISourceAttributeElementKey];
    if (!element) {
      NSDictionary *appData = [self getAppInfoFromResult:pivotObject];
      if (appData) {
        NSNumber *pid 
          = [appData objectForKey:@"NSApplicationProcessIdentifier"];
        element = [GTMAXUIElement elementWithProcessIdentifier:[pid intValue]];
      }     
    }
    if (element) {
      NSMutableArray *results = [NSMutableArray array];
      HGSQuery* query = [operation query];
      NSString *rawString = [query rawQueryString];
      rawString 
        = [HGSStringUtil stringByLowercasingAndStrippingDiacriticals:rawString];
      [self addResultsFromElement:element toArray:results matching:rawString];
      [operation setResults:results];
    }
  }
}

@end
