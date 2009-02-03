//
//  QSBApplicationDelegate.m
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
//

#import "QSBApplicationDelegate.h"

#import <unistd.h>
#import <Vermilion/Vermilion.h>

#import "QSBUISettings.h"
#import "QSBKeyMap.h"
#import "QSBPreferences.h"
#import "QSBPreferenceWindowController.h"
#import "GTMCarbonEvent.h"
#import "GTMGarbageCollection.h"
#import "GTMGeometryUtils.h"
#import "GTMMethodCheck.h"
#import "GTMNSArray+Merge.h"
#import "GTMNSEnumerator+Filter.h"
#import "GTMSystemVersion.h"
#import "QSBSearchWindowController.h"
#import "GTMHotKeyTextField.h"
#import "GTMNSWorkspace+Running.h"
#import "QSBHGSDelegate.h"
#import "QSBQueryController.h"
#import "GTMNSObject+KeyValueObserving.h"

// Local pref set once we've been launched. Used to control whether or not we
// show the help window at startup.
NSString *const kQSBBeenLaunchedPrefKey = @"QSBBeenLaunchedPrefKey";

// The preference containing the configuration for each plugin.
static NSString *const kQSBPluginConfigurationPrefKey 
  = @"QSBPluginConfigurationPrefKey";

static NSString *const kQSBHomepageKey = @"QSBHomepageURL";
static NSString *const kQSBFeedbackKey = @"QSBFeedbackURL";

// KVO Keys
// Observe each plugins protoExtensions so that we can update sourceExtensions.
static NSString *const kQSBProtoExtensionsKVOKey = @"protoExtensions";
// Signal a sourceExtensions change in response to a protoExtension change.
static NSString *const kQSBSourceExtensionsKVOKey = @"sourceExtensions";

@interface QSBApplicationDelegate ()

// sets us up so we're looking for the right hotkey
- (void)updateHotKeyRegistration;

// our hotkey has been hit, let's do something about it
- (void)hitHotKey:(id)sender;

// Called when we should update how our status icon appears
- (void)updateIconInMenubar;

- (void)hotKeyValueChanged:(GTMKeyValueChangeNotification *)note;
- (void)iconInMenubarValueChanged:(GTMKeyValueChangeNotification *)note;

// Reconcile what we previously knew about accounts and saved in our
// preferences with what we now know about accounts.
- (void)inventoryAccounts;

// Reconcile what we previously knew about plugins and extensions
// and had saved in our preferences with a new inventory
// of plugins and extensions, then enable each as appropriate.
- (void)inventoryPlugins;

// Given |modules|, merge the extensions therein with those previously
// in preferences or inventoried earlier, possibly resolving conflicts
// with the user for duplicate modules in different paths or modules
// that have moved.
- (NSMutableArray *)mergePlugins:(NSArray *)newPlugins
                     intoPlugins:(NSArray *)plugins;

// Set the array of plug-ins.
- (void)setPlugins:(NSArray *)plugins;

// Record all current plugin configuration information.
- (void)updatePluginPreferences;

// Check if the screen saver is running.
- (BOOL)isScreenSaverActive;

// Check if front row is active.
- (BOOL)frontRowActive;

// Called when we want to update menus with a proper app name
- (void)updateMenuWithAppName:(NSMenu* )menu;

// Each plugin's protoExtensions must be monitored in order for the app
// delegate's list of sourceExtensions to be properly updated.
- (void)observeProtoExtensions;
- (void)stopObservingProtoExtensions;
- (void)protoExtensionsValueChanged:(GTMKeyValueChangeNotification *)note;
@end


@interface NSEvent (QSBApplicationEventAdditions)

- (NSUInteger)qsbModifierFlags;

@end


@implementation QSBApplicationDelegate

GTM_METHOD_CHECK(NSWorkspace, gtm_processInfoDictionaryForActiveApp);
GTM_METHOD_CHECK(GTMHotKeyTextField, stringForKeycode:useGlyph:resourceBundle:);
GTM_METHOD_CHECK(NSEnumerator, 
                 gtm_filteredEnumeratorByMakingEachObjectPerformSelector:
                 withObject:);
GTM_METHOD_CHECK(NSArray, gtm_mergeArray:mergeSelector:);
GTM_METHOD_CHECK(NSEnumerator,
                 gtm_filteredEnumeratorByMakingEachObjectPerformSelector:
                 withObject:);
