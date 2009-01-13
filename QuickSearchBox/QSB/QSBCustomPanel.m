//
//  QSBCustomPanel.m
//
//  Copyright (c) 2006-2008 Google Inc. All rights reserved.
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

#import "QSBCustomPanel.h"

@implementation QSBCustomPanel

// Standard window init method. Sets up some special stuff for custom windows.
- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSUInteger)aStyle 
                  backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag {

  // Pass NSBorderlessWindowMask for the styleMask so we don't get a title bar
  aStyle = NSBorderlessWindowMask | NSNonactivatingPanelMask;
  self = [super initWithContentRect:contentRect 
                                      styleMask:aStyle
                                        backing:bufferingType 
                                          defer:flag];
  
  if (self) {
    // Set window to be clear and non-opaque so we can see through it.
    [self setBackgroundColor:[NSColor clearColor]];
    [self setOpaque:NO];
    
    // Pull the window up to Status Level
    [self setLevel:NSStatusWindowLevel];
    
    [self setCanBecomeKeyWindow:YES];
  }  
  return self;
}

// NSBorderlessWindowMask can't become key by default, so we return
// YES here to allow ours to become key.
- (BOOL)canBecomeKeyWindow {
  return canBecomeKeyWindow_;
}

- (void)setCanBecomeKeyWindow:(BOOL)becomeKey {
  canBecomeKeyWindow_ = becomeKey;
}

@end
