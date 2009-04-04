//
//  HGSSimpleAccountSetUpViewController.h
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

// A controller which manages a view used to specify a new account's
// name and password during the setup process.  The view associated with
// this controller gets injected into a window provided by the user
// interface of the client.
//
@interface HGSSimpleAccountSetUpViewController : NSViewController {
 @private
  HGSSimpleAccount *account_;  // The account, once created.
  NSString *accountName_;
  NSString *accountPassword_;
  __weak NSWindow *parentWindow_;
  Class accountTypeClass_;
}

@property (nonatomic, retain) HGSSimpleAccount *account;
@property (nonatomic, copy) NSString *accountName;
@property (nonatomic, copy) NSString *accountPassword;
@property (nonatomic, assign) Class accountTypeClass;

// Designated initializer.
- (id)initWithNibName:(NSString *)nibNameOrNil
               bundle:(NSBundle *)nibBundleOrNil
     accountTypeClass:(Class)accountTypeClass;
  
// Get/set the window off which to hang any alerts.
- (NSWindow *)parentWindow;
- (void)setParentWindow:(NSWindow *)parentWindow;

// Called when the user presses 'OK'.
- (IBAction)acceptSetupAccountSheet:(id)sender;

// Called when user presses 'Cancel'.
- (IBAction)cancelSetupAccountSheet:(id)sender;

// Called when authentication fails to, see if remediation is possible.  Pass 
// along the window off of which we can hang an alert, if so desired.
// See description of -[HGSSimpleAccountEditController canGiveUserAnotherTry]
// for an explanation.
- (BOOL)canGiveUserAnotherTryOffWindow:(NSWindow *)window;

// Used to present an alert message to the user.
- (void)presentMessageOffWindow:(NSWindow *)parentWindow
                    withSummary:(NSString *)summary
              explanationFormat:(NSString *)format
                     alertStyle:(NSAlertStyle)style;
@end