GTM_METHOD_CHECK(NSEnumerator,
                 gtm_enumeratorByMakingEachObjectPerformSelector:
                 withObject:);
GTM_METHOD_CHECK(NSObject, gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);

+ (NSSet *)keyPathsForValuesAffectingSourceExtensions {
  NSSet *affectingKeys = [NSSet setWithObject:@"plugins"];
  return affectingKeys;
}

- (id)init {
  if ((self = [super init])) {
    hgsDelegate_ = [[QSBHGSDelegate alloc] init];
    [[HGSModuleLoader sharedModuleLoader] setDelegate:hgsDelegate_];
    NSNotificationCenter *workSpaceNC 
      = [[NSWorkspace sharedWorkspace] notificationCenter];
    [workSpaceNC addObserver:self
                    selector:@selector(didLaunchApp:)
                        name:NSWorkspaceDidLaunchApplicationNotification
                      object:nil];
    [workSpaceNC addObserver:self
                    selector:@selector(didTerminateApp:)
                        name:NSWorkspaceDidTerminateApplicationNotification
                      object:nil];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(actionWillPerformNotification:)
               name:kQSBQueryControllerWillPerformActionNotification
             object:nil];
    [nc addObserver:self 
           selector:@selector(pluginOrExtensionDidChangeEnabled:)
               name:kHGSPluginDidChangeEnabledNotification
             object:nil];
    [nc addObserver:self 
           selector:@selector(pluginOrExtensionDidChangeEnabled:)
               name:kHGSExtensionDidChangeEnabledNotification
             object:nil];
    [nc addObserver:self 
           selector:@selector(didAddOrRemoveAccount:) 
               name:kHGSDidAddAccountNotification 
             object:nil];
    [nc addObserver:self 
           selector:@selector(didAddOrRemoveAccount:) 
               name:kHGSDidRemoveAccountNotification 
             object:nil];
    
    [QSBPreferences registerDefaults];
    BOOL iconInDock
      = [[NSUserDefaults standardUserDefaults] boolForKey:kQSBIconInDockKey];
    if (iconInDock) {
      ProcessSerialNumber psn = { 0, kCurrentProcess };
      TransformProcessType(&psn, kProcessTransformToForegroundApplication);
    }
    hotModifierDeltaTime_ = [QSBUISettings doubleClickTime];
    searchWindowController_ = [[QSBSearchWindowController alloc] init];
  }
  return self;
}

- (void)dealloc {
  [self stopObservingProtoExtensions];
  [statusItem_ release];
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  [prefs gtm_removeObserver:self 
                 forKeyPath:kQSBHotKeyKey
                   selector:@selector(hotKeyValueChanged:)];
  [prefs gtm_removeObserver:self 
                 forKeyPath:kQSBIconInMenubarKey
                   selector:@selector(iconInMenubarValueChanged:)];
  NSNotificationCenter *workspaceNC 
    = [[NSWorkspace sharedWorkspace] notificationCenter];
  [workspaceNC removeObserver:self];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [prefsWindowController_ release];
  [hgsDelegate_ release];
  [plugins_ release];
  [searchWindowController_ release];
  [super dealloc];
}

- (void)awakeFromNib {
  // set up all our menu bar UI
  [self updateIconInMenubar];

  [self updateMenuWithAppName:[NSApp mainMenu]];
  [self updateMenuWithAppName:dockMenu_];
  [self updateMenuWithAppName:statusItemMenu_];
  
  // watch for prefs changing
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults gtm_addObserver:self
                 forKeyPath:kQSBHotKeyKey
                   selector:@selector(hotKeyValueChanged:)
                   userInfo:nil
                    options:0];
  [defaults gtm_addObserver:self
                 forKeyPath:kQSBIconInMenubarKey
                   selector:@selector(iconInMenubarValueChanged:)
                   userInfo:nil
                    options:0];
  [statusShowSearchBoxItem_ setTarget:searchWindowController_];
  [statusShowSearchBoxItem_ setAction:@selector(showSearchWindow:)];
  [dockShowSearchBoxItem_ setTarget:searchWindowController_];
  [dockShowSearchBoxItem_ setAction:@selector(showSearchWindow:)];
}

- (void)hotKeyValueChanged:(GTMKeyValueChangeNotification *)note {
  [self updateHotKeyRegistration];
}

