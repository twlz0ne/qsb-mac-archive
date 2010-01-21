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
#import <QSBPluginUI/QSBPluginUI.h>
#import "ApplicationUISource.h"
#import "GTMAXUIElement.h"
#import "ApplicationUIAction.h"
#import "GTMNSWorkspace+Running.h"
#import "GTMNSNumber+64Bit.h"
#import "GTMMethodCheck.h"

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

GTM_METHOD_CHECK(NSNumber, gtm_numberWithCGFloat:);

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
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];

  if (result && [result isOfType:kHGSTypeFileApplication]) {
    NSString *path = [result filePath];
    if (path) {
      NSArray *runningApps = [ws gtm_launchedApplications];
      NSPredicate *pred 
      = [NSPredicate predicateWithFormat:@"SELF.NSApplicationPath == %@", 
         path];
      NSArray *results = [runningApps filteredArrayUsingPredicate:pred];
      if ([results count] > 0) {
        appInfo = [results objectAtIndex:0];
      }
    }
  } else {
    // Get the frontmost visible non qsb app.
    ProcessSerialNumber psn;
    ProcessSerialNumber currentProcess;
    GetCurrentProcess(&currentProcess);
    for (OSErr err = GetFrontProcess(&psn); 
         err == noErr && !appInfo;
         err = GetNextProcess(&psn)) {
      Boolean same = false;
      if (SameProcess(&psn, &currentProcess, &same) == noErr && !same) {
        appInfo = [ws gtm_processInfoDictionaryForPSN:&psn];
        if ([[appInfo objectForKey:@"LSUIElement"] boolValue] ||
            [[appInfo objectForKey:@"LSBackgroundOnly"] boolValue]) {
          appInfo = nil;
        }
      }
    }
  }
  return appInfo;
}

- (HGSScoredResult *)resultFromElement:(GTMAXUIElement *)element
                                  role:(NSString *)role
                           queryString:(HGSTokenizedString *)queryString
                         pathCellArray:(NSArray *)pathCellArray {
  NSNumber *enabled 
    = [element accessibilityAttributeValue:NSAccessibilityEnabledAttribute];
  if (enabled && [enabled boolValue] == NO) {
    return nil;
  }
  NSString *name 
    = [element stringValueForAttribute:NSAccessibilityTitleAttribute];
  if (!name) {
    name = [element stringValueForAttribute:NSAccessibilityRoleDescriptionAttribute];
  }
  if ([name length] == 0) return nil;
  
  // Filter out the ones we don't want.
  HGSTokenizedString *compareName 
    = [HGSTokenizer tokenizeString:name];
  
  CGFloat score = 0;
  NSIndexSet *matchedIndexes = nil;
  if ([queryString tokenizedLength]) {
    score = HGSScoreTermForItem(queryString, compareName, &matchedIndexes);
  } else {
    score = HGSCalibratedScore(kHGSCalibratedModerateScore);
  }
  if (!(score > 0.0)) {
    return nil;
  }
  // TODO(dmaclach): deal with lower level UI elements such as 
  // buttons, splitters etc.
  
  NSString *nameString 
    = [name stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
  NSString *uriString 
    = [NSString stringWithFormat:@"AppUISource://%@/%p", 
       nameString, element];
  NSImage *icon = nil;
  if ([role isEqualToString:NSAccessibilityWindowRole]) {
    icon = windowIcon_;
  } else if ([role isEqualToString:NSAccessibilityMenuRole] 
             || [role isEqualToString:(NSString*)kAXMenuBarItemRole]
             || [role isEqualToString:NSAccessibilityMenuBarRole]) {
    icon = menuIcon_;
  } else if ([role isEqualToString:NSAccessibilityMenuItemRole]) {
    icon = menuItemIcon_;
  } else {
    icon = viewIcon_;
  }
  NSDictionary *pathEntry 
    = [NSDictionary dictionaryWithObject:name 
                                forKey:kQSBPathCellDisplayTitleKey];
  pathCellArray = [pathCellArray arrayByAddingObject:pathEntry];  
  NSMutableDictionary *attributes
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       element, kAppUISourceAttributeElementKey,
       icon, kHGSObjectAttributeIconKey,
       pathCellArray, kQSBObjectAttributePathCellsKey,
       nil];
  HGSAction *defaultAction 
    = [ApplicationUIAction defaultActionForElement:element];
  if (defaultAction) {
    [attributes setObject:defaultAction 
                   forKey:kHGSObjectAttributeDefaultActionKey];
  }
  HGSScoredResult *result 
    = [HGSScoredResult resultWithURI:uriString
                                name:name
                                type:kHGSTypeAppUIItem
                              source:self
                          attributes:attributes
                               score:score
                         matchedTerm:queryString
                      matchedIndexes:matchedIndexes];
  return result;
}

