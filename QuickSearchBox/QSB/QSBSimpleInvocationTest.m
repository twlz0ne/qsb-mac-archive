//
//  QSBSimpleInvocationTest.m
//  QSB
//
//  Created by Dave MacLachlan on 9/28/09.
//  Copyright 2009 Google Inc. All rights reserved.
//

#import "GTMSenTestCase.h"
#import "QSBSimpleInvocation.h"

@interface QSBSimpleInvocationTest : GTMTestCase {
 @private
  BOOL wasHit_;
}
@end

static NSString *const kQSBSimpleInvocationTestString = @"testString";

@implementation QSBSimpleInvocationTest
- (void)wasHit:(NSString*)object {
  wasHit_ = [object isEqualToString:kQSBSimpleInvocationTestString];
}

- (void)testSimpleInvocation {
  wasHit_ = YES;
  // The autorelease pool business below is to guarantee that
  // QSBSimpleInvocation holds onto it's arguments.
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *arg = [NSString stringWithString:kQSBSimpleInvocationTestString];
  QSBSimpleInvocation *simpleInvocation
    = [QSBSimpleInvocation selector:@selector(wasHit:)
                             target:self 
                             object:arg];
  [simpleInvocation retain];
  [pool drain];
  [simpleInvocation invoke];
  [simpleInvocation release];
  STAssertTrue(wasHit_, nil);
}
@end
