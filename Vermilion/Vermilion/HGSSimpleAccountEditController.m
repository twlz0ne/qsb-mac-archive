//
//  HGSSimpleAccountEditController.m
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

#import "HGSSimpleAccountEditController.h"
#import "HGSBundle.h"
#import "HGSLog.h"
#import "HGSSimpleAccount.h"

@implementation HGSSimpleAccountEditController

@synthesize password = password_;
@synthesize account = account_;

- (void)dealloc {
  [password_ release];
  [super dealloc];
}

- (void)awakeFromNib {
  [account_ setAccountEditController:self];
  NSString *password = [account_ password];
  [self setPassword:password];
}

- (NSWindow *)editAccountSheet {
  return editAccountSheet_;
}

- (IBAction)acceptEditAccountSheet:(id)sender {
  NSWindow *sheet = [self window];
  NSString *password = [self password];
  if ([account_ authenticateWithPassword:[self password]]) {
    [account_ setPassword:password];
    [NSApp endSheet:sheet];
    [account_ setAuthenticated:YES];
  } else if (![self canGiveUserAnotherTry]) {
    NSString *summaryFormat = HGSLocalizedString(@"Could not set up that %@ "
                                                 @"account.", nil);
    NSString *summary = [NSString stringWithFormat:summaryFormat,
                         [account_ type]];
    NSString *explanationFormat
      = HGSLocalizedString(@"The %@ account '%@' could not be set up for "
                           @"use.  Please check your password and try "
                           @"again.", nil);
    NSString *explanation = [NSString stringWithFormat:explanationFormat,
                             [account_ type],
                             [account_ userName]];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert setMessageText:summary];
    [alert setInformativeText:explanation];
    [alert beginSheetModalForWindow:sheet
                      modalDelegate:self
                     didEndSelector:nil
                        contextInfo:nil];
  }
}

- (IBAction)cancelEditAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  [NSApp endSheet:sheet returnCode:NSAlertSecondButtonReturn];
}

- (BOOL)canGiveUserAnotherTry {
  return NO;
}

@end