- (void)iconInMenubarValueChanged:(GTMKeyValueChangeNotification *)note {
  [self updateIconInMenubar];
}

// method that is called when the modifier keys are hit and we are inactive
- (void)modifiersChangedWhileInactive:(NSEvent*)event {
  // If we aren't activated by hotmodifiers, we don't want to be here
  // and if we are in the process of activating, we want to ignore the hotkey
  // so we don't try to process it twice.
  if (!hotModifiers_ || [NSApp keyWindow]) return;
  
  NSUInteger flags = [event qsbModifierFlags];
  if (flags != hotModifiers_) return;
  const useconds_t oneMilliSecond = 10000;
  UInt16 modifierKeys[] = {
    0,
    kVK_Shift,
    kVK_CapsLock,
    kVK_RightShift,
  };
  if (hotModifiers_ == NSControlKeyMask) {
    modifierKeys[0] = kVK_Control;
  } else if (hotModifiers_ == NSAlternateKeyMask) {
    modifierKeys[0]  = kVK_Option;
  } else if (hotModifiers_ == NSCommandKeyMask) {
    modifierKeys[0]  = kVK_Command;
  }
  QSBKeyMap *hotMap = [[[QSBKeyMap alloc] initWithKeys:modifierKeys
                                               count:1] autorelease];
  QSBKeyMap *invertedHotMap
    = [[[QSBKeyMap alloc] initWithKeys:modifierKeys
                                count:sizeof(modifierKeys) / sizeof(UInt16)]
       autorelease];
  invertedHotMap = [invertedHotMap keyMapByInverting];
  NSTimeInterval startDate = [NSDate timeIntervalSinceReferenceDate];
  BOOL isGood = NO;
  while(([NSDate timeIntervalSinceReferenceDate] - startDate) 
        < hotModifierDeltaTime_) {
    QSBKeyMap *currentKeyMap = [QSBKeyMap currentKeyMap];
    if ([currentKeyMap containsAnyKeyIn:invertedHotMap]) {
      return;
    }
    if (![currentKeyMap containsAnyKeyIn:hotMap]) {
      // Key released;
      isGood = YES;
      break;
    }
    usleep(oneMilliSecond);
  }
  if (!isGood) return;
  isGood = NO;
  startDate = [NSDate timeIntervalSinceReferenceDate];
  while(([NSDate timeIntervalSinceReferenceDate] - startDate) 
        < hotModifierDeltaTime_) {
    QSBKeyMap *currentKeyMap = [QSBKeyMap currentKeyMap];
    if ([currentKeyMap containsAnyKeyIn:invertedHotMap]) {
      return;
    }
    if ([currentKeyMap containsAnyKeyIn:hotMap]) {
      // Key down
      isGood = YES;
      break;
    }
    usleep(oneMilliSecond);
  }
  if (!isGood) return;
  startDate = [NSDate timeIntervalSinceReferenceDate];
  while(([NSDate timeIntervalSinceReferenceDate] - startDate) 
        < hotModifierDeltaTime_) {
    QSBKeyMap *currentKeyMap = [QSBKeyMap currentKeyMap];
    if ([currentKeyMap containsAnyKeyIn:invertedHotMap]) {
      return;
    }
    if (![currentKeyMap containsAnyKeyIn:hotMap]) {
      // Key Released
      isGood = YES;
      break;
    }
    usleep(oneMilliSecond);
  }
  if (isGood) {
    [self hitHotKey:self];
  }
}

- (void)modifiersChangedWhileActive:(NSEvent*)event {
  // A statemachine that tracks our state via hotModifiersState_.
  // Simple incrementing state.
  if (!hotModifiers_) {
    return;
  }
  NSTimeInterval lastTime = lastHotModifiersEventCheckedTime_;
  lastHotModifiersEventCheckedTime_ = [event timestamp];
  if (hotModifiersState_
      && lastHotModifiersEventCheckedTime_ > lastTime + hotModifierDeltaTime_) {
    // Timed out. Reset.
    hotModifiersState_ = 0;
    return;
  }
  NSUInteger flags = [event qsbModifierFlags];
  BOOL isGood = NO;
  if (!(hotModifiersState_ % 2)) {
    // This is key down cases
    isGood = flags == hotModifiers_;
  } else {
    // This is key up cases
    isGood = flags == 0;
  }
  if (!isGood) {
    // reset
    hotModifiersState_ = 0;
    return;
  } else {
    hotModifiersState_ += 1;
  }
  if (hotModifiersState_ == 3) {
    // We've worked our way through the state machine to success!
    [self hitHotKey:self];
  }
}

