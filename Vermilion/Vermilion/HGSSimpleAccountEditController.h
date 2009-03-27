//
//  HGSSimpleAccountEditController.h
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

#import <Cocoa/Cocoa.h>

@class HGSSimpleAccount;

// A controller which manages a window used to update the password
// for the account account.
//
@interface HGSSimpleAccountEditController : NSWindowController {
 @private
  IBOutlet HGSSimpleAccount *account_;
  IBOutlet NSWindow *editAccountSheet_;
  
  NSString *password_;
}

@property (nonatomic, copy) NSString *password;
@property (nonatomic, retain, readonly) HGSSimpleAccount *account;

// Gets the edit window associated with this controller.
- (NSWindow *)editAccountSheet;

// Called when the user presses 'OK'.
- (IBAction)acceptEditAccountSheet:(id)sender;

// Called when user presses 'Cancel'.
- (IBAction)cancelEditAccountSheet:(id)sender;

// Called when authentication fails, to see if remediation is possible.
// The default returns NO.  Override this to determine if some additional
// action can be performed (within the setup process) to fix the
// authentication.  One common remediation is to respond to a captcha
// request.
- (BOOL)canGiveUserAnotherTry;

@end
