//
//  QSBPreferenceWindowController.m
//
//  Copyright (c) 2008-2009 Google Inc. All rights reserved.
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

#import "QSBPreferenceWindowController.h"
#import "HGSAccount.h"
#import "HGSAccountsExtensionPoint.h"
#import "QSBApplicationDelegate.h"
#import "QSBUISettings.h"
#import "QSBPreferences.h"
#import "QSBSearchWindowController.h"
#import "GTMHotKeyTextField.h"
#import "HGSCoreExtensionPoints.h"
#import "NSColor+Naming.h"
#import "KeychainItem.h"
#import "GTMMethodCheck.h"
#import "HGSLog.h"
#import "GTMGarbageCollection.h"

// The preference containing a list of knwon accounts.
NSString *const kQSBAccountsPrefKey = @"QSBAccountsPrefKey";

static void OpenAtLoginItemsChanged(LSSharedFileListRef inList, void *context);

@interface QSBPreferenceWindowController (QSBPreferenceWindowControllerPrivateMethods)

// Account setup handlers.
- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo;

// Adjust color popup to the corect color
- (void)updateColorPopup;

// Get/set the sources sort descriptor.
- (NSArray *)sourceSortDescriptor;
- (void)setSourceSortDescriptor:(NSArray *)value;

@end
  

static NSString *const kQSBBackgroundPref = @"backgroundColor";
static NSString *const kQSBBackgroundGlossyPref = @"backgroundIsGlossy";
static const NSInteger kCustomColorTag = -1;


@interface NSColor (QSBColorRendering)

- (NSImage *)menuImage;

@end


@implementation NSColor (QSBColorRendering)
- (NSImage *)menuImage {
  NSRect rect = NSMakeRect(0.0, 0.0, 24.0, 12.0);
  NSImage *image = [[[NSImage alloc] initWithSize:rect.size] autorelease];
  [image lockFocus];
  [self set];
  NSRectFill(rect);
  [[NSColor colorWithDeviceWhite:0.0 alpha:0.2] set];
  NSFrameRectWithWidthUsingOperation(rect, 1.0, NSCompositeSourceOver);
  [image unlockFocus];
  return image;
}
@end


@implementation QSBPreferenceWindowController

@synthesize selectedColor = selectedColor_;
@synthesize accountName = accountName_;
@synthesize accountPassword = accountPassword_;
@synthesize accountType = accountType_;

GTM_METHOD_CHECK(NSColor, crayonName);

- (id)init {
  if ((self = [super initWithWindowNibName:@"PreferencesWindow"])) {
    NSSortDescriptor *sortDesc
      = [[[NSSortDescriptor alloc] initWithKey:@"displayName" 
                                     ascending:YES
                                      selector:@selector(caseInsensitiveCompare:)]
                              autorelease];
    [self setSourceSortDescriptor:[NSArray arrayWithObject:sortDesc]];
    openAtLoginItemsList_ 
      = LSSharedFileListCreate(NULL, 
                               kLSSharedFileListSessionLoginItems, 
                               NULL);
    if (!openAtLoginItemsList_) {
      HGSLog(@"Unable to create kLSSharedFileListSessionLoginItems");
    } else {
      LSSharedFileListAddObserver(openAtLoginItemsList_,
                                  CFRunLoopGetMain(),
                                  kCFRunLoopDefaultMode,
                                  OpenAtLoginItemsChanged,
                                  self);
      openAtLoginItemsSeedValue_ 
        = LSSharedFileListGetSeedValue(openAtLoginItemsList_);
  }
  }
  return self;
}

- (void) dealloc {
  [colors_ release];
  [sourceSortDescriptor_ release];
  if (openAtLoginItemsList_) {
    LSSharedFileListRemoveObserver(openAtLoginItemsList_,
                                   CFRunLoopGetMain(), 
                                   kCFRunLoopDefaultMode, 
                                   OpenAtLoginItemsChanged,
                                   self);
    CFRelease(openAtLoginItemsList_);
  }
  [super dealloc];
}

