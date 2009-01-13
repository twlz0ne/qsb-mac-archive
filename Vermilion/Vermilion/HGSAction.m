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
#import "HGSObject.h"
#import "HGSLog.h"

NSString* const kHGSActionPrimaryObjectKey = @"HGSActionPrimaryObject";
NSString* const kHGSActionIndirectObjectKey = @"HGSActionIndirectObject";

// The result is already retained for you
static NSSet *CopyStringSetFromId(id value) {
  if (!value) return nil;
  
  NSSet *result = nil;
  if ([value isKindOfClass:[NSString class]]) {
    result = [[NSSet alloc] initWithObjects:value, nil];
  } else if ([value isKindOfClass:[NSArray class]]) {
    result = [[NSSet alloc] initWithArray:value];
  } else if ([value isKindOfClass:[NSSet class]]) {
    result = [value copy];
  }
  return result;
}

@implementation HGSAction

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
    
    id value = [configuration objectForKey:@"HGSActionDirectObjectTypes"];
    directObjectTypes_ = CopyStringSetFromId(value);
    
    value = [configuration objectForKey:@"HGSActionIndirectObjectTypes"];
    indirectObjectTypes_ = CopyStringSetFromId(value);
    
    value = [configuration objectForKey:@"HGSActionIndirectObjectOptional"];
    // Default is NO, so just call boolValue on nil
    indirectObjectOptional_ = [value boolValue];
    
    value = [configuration objectForKey:@"HGSActionShowActionInGlobalSearchResults"];
    // Default is NO, so just call boolValue on nil
    showActionInGlobalSearchResults_ = [value boolValue];
    
    value = [configuration objectForKey:@"HGSActionDoesActionCauseUIContextChange"];
    // Default is YES, so only call boolValue if it's non nil.
    if (value) {
      doesActionCauseUIContextChange_ = [value boolValue];
    } else {
      doesActionCauseUIContextChange_ = YES;
    }
  }
  return self;
}

- (void)dealloc {
  [directObjectTypes_ release];
  [indirectObjectTypes_ release];
  
  [super dealloc];
}

- (NSSet*)directObjectTypes {
  return [[directObjectTypes_ retain] autorelease];
}

- (NSSet*)indirectObjectTypes {
  return [[indirectObjectTypes_ retain] autorelease];
}

- (BOOL)isIndirectObjectOptional {
  return indirectObjectOptional_;
}

- (BOOL)doesActionApplyTo:(HGSObject*)result {
  return YES;
}

- (BOOL)showActionInGlobalSearchResults {
  return showActionInGlobalSearchResults_;
}

- (BOOL)doesActionCauseUIContextChange {
  return doesActionCauseUIContextChange_;
}

- (NSString*)displayNameForResult:(HGSObject*)result {
  // defaults to just our name
  return [self name];
}

- (id)displayIconForResult:(HGSObject*)result {
  // default to our init icon
  return [self icon];
}

// Subclasses should override to perform the action. Actions can have either one
// or two objects. If only one is present, it should act as "noun verb" such as
// "file open". If there are two it should behave as "noun verb noun" such as
// "file 'email to' hasselhoff" with the 2nd being the indirect object.
- (BOOL)performActionWithInfo:(NSDictionary*)info {
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:kHGSValidateActionBehaviorsPrefKey]) {
    HGSLog(@"ERROR: Action %@ forgot to override performActionWithInfo:.",
           [self class]);
  }
  [self doesNotRecognizeSelector:_cmd];
  return NO;  // COV_NF_LINE
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@<%p> name:%@", 
          [self class], self, [self name]];
}
@end