// method that is called when a key changes state and we are active
- (void)keysChangedWhileActive:(NSEvent*)event {
  if (!hotModifiers_) return;
  hotModifiersState_ = 0;
}

- (IBAction)orderFrontStandardAboutPanel:(id)sender {
  [NSApp activateIgnoringOtherApps:YES];
  [NSApp orderFrontStandardAboutPanelWithOptions:nil];
}

- (IBAction)showPreferences:(id)sender {
  if (!prefsWindowController_) {
    prefsWindowController_ = [[QSBPreferenceWindowController alloc] init];
  }
  [prefsWindowController_ showPreferences:sender];
  [NSApp activateIgnoringOtherApps:YES];
}

// Open a browser window with the QSB homepage
- (IBAction)showProductHomepage:(id)sender {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *homepageStr = [bundle objectForInfoDictionaryKey:kQSBHomepageKey];
  NSURL *homepageURL = [NSURL URLWithString:homepageStr];
  [[NSWorkspace sharedWorkspace] openURL:homepageURL];
}

- (IBAction)sendFeedbackToGoogle:(id)sender { 
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *feedbackStr = [bundle objectForInfoDictionaryKey:kQSBFeedbackKey];
  NSURL *feedbackURL = [NSURL URLWithString:feedbackStr];
  [[NSWorkspace sharedWorkspace] openURL:feedbackURL];
}

- (NSMenu*)statusItemMenu {
  return statusItemMenu_;
}

- (void)updateIconInMenubar {
  BOOL iconInMenubar 
    = [[NSUserDefaults standardUserDefaults] boolForKey:kQSBIconInMenubarKey];
  NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
  if (iconInMenubar) {
    NSImage *defaultImg = [NSImage imageNamed:@"QSBStatusMenuIconGray"];
    NSImage *altImg = [NSImage imageNamed:@"QSBStatusMenuIconGrayInverted"];
    HGSAssert(defaultImg, @"Can't find QSBStatusMenuIconGray");
    HGSAssert(altImg,  @"Can't find QSBStatusMenuIconGrayInverted");
    statusItem_ 
      = [[statusBar statusItemWithLength:NSSquareStatusItemLength] retain];
    [statusItem_ setMenu:statusItemMenu_];
    [statusItem_ setHighlightMode:YES];
    [statusItem_ setImage:defaultImg];
    [statusItem_ setAlternateImage:altImg];
  } else if (statusItem_) {
    [statusBar removeStatusItem:statusItem_];
    [statusItem_ autorelease];
    statusItem_ = nil;
  }
}

- (void)updateHotKeyRegistration {
  GTMCarbonEventDispatcherHandler *dispatcher 
    = [GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler];

  // Remove any hotkey we currently have.
  if (hotKey_) {
    [dispatcher unregisterHotKey:hotKey_];
    hotKey_ = nil;
  }

  NSMenuItem *statusMenuItem = [statusItemMenu_ itemAtIndex:0];
  NSString *statusMenuItemKey = @"";
  uint statusMenuItemModifiers = 0;
  [statusMenuItem setKeyEquivalent:statusMenuItemKey];
  [statusMenuItem setKeyEquivalentModifierMask:statusMenuItemModifiers];
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSDictionary *newKey = [ud valueForKeyPath:kQSBHotKeyKey];
  NSNumber *value = [newKey objectForKey:kGTMHotKeyDoubledModifierKey];
  if (!newKey || [value boolValue]) {
    // set up double tap if appropriate
    if (newKey) {
      value = [newKey objectForKey:kGTMHotKeyModifierFlagsKey];
      hotModifiers_ = [value unsignedIntValue];
    } else {
      hotModifiers_ = NSCommandKeyMask;
    }
    statusMenuItemKey = [NSString stringWithUTF8String:"⌘"];
    statusMenuItemModifiers = NSCommandKeyMask;
  } else {
    // setting hotModifiers_ means we're not looking for a double tap
    hotModifiers_ = 0;
    value = [newKey objectForKey:kGTMHotKeyModifierFlagsKey];
    uint modifiers = [value unsignedIntValue];
    value = [newKey objectForKey:kGTMHotKeyKeyCodeKey];
    uint keycode = [value unsignedIntValue];
    //fix for http://b/issue?id=596931
    if (modifiers != 0) {
      hotKey_ = [dispatcher registerHotKey:keycode
                                 modifiers:modifiers
                                    target:self
                                    action:@selector(hitHotKey:)
                               whenPressed:YES];

      NSBundle *bundle = [NSBundle mainBundle];
      statusMenuItemKey = [GTMHotKeyTextField stringForKeycode:keycode
                                                      useGlyph:YES
                                                resourceBundle:bundle];
      statusMenuItemModifiers = modifiers;
    }
  }
  [statusMenuItem setKeyEquivalent:statusMenuItemKey];
  [statusMenuItem setKeyEquivalentModifierMask:statusMenuItemModifiers];
}