- (void)windowDidLoad {
  [super windowDidLoad];
  
  [[colorPopUp_ menu] setDelegate:self];
  
  NSData *colorData = [[NSUserDefaults standardUserDefaults] objectForKey:kQSBBackgroundPref];
  NSColor *color = colorData ? [NSUnarchiver unarchiveObjectWithData:colorData]
                             : [NSColor whiteColor];
  [self setSelectedColor:color];
  
  // Add the Google color palette
  colors_ = [[NSColorList alloc] initWithName:@"Google"];
  
  [colors_ setColor:[NSColor whiteColor] 
             forKey:NSLocalizedString(@"White", @"")];
  
  [colors_ setColor:[NSColor colorWithCalibratedRed:0 
                                              green:102.0/255.0
                                               blue:204.0/255.0
                                              alpha:1.0] 
             forKey:NSLocalizedString(@"Blue", @"")];
  
  [colors_ setColor:[NSColor redColor] 
             forKey:NSLocalizedString(@"Red", @"")];
  [colors_ setColor:[NSColor colorWithCalibratedRed:255.0/255.0 
                                              green:204.0/255.0
                                               blue:0.0
                                              alpha:1.0] 
             forKey:NSLocalizedString(@"Yellow", @"")];
  [colors_ setColor:[NSColor colorWithCalibratedRed:0 
                                              green:153.0/255.0
                                               blue:57.0/255.0
                                              alpha:1.0] 
             forKey:NSLocalizedString(@"Green", @"")];  

  [colors_ setColor:[NSColor colorWithCalibratedWhite:0.75 alpha:1.0]
             forKey:NSLocalizedString(@"Silver", @"")];
  [colors_ setColor:[NSColor blackColor] 
             forKey:NSLocalizedString(@"Black", @"")];

  [self menuNeedsUpdate:[colorPopUp_ menu]];
  [colorPopUp_ selectItemAtIndex:0];
  [self updateColorPopup];
  
  [[self window] setHidesOnDeactivate:YES];
}


#pragma mark Color Menu

- (void)menuNeedsUpdate:(NSMenu *)menu {
  
  if (![[menu itemArray] count]) {
    NSArray *colorNames = [colors_ allKeys];
    for (NSUInteger i = 0; i < [colorNames count]; i++) {
      NSString *name = [colorNames objectAtIndex:i];
      NSMenuItem *item = [menu addItemWithTitle:name
                                         action:nil 
                                  keyEquivalent:@""];
      [item setTag:i];
      [item setRepresentedObject:[colors_ colorWithKey:name]];
    }
    
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *item = [menu addItemWithTitle:NSLocalizedString(@"Other...", @"") 
                     action:@selector(chooseOtherColor:)
                                keyEquivalent:@""];
    [item setTarget:self];
    [item setTag:kCustomColorTag];
    
    [menu addItem:[NSMenuItem separatorItem]];
    [[menu addItemWithTitle:NSLocalizedString(@"Glossy", @"")
                     action:@selector(setGlossy:)
              keyEquivalent:@""] setTarget:self];;
  }
}

- (NSInteger)indexOfColor:(NSColor *)color {
  for (NSString *key in [colors_ allKeys]) {
    NSColor *thisColor = [colors_ colorWithKey:key];
    if ([color isEqual:thisColor]) {
      return [[colors_ allKeys] indexOfObject:key];
    }
  }
  return NSNotFound;
}

- (void)setColor:(NSColor *)color {
  [self setSelectedColor:color];
  [[NSUserDefaults standardUserDefaults] setObject:[NSArchiver archivedDataWithRootObject:color]
                                            forKey:kQSBBackgroundPref]; 
  [self updateColorPopup];
}

- (IBAction)setColorFromMenu:(id)sender {
  NSColor *color = [[sender selectedItem] representedObject];
  [self setColor:color];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
  if ([item action] == @selector(setGlossy:)) {
    [item setState:[[NSUserDefaults standardUserDefaults] boolForKey:kQSBBackgroundGlossyPref]];
  } else if ([item action] == @selector(chooseOtherColor:))  {
    NSColor *color = [self selectedColor];
    [item setImage:[color menuImage]];
    [item setTitle:NSLocalizedString(@"Other...", @"")];
    [item menu];
  } else {
    if (![item image]) {
      NSColor *color = [colors_ colorWithKey:[item title]];
      [item setImage:[color menuImage]];
    }
  }
  return YES;
}

- (void)setGlossy:(id)sender {
  BOOL glossy = [[NSUserDefaults standardUserDefaults] boolForKey:kQSBBackgroundGlossyPref];
  [[NSUserDefaults standardUserDefaults] setBool:!glossy
                                          forKey:kQSBBackgroundGlossyPref];
  
  [self updateColorPopup];
}

