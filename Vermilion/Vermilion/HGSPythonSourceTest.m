//
//  HGSPythonSourceTest.m
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


#import "GTMSenTestCase.h"
#import "HGSPythonSource.h"
#import "HGSQuery.h"
#import "HGSResult.h"

@interface HGSPythonSourceTest : GTMTestCase {
  NSArray *results_;
}
@end

@implementation HGSPythonSourceTest

- (void)setUp {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self
         selector:@selector(gotResults:)
             name:kHGSSearchOperationDidUpdateResultsNotification
           object:nil];
}

- (void)tearDown {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [results_ release];
}

- (void)testSource {
  HGSPython *sharedPython = [HGSPython sharedPython];
  STAssertNotNil(sharedPython, nil);
  
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  [sharedPython appendPythonPath:[bundle resourcePath]];
  
  NSDictionary *config = [NSDictionary dictionaryWithObjectsAndKeys:
                          @"VermilionTest", kPythonModuleNameKey,
                          @"VermilionTest", kPythonClassNameKey,
                          @"python.test", kHGSExtensionIdentifierKey,
                          bundle, kHGSExtensionBundleKey,
                          nil];
  STAssertNotNil(config, nil);

  HGSPythonSource *source
    = [[[HGSPythonSource alloc] initWithConfiguration:config] autorelease];
  STAssertNotNil(source, nil);

  HGSQuery *query = [[[HGSQuery alloc] initWithString:@"Hello world"
                                              results:nil
                                           queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  
  STAssertTrue([source isValidSourceForQuery:query], nil);
  
  HGSPythonSearchOperation *op = [[[HGSPythonSearchOperation alloc]
                                   initWithQuery:query
                                          source:source] autorelease];
  STAssertNotNil(op, nil);
  
  [op startQuery];
  
  int loops = 0;
  while (![op isFinished] && loops++ < 20) {
    // Give the operation 2 seconds to complete
    [[NSRunLoop currentRunLoop] runUntilDate:
     [NSDate dateWithTimeIntervalSinceNow:.1]];
  }
  STAssertTrue([op isConcurrent], nil);
  STAssertTrue([op isFinished], nil);
  STAssertFalse([op isCancelled], nil);
  
  STAssertNotNil(results_, nil);
  
  PyObject *py = [sharedPython objectForQuery:query
                          withSearchOperation:nil];
  STAssertNotNULL(py, nil);
  
  NSURL *url = [NSURL URLWithString:@"http://www.google.com/"];
  NSURL *preview = [NSURL URLWithString:@"file:///icon.png"];
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"A Snippet", kHGSObjectAttributeSnippetKey,
                              preview, kHGSObjectAttributeIconPreviewFileKey,
                              @"none.test", kHGSObjectAttributeDefaultActionKey,
                              nil];
  HGSResult *result = [HGSResult resultWithURL:url
                                          name:@"Google"
                                          type:kHGSTypeWebBookmark
                                        source:source
                                    attributes:attributes];
  PyObject *results = PyList_New(1);
  STAssertNotNULL(results, nil);
  PyList_SetItem(results, 0, [sharedPython objectForResult:result]);
  PyObject *setResults = PyString_FromString("SetResults");
  STAssertNotNULL(setResults, nil);
  PyObject_CallMethodObjArgs(py, setResults, results, nil);
  
  Py_DECREF(results);
  Py_DECREF(setResults);
}

- (void)gotResults:(NSNotification *)note {
  STAssertNotNil([note userInfo], nil);
  if (results_) {
    [results_ release];
  }
  results_ = [[[note userInfo]
              valueForKey:kHGSSearchOperationNotificationResultsKey] copy];
}

@end
