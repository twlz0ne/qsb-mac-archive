//
//  HGSLRUCacheTest.m
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
#import "HGSLRUCache.h"
#import <OCMock/OCMock.h>

@interface HGSLRUCacheTest : GTMTestCase 
@end

static const void * HGSLRUCacheTestKeyRetain(CFAllocatorRef allocator, 
                                             const void *value) {
  return [(id)value retain];
}

static void HGSLRUCacheTestKeyRelease(CFAllocatorRef allocator, 
                                      const void *value) {
  [(id)value release];
}

static Boolean HGSLRUCacheTestKeyEqual(const void *value1, 
                                       const void *value2) {
  return [(id)value1 isEqual:(id)value2];
}

static CFHashCode HGSLRUCacheTestKeyHash(const void *value) {
  return [(id)value hash];
}

static const void * HGSLRUCacheTestValueRetain(CFAllocatorRef allocator, 
                                               const void *value) {
  return [(id)value retain];
}

static void HGSLRUCacheTestValueRelease(CFAllocatorRef allocator, 
                                        const void *value) {
  [(id)value release];
}

static BOOL HGSLRUCacheTestEvict(const void *key, 
                                 const void *value, 
                                 void *context) {
  return *(BOOL *)context;
}


@implementation HGSLRUCacheTest
- (void)testLRUCache {
  HGSLRUCache *cache 
    = [[[HGSLRUCache alloc] initWithCacheSize:0 
                                    callBacks:NULL 
                                 evictContext:NULL] autorelease];
  STAssertNil(cache, nil);
  HGSLRUCacheCallBacks callbacks = {
    1,
    HGSLRUCacheTestKeyRetain,
    HGSLRUCacheTestKeyRelease,
    HGSLRUCacheTestKeyEqual,
    HGSLRUCacheTestKeyHash,
    HGSLRUCacheTestValueRetain,
    HGSLRUCacheTestValueRelease,
    HGSLRUCacheTestEvict
  };
  
  cache = [[[HGSLRUCache alloc] initWithCacheSize:1024 
                                        callBacks:&callbacks 
                                     evictContext:NULL] autorelease];
  STAssertNil(cache, nil);
  callbacks.version = 0;
  cache = [[HGSLRUCache alloc] initWithCacheSize:1024 
                                       callBacks:&callbacks 
                                    evictContext:NULL];
  STAssertNotNil(cache, nil);
  STAssertEquals([cache count], (CFIndex)0, nil);
  STAssertNULL([cache valueForKey:NULL], nil);
  STAssertNULL([cache valueForKey:@"Foo"], nil);
  [cache getKeys:NULL values:NULL];
  id keys = @"happy";
  id values = @"happy";
  [cache getKeys:(const void**)&keys values:(const void**)&values];
  STAssertEqualObjects(keys, @"happy", nil);
  STAssertEqualObjects(values, @"happy", nil);
  id key = [OCMockObject mockForClass:[NSObject class]];
  id value = [OCMockObject mockForClass:[NSObject class]];
  [[[key stub] andReturn:key] retain];
  [[[value stub] andReturn:value] retain];
  STAssertTrue([cache setValue:value forKey:key size:1023], nil);
  [cache getKeys:(const void**)&keys values:(const void**)&values];
  
  // Calling equals vs equalobjects intentionally because I don't want
  // an isEqual method called on my mocks.
  STAssertEquals(keys, key, nil);
  STAssertEquals(values, value, nil);
  
  id value2 = [OCMockObject mockForClass:[NSObject class]];
  [[key stub] release];
  [[value stub] release];
  [[[key stub] andReturn:key] retain];
  [[[value2 stub] andReturn:value2] retain];
  STAssertTrue([cache setValue:value forKey:key size:1023], nil);
  [[key stub] release];
  [[value2 stub] release];
  [cache release];
}

- (void)testSetAndGetValueFromCache {
  HGSLRUCacheCallBacks callbacks = {
    0,
    HGSLRUCacheTestKeyRetain,
    HGSLRUCacheTestKeyRelease,
    HGSLRUCacheTestKeyEqual,
    HGSLRUCacheTestKeyHash,
    HGSLRUCacheTestValueRetain,
    HGSLRUCacheTestValueRelease,
    HGSLRUCacheTestEvict
  };
  BOOL evict = YES;
  HGSLRUCache *cache = [[HGSLRUCache alloc] initWithCacheSize:1024 
                                                    callBacks:&callbacks 
                                                 evictContext:&evict];
  STAssertNotNil(cache, nil);
  id key1 = [OCMockObject mockForClass:[NSObject class]];
  id value1 = [OCMockObject mockForClass:[NSObject class]];
  id key2 = [OCMockObject mockForClass:[NSObject class]];
  id value2 = [OCMockObject mockForClass:[NSObject class]];
  id key3 = [OCMockObject mockForClass:[NSObject class]];
  id value3 = [OCMockObject mockForClass:[NSObject class]];
  [[[key1 stub] andReturn:key1] retain];
  [[[value1 stub] andReturn:value1] retain];
  STAssertTrue([cache setValue:value1 forKey:key1 size:10], nil);
  [[[key2 stub] andReturn:key2] retain];
  [[[value2 stub] andReturn:value2 ] retain];
  STAssertTrue([cache setValue:value2 forKey:key2 size:20], nil);
  [[[key3 stub] andReturn:key3] retain];
  [[[value3 stub] andReturn:value3] retain];
  STAssertTrue([cache setValue:value3 forKey:key3 size:30], nil); 
  id value = (id)[cache valueForKey:@"Foo"];
  STAssertNil(value,nil);
  value = (id)[cache valueForKey:key3];
  STAssertEquals(value, value3, nil);
  value = (id)[cache valueForKey:key2];
  STAssertEquals(value, value2, nil);
  value = (id)[cache valueForKey:key1];
  STAssertEquals(value, value1, nil);
 
  [[key3 stub] release];
  [[value3 stub] release];
  [cache removeValueForKey:key3];
  
  [[[key3 stub] andReturn:key3] retain];
  [[[value3 stub] andReturn:value3] retain];
  [[key2 stub] release];
  [[value2 stub] release];
  STAssertTrue([cache setValue:value3 forKey:key3 size:1000], nil); 
  value = (id)[cache valueForKey:key2];
  STAssertNil(value, nil);
  evict = NO;
  STAssertFalse([cache setValue:value2 forKey:key2 size:1000], nil);
  evict = YES;
  [[key1 stub] release];
  [[value1 stub] release];
  [[key3 stub] release];
  [[value3 stub] release];  
  STAssertFalse([cache setValue:value2 forKey:key2 size:10000], nil);
  [cache release];
}

@end
