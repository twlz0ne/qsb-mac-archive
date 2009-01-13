//
//  HGSSearchSource.mm
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

#import "HGSSearchSource.h"
#import "HGSObject.h"
#import "HGSQuery.h"
#import "HGSLog.h"

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

@implementation HGSSearchSource

+ (void)initialize {
  if (self == [HGSSearchSource class]) {
#if DEBUG
    NSNumber *validateBehaviors = [NSNumber numberWithBool:YES];
#else
    NSNumber *validateBehaviors = [NSNumber numberWithBool:NO];
#endif
    NSDictionary *dict
      = [NSDictionary dictionaryWithObject:validateBehaviors
                                    forKey:kHGSValidateSearchSourceBehaviorsPrefKey];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults registerDefaults:dict];
  }
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {

    id value = [configuration objectForKey:@"HGSSearchSourcePivotableTypes"];
    pivotableTypes_ = CopyStringSetFromId(value);

    value
      = [configuration objectForKey:@"HGSSearchSourceUTIsToExcludeFromDiskSources"];
    utiToExcludeFromDiskSources_ = CopyStringSetFromId(value);
    
    value = [configuration objectForKey:@"HGSSearchSourceCannotArchive"];
    cannotArchive_ = [value boolValue];
  }
  return self;
}

- (void)dealloc {
  [pivotableTypes_ release];
  [utiToExcludeFromDiskSources_ release];

  [super dealloc];
}

- (NSSet *)pivotableTypes {
  return [[pivotableTypes_ retain] autorelease];
}

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  // Must have a pivot or something we parse as a word
  BOOL isValid = (([query pivotObject] != nil) ||
                  ([[query uniqueWords] count] > 0));
  return isValid;
}

- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query {  
  // subclasses must provide a search op
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  if ([defaults boolForKey:kHGSValidateSearchSourceBehaviorsPrefKey]) {
    HGSLog(@"ERROR: Source %@ forgot to override searchOperationForQuery:.",
           [self class]);
  }
  [self doesNotRecognizeSelector:_cmd];
  return nil;  // COV_NF_LINE
}

// allows a Search Source the ability to add more information to a result. This
// is different from merging two results together because they're duplicates in
// that the query that generated |result| in another source may not have any results in
// this source, but the full result as presented here may carry with it enough info
// to allows this source to find a match and annotate it with extra data.
- (void)annotateObject:(HGSObject*)result withQuery:(HGSQuery*)query{
  // default does nothing, subclasses do not have to override. 
}

- (NSSet *)utisToExcludeFromDiskSources {
  return [[utiToExcludeFromDiskSources_ retain] autorelease];
}

- (id)provideValueForKey:(NSString*)key result:(HGSObject*)result {
  return nil;
}

- (NSMutableDictionary *)archiveRepresentationForObject:(HGSObject*)result {
  // Do we allow archiving?
  if (cannotArchive_) return nil;
  
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  NSString *kHGSObjectDefaultArchiveKeys[] = {
    kHGSObjectAttributeNameKey,
    kHGSObjectAttributeURIKey,
    kHGSObjectAttributeTypeKey,
    kHGSObjectAttributeSnippetKey,
    kHGSObjectAttributeSourceURLKey,
  };
  
  for (size_t i = 0;
       i < (sizeof(kHGSObjectDefaultArchiveKeys) / sizeof(NSString*));
       ++i) {
    NSString *key = kHGSObjectDefaultArchiveKeys[i];
    id value = [result valueForKey:key];
    if (value) {
      [dict setObject:value forKey:key];
    }
  }
  return dict;
}

- (HGSObject *)objectWithArchivedRepresentation:(NSDictionary *)representation {
  // Do we allow archiving?
  if (cannotArchive_) return nil;

  return [HGSObject objectWithDictionary:representation source:self];
}

@end
