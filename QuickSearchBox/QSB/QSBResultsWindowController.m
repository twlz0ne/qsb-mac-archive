//
//  QSBResultsWindowController.m
//
//  Copyright (c) 2010 Google Inc. All rights reserved.
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

#import "QSBResultsWindowController.h"
#import "QSBCustomPanel.h"
#import "QSBSimpleInvocation.h"
#import "QSBViewAnimation.h"
#import "QSBSearchWindowController.h"

static const CGFloat kQSBResultsAnimationDistance = 12.0;
static NSString *const kQSBResultWindowVisibilityAnimationName 
  = @"QSBResultWindowVisibilityAnimationName";

@implementation QSBResultsWindowController

- (id)init {
  return [super initWithWindowNibName:@"QSBResultsWindow"];
}

- (void)dealloc {
  [windowVisibilityAnimation_ release];
  [super dealloc];
}

- (void)windowDidLoad {
  HGSAssert(searchWindowController_ != nil, 
            @"Did you forget to hook up searchWindowController_ in the nib?");
  QSBCustomPanel *window = (QSBCustomPanel*)[self window];
  [window setCanBecomeKeyWindow:NO];
  [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
  
  windowVisibilityAnimation_ 
    = [[QSBViewAnimation alloc] initWithViewAnimations:nil 
                                                  name:kQSBResultWindowVisibilityAnimationName
                                              userInfo:nil];
  [windowVisibilityAnimation_ setDelegate:self];
}

- (void)hideWindowAnimated {
  NSWindow *window = [self window];
  if (![window ignoresMouseEvents]) {
    [window setIgnoresMouseEvents:YES];
    [windowVisibilityAnimation_ stopAnimation];
    NSDictionary *animation 
      = [NSDictionary dictionaryWithObjectsAndKeys:
         window, NSViewAnimationTargetKey,
         NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
         nil];
    NSArray *animations = [NSArray arrayWithObject:animation];
    [windowVisibilityAnimation_ setViewAnimations:animations];
    QSBSimpleInvocation *invocation
      = [QSBSimpleInvocation selector:@selector(hideResultsWindowAnimationCompleted:) 
                               target:self 
                               object:window];
    [windowVisibilityAnimation_ setUserInfo:invocation];
    [windowVisibilityAnimation_ setAnimationBlockingMode:NSAnimationNonblocking];
    [windowVisibilityAnimation_ setDuration:kQSBHideDuration];
    [windowVisibilityAnimation_ setDelegate:self];
    [windowVisibilityAnimation_ startAnimation];
  }
}

- (void)hideResultsWindowAnimationCompleted:(NSWindow *)window {
  [[window parentWindow] removeChildWindow:window];
  [window orderOut:self];
}

- (void)showWindowAnimated {
  NSWindow *window = [self window];
  NSRect frame = [window frame];
  [window setAlphaValue:0.0];  
  
  [window setFrame:NSOffsetRect(frame, 0.0, kQSBResultsAnimationDistance) 
                   display:YES
                   animate:YES];
  NSWindow *searchWindow = [searchWindowController_ window];
  // Fix for stupid Apple ordering bug. By removing and re-adding all the
  // the children we keep the window list in the right order.
  // TODO(dmaclach):log a radar on this. Try removing the two
  // for loops, and doing a search with the help window showing.
  NSArray *children = [searchWindow childWindows];
  for (NSWindow *child in children) {
    [searchWindow removeChildWindow:child];
  }
  [searchWindow addChildWindow:window ordered:NSWindowBelow];
  for (NSWindow *child in children) {
    [searchWindow addChildWindow:child ordered:NSWindowBelow];
  }
  [window setLevel:kCGStatusWindowLevel + 1];
  [window setIgnoresMouseEvents:NO];
  [window makeKeyAndOrderFront:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:window 
                                           selector:@selector(orderOut:) 
                                             object:nil];
  
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:kQSBShowDuration];
  [[window animator] setAlphaValue:1.0];
  [searchWindowController_ setResultsWindowHeight:NSHeight(frame) animating:YES];
  [NSAnimationContext endGrouping];
}

- (void)animationDidEnd:(QSBViewAnimation *)animation {
  HGSAssert([animation isKindOfClass:[QSBViewAnimation class]], nil);
  id<NSObject> userInfo = [animation userInfo];
  if ([userInfo isKindOfClass:[QSBSimpleInvocation class]]) {
    [(QSBSimpleInvocation *)userInfo invoke];
  }
}

- (void)stopWindowAnimation {
  [windowVisibilityAnimation_ stopAnimation];
}

@end