- (void)changeColor:(id)sender {
  [self setColor:[sender color]];
}

- (void)chooseOtherColor:(id)sender {
  // If the user should decide to change colors on us
  // we want the following settings available.
  [[NSColorPanel sharedColorPanel] setShowsAlpha:YES];
  [[NSColorPanel sharedColorPanel] setMode:NSCrayonModeColorPanel];
  [[NSColorPanel sharedColorPanel] setAction:@selector(changeColor:)];
  [[NSColorPanel sharedColorPanel] setTarget:self];
  [[NSColorPanel sharedColorPanel] makeKeyAndOrderFront:sender];
  
}

- (IBAction)showPreferences:(id)sender {
  [NSApp activateIgnoringOtherApps:YES];
  NSWindow *prefWindow = [self window];
  [prefWindow center];
  [prefWindow makeKeyAndOrderFront:nil];
  if (prefsColorWellWasShowing_) {
    [[NSColorPanel sharedColorPanel] setIsVisible:YES];
  }
}

- (void)hidePreferences {
  if ([self preferencesWindowIsShowing]) {
    [[self window] setIsVisible:NO];
  }
}

- (BOOL)preferencesWindowIsShowing {
  return ([[self window] isVisible]);
}

- (IBAction)resetHotKey:(id)sender {
  // Just write the pref, KVO and bindings takes care of the rest.
  [[NSUserDefaults standardUserDefaults] setObject:kQSBHotKeyDefault
                                            forKey:kQSBHotKeyKey];
}

#pragma mark Account Management

- (IBAction)setupAccount:(id)sender {
  // TODO(mrossetti):Accommodate different types of accounts, preferably 
  // dynamically.
  [self setAccountType:@"Google"];
  [self setAccountName:nil];
  [self setAccountPassword:nil];
  [NSApp beginSheet:setupAccountSheet_
     modalForWindow:[self window]
      modalDelegate:self
     didEndSelector:@selector(accountSheetDidEnd:returnCode:contextInfo:)
        contextInfo:nil];
}

- (IBAction)editAccount:(id)sender {
  NSArray *selections = [accountsListController_ selectedObjects];
  id<HGSAccount> account = [selections objectAtIndex:0];
  if ([account isEditable]) {
    accountBeingEdited_ = account;
    [self setAccountType:[account accountType]];
    [self setAccountName:[account accountName]];
    NSString *password = [account accountPassword];
    [self setAccountPassword:password];
    [NSApp beginSheet:editAccountSheet_
       modalForWindow:[self window]
        modalDelegate:self
       didEndSelector:@selector(accountSheetDidEnd:returnCode:contextInfo:)
          contextInfo:account];
  }
}

- (IBAction)removeAccount:(id)sender {
  NSArray *selections = [accountsListController_ selectedObjects];
  if ([selections count]) {
    id<HGSAccount> accountToRemove = [selections objectAtIndex:0];
    NSString *summary = NSLocalizedString(@"About to remove an account.",
                                          nil);
    NSString *format
    = NSLocalizedString(@"Removing the account '%@' will disable and remove "
                        @"all search sources associated with this account.",
                        nil);
    NSString *accountName = [accountToRemove accountName];
    NSString *explanation = [NSString stringWithFormat:format, accountName];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert setMessageText:summary];
    [alert setInformativeText:explanation];
    [alert addButtonWithTitle:NSLocalizedString(@"Remove", nil)];
    [alert addButtonWithTitle:NSLocalizedString(@"Cancel", nil)];
    [alert beginSheetModalForWindow:[self window]
                      modalDelegate:self
                     didEndSelector:@selector(removeAccountAlertDidEnd:
                                              returnCode:contextInfo:)
                        contextInfo:accountToRemove];
  }
}

