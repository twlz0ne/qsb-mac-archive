//
//  HGSActionArgument.m
//
//  Copyright (c) 2010 Google Inc. All rights reserved.
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

#import "HGSActionArgument.h"
#import "HGSTypeFilter.h"
#import "HGSBundle.h"
#import "HGSExtension.h"

NSString* const kHGSActionArgumentSupportedTypesKey 
  = @"HGSActionArgumentSupportedTypes";
NSString* const kHGSActionArgumentUnsupportedTypesKey
  = @"HGSActionArgumentUnsupportedTypes";
NSString* const kHGSActionArgumentOptionalKey = @"HGSActionArgumentOptional";
NSString* const kHGSActionArgumentOtherTermsKey = @"HGSActionArgumentOtherTerms";
NSString* const kHGSActionArgumentNameKey = @"HGSActionArgumentName";
NSString* const kHGSActionArgumentDescriptionKey 
  = @"HGSActionArgumentDescription";

@implementation HGSActionArgument

@synthesize optional = optional_;
@synthesize name = name_;
@synthesize localizedName = localizedName_;
@synthesize typeFilter = typeFilter_;
@synthesize localizedDescription = localizedDescription_;
@synthesize localizedOtherTerms = localizedOtherTerms_;

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super init])) {
    NSBundle *bundle = HGSGetPluginBundle();
    optional_ 
      = [[configuration valueForKey:kHGSActionArgumentOptionalKey] boolValue];

    name_ = [[configuration valueForKey:kHGSActionArgumentNameKey] retain];
    localizedName_ = [[bundle localizedStringForKey:name_ 
                                              value:@"" 
                                              table:nil] retain];
    localizedDescription_ 
      = [configuration valueForKey:kHGSActionArgumentDescriptionKey];

    // We don't use HGSLocalizedString because the macro is designed to be
    // used with a string constant so that it can be used with 'genstrings'.
    localizedDescription_ = [[bundle localizedStringForKey:localizedDescription_ 
                                                     value:@"" 
                                                     table:nil] retain];
    
    id value = [configuration objectForKey:kHGSActionArgumentOtherTermsKey];
    NSSet *otherTerms = [NSSet setFromId:value];
    NSMutableSet *localizedOtherTerms 
      = [[NSMutableSet alloc] initWithCapacity:[otherTerms count]];
    for (NSString *term in otherTerms) {
      // We don't use HGSLocalizedString because the macro is designed to be
      // used with a string constant so that it can be used with 'genstrings'.
      NSString *localizedTerm = [bundle localizedStringForKey:term 
                                                        value:@"" 
                                                        table:nil];
      [localizedOtherTerms addObject:localizedTerm];
    }
    
    value = [configuration objectForKey:kHGSActionArgumentSupportedTypesKey];
    NSSet *supportedTypes = [NSSet setFromId:value];
    
    value = [configuration objectForKey:kHGSActionArgumentUnsupportedTypesKey];
    NSSet *unsupportedTypes = [NSSet setFromId:value];
    
    if (supportedTypes || unsupportedTypes) {
      typeFilter_ 
        = [[HGSTypeFilter alloc] initWithConformTypes:supportedTypes 
                                  doesNotConformTypes:unsupportedTypes];
    }
  }
  return self;
}

- (void)dealloc {
  [name_ release];
  [localizedName_ release];
  [typeFilter_ release];
  [localizedDescription_ release];
  [localizedOtherTerms_ release];
  [super dealloc];
}

@end


