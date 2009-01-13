//
//  HGSMemorySearchSource.h
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

#import "HGSCallbackSearchSource.h"

@class HGSQuery;

// Subclass of HGSCallbackSearchSource that handles the search logic for simple
// sources that precompute all possible results and keep them in memory.
//
// When a query comes in, all matching items will be found, then passed through
// |processMatchingResults:forQuery:| and returned. The default implementation
// of that method does nothing, so by default results will be returned
// unchanged.
//
// HGSMemorySearchSource gets the base behavior for |pivotableTypes| and
// |isValidSourceForQuery:|, meaning it will support a query w/o a context
// object, but not match if there is a context (pivot) object.  Subclasses can
// override this method to support pivots.  When a query w/ a pivot w/o a search
// term comes in, all objects are returned as matches, meaning they all get sent
// to |processMatchingResults:forQuery:|, the subclass then has the
// responsibility to filter based on the pivot object.
@interface HGSMemorySearchSource : HGSCallbackSearchSource {
  NSMutableArray* resultsArray_;
 @private
  NSUInteger cacheHash_;
  NSString *cachePath_;
}

// Clear out the data currenting indexing w/in the source
- (void)clearResultIndex;

// Add a result to the memory index.  |nameString| are the words that count as
// name matches for |hgsResult|.  |otherString| are the words that can be used
// to match |hgsResult| but of less importance.  The two strings (|nameString|
// and |otherString|) will be properly broken into terms for the caller, so they
// don't need to worry about the details.  |otherString| can be nil since it's
// optional.
- (void)indexResult:(HGSObject*)hgsResult
         nameString:(NSString*)nameString
        otherString:(NSString*)otherString;
// Like the above, but takes an array of "other" strings.
- (void)indexResult:(HGSObject*)hgsResult
         nameString:(NSString*)nameString
  otherStringsArray:(NSArray*)otherStrings;

// Save the contents of the memory index to disk. If the contents of the index
// haven't changed since the last call to saveResultsCache or loadResultsCache,
// the write is skipped (although there is still a small amount of overhead
// in determining whether or not the index has changed). The usage pattern is
// to call saveResultsCache after each periodic or event-triggered indexing
// pass, and call loadResultsCache once at startup so that the previous
// index is immediately available, though perhaps a little stale.
- (void)saveResultsCache;

// Load the results saved by a previous call to saveResultsCache, populating
// the memory index (and overwriting any existing entries in the index).
- (void)loadResultsCache;
@end

// These are methods subclasses can override to control behaviors
@interface HGSMemorySearchSource (ProtectedMethods)

// Called after matching results are found, before the array is returned.
// |results| is an array of HGSObjects matching the query. The array and results
// may be modified in any way, but note that the result objects are references
// to the cached versions, not copies, so modifications to result objects that
// are not intended to be persistent should be made to a substituted copy.
- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query;

@end
