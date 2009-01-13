//
//  HGSSearchSource.h
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

#import "HGSExtension.h"

// kHGSValidateSearchSourceBehaviorsPrefKey is a boolean preference that the
// engine can use to enable extra logging about Source behaviors to help
// developers make sure their Source is acting right.  The pref should be set
// before launch to ensure it is all possible checks are done.
#define kHGSValidateSearchSourceBehaviorsPrefKey \
  @"HGSValidateSearchSourceBehaviors"


@class HGSObject;
@class HGSQuery;
@class HGSSearchOperation;

//
// HGSSearchSource
//
// An abstraction for searching a particular collection of data. There will be
// many search sources that provide results to a query and the results of a 
// given search source may span many result types. 
//

@protocol HGSSearchSource <HGSExtension>

// Returns the list of types this source can do a pivot search on.
// Return a set of @"*" to pivot on any object.
- (NSSet *)pivotableTypes;

// Returns whether this source is valid for the query string/terms.
- (BOOL)isValidSourceForQuery:(HGSQuery *)query;

// Query Flow:
// If the query has a pivot object, the calling code will check if the
// source handles that type for pivots (|pivotableTypes|).  Then the calling
// code will call |isValidSourceForQuery:| to perform any other validation.  If
// all of those pass, then |searchOperationForQuery:| gets called.

// Returns an operation to search this source for |query| and posts notifs 
// to |observer|. Sources can override this factory method to return something
// that holds state specific to the source.
- (HGSSearchOperation *)searchOperationForQuery:(HGSQuery *)query;

// allows a Search Source the ability to add more information to a result. This
// is different from merging two results together because they're duplicates in
// that the query that generated |result| in another source may not have any 
// results in this source, but the full result as presented here may carry with 
// it enough info to allows this source to find a match and annotate it with 
// extra data.
- (void)annotateObject:(HGSObject *)object withQuery:(HGSQuery *)query;

// allows a Search Sources to claim a set of file UTIs that should be ignored
// by any sources that walk file systems because this source is returning them
// through other means.  This allows a source to prevent something like a
// Spotlight based source from returning the MetaData files normally used by
// Spotlight.
// NOTES:
//   - this can not change over time as callers are allowed to cache the value
//     for the lifetime of the app for performance reasons.
//   - this can be called on any thread, so keep that in mind for a sources
//     implementation.
- (NSSet *)utisToExcludeFromDiskSources;

// Fetch the actual value. This returns value. In some cases you will get a
// temp value that will be updated in the future via KVO.
- (id)provideValueForKey:(NSString*)key result:(HGSObject*)result;

// Supports archiving something for the source to allow the result to be
// remembered in shortcuts.  Return nil to avoid your objects being archivable.
// Simply store the key/value pars in the dict you need to recreate your object.
- (NSMutableDictionary *)archiveRepresentationForObject:(HGSObject*)object;
- (HGSObject *)objectWithArchivedRepresentation:(NSDictionary *)representation;

@end

// The HGSSearchSource class is provided as a convenience class for people doing
// simple sources. People may want to use the protocol if they prefer to reuse
// some existing class without subclassing.

@interface HGSSearchSource : HGSExtension <HGSSearchSource> {
 @protected
  NSSet *pivotableTypes_;
  NSSet *utiToExcludeFromDiskSources_;
  BOOL cannotArchive_;
}

// The defaults for the apis in the protocol are as follow:
//
//   -pivotableTypes
//      nil or the value of "HGSSearchSourcePivotTypes" from config dict.
//   -isValidSourceForQuery:
//      YES if there's a pivot or if -[HGSQuery uniqueWords] returns a
//      set of one or more items.
//   -utisToExcludeFromDiskSources
//      nil or the value of "HGSSearchSourceUTIsToExcludeFromDiskSources" from
//      config dict.
//   -provideValueForKey:result:
//      returns nil
//   -archiveRepresentationForObject:
//   -objectWithArchivedRepresentation:
//      These return a dictionary w/ the name, URI, type, snippet, and details
//      so they are saved and the object is receated w/ those attributes.  If
//      the config dict has the boolean "HGSSearchSourceCannotArchive" set to
//      YES, this will return nil instead (blocking archiving).

@end