- (IBAction)acceptSetupAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  NSString *accountName = [self accountName];
  if ([accountName length] > 0) {
    // Create the new account entry.
    HGSAccountsExtensionPoint *accountsExtensionPoint
      = [HGSAccountsExtensionPoint accountsExtensionPoint];
    NSString *accountType = [self accountType];
    Class accountClass
      = [accountsExtensionPoint classForAccountType:accountType];
    id<HGSAccount> newAccount
      = [[accountClass alloc] initWithName:accountName
                                  password:[self accountPassword]
                                      type:[self accountType]];
    
    // Update the account name in case initWithName: adjusted it.
    NSString *revisedAccountName = [newAccount accountName];
    if ([revisedAccountName length]) {
      accountName = revisedAccountName;
      [self setAccountName:accountName];
    }
    
    BOOL isGood = [newAccount isAuthenticated];
    if (isGood) {
      isGood = [accountsExtensionPoint extendWithObject:newAccount];
      if (isGood) {
        NSArray *accounts = [NSArray arrayWithObject:newAccount];
        [accountsListController_ setSelectedObjects:accounts];
      }
    }
    if (isGood) {
      [sheet makeFirstResponder:userField_];
      [self setAccountName:nil];
      [self setAccountPassword:nil];
      [NSApp endSheet:sheet];

      NSString *summary = NSLocalizedString(@"Relaunch required to activate account.",
                                            nil);
      NSString *format
        = NSLocalizedString(@"Relaunch Google Quick Search in order to activate "
                            @"account '%@'. It may be necessary to manually "
                            @"enable search sources which uses this account "
                            @"via the 'Search Sources' tab in Preferences "
                            @"after relaunching.", nil);
      NSString *explanation = [NSString stringWithFormat:format, accountName];
      NSAlert *alert = [[[NSAlert alloc] init] autorelease];
      [alert setAlertStyle:NSWarningAlertStyle];
      [alert setMessageText:summary];
      [alert setInformativeText:explanation];
      [alert beginSheetModalForWindow:[self window]
                        modalDelegate:self
                       didEndSelector:nil
                          contextInfo:nil];
    } else {
      NSString *summary = NSLocalizedString(@"Could not set up that account.",
                                            nil);
      NSString *format
        = NSLocalizedString(@"The account ‘%@’ could not be set up for use.  "
                            @"Please insure that you have used the correct "
                            @"account name and password.", nil);
      NSString *explanation = [NSString stringWithFormat:format, accountName];
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
}

- (IBAction)cancelSetupAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  [NSApp endSheet:sheet returnCode:NSAlertSecondButtonReturn];
}

- (IBAction)acceptEditAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  id<HGSAccount> account = accountBeingEdited_;
  [account setAccountPassword:[self accountPassword]];
  // See if the new password authenticates.
  if ([account isAuthenticated]) {
    [NSApp endSheet:sheet];
  } else {
    NSString *summary = NSLocalizedString(@"Could not set up that account.", nil);
    NSString *format
      = NSLocalizedString(@"The account ‘%@’ could not be set up for use.  "
                          @"Please insure that you have used the correct "
                          @"password.", nil);
    NSString *explanation = [NSString stringWithFormat:format,
                             [self accountName]];
    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setAlertStyle:NSWarningAlertStyle];
    [alert setMessageText:summary];
    [alert setInformativeText:explanation];
    [alert beginSheetModalForWindow:sheet
                      modalDelegate:self
                     didEndSelector:nil
                        contextInfo:account];
  }
}

- (IBAction)cancelEditAccountSheet:(id)sender {
  NSWindow *sheet = [sender window];
  [NSApp endSheet:sheet returnCode:NSAlertSecondButtonReturn];
}

#pragma mark Delegate Methods

- (void)windowDidResignKey:(NSNotification *)notification {
  NSWindow *window = [notification object];
  if (window == [self window]) {
    prefsColorWellWasShowing_ = [[NSColorPanel sharedColorPanel] isVisible];
    [[NSColorPanel sharedColorPanel] setIsVisible:NO];
  }
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
  if ([client isKindOfClass:[GTMHotKeyTextField class]]) {
    return [GTMHotKeyFieldEditor sharedHotKeyFieldEditor];
  } else {
    return nil;
  }
}

@end

@implementation QSBPreferenceWindowController (QSBPreferenceWindowControllerPrivateMethods)

- (void)updateColorPopup {
  NSInteger idx = [self indexOfColor:[self selectedColor]];
  if (idx == NSNotFound) {
    [colorPopUp_ selectItemWithTag:kCustomColorTag]; 
    NSMenuItem *item = [colorPopUp_ selectedItem];
    [item setTitle:[[self selectedColor] crayonName]];
  } else {
    [colorPopUp_ selectItemAtIndex:idx];
  }
  [self validateMenuItem:[colorPopUp_ selectedItem]];
}

- (NSArray *)sourceSortDescriptor {
  return sourceSortDescriptor_;
}

- (void)setSourceSortDescriptor:(NSArray *)value {
  [sourceSortDescriptor_ autorelease];
  sourceSortDescriptor_ = [value retain];
}