- (void)addMenuResultsFromElement:(GTMAXUIElement*)element 
                          toArray:(NSMutableArray*)array
                         matching:(HGSTokenizedString *)queryString
                    pathCellArray:(NSArray *)pathCellArray {
  if (!element) return;
  NSArray *children 
    = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
  for (GTMAXUIElement *child in children) {
    NSString *role 
      = [child stringValueForAttribute:NSAccessibilityRoleAttribute];
    NSString *name 
      = [element stringValueForAttribute:NSAccessibilityTitleAttribute];
    NSArray *newPathCellArray = nil;
    if (name) {
      NSDictionary *pathEntry 
        = [NSDictionary dictionaryWithObject:name 
                                      forKey:kQSBPathCellDisplayTitleKey];
      newPathCellArray = [pathCellArray arrayByAddingObject:pathEntry];
    } else {
      newPathCellArray = pathCellArray;
    }
    
    if ([role isEqual:NSAccessibilityMenuBarRole] ||
      [role isEqual:NSAccessibilityMenuRole] ||
      [role isEqualToString:(NSString*)kAXMenuBarItemRole]) {
      [self addMenuResultsFromElement:child 
                              toArray:array 
                             matching:queryString
                        pathCellArray:newPathCellArray];
    } else if ([role isEqual:NSAccessibilityMenuItemRole]) {
      NSUInteger currentCount = [array count];      
      [self addMenuResultsFromElement:child 
                              toArray:array 
                             matching:queryString 
                        pathCellArray:newPathCellArray];
      if (currentCount == [array count]) {
        HGSScoredResult *result = [self resultFromElement:child
                                                     role:role
                                              queryString:queryString
                                            pathCellArray:pathCellArray];
        if (result) {
          [array addObject:result];
        }
      }
    }
  }
}

- (void)addResultsFromElement:(GTMAXUIElement*)element 
                      toArray:(NSMutableArray*)array
                     matching:(HGSTokenizedString *)queryString 
                pathCellArray:(NSArray *)pathCellArray {
  if (element) {
    NSArray *children 
      = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
    NSArray *placeHolderRoles = [NSArray arrayWithObjects:
                                 NSAccessibilityMenuRole, 
                                 NSAccessibilityMenuBarRole,
                                 nil];
    for (GTMAXUIElement *child in children) {
      NSString *role 
        = [child stringValueForAttribute:NSAccessibilityRoleAttribute];
      if ([placeHolderRoles containsObject:role]) {
        [self addResultsFromElement:child 
                            toArray:array 
                           matching:queryString 
                      pathCellArray:pathCellArray];
      } else {
        HGSScoredResult *result = [self resultFromElement:child
                                                     role:role
                                              queryString:queryString
                                            pathCellArray:pathCellArray];
        if (result) {
          [array addObject:result];
        }
      }
    }
  }
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  return [GTMAXUIElement isAccessibilityEnabled] 
    && [super isValidSourceForQuery:query];
}

- (void)performSearchOperation:(HGSCallbackSearchOperation *)operation {
  HGSResult *pivotObject = [[operation query] pivotObject];
  GTMAXUIElement *element
    = [pivotObject valueForKey:kAppUISourceAttributeElementKey];
  NSMutableArray *results = [NSMutableArray array];
  if (!element) {
    NSDictionary *appData = [self getAppInfoFromResult:pivotObject];
    if (appData) {
      NSNumber *pid 
        = [appData objectForKey:@"NSApplicationProcessIdentifier"];
      if (!pid) {
        pid = [appData objectForKey:@"pid"];
      }
      element = [GTMAXUIElement elementWithProcessIdentifier:[pid intValue]];
    }     
  }
  if (element) {
    HGSQuery* query = [operation query];
    HGSTokenizedString *queryString = [query tokenizedQueryString];
    if (pivotObject) {
      NSArray *pathCellArray 
        = [pivotObject valueForKey:kQSBObjectAttributePathCellsKey];
      if (!pathCellArray) {
        pathCellArray = [NSArray array];
      }
      [self addResultsFromElement:element 
                          toArray:results 
                         matching:queryString
                    pathCellArray:pathCellArray];
    } else {
      NSArray *pathCellArray = [NSArray array];
      [self addMenuResultsFromElement:element 
                              toArray:results 
                             matching:queryString
                        pathCellArray:pathCellArray];
    }      
  }
  [operation setRankedResults:results];
}

@end