- (QSBSearchWindowController *)searchWindowController { 
  return searchWindowController_;
}

- (void)hitHotKey:(id)sender {
  hotModifiersState_ = 0;
  if (otherQSBPid_) {
    // We bow down before the other QSB
    return;
  }

  // Try to (partially) address radar 5856746. On Leopard we can steal focus
  // from the screensaver password dialog (SecurityAgent.app) on hotkey.
  // This is an Apple bug, and potential lets an attacker open Terminal and
  // type commands.
  // We can't fix this (there is a race condition around detecting whether
  // the screensaver is frontmost), but we can at least try to make it
  // less likely.
  // Also check to see if frontRow is running, and if so beep and don't
  // activate. 
  // For http://buganizer/issue?id=652067
  if ([self isScreenSaverActive] || [self frontRowActive]) {
    NSBeep();
    return;
  }
  
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBApplicationDidHitHotKeyNotification 
                    object:NSApp];
}

- (BOOL)isScreenSaverActive {
  NSDictionary *processInfo 
  = [[NSWorkspace sharedWorkspace] gtm_processInfoDictionaryForActiveApp];    
  NSString *bundlePath 
  = [processInfo objectForKey:kGTMWorkspaceRunningBundlePath];
  // ScreenSaverEngine is the frontmost app if the screen saver is actually
  // running Security Agent is the frontmost app if the "enter password"
  // dialog is showing
  return ([bundlePath hasSuffix:@"ScreenSaverEngine.app"] 
          || [bundlePath hasSuffix:@"SecurityAgent.app"]);
}

- (BOOL)frontRowActive {
  // Can't use NSWorkspace here because of
  // rdar://5049713 When FrontRow is frontmost app, 
  // [NSWorkspace -activeApplication] returns nil
  NSDictionary *processDict 
  = [[NSWorkspace sharedWorkspace] gtm_processInfoDictionaryForActiveApp];
  NSString *bundleID 
  = [processDict objectForKey:kGTMWorkspaceRunningBundleIdentifier];
  return [bundleID isEqualToString:@"com.apple.frontrow"];
}

- (void)updateMenuWithAppName:(NSMenu* )menu {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *newName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
  NSArray *items = [menu itemArray];
  for (NSMenuItem *item in items) {
    NSString *appName = @"$APPNAME$";
    NSString *title = [item title];
    
    if ([title rangeOfString:appName].length != 0) {
      NSString *newTitle = [title stringByReplacingOccurrencesOfString:appName
                                                            withString:newName];
      [item setTitle:newTitle];
    }
    NSMenu *subMenu = [item submenu];
    if (subMenu) {
      [self updateMenuWithAppName:subMenu];
    }
  }
}



#pragma mark Plugins & Extensions Management

- (NSArray *)plugins {
  return [[plugins_ retain] autorelease];
}

