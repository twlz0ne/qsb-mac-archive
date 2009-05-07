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

/*!
 @header
 @discussion
*/

@class HGSQuery;

/*!
 Subclass of HGSCallbackSearchSource that handles the search logic for simple
 sources that precompute all possible results and keep them in memory.

 When a query comes in, all matching items will be found, then passed through
 |processMatchingResults:forQuery:| and returned. The default implementation
 of that method does nothing, so by default results will be returned
 unchanged.

 HGSMemorySearchSource gets the base behavior for |pivotableTypes| and
 |isValidSourceForQuery:|, meaning it will support a query without a context
 object, but not match if there is a context (pivot) object.  Subclasses can
 override this method to support pivots.  When a query with a pivot without a 
 search term comes in, all objects are returned as matches, meaning they all get 
 sent to |processMatchingResults:forQuery:|, the subclass then has the
 responsibility to filter based on the pivot object.
*/
@interface HGSMemorySearchSource : HGSCallbackSearchSource {
 @private
  NSMutableArray* resultsArray_;
  NSUInteger cacheHash_;
  NSString *cachePath_;
}

/*! Clear out the data currenting indexing w/in the source. */
- (void)clearResultIndex;

/*!
 Add a result to the memory index.
 
 The two strings (name and otherTerm) will be properly tokenized for the caller, 
 so pass them in as raw unnormalized, untokenized strings.
 @param hgsResult the result to index
 @param name are the words that count as name matches for hgsResult. 
 @param otherTerm is another term that can be used to match hgsResult but is
        of less importance than name. This argument is optional and can be nil.
*/
- (void)indexResult:(HGSResult *)hgsResult
               name:(NSString *)name
          otherTerm:(NSString *)otherTerm;
/*!
 Add a result to the memory index. 
 
 The strings (name and otherTerms) will be properly tokenized for the caller, 
 so pass them in as raw unnormalized, untokenized strings.
 @param hgsResult the result to index
 @param name are the words that count as name matches for hgsResult. 
 @param otherTerms is an array of terms that can be used to match hgsResult but 
 are of less importance than name. This argument is optional and can be nil.
*/
- (void)indexResult:(HGSResult *)hgsResult
               name:(NSString *)name
         otherTerms:(NSArray *)otherTerms;
/*!
 Add a result to the memory index. 
 Equivalent to calling 
 @link indexResult:name:otherTerm: indexResult:name:otherTerm: @/link
 with name set to the displayName of the hgsResult, and nil for otherTerm. 
 @param hgsResult the result to index
*/
- (void)indexResult:(HGSResult *)hgsResult;
/*!
 Save the contents of the memory index to disk. If the contents of the index
 haven't changed since the last call to saveResultsCache or loadResultsCache,
 the write is skipped (although there is still a small amount of overhead
 in determining whether or not the index has changed). The usage pattern is
 to call saveResultsCache after each periodic or event-triggered indexing
 pass, and call loadResultsCache once at startup so that the previous
 index is immediately available, though perhaps a little stale.
 @seealso //google_vermilion_ref/occ/instm/HGSMemorySearchSource/loadResultsCache loadResultsCache
*/
- (void)saveResultsCache;
/*!
 Load the results saved by a previous call to 
 saveResultsCache, populating
 the memory index (and overwriting any existing entries in the index).
 @result Returns yes if anything was loaded into the cache.
 @seealso //google_vermilion_ref/occ/instm/HGSMemorySearchSource/saveResultsCache saveResultsCache
*/
- (BOOL)loadResultsCache;
@end

/*! These are methods subclasses can override to control behaviors. */
@interface HGSMemorySearchSource (ProtectedMethods)

/*!
 Called after matching results are found, before the array is returned.
 The array and results in the array may be modified in any way.
 @param results is an array of HGSObjects matching the query. 
 @param query is the query that the results matched to.
*/
- (void)processMatchingResults:(NSMutableArray*)results
                      forQuery:(HGSQuery *)query;

@end
