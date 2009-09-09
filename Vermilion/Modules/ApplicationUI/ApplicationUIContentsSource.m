//
//  ApplicationUIContentsSource.m
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
#import "QSBHGSDelegate.h"
#import "GTMNSWorkspace+Running.h"
#import "GTMNSNumber+64Bit.h"
#import "GTMMethodCheck.h"

// Turns out the Finder has a couple of places with recursive
// accessibility references. 10 should be deep enough for most cases.
const NSUInteger kApplicationUIContentsSourceMaximumRecursion = 10;

@interface ApplicationUIContentsSource : HGSCallbackSearchSource {
 @private
  NSImage *windowIcon_;  // STRONG
}
@end

@implementation ApplicationUIContentsSource

GTM_METHOD_CHECK(NSNumber, gtm_numberWithCGFloat:);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    NSBundle *bundle = HGSGetPluginBundle();
    NSString *path = [bundle pathForResource:@"window" ofType:@"icns"];
    HGSAssert(path, @"Icons for 'window' are missing from the "
              @"ApplicationUIContentsSource bundle.");
    windowIcon_ = [[NSImage alloc] initByReferencingFile:path];
  }
  return self;
}

- (void)dealloc {
  [windowIcon_ release];
  [super dealloc];
}

- (BOOL)addResultsForQuery:(HGSSearchOperation *)operation 
              fromElements:(NSArray *)elements
                fromWindow:(GTMAXUIElement *)window
                   toArray:(NSMutableArray *)results 
            recursionDepth:(NSUInteger)depth {
  if (depth > kApplicationUIContentsSourceMaximumRecursion) return NO;
  HGSQuery *query = [operation query];
  NSString *normalizedQuery = [query normalizedQueryString];
  BOOL addedElement = NO;
  for (GTMAXUIElement *element in elements) {
    if ([operation isCancelled]) return NO;
    id value 
      = [element accessibilityAttributeValue:NSAccessibilityVisibleCharacterRangeAttribute];
    if (value) {
      value 
        = [element accessibilityAttributeValue:NSAccessibilityStringForRangeParameterizedAttribute 
                                  forParameter:value];
    }
    if (!value) {
      [element accessibilityAttributeValue:NSAccessibilityValueAttribute];
    }
    if (!(value && [value isKindOfClass:[NSString class]])) {
      value = [element accessibilityAttributeValue:NSAccessibilityTitleAttribute];
    } 
    if (value) {
      NSString *normalizedValue = [HGSTokenizer tokenizeString:value];
      CGFloat rank = HGSScoreTermForItem(normalizedQuery, normalizedValue, NULL);
      if (rank > 0) {
        NSString *name 
          = [window stringValueForAttribute:NSAccessibilityTitleAttribute];
        if ([name length] == 0) continue;
        NSString *nameString 
          = [name stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        NSString *uriString 
          = [NSString stringWithFormat:@"AppUISource://%@/%p", 
             nameString, window];
        NSNumber *nsRank = [NSNumber gtm_numberWithCGFloat:rank];
        NSDictionary *attributes
          = [NSDictionary dictionaryWithObjectsAndKeys:
             window, kAppUISourceAttributeElementKey, 
             windowIcon_, kHGSObjectAttributeIconKey,
             nsRank, kHGSObjectAttributeRankKey,
             nil];
        HGSResult *result 
          = [HGSResult resultWithURI:uriString
                                name:name
                                type:kHGSTypeAppUIItem
                              source:self
                          attributes:attributes];
        [results addObject:result];
        addedElement = YES;
        break;
      }
    }
    if (!addedElement) {
      id role = [element accessibilityAttributeValue:NSAccessibilityRoleAttribute];
      if ([role isEqualToString:@"AXFinderItem"]) {
        // we never want to descend into AXFinderItems due to radar
        // 6351511 Path control in finder is recursive when viewed with 
        //         accessibility inspector
        // 6328465 AXFinderItem returns recursive AXChildren
        continue;
      }
      id children 
        = [element accessibilityAttributeValue:NSAccessibilityVisibleRowsAttribute];
      if (!children) {
        children 
          = [element accessibilityAttributeValue:NSAccessibilityVisibleChildrenAttribute];
      }
      if (!children) {
        children 
          = [element accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
      }
      if (children) {
        addedElement = [self addResultsForQuery:operation 
                                   fromElements:children 
                                     fromWindow:window 
                                        toArray:results
                                 recursionDepth:depth + 1];
      }
    } 
    if (addedElement) {
      break;
    }
  }
  return addedElement;
}

- (void)addResultsForQuery:(HGSSearchOperation *)operation
                fromWindow:(GTMAXUIElement *)window
                   toArray:(NSMutableArray *)results {
  id children 
    = [window accessibilityAttributeValue:NSAccessibilityVisibleChildrenAttribute];
  if (!children) {
    children 
      = [window accessibilityAttributeValue:NSAccessibilityChildrenAttribute];
  }
  if (children) {
    [self addResultsForQuery:operation 
                fromElements:children 
                  fromWindow:window 
                     toArray:results
              recursionDepth:0];
  }
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  return [GTMAXUIElement isAccessibilityEnabled]
    && [super isValidSourceForQuery:query];
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSArray *apps = [[NSWorkspace sharedWorkspace] gtm_launchedApplications];
  pid_t mypid = getpid();
  NSMutableArray *results = [NSMutableArray array];
  for (NSDictionary *appInfo in apps) {
    NSNumber *nspid = [appInfo objectForKey:@"NSApplicationProcessIdentifier"];
    if (nspid) {
      pid_t pid = [nspid intValue];
      if (pid != mypid) {
        GTMAXUIElement *appElement 
          = [GTMAXUIElement elementWithProcessIdentifier:pid];
        NSArray *windows 
          = [appElement accessibilityAttributeValue:NSAccessibilityWindowsAttribute];
        if (windows) {
          for (GTMAXUIElement *window in windows) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            [self addResultsForQuery:operation
                          fromWindow:window
                             toArray:results];
            [pool release];
            if ([operation isCancelled]) return;
          }
        }
      }
    }
  }
  [operation setResults:results];
}
   
- (id)provideValueForKey:(NSString*)key result:(HGSResult*)result {
  id value = nil;
  GTMAXUIElement *element 
    = [result valueForKey:kAppUISourceAttributeElementKey];
  if (element) {
    if ([key isEqualToString:kHGSObjectAttributeDefaultActionKey]) {
      value = [ApplicationUIAction defaultActionForElement:element];
    } else if ([key isEqualToString:kQSBObjectAttributePathCellsKey]) {
      // TODO(dmaclach): Build up the path cells for the element
    }
  }
  if (!value) {
    value = [super provideValueForKey:key result:result];
  }
  return value;
}

@end