- (void)inventoryPlugins {
  // Retrieve list of and configuration information for previously
  // inventoried plug-ins and mark as undiscovered.
  NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
  NSArray *pluginsFromPrefs = [standardDefaults
                               objectForKey:kQSBPluginConfigurationPrefKey];
  NSUInteger pluginCount = [pluginsFromPrefs count];
  NSMutableArray *oldPlugins = [NSMutableArray arrayWithCapacity:pluginCount];
  for (NSDictionary *pluginFromPrefs in pluginsFromPrefs) {
    id oldPlugin = [[[HGSPlugin alloc] initWithDictionary:pluginFromPrefs]
                    autorelease];
    if (oldPlugin) {
      [oldPlugins addObject:oldPlugin];
    }
  }
  
  // Rediscover plug-ins by scanning all plugin folders.
  NSMutableArray *factorablePlugins = [NSMutableArray array];
  NSArray *pluginPaths = [hgsDelegate_ pluginFolders];
  for (NSString *pluginPath in pluginPaths) {
    NSArray *pathPlugins
    = [[HGSModuleLoader sharedModuleLoader] loadPluginsAtPath:pluginPath];
    [factorablePlugins addObjectsFromArray:pathPlugins];
  }
  
  // Install the account type extensions.  We do this here because we 
  // want the account types to be available before factoring extensions  
  // that rely on those account types.
  [factorablePlugins makeObjectsPerformSelector:@selector(installAccountTypes)];
  
  // Identify our accounts now that we know about available account types.
  [self inventoryAccounts];
  
  // Factor the new extensions now that we know all available accounts.
  [factorablePlugins makeObjectsPerformSelector:@selector(factorExtensions)];
  
  oldPlugins = [self mergePlugins:factorablePlugins intoPlugins:oldPlugins];
  
  // Review our plugins and see if there are any that have gone missing.
  // TODO(mrossetti): We just strip those out for now.  Should we do
  // something else?
  NSEnumerator *oldPluginsEnum = [oldPlugins objectEnumerator];
  NSEnumerator *availablePluginsEnum
  = [oldPluginsEnum
     gtm_filteredEnumeratorByMakingEachObjectPerformSelector:@selector(notIsOld)
     withObject:nil];
  NSArray *availablePlugins = [availablePluginsEnum allObjects];
  
  // Tell all non-new plugins to strip unmatched old extensions.
  // TODO(mrossetti): Do we want to review with the user before doing this?
  NSEnumerator *allAvailablePluginsEnum = [availablePlugins objectEnumerator];
  NSEnumerator *mergedPluginsEnum
  = [allAvailablePluginsEnum
     gtm_filteredEnumeratorByMakingEachObjectPerformSelector:@selector(notIsNew)
     withObject:nil];
  NSArray *allMergedPlugins = [mergedPluginsEnum allObjects];
  [allMergedPlugins
   makeObjectsPerformSelector:@selector(stripOldUnmergedExtensions)];
  
  // TODO(mrossetti): Implement special configurating when required.
  // Review our plugins and see if there are any new modules which require
  // configuration before enabling.
  
  // Review plugins for new extensions that should not automatically be
  // enabled.
  [availablePlugins
   makeObjectsPerformSelector:@selector(autoSetEnabledForNewExtensions)];
  
  
  // Save the current plugin/extension configuration.
  [self setPlugins:availablePlugins];
  
  // Lock and load all enabled modules, sources and actions.
  NSEnumerator *availableEnum = [availablePlugins objectEnumerator];
  NSEnumerator *pluginsToEnableEnum
  = [availableEnum
     gtm_filteredEnumeratorByMakingEachObjectPerformSelector:@selector(isEnabled)
     withObject:nil];
  for (HGSPlugin *plugin in pluginsToEnableEnum) {
    [plugin installExtensions];
  }
}

- (NSMutableArray *)mergePlugins:(NSArray *)factorablePlugins
                     intoPlugins:(NSArray *)oldPlugins {
  // Match up extensions in |modules| with those already in |oldPlugins| by
  // identifier, path.  If there's an exact match then treat it as 'known'.
  // Otherwise, treat it as 'new'.  No plugin loading and enabling occurs
  // in this method.
  // TODO(mrossetti): Enhance the merge function in the future to handle
  // updated versions, plugins which appear in multiple paths, plugins
  // which have moved, and plugins which have updated versions.
  // TODO(mrossetti): This might be a good spot for reconciling extensions
  // that require account access.
  NSMutableArray *mergedPlugins
  = [[[oldPlugins gtm_mergeArray:factorablePlugins
                   mergeSelector:@selector(merge:)] mutableCopy] autorelease];
  return mergedPlugins;
}

- (void)setPlugins:(NSArray *)plugins {
  [self stopObservingProtoExtensions];
  [plugins_ autorelease];
  plugins_ = [plugins retain];
  [self observeProtoExtensions];
  [self updatePluginPreferences];
}

