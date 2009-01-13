//
//  HGSSearchSourceTest.mm
//  GoogleMobile
//
//  Created by Alastair Tse on 2008/05/17.
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

#import "HGSSearchSourceTest.h"
//
#import "HGSSearchSource.h"
#import "HGSSearchSourceBlockingObserver.h"
#import "HGSTestingSupport.h"

@implementation HGSSearchSourceTest

- (void)setUp {
  source_ = [[HGSSearchSource alloc] initWithName:@"com.google.desktop.test"];
}

- (void)testSearchOperationForQueryWithObserver {
  HGSSearchOperation* operation;

  // Test operation creation
  for (HGSPredicate* predicate in [HGSTestingSupport predicates]) {
    operation = [source_ searchOperationForQuery:predicate withObserver:nil];
    STAssertNotNil(operation, [[predicate query] description]);
    if (testFirstTier_) {
      STAssertTrue([operation isFirstTier], @"Should be first tier");
    }
  }

  // Test disabled source creation
  if (testEnabled_) {
    [source_ setEnabled:NO];
    for (HGSPredicate* predicate in [HGSTestingSupport predicates]) {
      operation = [source_ searchOperationForQuery:predicate withObserver:nil];
      STAssertNil(operation, [[predicate query] description]);
    }
    [source_ setEnabled:YES];
  }
}

- (void)testPerformSearchOperation {
  if (!testPerformSearchOperation_) return;

  HGSSearchOperation* operation;

  for (HGSPredicate* predicate in [HGSTestingSupport predicates]) {
    // With no observer (shouldn't crash.)
    operation = [source_ searchOperationForQuery:predicate withObserver:nil];
    [self _testSingleQuery:predicate expectingResults:nil comparator:nil];
  }
}

- (NSArray *)_testSingleQuery:(HGSPredicate*)predicate
             expectingResults:(NSArray*)expectedResults
                   comparator:(NSInvocation*)comparator {
  HGSSearchSourceBlockingObserver* observer =
    [[[HGSSearchSourceBlockingObserver alloc] init] autorelease];
  HGSSearchOperation* operation = [source_ searchOperationForQuery:predicate
                                                      withObserver:observer];
  [source_ performSearchOperation:operation];

  if ([operation isConcurrent]) {
    // If operation is concurrent, we should wait until results return.
    [observer runUntilSearchOperationFinishedCalled:5.0];
    STAssertTrue([observer finished], [[predicate query] description]);
  }

  if ([[operation results] count]) {
    // If there are results, searchOperationUpdated: must be called.
    [observer runUntilSearchOperationUpdatedCalled:1.0];
    STAssertTrue([observer updateCount] > 0, [[predicate query] description]);
  }

  // Compare results if we are given both the result array and comparator.
  if (expectedResults && comparator) {
    [HGSTestingSupport compareActualResults:[operation results]
                            expectedResults:expectedResults
                             withComparator:comparator];
  }
  return [operation results];
}

- (void)tearDown {
  [source_ release];
  source_ = nil;
}

@end