#pragma mark Account Management

- (void)accountSheetDidEnd:(NSWindow *)sheet
                returnCode:(int)returnCode
               contextInfo:(void *)contextInfo {
  [self setAccountPassword:nil];
  [sheet orderOut:self];
}

- (void)removeAccountAlertDidEnd:(NSWindow *)sheet
                      returnCode:(int)returnCode
                     contextInfo:(void *)contextInfo {
  if (returnCode == NSAlertFirstButtonReturn) {
    id<HGSAccount> accountToRemove = (id<HGSAccount>)contextInfo;
    NSUInteger selection = [accountsListController_ selectionIndex];
    if (selection > 0) {
      [accountsListController_ setSelectionIndex:(selection - 1)];
    }
    [accountToRemove remove];
  }
}

#pragma mark Bindings

// Tied to the Open QSB At Login checkbox
- (UInt32)openedAtLoginSeedValue {
  return openAtLoginItemsSeedValue_;
}

- (BOOL)openedAtLogin {
  BOOL opened = NO;
  if (openAtLoginItemsList_) {
    NSBundle *ourBundle = [NSBundle mainBundle];
    NSString *bundlePath = [ourBundle bundlePath];
    NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];
    CFArrayRef cfItems = LSSharedFileListCopySnapshot(openAtLoginItemsList_, 
                                                      &openAtLoginItemsSeedValue_);
    NSArray *items = GTMCFAutorelease(cfItems);
    for (id item in items) {
      CFURLRef itemURL;
      if (LSSharedFileListItemResolve((LSSharedFileListItemRef)item, 
                                      0, &itemURL, NULL) == 0) {
        if ([bundleURL isEqual:(NSURL *)itemURL]) {
          opened = YES;
          break;
        }
        CFRelease(itemURL);
      }
    }
  }
  return opened;
}

- (void)setOpenedAtLogin:(BOOL)opened {
  if (!openAtLoginItemsList_) return;
  NSBundle *ourBundle = [NSBundle mainBundle];
  NSString *bundlePath = [ourBundle bundlePath];
  NSURL *bundleURL = [NSURL fileURLWithPath:bundlePath];
  if (opened) {
    // Hidden isn't set in 10.5.6
    // http://openradar.appspot.com/6482251
    NSNumber *nsTrue = [NSNumber numberWithBool:YES];
    NSDictionary *propertiesToSet 
      = [NSDictionary dictionaryWithObject:nsTrue 
                                    forKey:(id)kLSSharedFileListItemHidden];
    LSSharedFileListItemRef item 
      = LSSharedFileListInsertItemURL(openAtLoginItemsList_, 
                                      kLSSharedFileListItemLast, 
                                      NULL,
                                      NULL, 
                                      (CFURLRef)bundleURL, 
                                      (CFDictionaryRef)propertiesToSet, 
                                      NULL);
    CFRelease(item);
    openAtLoginItemsSeedValue_ 
      = LSSharedFileListGetSeedValue(openAtLoginItemsList_);
  } else {
    CFArrayRef cfItems = LSSharedFileListCopySnapshot(openAtLoginItemsList_, 
                                                      &openAtLoginItemsSeedValue_);
    NSArray *items = GTMCFAutorelease(cfItems);
    for (id item in items) {
      CFURLRef itemURL;
      if (LSSharedFileListItemResolve( (LSSharedFileListItemRef)item, 
                                      0, &itemURL, NULL) == 0) {
        if ([bundleURL isEqual:(NSURL *)itemURL]) {
          OSStatus status 
            = LSSharedFileListItemRemove(openAtLoginItemsList_, 
                                         (LSSharedFileListItemRef)item);
          if (status) {
            HGSLog(@"Unable to remove %@ from open at login (%d)", 
                   itemURL, status);
          }
        }
        CFRelease(itemURL);
      }
    }
  }
}

void OpenAtLoginItemsChanged(LSSharedFileListRef inList, void *context) {
  UInt32 seedValue = LSSharedFileListGetSeedValue(inList);
  QSBPreferenceWindowController *controller
    = (QSBPreferenceWindowController *)context;
  UInt32 contextSeedValue = [controller openedAtLoginSeedValue];
  if (contextSeedValue != seedValue) {
    [controller willChangeValueForKey:@"openedAtLogin"];
    [controller didChangeValueForKey:@"openedAtLogin"];
  }
}

@end
