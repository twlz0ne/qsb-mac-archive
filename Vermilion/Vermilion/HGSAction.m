//
//  HGSAction.m
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

#import "HGSAction.h"
#import "HGSResult.h"
#import "HGSLog.h"

NSString *const kHGSActionDirectObjectsKey = @"HGSActionDirectObjects";
NSString *const kHGSActionIndirectObjectsKey = @"HGSActionIndirectObjects";
NSString *const kHGSActionDirectObjectTypesKey = @"HGSActionDirectObjectTypes";
NSString *const kHGSActionIndirectObjectTypesKey 
  = @"HGSActionIndirectObjectTypes";
NSString *const kHGSActionIndirectObjectOptionalKey 
  = @"HGSActionIndirectObjectOptional";
NSString *const kHGSActionDoesActionCauseUIContextChangeKey
  = @"HGSActionDoesActionCauseUIContextChange";
NSString *const kHGSActionMustRunOnMainThreadKey
  = @"HGSActionMustRunOnMainThread";
NSString* const kHGSActionOtherTermsKey
  = @"HGSActionOtherTerms";

// The result is already retained for you
static NSSet *CopyStringSetFromId(id value) {  
  NSSet *result = nil;
  if (!value) {
    result = nil;
  } else if ([value isKindOfClass:[NSString class]]) {
    result = [[NSSet alloc] initWithObjects:value, nil];
  } else if ([value isKindOfClass:[NSArray class]]) {
    result = [[NSSet alloc] initWithArray:value];
  } else if ([value isKindOfClass:[NSSet class]]) {
    result = [value copy];
  }
  return result;
}

@implementation HGSAction

@synthesize directObjectTypes = directObjectTypes_;
@synthesize indirectObjectTypes = indirectObjectTypes_;
@synthesize indirectObjectOptional = indirectObjectOptional_;
@synthesize causesUIContextChange = causesUIContextChange_;
@synthesize mustRunOnMainThread = mustRunOnMainThread_;
@synthesize otherTerms = otherTerms_;

+ (void)initialize {
  if (self == [HGSAction class]) {
#if DEBUG
    NSNumber *validateBehaviors = [NSNumber numberWithBool:YES];
#else
    NSNumber *validateBehaviors = [NSNumber numberWithBool:NO];
#endif
    NSDictionary *dict
      = [NSDictionary dictionaryWithObject:validateBehaviors
                                    forKey:kHGSValidateActionBehaviorsPrefKey];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:dict];
  }
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    
    id value = [configuration objectForKey:kHGSActionDirectObjectTypesKey];
    directObjectTypes_ = CopyStringSetFromId(value);
    
    value = [configuration objectForKey:kHGSActionIndirectObjectTypesKey];
    indirectObjectTypes_ = CopyStringSetFromId(value);
    
    value = [configuration objectForKey:kHGSActionIndirectObjectOptionalKey];
    // Default is NO, so just call boolValue on nil
    indirectObjectOptional_ = [value boolValue];
  
    value = [configuration objectForKey:kHGSActionOtherTermsKey];
    otherTerms_ = CopyStringSetFromId(value);
    
    value 
      = [configuration objectForKey:kHGSActionDoesActionCauseUIContextChangeKey];
    // Default is YES, so only call boolValue if it's non nil.
    if (value) {
      causesUIContextChange_ = [value boolValue];
    } else {
      causesUIContextChange_ = YES;
    }
    
    value = [configuration objectForKey:kHGSActionMustRunOnMainThreadKey];
    if (value) {
      mustRunOnMainThread_ = [value boolValue];
    } else {
      mustRunOnMainThread_ = NO;
    }
  }
  return self;
}

- (void)dealloc {
  [directObjectTypes_ release];
  [indirectObjectTypes_ release];
  
  [super dealloc];
}

- (BOOL)appliesToResults:(HGSResultArray *)results {
  BOOL doesApply = YES;
  NSSet *directObjectTypes = [self directObjectTypes];
  
  if (!directObjectTypes) {
    // must be global only action
    doesApply = NO;
  } else {
    NSSet *allTypes = [NSSet setWithObject:@"*"];
    if (![directObjectTypes isEqual:allTypes] &&
        ![results conformsToTypeSet:directObjectTypes]) {
      // not a valid type for this action
      doesApply = NO;
    }
  }
  if (doesApply) {
    for (HGSResult *result in results) {
      doesApply = [self appliesToResult:result];
      if (!doesApply) break;
    }
  }
  return doesApply;
}

- (BOOL)appliesToResult:(HGSResult *)result {
  return YES;
}

- (NSString*)displayNameForResults:(HGSResultArray *)result {
  // defaults to just our name
  return [self displayName];
}

- (NSString *)defaultIconName {
  return @"red-gear";
}

- (id)displayIconForResults:(HGSResultArray *)result {
  // default to our init icon
  return [self icon];
}

- (BOOL)showInGlobalSearchResults {
  return [self directObjectTypes] == nil;
}

// Subclasses should override to perform the action. Actions can have either one
// or two objects. If only one is present, it should act as "noun verb" such as
// "file open". If there are two it should behave as "noun verb noun" such as
// "file 'email to' hasselhoff" with the 2nd being the indirect object.
- (BOOL)performWithInfo:(NSDictionary*)info {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:kHGSValidateActionBehaviorsPrefKey]) {
    HGSLog(@"ERROR: Action %@ forgot to override performWithInfo:.",
           [self class]);
  }
  [self doesNotRecognizeSelector:_cmd];
  return NO;  // COV_NF_LINE
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@<%p> name:%@", 
          [self class], self, [self displayName]];
}
@end
