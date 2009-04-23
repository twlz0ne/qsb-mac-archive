//
//  ActionSource.m
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

//
// ActionSource
//
// Implements a SearchSource for finding actions in both the global and
// pivoted context

static NSString * const kActionIdentifierArchiveKey = @"ActionIdentifier";

// When an action is selected directly from the UI as a "sub object" of a pivot
// we want it to apply to the pivot object. By wrapping it in an
// ActionPivotObjectProxy it will act exactly like the action it wraps
// EXCEPT when invoked it will pass the pivot object from the predicate_
// into the action as it's direct object.
// See -[ActionPivotObjectProxy performActionWithInfo] for details.
@interface ActionPivotObjectProxy : NSProxy {
 @private
  HGSAction *action_;
  HGSQuery *query_;
}
- (id)initWithAction:(HGSAction *)action
               query:(HGSQuery *)query;
@end

@interface ActionSource : HGSMemorySearchSource {
 @private
  BOOL rebuildCache_;
}
- (void)extensionPointActionsChanged:(NSNotification*)notification;
- (void)collectActions;
@end

@implementation ActionSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    rebuildCache_ = YES;
    NSNotificationCenter *dc = [NSNotificationCenter defaultCenter];
    HGSExtensionPoint *actionsPoint = [HGSExtensionPoint actionsPoint];
    [dc addObserver:self
           selector:@selector(extensionPointActionsChanged:)
               name:kHGSExtensionPointDidAddExtensionNotification
             object:actionsPoint];
    [dc addObserver:self
           selector:@selector(extensionPointActionsChanged:)
               name:kHGSExtensionPointDidRemoveExtensionNotification
             object:actionsPoint];
  }
  return self;
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

#pragma mark -

- (void)extensionPointActionsChanged:(NSNotification*)notification {
  // Since the notifications can come in baches as we load things (and if/when
  // we support enable/disable they too could come in batches), we set a flag
  // and rebuild it next time it's needed.
  rebuildCache_ = YES;
}

- (HGSResult *)objectFromAction:(HGSAction *)action 
                    resultArray:(HGSResultArray *)array {
  // Set some of the flags to bump them up in the result's ranks
  NSNumber *rankFlags 
    = [NSNumber numberWithUnsignedInt:eHGSLaunchableRankFlag 
       | eHGSSpecialUIRankFlag 
       | eHGSUnderHomeRankFlag 
       | eHGSHomeChildRankFlag];
  NSMutableDictionary *attributes 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       rankFlags, kHGSObjectAttributeRankFlagsKey,
       action, kHGSObjectAttributeDefaultActionKey,
       nil];
  NSImage *icon = [action displayIconForResults:array];
  if (icon) {
    [attributes setObject:icon forKey:kHGSObjectAttributeIconKey];
  }
  NSString *name = [action displayNameForResults:nil];
  NSString *extensionIdentifier = [action identifier];
  NSString *urlStr = [NSString stringWithFormat:@"action:%@", extensionIdentifier];
  
  HGSResult *actionObject
    = [HGSResult resultWithURL:[NSURL URLWithString:urlStr]
                          name:name
                          type:kHGSTypeAction
                        source:self
                    attributes:attributes];

  return actionObject;
}

- (void)collectActions {
  rebuildCache_ = NO;
  [self clearResultIndex];

  HGSExtensionPoint* actionPoint = [HGSExtensionPoint actionsPoint];
  for (HGSAction *action in [actionPoint extensions]) {
    // Create a result object that wraps our action
    HGSResult *actionObject = [self objectFromAction:action
                                         resultArray:nil];
    // Index our result
    [self indexResult:actionObject];
  }
}

#pragma mark -

- (NSMutableDictionary *)archiveRepresentationForResult:(HGSResult*)result {
  // For action results, we pull out the action, and save off it's extension
  // identifier.
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  HGSAction *action = [result valueForKey:kHGSObjectAttributeDefaultActionKey];
  NSString *extensionIdentifier = [action identifier];
  if (extensionIdentifier) {
    [dict setObject:extensionIdentifier forKey:kActionIdentifierArchiveKey];
  }
  return dict;
}

- (HGSResult *)resultWithArchivedRepresentation:(NSDictionary *)representation {
  HGSResult *result = nil;
  NSString *extensionIdentifier
    = [representation objectForKey:kActionIdentifierArchiveKey];
  if (extensionIdentifier) {
    HGSExtensionPoint* actionPoint = [HGSExtensionPoint actionsPoint];
    HGSAction *action
      = [actionPoint extensionWithIdentifier:extensionIdentifier];
    if (action) {
      // We create a new result, but it should fold based out the url
      result = [self objectFromAction:action
                          resultArray:nil];
    }
  }
  
  return result;
}

#pragma mark -

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  // Recollect things on demand
  if (rebuildCache_) {
    [self collectActions];
  }
  [super performSearchOperation:operation];
}

- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query {
  NSMutableArray *filteredResults
    = [NSMutableArray arrayWithCapacity:[results count]];

  
  HGSResultArray *queryResults = [query results];
  if (queryResults) {
    BOOL emptyQuery = [[query rawQueryString] length] == 0;
    
    // Pivot: filter to actions that support this object as the target of the
    // action.
    for (HGSResult *actionObject in results) {
      HGSAction *action
        = [actionObject valueForKey:kHGSObjectAttributeDefaultActionKey];
      if ([action appliesToResults:queryResults]) {
        // Now that it is all set up, let's wrap it up in our proxy action.
        // We do this so that we can sub in the query's pivot object
        // when our action is called.
        ActionPivotObjectProxy *proxy 
          = [[[ActionPivotObjectProxy alloc] initWithAction:action
                                                      query:query]
             autorelease];
        
        actionObject = [self objectFromAction:(HGSAction *)proxy
                                  resultArray:queryResults];
        
        if (emptyQuery) {
          HGSMutableResult *mutable = [[actionObject mutableCopy] autorelease];
          [mutable addRankFlags:eHGSBelowFoldRankFlag];
          actionObject = mutable;
        }
        
        [filteredResults addObject:actionObject];
      }
    }

  } else {

    // No pivot: so just include the actions that are valid for a top level
    // query.
    for (HGSResult *actionObject in results) {
      HGSAction *action
        = [actionObject valueForKey:kHGSObjectAttributeDefaultActionKey];
      if ([action showInGlobalSearchResults]) {
        [filteredResults addObject:actionObject];
      }
    }
  }

  [results setArray:filteredResults];
}

@end

@implementation ActionPivotObjectProxy
- (id)initWithAction:(HGSAction *)action
               query:(HGSQuery *)query {
  action_ = [action retain];
  query_ = [query retain];
  return self;
}
 
- (void)dealloc {
  [action_ release];
  [query_ release];
  [super dealloc];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
  [invocation invokeWithTarget:action_];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
  return [action_ methodSignatureForSelector:sel];
}

- (BOOL)performWithInfo:(NSDictionary*)info {
  // We sub in the pivot object as the primary object, ignoring whatever
  // info we got from above.
  HGSResultArray *directObjects = [query_ results];
  NSDictionary *newInfo 
    = [NSDictionary dictionaryWithObject:directObjects
                                  forKey:kHGSActionDirectObjectsKey];
  return [action_ performWithInfo:newInfo];
}


@end
