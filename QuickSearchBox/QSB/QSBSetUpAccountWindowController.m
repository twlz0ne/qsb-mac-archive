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
#import <Vermilion/Vermilion.h>

@interface QSBSetUpAccountWindowController ()
@property (nonatomic, retain, readwrite) NSArray *accountTypes;
@property (nonatomic, assign, readwrite) NSString *selectedAccountType;
@property (nonatomic, retain, readwrite) NSView *installedSetupView;
@end

@implementation QSBSetUpAccountWindowController

@synthesize selectedAccountType = selectedAccountType_;
@synthesize installedSetupView = installedSetupView_;
@synthesize accountTypes = accountTypes_;

- (id)initWithParentWindow:(NSWindow *)parentWindow {
  parentWindow_ = parentWindow;
  self = [self init];
  return self;
}

- (id)init {
  if ((self = [super initWithWindowNibName:@"SetUpAccount"])) {
    HGSAccountsExtensionPoint *accountsPoint 
      = [HGSExtensionPoint accountsPoint];
    accountTypes_ = [[accountsPoint accountTypeNames] retain];
  }
  return self;
}

- (void) dealloc {
  [accountTypes_ release];
  [installedSetupView_ release];
  [super dealloc];
}

- (void)awakeFromNib {
  NSSortDescriptor *sort 
    = [[[NSSortDescriptor alloc] initWithKey:@"self" 
                                   ascending:YES] autorelease];
  [accountTypesController_ setSortDescriptors:[NSArray arrayWithObject:sort]];
  NSArray *arrangedObjects = [accountTypesController_ arrangedObjects];
  NSString *type = [arrangedObjects objectAtIndex:0];
  [self setSelectedAccountType:type];
}

- (void)setSelectedAccountType:(NSString *)accountType {
  selectedAccountType_ = accountType;
  HGSAccountsExtensionPoint *accountsPoint 
    = [HGSExtensionPoint accountsPoint];

  Class accountClass = [accountsPoint classForAccountType:accountType];
  NSView *viewToInstall
    = [accountClass setupViewToInstallWithParentWindow:parentWindow_];
  if (viewToInstall) {
    [self setInstalledSetupView:viewToInstall];
  } else {
    HGSLog(@"Failed to find setupView for account class '%@'",
           accountClass);
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

@end
