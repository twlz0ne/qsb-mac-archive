//
//  ShortcutsTest.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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

#import "HGSUnitTestingUtilities.h"
#import "QSBSearchWindowController.h"
#import "QSBTableResult.h"
#import "QSBSearchController.h"

// A mocked up table result for using in tests. Didn't use OCMock because
// I didn't want to bring QSBTableResult into my binary.
@interface ShortcutTestQSBTableResult : NSObject {
 @private
  HGSResult *representedResult_;
}

@property (readonly, retain) HGSResult *representedResult;

- (id)initWithResult:(HGSResult *)result;

@end

@implementation ShortcutTestQSBTableResult

@synthesize representedResult = representedResult_;

- (id)initWithResult:(HGSResult *)result {
  if ((self = [super init])) {
    representedResult_ = [result retain];
  }
  return self;
}

- (void)dealloc {
  [representedResult_ release];
  [super dealloc];
}

@end

// A mocked up QSBSearchController for using in tests. Didn't use OCMock because
// I didn't want to bring QSBSearchController into my binary.
@interface ShortcutTestQSBSearchController : NSObject {
 @private
  NSString *queryString_;
}

@property (readonly, copy) NSString *queryString;
@property (readonly, assign) ShortcutTestQSBSearchController* parentSearchController;

- (id)initWithQueryString:(NSString *)queryString;

@end

@implementation ShortcutTestQSBSearchController

@synthesize queryString = queryString_;

- (id)initWithQueryString:(NSString *)queryString {
  if ((self = [super init])) {
    queryString_ = [queryString copy];
  }
  return self;
}

- (void)dealloc {
  [queryString_ release];
  [super dealloc];
}

- (ShortcutTestQSBSearchController *)parentSearchController {
  return nil;
}
@end 


@interface ShortcutsSourceTest : HGSSearchSourceAbstractTestCase
@end

@implementation ShortcutsSourceTest
  
- (id)initWithInvocation:(NSInvocation *)invocation {
  self = [super initWithInvocation:invocation 
                       pluginNamed:@"Shortcuts" 
               extensionIdentifier:@"com.google.qsb.shortcuts.source"];
  return self;
}

- (void)testEmptySource {
  HGSSearchSource *source = [self source];
  HGSQuery *query = [[HGSQuery alloc] initWithString:@"i" 
                                             results:nil 
                                          queryFlags:0];
  HGSSearchOperation *op = [source searchOperationForQuery:query];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
  [center addObserver:self 
             selector:@selector(emptyResults:) 
                 name:kHGSSearchOperationDidUpdateResultsNotification 
               object:op];
  [op run:YES];
  NSRunLoop *rl = [NSRunLoop currentRunLoop];
  [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
  [center removeObserver:self];
}

- (void)emptyResults:(NSNotification *)notification {
  STFail(@"Shouldn't get here with no results");
}

- (void)testSinglePivot {
  NSString *queryString = @"i";
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSString *resultPath = [bundle pathForResource:@"SampleContact" 
                                          ofType:@"abcdp"];
  STAssertNotNil(resultPath, nil);
  HGSSearchSource *source = [HGSUnitTestingSource sourceWithBundle:bundle];
  STAssertNotNil(source, nil);
  HGSResult *result = [HGSResult resultWithFilePath:resultPath 
                                               rank:kHGSResultUnknownRank
                                             source:source
                                         attributes:nil];
  STAssertNotNil(result, nil);
  ShortcutTestQSBSearchController *searchController 
    = [[[ShortcutTestQSBSearchController alloc] initWithQueryString:queryString] 
       autorelease];
  STAssertNotNil(searchController, nil);
  ShortcutTestQSBTableResult *tableResult 
    = [[[ShortcutTestQSBTableResult alloc] initWithResult:result] autorelease];
  STAssertNotNil(tableResult, nil);
  NSDictionary *userInfo 
    = [NSDictionary dictionaryWithObject:searchController 
                                forKey:kQSBNotificationSearchControllerKey];
  NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

  [center postNotificationName:kQSBWillPivotNotification
                        object:tableResult 
                      userInfo:userInfo];
  HGSQuery *query = [[HGSQuery alloc] initWithString:queryString
                                             results:nil 
                                          queryFlags:0];
  HGSSearchOperation *op = [[self source] searchOperationForQuery:query];
  [center addObserver:self
             selector:@selector(singleResult:) 
                 name:kHGSSearchOperationDidUpdateResultsNotification 
               object:op];
  [op run:YES];

  NSRunLoop *rl = [NSRunLoop currentRunLoop];
  [rl runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];

  [center removeObserver:self];
}

- (void)singleResult:(NSNotification *)notification {
  HGSSearchOperation *op = [notification object];
  STAssertEquals([op resultCount], 1U, nil);
  HGSResult *result = [op sortedResultAtIndex:0];
  STAssertEqualObjects([result displayName], @"SampleContact.abcdp", nil);
}

// TODO(dmaclach): Add more ShortcutsTests when time is available.
// - Specifically adding multiple items and pivoting back and forth to
// see which one stays in the first position.
// - Adding an item which exists, and then deleting it, and making sure that
// it gets cleaned up.
// - Make sure that writing out and reading in function correctly.
// Others...
@end

