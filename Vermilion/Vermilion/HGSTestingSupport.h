//
//  HGSTestingSupport.h
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

#import <Foundation/Foundation.h>

@class HGSObject;

// A support class that contains helper methods for generating test data
// when testing HGS sources.
@interface HGSTestingSupport : NSObject {
}

// Returns some example HGSPredicate's in an array. A source of example
// queries to run against all sources.
+ (NSArray*)predicates;

// Returns a NSInvocation that implements a comparator for two HGSObjects.
// The NSInvocation follows the method signature:
//
// compareActualResult:(HGSObject*)actualResult
//      expectedResult:(HGSObject*)expectedResult
//             forKeys:(NSArray*)keys
//
// The caller can customize the returned NSInvocation by setting the
// 4th argument (0-based) to an NSArray of kHGSObjectAttribute* keys.
//
+ (NSInvocation*)resultComparator;

// Returns a result comparator that just checks the name and result type.
+ (NSInvocation*)resultComparatorWithNameAndType;

// Compare an actual result with an expected result for the given |validKeys|.
// If a mismatch is found, it will do invoke STAssert().
+ (void)compareActualResult:(HGSObject*)actualResult
             expectedResult:(HGSObject*)expectedResult
                    forKeys:(NSArray*)validKeys;

// Compare an array of actual results with an array of expected results
// with a comparator (created by the |resultComparator|).
+ (void)compareActualResults:(NSArray*)actualResults
             expectedResults:(NSArray*)expectedResults
              withComparator:(NSInvocation*)comparator;

// Instantiate an array of HGSObject from a property list that exists insideh
// the testing bundle.
+ (NSArray*)objectsFromBundleResource:(NSString*)testResourceName;
@end