- (void)updatePluginPreferences {
  // Save these plugins in preferences.
  NSEnumerator *archivePluginEnum
  = [[[self plugins] objectEnumerator]
     gtm_enumeratorByMakingEachObjectPerformSelector:@selector(dictionaryValue)
     withObject:nil];
  NSArray *archivablePlugins = [archivePluginEnum allObjects]; 
  NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
  [standardDefaults setObject:archivablePlugins
                       forKey:kQSBPluginConfigurationPrefKey];
  [standardDefaults synchronize];
}

- (NSArray *)sourceExtensions {
  // Iterate through all plugins and gather all source extensions.
  NSMutableArray *protoExtensions = [NSMutableArray array];
  for (HGSPlugin *plugin in [self plugins]) {
    NSArray *allExtensions = [plugin protoExtensions];
    NSEnumerator *allExtensionsEnum = [allExtensions objectEnumerator];
    NSEnumerator *sourceProtoExtensionsEnum
      = [allExtensionsEnum
         gtm_filteredEnumeratorByMakingEachObjectPerformSelector:
           @selector(isUserVisibleAndExtendsExtensionPoint:)
         withObject:kHGSSourcesExtensionPoint];
    NSArray *allsourceProtoExtensions = [sourceProtoExtensionsEnum allObjects];
    [protoExtensions addObjectsFromArray:allsourceProtoExtensions];
  }
  return protoExtensions;
}

- (void)observeProtoExtensions {
  NSArray *plugins = [self plugins];
  for (HGSPlugin *plugin in plugins) {
    [plugin gtm_addObserver:self
                 forKeyPath:kQSBProtoExtensionsKVOKey
                   selector:@selector(protoExtensionsValueChanged:) 
                   userInfo:nil
                    options:0];
  }
}

- (void)stopObservingProtoExtensions {
  NSArray *plugins = [self plugins];
  for (HGSPlugin *plugin in plugins) {
    [plugin gtm_removeObserver:self 
                    forKeyPath:kQSBProtoExtensionsKVOKey
                      selector:@selector(protoExtensionsValueChanged:)];
  }
}

- (void)protoExtensionsValueChanged:(GTMKeyValueChangeNotification *)note {
  [self willChangeValueForKey:kQSBSourceExtensionsKVOKey];
  [self didChangeValueForKey:kQSBSourceExtensionsKVOKey];
}

#pragma mark Account Management

- (NSArray *)accounts {
  HGSAccountsExtensionPoint *accountsExtensionPoint
    = [HGSAccountsExtensionPoint accountsExtensionPoint];
  NSArray *accounts = [accountsExtensionPoint extensions];
  return accounts;
}

- (void)inventoryAccounts {
  HGSAccountsExtensionPoint *accountsExtensionPoint
  = [HGSAccountsExtensionPoint accountsExtensionPoint];
  // Retrieve list of known accounts.
  NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
  NSArray *accountsFromPrefs = [standardDefaults
                                objectForKey:kQSBAccountsPrefKey];
  [accountsExtensionPoint addAccountsFromArray:accountsFromPrefs];
}

#pragma mark Application Delegate Methods

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
  [self updateHotKeyRegistration];
  
  // Inventory and process all plugins and extensions.
  [self inventoryPlugins];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)theApplication
                    hasVisibleWindows:(BOOL)flag {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBApplicationDidReopenNotification
                    object:NSApp];  
  return NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
  hotModifiersState_ = 0;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  if (hotKey_) {
    GTMCarbonEventDispatcherHandler *dispatcher 
      = [GTMCarbonEventDispatcherHandler sharedEventDispatcherHandler];
    [dispatcher unregisterHotKey:hotKey_];
    hotKey_ = nil;
  }
  
  // Clean up our dock tile in case it got modified when
  // another qsb was launched.
  NSDockTile *tile = [NSApp dockTile];
  [tile setContentView:nil];
  [tile display];
  
  // Set it so we don't think this is first launch anymore
  [[NSUserDefaults standardUserDefaults] setBool:YES 
                                          forKey:kQSBBeenLaunchedPrefKey];
  
  // Uninstall all extensions.
  [plugins_ makeObjectsPerformSelector:@selector(uninstallExtensions)];
}

// Reroute certain properties off to our delegate for scripting purposes.
- (BOOL)application:(NSApplication *)sender delegateHandlesKey:(NSString *)key
{
  if ([key isEqual:@"plugins"] || [key isEqual:kQSBSourceExtensionsKVOKey]) {
    return YES;
  } else {
    return NO;
  }
}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
  return dockMenu_;
}

