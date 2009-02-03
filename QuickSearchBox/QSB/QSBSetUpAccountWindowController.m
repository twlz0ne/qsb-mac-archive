//
//  QSBSetUpAccountWindowController.m
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

#import "QSBSetUpAccountWindowController.h"
#import "HGSAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "HGSLog.h"


@interface QSBSetUpAccountWindowController (QSBSetUpAccountWindowControllerPrivateMethods)

// Get/set the account type which is shown in a popup in the setup window.
- (NSString *)accountType;
- (void)setAccountType:(NSString *)accountType;

// Account setup handlers.
- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo;

// Sets/gets the installed account setup view.
- (void)setInstalledSetupView:(NSView *)setupView;
- (NSView *)installedSetupView;

// Private setters.
- (void)setAccountTypes:(NSArray *)accountTypes;

@end


@implementation QSBSetUpAccountWindowController

@synthesize accountTypes = accountTypes_;

- (void) dealloc {
  [accountType_ release];
  [accountTypes_ release];
  [installedSetupView_ release];
  [super dealloc];
}

- (void)presentSetUpAccountSheet {
  // Set up the popup.
  HGSAccountsExtensionPoint *accountsExtensionPoint
    = [HGSAccountsExtensionPoint accountsExtensionPoint];
  NSArray *accountTypeNames = [accountsExtensionPoint accountTypeNames];
  accountTypeNames
    = [accountTypeNames sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
  [self setAccountTypes:accountTypeNames];
  
  // Pick 'Google' if available.
  if ([accountTypeNames count]) {
    NSString *firstTypeName = [accountTypeNames objectAtIndex:0];
    [self setAccountType:firstTypeName];
  }
      
  [setupAccountSheet_ makeFirstResponder:installedSetupView_];
  [NSApp beginSheet:setupAccountSheet_
     modalForWindow:parentWindow_
      modalDelegate:self
     didEndSelector:@selector(accountSheetDidEnd:returnCode:contextInfo:)
        contextInfo:nil];
}

@end


@implementation QSBSetUpAccountWindowController (QSBSetUpAccountWindowControllerPrivateMethods)

- (NSString *)accountType {
  return [[accountType_ retain] autorelease];
}

- (void)setAccountType:(NSString *)accountType {
  // If the account type has changed then we need to swap the presentation.
  NSString *currentType = [self accountType];
  if (![currentType isEqualToString:accountType]) {
    [accountType_ release];
    accountType_ = [accountType copy];
    
    // Install the new account setup view.
    HGSAccountsExtensionPoint *accountsExtensionPoint
      = [HGSAccountsExtensionPoint accountsExtensionPoint];
    Class accountClass = [accountsExtensionPoint classForAccountType:accountType];
    NSView *viewToInstall
      = [accountClass accountSetupViewToInstallWithParentWindow:parentWindow_];
    if (viewToInstall) {
      [self setInstalledSetupView:viewToInstall];
    } else {
      HGSLog(@"Failed to find setupView for account class '%@'",
             accountClass);
    }
  }
}

- (void)setInstalledSetupView:(NSView *)setupView {
  if (installedSetupView_ != setupView) {
    // Remove any previously installed setup view.
    [installedSetupView_ removeFromSuperview];
    [installedSetupView_ autorelease];
    installedSetupView_ = [setupView retain];
    
    // 1) Adjust the window height to accommodate the new view, 2) adjust
    // the width of the new view to fit the container, then 3) install the
    // new view.
    // Assumption: The container view is set to resize with the window.
    NSRect containerFrame = [setupContainerView_ frame];
    NSRect setupViewFrame = [installedSetupView_ frame];
    CGFloat deltaHeight = NSHeight(setupViewFrame) - NSHeight(containerFrame);
    NSWindow *setupWindow = [setupContainerView_ window];
    NSRect setupWindowFrame = [setupWindow frame];
    setupWindowFrame.origin.y -= deltaHeight;
    setupWindowFrame.size.height += deltaHeight;
    [setupWindow setFrame:setupWindowFrame display:YES];
    
    containerFrame = [setupContainerView_ frame];  // Refresh
    CGFloat deltaWidth = NSWidth(containerFrame) - NSWidth(setupViewFrame);
    setupViewFrame.size.width += deltaWidth;
    [installedSetupView_ setFrame:setupViewFrame];
    
    [setupContainerView_ addSubview:installedSetupView_];
    
    // Set the focused field.
    NSView *wannabeKeyView = [installedSetupView_ nextKeyView];
    [setupWindow makeFirstResponder:wannabeKeyView];
  }
}

- (NSView *)installedSetupView {
  return [[installedSetupView_ retain] autorelease];
}

- (void)setAccountTypes:(NSArray *)accountTypes {
  [accountTypes autorelease];
  accountTypes_ = [accountTypes retain];
}

- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo {
  [sheet orderOut:self];
}

@end
