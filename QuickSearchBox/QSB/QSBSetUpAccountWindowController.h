//
//  QSBSetUpAccountWindowController.h
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

#import <Cocoa/Cocoa.h>

// A window controller that manages the account setup sheet that drops
// out of the preferences window.
//
// The "Set Up Account Sheet" provides the core of a window in which there
// is a control for specifying the type of account to be created and a
// placeholder view into which a custom view of the specified account class
// is inserted.  The window height is adjusted to accommodate the custom
// view; the custom view width is asjusted to match the window.
//
@interface QSBSetUpAccountWindowController : NSWindowController {
 @private
  IBOutlet NSArrayController *accountTypesController_;
  IBOutlet NSView *setupContainerView_;  // Account view inserts here.
  NSView *installedSetupView_;  // The currently inserted account view.
  NSArray *accountTypes_;  // List of account type names for popup.
  NSString *selectedAccountType_;
  __weak NSWindow *parentWindow_;
}

// Preferred initializer.
- (id)initWithParentWindow:(NSWindow *)parentWindow;

@end