#pragma mark Notifications

- (void)actionWillPerformNotification:(NSNotification *)notification {
  id<HGSAction> action = [notification object];
  if ([action doesActionCauseUIContextChange]) {
    [searchWindowController_ hideSearchWindow:nil];
  }
}

- (void)pluginOrExtensionDidChangeEnabled:(NSNotification*)notification {
  // A plugin or extension has been enabled or disabled.  Update our prefs.
  [self updatePluginPreferences];
}

// If we launch up another QSB we will let it handle all the activations until
// it dies. This is to make working with QSB easier for us as we can have a
// version running all the time, even when we are debugging the newer version.
// See "hitHotKey:" to see where otherQSBPid_ is actually used.
- (void)didLaunchApp:(NSNotification *)notification {
  if (!otherQSBPid_) {
    NSDictionary *userInfo = [notification userInfo];
    NSString *bundleID 
      = [userInfo objectForKey:@"NSApplicationBundleIdentifier"];
    NSString *myBundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSNumber *nsPid = [userInfo objectForKey:@"NSApplicationProcessIdentifier"];
    pid_t pid = [nsPid intValue];
    if (pid != getpid() && [bundleID isEqualToString:myBundleID]) {
      otherQSBPid_ = pid;
      
      // Fade out our dock tile
      NSDockTile *tile = [NSApp dockTile];
      NSRect tileRect = GTMNSRectOfSize([tile size]);
      NSImage *appImage = [NSImage imageNamed:@"NSApplicationIcon"];
      NSImage *newImage 
        = [[[NSImage alloc] initWithSize:tileRect.size] autorelease];
      [newImage lockFocus];
      [appImage drawInRect:tileRect
                  fromRect:GTMNSRectOfSize([appImage size]) 
                 operation:NSCompositeCopy
                  fraction:0.3];
      [newImage unlockFocus];
      NSImageView *imageView 
        = [[[NSImageView alloc] initWithFrame:tileRect] autorelease];
      [imageView setImageFrameStyle:NSImageFrameNone];
      [imageView setImageScaling:NSImageScaleProportionallyDown];      
      [imageView setImage:newImage];
      [tile setContentView:imageView];
      [tile display];
    }
  }
}

- (void)didTerminateApp:(NSNotification *)notification {
  if (otherQSBPid_) {
    NSDictionary *userInfo = [notification userInfo];
    NSString *bundleID 
      = [userInfo objectForKey:@"NSApplicationBundleIdentifier"];
    if ([bundleID isEqualToString:[[NSBundle mainBundle] bundleIdentifier]]) {
      NSNumber *nsDeadPid 
        = [userInfo objectForKey:@"NSApplicationProcessIdentifier"];
      pid_t deadPid = [nsDeadPid intValue];
      if (deadPid == otherQSBPid_) {
        otherQSBPid_ = 0;
        NSDockTile *tile = [NSApp dockTile];
        [tile setContentView:nil];
        [tile display];
      }
    }
  }
}

- (void)didAddOrRemoveAccount:(NSNotification *)notification {
  // What should we do?
  [self willChangeValueForKey:@"accounts"];

  // Update preferences to current account knowledge.
  NSArray *archivableAccounts
    = [[HGSAccountsExtensionPoint accountsExtensionPoint] accountsAsArray]; 
  NSUserDefaults *standardDefaults = [NSUserDefaults standardUserDefaults];
  [standardDefaults setObject:archivableAccounts
                       forKey:kQSBAccountsPrefKey];
  [standardDefaults synchronize];

  [self didChangeValueForKey:@"accounts"];
}




@end


@implementation NSEvent (QSBApplicationEventAdditions)

- (NSUInteger)qsbModifierFlags {
  NSUInteger flags 
    = ([self modifierFlags] & NSDeviceIndependentModifierFlagsMask);
  // Ignore caps lock if it's set http://b/issue?id=637380
  if (flags & NSAlphaShiftKeyMask) flags -= NSAlphaShiftKeyMask;
  // Ignore numeric lock if it's set http://b/issue?id=637380
  if (flags & NSNumericPadKeyMask) flags -= NSNumericPadKeyMask;
  return flags;
}

@end

