//
//  SLFilesSource.h
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

@class SLFilesOperation;

@interface SLFilesSource : HGSSearchSource {
 @private
  NSString *utiFilter_;
  BOOL rebuildUTIFilter_;
  NSArray *attributeArray_;
}
@property (readonly, nonatomic) NSArray *attributeArray;

- (void)operationReceivedNewResults:(SLFilesOperation*)operation
                   withNotification:(NSNotification*)notification;
- (HGSResult *)hgsResultFromQueryItem:(MDItemRef)item 
                            operation:(SLFilesOperation *)operation;
- (void)operationCompleted:(SLFilesOperation*)operation;
- (void)startSearchOperation:(HGSSearchOperation*)operation;
- (void)extensionPointSourcesChanged:(NSNotification*)notification;
@end

#pragma mark -

@interface SLFilesOperation : HGSSearchOperation {
 @private
  NSMutableArray* accumulatedResults_;
  CFIndex nextQueryItemIndex_;
  BOOL mdQueryFinished_;
}

// Runs |query|
- (void)runMDQuery:(MDQueryRef)query;

// Using an accumulator rather than using setResults: directly allows us to
// control the timing of propagation of results to observers.
- (NSMutableArray*)accumulatedResults;

// Callbacksfor MDQuery updates
- (void)queryNotification:(NSNotification*)notification;
@end

@interface SLHGSResult : HGSResult {
 @private
  MDItemRef mdItem_;
}
- (id)initWithMDItem:(MDItemRef)mdItem 
           operation:(SLFilesOperation *)operation;
@end

