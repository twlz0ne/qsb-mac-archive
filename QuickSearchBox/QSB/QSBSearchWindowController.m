//
//  QSBSearchWindowController.m
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

#import "QSBSearchWindowController.h"

#import <QuartzCore/QuartzCore.h>

#import "QSBLargeIconView.h"
#import "QSBApplicationDelegate.h"
#import "QSBTextField.h"
#import "QSBPreferences.h"
#import "QSBSearchController.h"
#import "QSBSearchViewController.h"
#import "QSBCustomPanel.h"
#import "GTMMethodCheck.h"
#import "GTMNSImage+Scaling.h"
#import "GoogleCorporaSource.h"
#import "QSBResultsViewBaseController.h"
#import "QSBTableResult.h"
#import "GTMNSWorkspace+Running.h"
#import "QLUIPrivate.h"
#import "GTMNSObject+KeyValueObserving.h"
#import "GTMNSAppleEventDescriptor+Foundation.h"
#import "NSString+CaseInsensitive.h"
#import "QSBTableResult.h"
#import "QSBWelcomeController.h"
#import "QSBViewAnimation.h"
#import "QSBSimpleInvocation.h"

static const NSTimeInterval kQSBShowDuration = 0.1;
static const NSTimeInterval kQSBHideDuration = 0.3;
static const NSTimeInterval kQSBShortHideDuration = 0.15;
static const NSTimeInterval kQSBResizeDuration = 0.1;
static const NSTimeInterval kQSBPushPopDuration = 0.2;
const NSTimeInterval kQSBAppearDelay = 0.2;
static const NSTimeInterval kQSBLongerAppearDelay = 0.667;
const NSTimeInterval kQSBUpdateSizeDelay = 0.333;
static const NSTimeInterval kQSBReshowResultsDelay = 4.0;
static const CGFloat kTextFieldPadding = 2.0;
static const CGFloat kResultsAnimationDistance = 12.0;

// Should we fade the background. User default. Bool value.
static NSString * const kQSBSearchWindowDimBackground
  = @"QSBSearchWindowDimBackground";
// How long should the fade animation be. User default. Float value.
static NSString * const kQSBSearchWindowDimBackgroundDuration
  = @"QSBSearchWindowDimBackgroundDuration";
// How dark should the fade be. User default. Float value.
static NSString * const kQSBSearchWindowDimBackgroundAlpha
  = @"QSBSearchWindowDimBackgroundAlpha";

static NSString * const kQSBHideQSBWhenInactivePrefKey = @"hideQSBWhenInactive";
static NSString * const kQSBSearchWindowFrameTopPrefKey
  = @"QSBSearchWindow Top QSBSearchResultsWindow";
static NSString * const kQSBSearchWindowFrameLeftPrefKey
  = @"QSBSearchWindow Left QSBSearchResultsWindow";
static NSString * const kQSBUserPrefBackgroundColorKey = @"backgroundColor";
static NSString * const kQSBQueryStringKey = @"queryString";

static NSString * const kQSBMainInterfaceNibName = @"MainInterfaceNibName";
static NSString * const kQSBWelcomeWindowNibName = @"WelcomeWindow";

static NSString * const kQSBAnimationNameKey = @"QSBAnimationName";

// Animation names
static NSString *const kQSBHideSearchAndResultsWindowAnimationName
  = @"QSBHideSearchAndResultsWindowAnimationName";

static NSString *const kQSBResultWindowVisibilityAnimationName 
  = @"QSBResultWindowVisibilityAnimationName"; 
static NSString *const kQSBSearchWindowVisibilityAnimationName 
  = @"QSBSearchWindowVisibilityAnimationName"; 
static NSString *const kQSBPivotingAnimationName 
  = @"QSBPivotingAnimationName"; 
static NSString *const kQSBResultWindowFrameAnimationName 
  = @"QSBResultWindowFrameAnimationName"; 
static NSString *const kQSBSearchWindowFrameAnimationName 
  = @"QSBSearchWindowFrameAnimationName"; 

// NSNumber value in seconds that controls how fast the QSB clears out
// an old query once it's put in the background.
static NSString *const kQSBResetQueryTimeoutPrefKey 
  = @"QSBResetQueryTimeoutPrefKey";

// This is a tag value for corpora in the corpora menu.
static const NSInteger kBaseCorporaTagValue = 10000;

@interface QSBSearchWindowController ()

@property (nonatomic, retain) QSBWelcomeController *welcomeController;

- (void)updateLogoView;
- (BOOL)firstLaunch;

// Bottleneck function for registering/deregistering for window changes.
- (void)setObservingMoveAndResizeNotifications:(BOOL)doRegister;

// Utility function to update the shadows around our custom table view
- (void)updateShadows;

// Hides the result window.
- (void)hideResultsWindow;

// Shows the result window.
- (void)showResultsWindow;

// Reposition our window on screen as appropriate
- (void)centerWindowOnScreen;

// Sets the currently active search view controller.  Should only be called by
// push/popQueryController.
- (void)setActiveSearchViewController:(QSBSearchViewController *)controller;

// Pushes or pops the top (active) view controller.
- (void)pushViewController:(NSViewController *)viewController;

// Pops off and releases the top view controller and returns the popped
// view controller if is it isn't the base controller.
- (NSViewController *)popViewControllerAnimate:(BOOL)animate;

// Flush all stacked view/query controllers and clear the search text
// without any user visible view changes.
- (void)clearAllViewControllersAndSearchString;

// Resets the query to blank after a given time interval
- (void)resetQuery:(NSTimer *)timer;

// Checks the find pasteboard to see if it's changed
- (void)checkFindPasteboard:(NSTimer *)timer;

- (void)displayResults:(NSTimer *)timer;

// Returns YES if the screen that our search window is on is captured.
// NOTE: Frontrow in Tiger DOES NOT capture the screen, so this is not a valid
// way of checking for Frontrow. The only way we know of to check for Frontrow
// is the method used by GoogleDesktop to do it. Search for "5049713"
- (BOOL)isOurScreenCaptured;

// Returns the content view of the results window
- (NSView *)resultsView;

// Returns the left/right/main view rects for push/pop animations
- (NSRect)rightOffscreenViewRect;
- (NSRect)leftOffscreenViewRect;
- (NSRect)mainViewRect;

// Given a proposed frame, returns a frame that fully exposes 
// the proposed frame on |screen| as close to it's original position as 
// possible.
// Args:
//    proposedFrame - the frame to be adjusted to fit on the screen
//    respectingDock - if YES, we won't cover the dock.
//    screen - the screen the rect is on
// Returns:
//   The frame rect offset such that if used to position the window
//   will fully exposes the window on the screen. If the proposed
//   frame is bigger than the screen, it is anchored to the upper
//   left.  The size of the proposed frame is never adjusted.
- (NSRect)fullyExposedFrameForFrame:(NSRect)proposedFrame
                     respectingDock:(BOOL)respectingDock
                           onScreen:(NSScreen *)screen;

// Update token in text field
- (void)updatePivotToken;

- (void)hideSearchWindowBecause:(NSString *)toggle;

// Presents the welcome window.
- (void)showWelcomeWindow;

// Closes and disposes of the welcome window and its controller.
- (void)closeWelcomeWindow;

// Change the visibility of the welcome window.
- (void)setWelcomeHidden:(BOOL)hidden;

- (QSBTableResult *)selectedTableResult;
@end


@implementation QSBSearchWindowController

@synthesize activeSearchViewController = activeSearchViewController_;
@synthesize welcomeController = welcomeController_;

GTM_METHOD_CHECK(NSWorkspace, gtm_processInfoDictionary);
GTM_METHOD_CHECK(NSWorkspace, gtm_wasLaunchedAsLoginItem);

GTM_METHOD_CHECK(NSObject, 
                 gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);
GTM_METHOD_CHECK(NSAppleEventDescriptor, gtm_arrayValue);
GTM_METHOD_CHECK(NSString, qsb_hasPrefix:options:)

- (id)init {
  // Read the nib name from user defaults to allow for ui switching
  // Defaults to ResultsWindow.xib
  NSString *nibName = [[NSUserDefaults standardUserDefaults]
                        stringForKey:kQSBMainInterfaceNibName];
  if (!nibName) nibName = @"ResultsWindow";
  if ((self = [self initWithWindowNibName:nibName])) {
    [self loadWindow];
  }
  return self;
}

- (void)awakeFromNib {  
  // If we have a remembered position for the search window then restore it.
  // Note: See note in |windowPositionChanged:|.
  NSWindow *searchWindow = [self window];
  NSPoint topLeft = NSMakePoint(
                                [[NSUserDefaults standardUserDefaults]
                                 floatForKey:kQSBSearchWindowFrameLeftPrefKey],
                                [[NSUserDefaults standardUserDefaults]
                                 floatForKey:kQSBSearchWindowFrameTopPrefKey]);
  [searchWindow setFrameTopLeftPoint:topLeft];
  // Now insure that the window's frame is fully visible.
  NSRect searchFrame = [searchWindow frame];
  NSRect actualFrame = [self fullyExposedFrameForFrame:searchFrame
                                        respectingDock:YES
                                              onScreen:[searchWindow screen]];
  [searchWindow setFrame:actualFrame display:NO];

  // get us so that the IME windows appear above us as necessary.
  // http://b/issue?id=602250
  [searchWindow setLevel:kCGStatusWindowLevel + 2];
  
  // Tell the window to tell us when it has changed position on the screen.
  [self setObservingMoveAndResizeNotifications:YES];
  
  NSUserDefaults *userPrefs = [NSUserDefaults standardUserDefaults];
  [userPrefs gtm_addObserver:self
                  forKeyPath:kQSBSnippetsKey
                    selector:@selector(snippetsChanged:)
                    userInfo:nil
                 options:0];

  [userPrefs gtm_addObserver:self
                  forKeyPath:kQSBUserPrefBackgroundColorKey
                    selector:@selector(backgroundColorChanged:)
                    userInfo:nil
                     options:0];
  
  [self updateLogoView];
  
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc addObserver:self 
         selector:@selector(applicationDidBecomeActive:)
             name:NSApplicationDidBecomeActiveNotification
           object:NSApp];
  
  [nc addObserver:self 
         selector:@selector(applicationWillResignActive:)
             name:NSApplicationWillResignActiveNotification
           object:NSApp];
  
  [nc addObserver:self 
         selector:@selector(applicationDidChangeScreenParameters:)
             name:NSApplicationDidChangeScreenParametersNotification
           object:NSApp];
  
  [nc addObserver:self 
         selector:@selector(applicationDidFinishLaunching:)
             name:NSApplicationDidFinishLaunchingNotification
           object:NSApp];
  
  [nc addObserver:self
         selector:@selector(applicationDidReopen:)
             name:kQSBApplicationDidReopenNotification
           object:NSApp];
  
  // named aWindowDidBecomeKey instead of windowDidBecomeKey because if we
  // used windowDidBecomeKey we would be called twice for our window (once
  // for the notification, and once because we are the search window's delegate)
  [nc addObserver:self
         selector:@selector(aWindowDidBecomeKey:)
             name:NSWindowDidBecomeKeyNotification
           object:nil];

  HGSPluginLoader *sharedLoader = [HGSPluginLoader sharedPluginLoader];
  [nc addObserver:self 
         selector:@selector(pluginWillLoad:) 
             name:kHGSPluginLoaderWillLoadPluginNotification 
           object:sharedLoader];
  [nc addObserver:self 
         selector:@selector(pluginWillInstall:) 
             name:kHGSPluginLoaderWillInstallPluginNotification 
           object:sharedLoader];
  [nc addObserver:self 
         selector:@selector(pluginsDidInstall:) 
             name:kHGSPluginLoaderDidInstallPluginsNotification 
           object:sharedLoader];
  
  // Support spaces on Leopard. 
  // http://b/issue?id=648841

  [searchWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces]; 
  
  [searchWindow setMovableByWindowBackground:YES];
  [searchWindow invalidateShadow];
  [searchWindow setAlphaValue:0.0];
  [resultsWindow_ setCanBecomeKeyWindow:NO];
  [resultsWindow_ setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces]; 
  
  
  // Load up the base results views nib and install the subordinate results views.
  QSBSearchViewController *baseResultsController
    = [[[QSBSearchViewController alloc] initWithWindowController:self]
       autorelease];
  [self pushViewController:baseResultsController];
  
  // get the pasteboard count and make sure we change it to something different
  // so that when the user first brings up the QSB its query is correct.
  NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
  NSTimeInterval resetInterval;
  resetInterval = [userDefaults floatForKey:kQSBResetQueryTimeoutPrefKey];
  if (resetInterval < 1) {
    resetInterval = 60; // One minute
    [userDefaults setDouble:resetInterval forKey:kQSBResetQueryTimeoutPrefKey];
    // No need to worry about synchronize here as somebody else will sync us
  }
  
  // subtracting one just makes sure that we are initialized to something other 
  // than what |changeCount| is going to be. |Changecount| always increments.
  NSPasteboard *findPasteBoard = [NSPasteboard pasteboardWithName:NSFindPboard];
  findPasteBoardChangeCount_ = [findPasteBoard changeCount] - 1;
  [self checkFindPasteboard:nil];
  findPasteBoardChangedTimer_ 
    = [NSTimer scheduledTimerWithTimeInterval:resetInterval
                                       target:self
                                     selector:@selector(checkFindPasteboard:) 
                                     userInfo:nil
                                      repeats:YES];
  if ([self firstLaunch]) {
    [searchWindow center];
  }
  NSString *startupString = HGSLocalizedString(@"Starting up…", 
                                               @"A string shown "
                                               @"at launchtime to denote that QSB " 
                                               @"is starting up.");
  
  [searchTextField_ setStringValue:startupString];
  [searchTextField_ setEnabled:NO];
  
  resultWindowVisibilityAnimation_ 
    = [[QSBViewAnimation alloc] initWithViewAnimations:nil 
                                                  name:kQSBResultWindowVisibilityAnimationName
                                              userInfo:nil];
  [resultWindowVisibilityAnimation_ setDelegate:self];
  
  searchWindowVisibilityAnimation_
    = [[QSBViewAnimation alloc] initWithViewAnimations:nil 
                                                  name:kQSBSearchWindowVisibilityAnimationName
                                              userInfo:nil];
  [searchWindowVisibilityAnimation_ setDelegate:self];
  pivotingAnimation_
    = [[QSBViewAnimation alloc] initWithViewAnimations:nil 
                                                  name:kQSBPivotingAnimationName
                                              userInfo:nil];
  [pivotingAnimation_ setDelegate:self];
  
  [thumbnailView_ setHidden:YES];
  
  [nc addObserver:self 
         selector:@selector(selectedTableResultDidChange:) 
             name:kQSBSelectedTableResultDidChangeNotification 
           object:nil];
}
  
- (void)dealloc {
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  [ud gtm_removeObserver:self 
              forKeyPath:kQSBSnippetsKey
                selector:@selector(snippetsChanged:)];
  [ud gtm_removeObserver:self 
              forKeyPath:kQSBUserPrefBackgroundColorKey
                selector:@selector(backgroundColorChanged:)];
  [self setActiveSearchViewController:nil];
  [queryResetTimer_ invalidate];
  [findPasteBoardChangedTimer_ invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [activeSearchViewController_ release];
  [corpora_ release];
  [welcomeController_ release];
  [resultWindowVisibilityAnimation_ release];
  [searchWindowVisibilityAnimation_ release];
  [pivotingAnimation_ release];
  [super dealloc];
}

- (BOOL)firstLaunch {
  NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
  BOOL beenLaunched = [standardUserDefaults boolForKey:kQSBBeenLaunchedPrefKey];
  return !beenLaunched;
}

- (void)backgroundColorChanged:(GTMKeyValueChangeNotification *)notification {
  [self updateLogoView];
}

- (void)snippetsChanged:(GTMKeyValueChangeNotification *)notification {
  // if they've changed the way we show results, we have to resize our table
  [self updateResultsView];
}

- (void)queryStringChanged:(GTMKeyValueChangeNotification *)notification {
  // The query text has changed so cancel any outstanding display
  // operations and kick off another or clear.
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(displayResults:)
                                             object:nil];
  
  if ([activeSearchViewController_ queryString]
      || [activeSearchViewController_ results]) {
    // Dispose of the welcome window if it is being shown.
    [self closeWelcomeWindow];

    BOOL likelyResult = [[self selectedTableResult] rank] > 1.0;
    NSTimeInterval delay 
      = likelyResult ? kQSBLongerAppearDelay : kQSBAppearDelay;
    [self performSelector:@selector(displayResults:)
               withObject:nil 
               afterDelay:delay];
  } else {
    showResults_ = NO;
    [self updateResultsView];
  }
}

- (QSBTableResult *)selectedTableResult {
  QSBResultsViewBaseController *resultsViewController 
    = [activeSearchViewController_ activeResultsViewController];
  return [resultsViewController selectedTableResult];
}

- (QSBSearchViewController *)activeSearchViewController {
  return activeSearchViewController_;
}

- (void)setObservingMoveAndResizeNotifications:(BOOL)doRegister {
  NSWindow *searchWindow = [self window];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  if (doRegister) {
    [nc addObserver:self 
           selector:@selector(windowPositionChanged:) 
               name:NSWindowDidMoveNotification 
             object:searchWindow];
    [nc addObserver:self 
           selector:@selector(windowPositionChanged:) 
               name:NSWindowDidResizeNotification 
             object:searchWindow];
  } else {
    [nc removeObserver:self 
                  name:NSWindowDidMoveNotification 
                object:searchWindow];
    [nc removeObserver:self 
                  name:NSWindowDidResizeNotification 
                object:searchWindow];
  }
}

- (void)updateLogoView {
  NSImage *menuImage = nil;
  NSImage *logoImage = nil;
  NSData *data = [[NSUserDefaults standardUserDefaults]
                  dataForKey:kQSBUserPrefBackgroundColorKey];
  NSColor *color = data ? [NSUnarchiver unarchiveObjectWithData:data] 
                        : [NSColor whiteColor];
  color = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
  
  CGFloat brightness = [color brightnessComponent];
  CGFloat hue = [color hueComponent];    
  CGFloat saturation = [color saturationComponent];
  
  // Only pastels show color logo
  if (saturation < 0.25 && brightness > 0.9) {
    logoImage = [NSImage imageNamed:@"ColorLargeGoogle"]; 
    menuImage = [NSImage imageNamed:@"MenuArrowBlack"]; 
  } else {
    // If is a bright, saturated color, use the black logo
    const CGFloat kYellowHue = 1.0 / 6.0;
    const CGFloat kMinDistance = 1.0 / 12.0;
    CGFloat yellowDistance = fabs(kYellowHue - hue);
    if (yellowDistance < kMinDistance && brightness > 0.8) {
      logoImage = [NSImage imageNamed:@"BlackLargeGoogle"];
      menuImage = [NSImage imageNamed:@"MenuArrowBlack"]; 
    } else {
      logoImage = [NSImage imageNamed:@"WhiteLargeGoogle"];
      menuImage = [NSImage imageNamed:@"MenuArrowWhite"]; 
    }
  }
  [logoView_ setImage:logoImage];
  if (menuImage) [windowMenuButton_ setImage:menuImage];
}

- (void)openResultsTableItem:(id)sender {
  [activeSearchViewController_ performDefaultActionOnSelectedRow];
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {
  if (client == searchTextField_) {
    return searchTextFieldEditor_;
  } else {
    return nil;
  }
}

- (NSArray *)corpora {
  if (!corpora_) {
    // Lazy initialize corpora
    HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
    HGSExtension *corporaSource 
      = [sourcesPoint extensionWithIdentifier:kGoogleCorporaSourceIdentifier];
    SEL selector = NSSelectorFromString(@"groupedSearchableCorpora");
    if ([corporaSource respondsToSelector:selector]) {
      corpora_ = [[corporaSource performSelector:selector] retain];
    } else {
      corpora_ = [[NSArray array] retain];
      HGSLogDebug(@"Corpora %@ doesn't respond to groupedSearchableCorpora",
                  corporaSource);
    }
  }
  return corpora_;
}

// Delegate callback for the window menu, this propogates the dropdown of 
// search sites
- (void)menuNeedsUpdate:(NSMenu *)menu {
  // If this isn't the expected menu return
  if ([searchMenu_ menu] != menu) return;
  // If we've already added the items, return
  if ([menu indexOfItemWithTag:kBaseCorporaTagValue] != -1) return;
  // Add our items.
  NSArray *corpora = [self corpora];
  for (unsigned int i = 0; i < [corpora count]; i++) {
    HGSResult *corpus = [corpora objectAtIndex:i];
    NSString *key = [[NSNumber numberWithUnsignedInt:i] stringValue];
    NSMenuItem *item 
      = [[[NSMenuItem alloc] initWithTitle:[corpus displayName]
                                    action:@selector(selectCorpus:)
                             keyEquivalent:key]
         autorelease];
    
    // Insert after the everything item
    [menu insertItem:item atIndex:i + 2];
    [item setTag:i + kBaseCorporaTagValue];
    NSImage *image = [corpus valueForKey:kHGSObjectAttributeIconKey];
    image = [image gtm_duplicateOfSize:NSMakeSize(16,16)];
    [item setImage: image];
  }
}

- (IBAction)resetSearchOrHideQuery:(id)sender {
  // Hide the results window if it's showing.
  if ([resultsWindow_ isVisible]) {
    while ([self popViewControllerAnimate:NO]) { }
    [activeSearchViewController_ setQueryString:nil];
    [searchTextField_ setStringValue:@""];
    [self hideResultsWindow];
  } else {
    NSString *queryString = [activeSearchViewController_ queryString];
    if ([queryString length]) {
      // Clear the text in the search box.
      [activeSearchViewController_ setQueryString:nil];
      [searchTextField_ setStringValue:@""];
    } else {
      // Otherwise hide the query window.
      [self hideSearchWindow:self];
    }
  }
}

- (IBAction)selectCorpus:(id)sender {
  // If there's not a current pivot then add one.  Then change the pivot object
  // for the pivot (either the existing one or the newly created one) to the
  // chosen corpus.  Don't alter the search text.
  
  NSString *queryString = [activeSearchViewController_ queryString];
  
  NSInteger tag = [sender tag] - kBaseCorporaTagValue;
  HGSResult *corpus = [[self corpora] objectAtIndex:tag];
  HGSResultArray *results = [HGSResultArray arrayWithResult:corpus];
  [self selectResults:results];
  
  // Restore the query string. The following also triggers a query refresh.
  [activeSearchViewController_ setQueryString:queryString];
  if (!queryString) queryString = @"";
  [searchTextField_ setStringValue:queryString];
}

- (IBAction)performSearch:(id)sender {
  // For now we just blindly submit a google search. 
  // TODO(alcor): make this perform a contextual search depending on the pivot
  NSString *queryString = [activeSearchViewController_ queryString];
  QSBGoogleTableResult *googleResult
    = [QSBGoogleTableResult tableResultForQuery:queryString];
  [googleResult performDefaultActionWithSearchViewController:activeSearchViewController_];
}

- (void)pivotOnObject:(QSBTableResult *)pivotObject {
  // Use the currently selected results item as a pivot and clear the search 
  // text by setting up a new query by instantiating a pivot view and creating
  // a query on the pivot.
  if ([pivotObject isPivotable]) {
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    QSBSearchController *searchController 
      = [activeSearchViewController_ searchController];
    NSDictionary *userInfo 
      = [NSDictionary dictionaryWithObject:searchController
                                    forKey:kQSBNotificationSearchControllerKey];
    // We have to retain/autorelease here because once we've pivoted
    // our pivot object get released and we will lose it.
    [[pivotObject retain] autorelease];
    [nc postNotificationName:kQSBWillPivotNotification
                      object:pivotObject 
                    userInfo:userInfo];
    // Load up the pivot results views nib and install
    // the subordinate results views.
    QSBSearchViewController *pivotResultsController
      = [[[QSBSearchViewController alloc] initWithWindowController:self] 
         autorelease];
    [pivotObject willPivot];
    NSUInteger flags = [[NSApp currentEvent] modifierFlags];
    [[pivotResultsController searchController] setPushModifierFlags:flags];
    [self pushViewController:pivotResultsController];
    // We're starting a new query so clear the search string.
    [activeSearchViewController_ setQueryString:nil];
    [searchTextField_ setStringValue:@""];
    [nc postNotificationName:kQSBDidPivotNotification
                      object:pivotObject 
                    userInfo:userInfo];
  }  
}


- (void)searchForString:(NSString *)string {
  // Selecting destroys the stack
  [self clearAllViewControllersAndSearchString];
  [searchTextField_ setStringValue:string];
  if ([string length]) {
    [activeSearchViewController_ setQueryString:string];
    [self showResultsWindow];
  }
}

- (void)selectResults:(HGSResultArray *)results {
  // Selecting destroys the stack
  [self clearAllViewControllersAndSearchString];
  
  // Create a pivot with the current text, and set the base query to the
  // indicated corpus.
  
  QSBSearchViewController *pivotResultsController
    = [[[QSBSearchViewController alloc] initWithWindowController:self]
       autorelease];
  [self pushViewController:pivotResultsController];
  
  // Set the existing pivot to the indicated corpus.
  // Note that this subverts the parent's idea of what the pivot object is.
  [activeSearchViewController_ setResults:results];
  [self updatePivotToken];
}

- (IBAction)grabSelection:(id)sender {
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *path = [bundle pathForResource:@"GrabFinderSelectionAsPosixPaths" 
                                    ofType:@"scpt"
                               inDirectory:@"Scripts"];
  HGSAssert(path, @"Can't find GrabFinderSelectionAsPosixPaths.scpt");
  NSURL *url = [NSURL fileURLWithPath:path];
  NSDictionary *error = nil;
  
  NSAppleScript *grabScript
    = [[[NSAppleScript alloc] initWithContentsOfURL:url 
                                              error:&error] autorelease];
  if (!error) {
    NSAppleEventDescriptor *desc = [grabScript executeAndReturnError:&error];
    if (!error) {
      NSArray *paths = [desc gtm_arrayValue];
      if (paths) {
        HGSResultArray *results
          = [HGSResultArray arrayWithFilePaths:paths];
        [self selectResults:results];
        showResults_ = ([results count] > 0);
      }
    }
  }
}

- (IBAction)dropSelection:(id)sender {
  [self selectResults:nil];
}

- (void)pivotOnSelection {
  QSBTableResult *pivotObject = [self selectedTableResult];
  [self pivotOnObject:pivotObject];
}

- (BOOL)moveDownQSB {
  BOOL handled = YES;  // Forstall any additional action by default.
  QSBSearchViewController *activeSearchViewController
    = [self activeSearchViewController];
  QSBResultsViewBaseController *activeResultsViewController
    = [activeSearchViewController activeResultsViewController];
  QSBResultsViewTableView *tableView 
    = [activeResultsViewController resultsTableView];
  if ([tableView numberOfRows] > 0) {
    [self displayResults:nil];
    handled = NO;  // Allow it to proceed to change the selection.
  }
  return handled;
}

- (BOOL)insertNewlineQSB {
  // We need to let our fast sources have a chance to get to the query
  // In the case of a really fast typist, they can sometimes overwhelm our
  // event queue. This delay is enough to give our initial results a chance
  // to populate the table before we select something.
  [NSTimer scheduledTimerWithTimeInterval:0.1
                                   target:self 
                                 selector:@selector(openResultsTableItem:) 
                                 userInfo:NULL 
                                  repeats:NO];
  return YES;
}

- (BOOL)insertTabQSB {
  BOOL handled = NO;
  if (![[NSApp currentEvent] isARepeat]) {
    [self pivotOnSelection];
    handled = YES;
  }
  return handled;
}

- (BOOL)insertTabIgnoringFieldEditorQSB {
  return [self insertTabQSB];
}

- (BOOL)insertBacktabQSB {
  BOOL handled = NO;
  if (![[NSApp currentEvent] isARepeat]) {
    [self popViewControllerAnimate:YES];
    handled = YES;
  }
  return handled;
}

- (BOOL)moveRightQSB {
  BOOL isAtEnd = [searchTextFieldEditor_ isAtEnd];
  BOOL isARepeat = [[NSApp currentEvent] isARepeat];
  if (isAtEnd && !isARepeat) {
    [self pivotOnSelection];
  } else {
    [searchTextFieldEditor_ moveRight:nil];
  }
  return YES;
}

- (BOOL)moveWordRightQSB {
  if ([searchTextFieldEditor_ isAtEnd]
      && ![[NSApp currentEvent] isARepeat]) {
    [self pivotOnSelection];
  } else {
    [searchTextFieldEditor_ moveWordRight:nil];
  }
  return YES;
}

- (BOOL)moveLeftQSB {
  BOOL handled = NO;
  if ([searchTextFieldEditor_ isAtBeginning]
      && ![[NSApp currentEvent] isARepeat]) {
    [self popViewControllerAnimate:YES];
    handled = YES;
  }
  return handled;
}

- (BOOL)moveWordLeftQSB {
  return [self moveLeftQSB];
}

- (BOOL)deleteBackwardQSB {
  BOOL handled = NO;
  if (![[NSApp currentEvent] isARepeat]) {
    if ([searchTextFieldEditor_ isAtBeginning]) {
      NSString *currentQueryString = [activeSearchViewController_ queryString];
      while([self popViewControllerAnimate:YES]) { }
      
      [searchTextField_ setStringValue:currentQueryString ? 
                   currentQueryString : @""];
      [searchTextFieldEditor_ setSelectedRange:NSMakeRange(0, 0)];
      [activeSearchViewController_ setQueryString:currentQueryString];
      handled = YES;
    }
  }
  return handled;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
  BOOL validated = NO;
  if ([anItem action] == @selector(copy:)) {
    QSBTableResult *qsbTableResult 
      = [activeSearchViewController_ selectedTableResult];
    validated = [qsbTableResult isKindOfClass:[QSBSourceTableResult class]];
  } else {
    HGSLogDebug(@"Unexpected userItem validation %@ at [%@ %@]", 
                anItem, [self class], _cmd);
  }
  return validated;
}

- (void)copy:(id)sender {
  QSBTableResult *qsbTableResult 
    = [activeSearchViewController_ selectedTableResult];
  NSPasteboard *pb = [NSPasteboard generalPasteboard];
  [qsbTableResult copyToPasteboard:pb];
}

- (void)hitHotKey:(id)sender {
  if (![[self window] ignoresMouseEvents]) {
    [self hideSearchWindowBecause:kQSBHotKeyChangeVisiblityToggle];
  } else {
    // Check to see if the display is captured, and if so beep and don't
    // activate. 
    // For http://buganizer/issue?id=652067
    if ([self isOurScreenCaptured]) {
      NSBeep();
      return;
    }
    [self showSearchWindowBecause:kQSBHotKeyChangeVisiblityToggle];
  }
}

- (BOOL)control:(NSControl *)control 
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
  BOOL handled = NO;
  
  // Dynamically reroute the command based on the selector
  NSString *selString = NSStringFromSelector(commandSelector);
  // Chop off the colon
  selString = [selString substringToIndex:[selString length] - 1];
  selString = [selString stringByAppendingString:@"QSB"];
  SEL qsbCommandSelector = NSSelectorFromString(selString);
  if ([self respondsToSelector:qsbCommandSelector]) {
    NSMethodSignature *ms = [self methodSignatureForSelector:qsbCommandSelector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:ms];
    [invocation setSelector:qsbCommandSelector];
    [invocation invokeWithTarget:self];
    [invocation getReturnValue:&handled];
  } 
  if (!handled) {
    handled 
      = [activeSearchViewController_ performSelectionMovementSelector:commandSelector];
  }
  // Keep the completion text up-to-date for some cursor movement.
  if (handled
      || commandSelector == @selector(moveLeft:)
      || commandSelector == @selector(moveRight:)
      || commandSelector == @selector(insertNewline:)) {
    [textView complete:self];
  }
  return handled;
}

- (NSArray *)control:(NSControl *)control 
            textView:(NSTextView *)textView 
         completions:(NSArray *)words 
 forPartialWordRange:(NSRange)charRange 
 indexOfSelectedItem:(int *)idx {
  *idx = 0;
  NSString *completion = nil;
  // We grab the string from the textStorage instead of from the
  // activeSearchController_ because the string from textStorage includes marked
  // text.
  NSString *queryString = [[textView textStorage] string];
  if ([queryString length]) {
    id result = [self selectedTableResult];
    if (result && [result respondsToSelector:@selector(displayName)]) {
      completion = [result displayName];
      // If the query string is not a prefix of the completion then
      // ignore the completion.
      if (![completion qsb_hasPrefix:queryString 
                             options:(NSWidthInsensitiveSearch 
                                      | NSCaseInsensitiveSearch
                                      | NSDiacriticInsensitiveSearch)]) {
        completion = nil;
      }
    }
  }  
  return completion ? [NSArray arrayWithObject:completion] : nil;
}

- (void)updateResultsViewNow {
  BOOL isVisible = [resultsWindow_ isVisible];
  
  if (!isVisible || showResults_) {
    if (isVisible) {
      [NSAnimationContext beginGrouping];
      [[NSAnimationContext currentContext] setDuration:kQSBResizeDuration];
    }
    
    // Mark the current query results view as needing to be updated.
    // Immediately update the active controller and determine window height.
    [activeSearchViewController_ updateResultsViewNow];
    CGFloat newWindowHeight = [activeSearchViewController_ windowHeight];
    [self setResultsWindowHeight:newWindowHeight animating:isVisible];
    if (isVisible)
      [NSAnimationContext endGrouping];      
  }
  
  if (showResults_ != isVisible) {
    if (showResults_) {
      [self showResultsWindow];
    } else {
      [self hideResultsWindow];
    }
  }
}

- (void)updateResultsView {
  if ([resultsWindow_ isVisible]) {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateResultsViewNow) 
                                               object:nil];
    
    [self performSelector:@selector(updateResultsViewNow) 
               withObject:nil
               afterDelay:kQSBUpdateSizeDelay];
  } else {
    [self updateResultsViewNow];
  }
}

- (NSWindow *)shieldWindow {
  if (!shieldWindow_) {
    NSRect windowRect = [[NSScreen mainScreen] frame];
    shieldWindow_ = [[NSWindow alloc] initWithContentRect:windowRect 
                                                styleMask:NSBorderlessWindowMask 
                                                  backing:NSBackingStoreBuffered 
                                                    defer:NO];
    [shieldWindow_ setIgnoresMouseEvents:YES];
    [shieldWindow_
       setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces]; 
    [shieldWindow_ setBackgroundColor: [NSColor blackColor]];
    [shieldWindow_ setLevel:kCGStatusWindowLevel];
    [shieldWindow_ setOpaque:YES];
    [shieldWindow_ setHasShadow:NO];
    [shieldWindow_ setReleasedWhenClosed:YES];
    [shieldWindow_ setAlphaValue:0.0];
    [shieldWindow_ display];
  }
  return shieldWindow_;
  
}

- (NSString *)searchWindowVisibilityToggleBasedOnSender:(id)sender {
  NSString *toggle = kQSBUnknownChangeVisibilityToggle;
  if ([sender isKindOfClass:[NSMenuItem class]]) {
    NSMenu *senderMenu = [sender menu];
    id appDelegate = [NSApp delegate];
    if ([senderMenu isEqual:[appDelegate applicationDockMenu:NSApp]]) {
      toggle = kQSBDockMenuItemChangeVisiblityToggle;
    } else if ([senderMenu isEqual:[appDelegate statusItemMenu]]) {
      toggle = kQSBStatusMenuItemChangeVisiblityToggle;
    }
  }
  return toggle;
}
      
      
- (IBAction)showSearchWindow:(id)sender {
  NSString *toggle = [self searchWindowVisibilityToggleBasedOnSender:sender];
  [self showSearchWindowBecause:toggle];
}

- (IBAction)hideSearchWindow:(id)sender {
  NSString *toggle = [self searchWindowVisibilityToggleBasedOnSender:sender];
  [self hideSearchWindowBecause:toggle];
}

- (void)showSearchWindowBecause:(NSString *)toggle {
  NSWindow *modalWindow = [NSApp modalWindow];
  if (!modalWindow) {
    // a window must be "visible" for it to be key. This makes it "visible"
    // but invisible to the user so we can accept keystrokes while we are
    // busy opening the window. We order it front as a invisible window, and 
    // then slowly fade it in.
    NSWindow *searchWindow = [self window];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    NSDictionary *visibilityChangedUserInfo
      = [NSDictionary dictionaryWithObjectsAndKeys:
         toggle, kQSBSearchWindowChangeVisibilityToggleKey,
         nil];
    [nc postNotificationName:kQSBSearchWindowWillShowNotification
                      object:searchWindow
                    userInfo:visibilityChangedUserInfo];
    
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:kQSBSearchWindowDimBackground]) {
      NSWindow *shieldWindow = [self shieldWindow];
      [shieldWindow setFrame:[[NSScreen mainScreen] frame] display:NO];
      if (![shieldWindow isVisible]) {
        [shieldWindow setAlphaValue:0.0];
        [shieldWindow makeKeyAndOrderFront:nil];
      } 
      CGFloat fadeDuration 
        = [ud floatForKey:kQSBSearchWindowDimBackgroundDuration];
      CGFloat fadeAlpha = [ud floatForKey:kQSBSearchWindowDimBackgroundAlpha];
      // If fadeDuration (or fadeAlpha) < FLT_EPSILON then the user is using
      // a bogus value, so we ignore it and use the default value.
      if (fadeDuration < FLT_EPSILON) {
        fadeDuration = 0.5;
      }
      if (fadeAlpha < FLT_EPSILON) {
        fadeAlpha = 0.1;
      }
      fadeAlpha = MIN(fadeAlpha, 1.0);
      [NSAnimationContext beginGrouping];
      [[NSAnimationContext currentContext] setDuration:fadeDuration];
      [[shieldWindow animator] setAlphaValue:fadeAlpha];
      [NSAnimationContext endGrouping];
    }
    [searchWindow setIgnoresMouseEvents:NO];
    [searchWindowVisibilityAnimation_ setViewAnimations:nil];
    [searchWindow makeKeyAndOrderFront:self];
    [self setWelcomeHidden:NO];
    [searchWindow setAlphaValue:1.0];
    [nc postNotificationName:kQSBSearchWindowDidShowNotification
                      object:[self window]
                    userInfo:visibilityChangedUserInfo];
    if ([[activeSearchViewController_ queryString] length]) {
      [self performSelector:@selector(displayResults:)
                 withObject:nil 
                 afterDelay:kQSBReshowResultsDelay];
    }
  } else {
    // Bring whatever modal up front.
    [NSApp activateIgnoringOtherApps:YES];
    [modalWindow makeKeyAndOrderFront:self];
  }
}

- (void)hideSearchWindowBecause:(NSString *)toggle {
  NSWindow *searchWindow = [self window];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  NSDictionary *visibilityChangedUserInfo
    = [NSDictionary dictionaryWithObjectsAndKeys:
       toggle, kQSBSearchWindowChangeVisibilityToggleKey,
       nil];
  [nc postNotificationName:kQSBSearchWindowWillHideNotification
                    object:searchWindow
                  userInfo:visibilityChangedUserInfo];
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(displayResults:)
                                             object:nil];
  [activeSearchViewController_ stopQuery];
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  if ([ud boolForKey:kQSBSearchWindowDimBackground]) {
    CGFloat fadeDuration 
      = [ud floatForKey:kQSBSearchWindowDimBackgroundDuration];
    if (fadeDuration < FLT_EPSILON) {
      // If fadeDuration < FLT_EPSILON then the user has set the duration
      // to a bogus value, so we ignore it and use the default value.
      fadeDuration = 0.5;
    }
    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:fadeDuration];
    [[[self shieldWindow] animator] setAlphaValue:0.0];
    [NSAnimationContext endGrouping];
  }
  
  showResults_ = NO;
  
  if ([toggle isEqualToString:kQSBExecutedChangeVisiblityToggle]) {
    // Block when executing
    NSDictionary *anim1 
      = [NSDictionary dictionaryWithObjectsAndKeys:
         searchWindow, NSViewAnimationTargetKey, 
         NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey, 
         nil];
    
    NSDictionary *anim2 
      = [NSDictionary dictionaryWithObjectsAndKeys:
         resultsWindow_, NSViewAnimationTargetKey, 
         NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey, 
         nil];
    NSArray *animations = [NSArray arrayWithObjects:anim1, anim2, nil];
    
    // Stop any other visibility animations we may have currently running
    [resultWindowVisibilityAnimation_ stopAnimation];
    [searchWindowVisibilityAnimation_ stopAnimation];

    QSBViewAnimation *animation 
      = [[QSBViewAnimation alloc] initWithViewAnimations:animations
                                                    name:kQSBHideSearchAndResultsWindowAnimationName
                                                userInfo:nil];
    [animation setDuration:0.2];
    [animation setAnimationBlockingMode:NSAnimationBlocking];
    [animation startAnimation];
    [animation release];
    [resultsWindow_ setIgnoresMouseEvents:YES];
    [searchWindow setIgnoresMouseEvents:YES];
    [resultsWindow_ orderOut:nil];
    [searchWindow orderOut:nil];
  }  else {
    [self hideResultsWindow];
    [searchWindow setIgnoresMouseEvents:YES];
    [self setWelcomeHidden:YES];
    [searchWindowVisibilityAnimation_ stopAnimation];
    NSDictionary *animation 
      = [NSDictionary dictionaryWithObjectsAndKeys:
         searchWindow, NSViewAnimationTargetKey,
         NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
         nil];
    NSArray *animations = [NSArray arrayWithObject:animation];
    [searchWindowVisibilityAnimation_ setViewAnimations:animations];
    QSBSimpleInvocation *invocation 
      = [QSBSimpleInvocation selector:@selector(hideSearchWindowAnimationCompleted:) 
                               target:self 
                               object:visibilityChangedUserInfo];
    [searchWindowVisibilityAnimation_ setUserInfo:invocation];
    [searchWindowVisibilityAnimation_ setDuration:kQSBHideDuration];
    [searchWindowVisibilityAnimation_ setAnimationBlockingMode:NSAnimationNonblocking];
    [searchWindowVisibilityAnimation_ startAnimation];   
  }
}

- (void)hideSearchWindowAnimationCompleted:(NSDictionary *)userInfo {
  NSWindow *window = [self window];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc postNotificationName:kQSBSearchWindowDidHideNotification
                    object:window
                  userInfo:userInfo];
  [window orderOut:self];
}

- (NSWindow *)resultsWindow {
  return resultsWindow_;
}

- (void)setResultsWindowHeight:(CGFloat)newHeight
                     animating:(BOOL)animating {
  // Don't let one of these trigger during our animations, they can cause
  // view corruption.
  [NSObject cancelPreviousPerformRequestsWithTarget:self
                                           selector:@selector(updateResultsViewNow) 
                                             object:nil];
  // Prevent a recursion since we're quite likely to resize the window.
  [self setObservingMoveAndResizeNotifications:NO];
  
  NSWindow *queryWindow = [self window];
  
  BOOL resultsVisible = [resultsWindow_ isVisible];
  NSRect baseFrame = [resultsOffsetterView_ frame];
  baseFrame.origin = [queryWindow convertBaseToScreen:baseFrame.origin];
  // Always start with the baseFrame and enlarge it to fit the height
  NSRect proposedFrame = baseFrame;
  proposedFrame.origin.y -= newHeight; // one more for borders
  proposedFrame.size.height += newHeight;
  if (resultsVisible) {
    // If the results panel is visible then we first size and position it
    // and then reposition the search box.
  
    // second, determine a frame that actually fits within the screen.
    NSRect actualFrame = [self fullyExposedFrameForFrame:proposedFrame
                                          respectingDock:YES
                                                onScreen:[queryWindow screen]];
    if (!NSEqualRects(actualFrame, proposedFrame)) {
      // We need to move the query window as well as the results window.
      NSPoint deltaPoint 
        = NSMakePoint(actualFrame.origin.x - proposedFrame.origin.x,
                      actualFrame.origin.y - proposedFrame.origin.y);
      
      NSRect queryFrame = NSOffsetRect([queryWindow frame],
                                deltaPoint.x, deltaPoint.y);
      [queryWindow setFrame:queryFrame display:YES animate:animating];
    }
    
    [resultsWindow_ setFrame:actualFrame display:YES animate:animating];
  }

  // Turn back on size/move notifications.
  [self setObservingMoveAndResizeNotifications:YES];
}

- (CGFloat)resultsViewOffsetFromTop {
  return NSHeight([resultsOffsetterView_ frame]);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
  BOOL valid = YES;
  SEL action = [menuItem action];
  SEL showSearchWindowSel = @selector(showSearchWindow:);
  SEL hideSearchWindowSel = @selector(hideSearchWindow:);
  BOOL searchWindowActive = [[self window] isVisible];
  if (action == showSearchWindowSel && searchWindowActive) {
    [menuItem setAction:hideSearchWindowSel];
    [menuItem setTitle:NSLocalizedString(@"Hide Quick Search Box", nil)];
  } else if (action == hideSearchWindowSel && !searchWindowActive) {
    [menuItem setAction:showSearchWindowSel];
    [menuItem setTitle:NSLocalizedString(@"Show Quick Search Box", nil)];
  } else if (action == @selector(selectCorpus:)) {
    NSArray *corpora = [self corpora];
    NSUInteger idx = [menuItem tag] - kBaseCorporaTagValue;
    if (idx < [corpora  count]) {
      HGSResult *corpus = [corpora objectAtIndex:idx];
      HGSResultArray *results 
        = [activeSearchViewController_ results];
      if ([results count] == 1) {
        HGSResult *result = [results objectAtIndex:0];
        [menuItem setState:([corpus isEqual:result])];
      }
    } else {
      valid = NO;
    }
  }
  
  return valid;
}

#pragma mark NSWindow delegate methods

- (void)windowPositionChanged:(NSNotification *)notification {
  // The search window position on the screen has changed so record
  // this in our preferences so that we can later restore the window
  // to its new position.
  //
  // NOTE: We do this because it is far simpler than trying to use the autosave
  // approach and intercepting a number of window moves and resizes during
  // initial nib loading.
  NSRect windowFrame = [[self window] frame];
  NSPoint topLeft = windowFrame.origin;
  topLeft.y += windowFrame.size.height;
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  [ud setDouble:topLeft.x forKey:kQSBSearchWindowFrameLeftPrefKey];
  [ud setDouble:topLeft.y forKey:kQSBSearchWindowFrameTopPrefKey];
  CGFloat newWindowHeight = windowFrame.size.height;
  if ([resultsWindow_ isVisible]) {
    newWindowHeight = [activeSearchViewController_ windowHeight];
  }
}

#pragma mark NSWindow Notification Methods
- (void)aWindowDidBecomeKey:(NSNotification *)notification {
  NSWindow *window = [notification object];
  NSWindow *searchWindow = [self window];
  
  if ([window isEqual:searchWindow]) {
    if (needToUpdatePositionOnActivation_) {
      [self centerWindowOnScreen];
      needToUpdatePositionOnActivation_ = NO;
    }  
    [queryResetTimer_ invalidate];
    queryResetTimer_ = nil;

    [self checkFindPasteboard:nil];
    if (insertFindPasteBoardString_) {
      insertFindPasteBoardString_ = NO;
      NSPasteboard *findPBoard = [NSPasteboard pasteboardWithName:NSFindPboard];
      NSArray *types = [findPBoard types];
      if ([types count]) {
        NSString *text = [findPBoard stringForType:[types objectAtIndex:0]];
        if ([text length] > 0) {
          [searchTextFieldEditor_ selectAll:self];
          [searchTextFieldEditor_ insertText:text];
          [searchTextFieldEditor_ selectAll:self];
        }
      }
    }
  } else if (![window isKindOfClass:[QLPreviewPanel class]] 
             && [searchWindow isVisible]) {
    // We check for QLPreviewPanel because we don't want to hide for quicklook
    [self hideSearchWindowBecause:kQSBAppLostKeyFocusVisibilityToggle];
  }
  
}

- (void)windowDidResignKey:(NSNotification *)notification {
  // If we resigned key because of a quick look panel, then we don't want
  // to hide ourselves.
  if ([[NSApp keyWindow] isKindOfClass:[QLPreviewPanel class]]) return;
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSTimeInterval resetInterval = [ud floatForKey:kQSBResetQueryTimeoutPrefKey];
  // preset previously in awakeFromNib:
  queryResetTimer_ = [NSTimer scheduledTimerWithTimeInterval:resetInterval 
                                                      target:self 
                                                    selector:@selector(resetQuery:) 
                                                    userInfo:nil 
                                                     repeats:NO];
  BOOL hideWhenInactive = YES;
  NSNumber *hideNumber = [[NSUserDefaults standardUserDefaults]
                          objectForKey:kQSBHideQSBWhenInactivePrefKey];
  if (hideNumber) {
    hideWhenInactive = [hideNumber boolValue];
  }
  if (hideWhenInactive) {

    // If we've pivoted and have a token in the search text box we will just
    // blow everything away (http://b/issue?id=1567906), otherwise we will
    // select all of the text, so the next time the user brings us up we will
    // immediately replace their selection with what they type.
    if ([activeSearchViewController_ parentSearchViewController]) {
      [self clearAllViewControllersAndSearchString];
    } else {
      [searchTextFieldEditor_ selectAll:self];
    }
    if (![[self window] ignoresMouseEvents]) {
      [self hideSearchWindowBecause:kQSBAppLostKeyFocusVisibilityToggle];
    }
  }
}

#pragma mark NSApplication Notification Methods

- (void)applicationDidBecomeActive:(NSNotification *)notification {
  if ([NSApp keyWindow] == nil
      || [NSApp keyWindow] == [[self welcomeController] window]) {
    [self showSearchWindowBecause:kQSBActivationChangeVisiblityToggle];
  }
}

- (void)applicationWillResignActive:(NSNotification *)notification {
  if ([[self window] isVisible]) {
    BOOL hideWhenInactive = YES;
    NSNumber *hideNumber = [[NSUserDefaults standardUserDefaults]
                            objectForKey:kQSBHideQSBWhenInactivePrefKey];
    if (hideNumber) {
      hideWhenInactive = [hideNumber boolValue];
    }
    if (hideWhenInactive) {
      [self hideSearchWindowBecause:kQSBActivationChangeVisiblityToggle];
    }
  }
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification {
  if ([[self window] isVisible]) {
    // if we are active, do our change immediately.
    [self centerWindowOnScreen];
  } else {
    // We don't want to update immediately if we are in the background because
    // we don't want to move unnecessarily if the user doesn't invoke us in
    // the different mode change.
    needToUpdatePositionOnActivation_ = YES;
  }
}

- (void)applicationDidReopen:(NSNotification *)notification {
  if (![NSApp keyWindow]) {
    [self showSearchWindowBecause:kQSBReopenChangeVisiblityToggle];
  }
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  // If the user launches us hidden we don't want to activate.
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSDictionary *processDict 
    = [ws gtm_processInfoDictionary];
  NSNumber *nsDoNotActivateOnStartup 
    = [processDict valueForKey:kGTMWorkspaceRunningIsHidden];
  BOOL doNotActivateOnStartup = [nsDoNotActivateOnStartup boolValue];
  if (!doNotActivateOnStartup) {
    doNotActivateOnStartup = [ws gtm_wasLaunchedAsLoginItem];
  }
  if (!doNotActivateOnStartup) {
    // During startup we may inadvertently be made inactive, most likely due
    // to keychain access requests, so let's just force ourself to be
    // active.
    id notificationObject = [notification object];
    if ([notificationObject isKindOfClass:[NSApplication class]]) {
      NSApplication *application = notificationObject;
      [application activateIgnoringOtherApps:YES];
    }
    // UI elements don't get activated by default, so if the user launches
    // us from the finder, and we are a UI element, force ourselves active.
    [self showSearchWindowBecause:kQSBAppLaunchedChangeVisiblityToggle];
    if ([self firstLaunch]) {
      [self showWelcomeWindow];
    }
  }
}

#pragma mark NSControl Delegate Methods (for QSBTextField)

- (void)controlTextDidChange:(NSNotification *)obj {
  NSString *queryString = [[obj object] stringValue];
  if (![queryString length]) {
    queryString = nil;
  }

  [activeSearchViewController_ setQueryString:queryString];
}

#pragma mark Other Notifications

- (void)pluginWillLoad:(NSNotification *)notification {
  NSDictionary *userInfo = [notification userInfo];
  NSString *pluginName = [userInfo objectForKey:kHGSPluginLoaderPluginNameKey];
  NSString *startupString = nil;
  if (pluginName) {
    NSString *format = HGSLocalizedString(@"Starting up… Loading %@", 
                                          @"A string shown "
                                          @"at launchtime to denote that QSB " 
                                          @"is starting up and is loading a "
                                          @"plugin.");
    startupString = [NSString stringWithFormat:format, pluginName];
  } else {
    startupString = HGSLocalizedString(@"Starting up…", 
                                       @"A string shown "
                                       @"at launchtime to denote that QSB " 
                                       @"is starting up.");
    
  }
  [searchTextField_ setStringValue:startupString];
  [searchTextField_ displayIfNeeded];
}

- (void)pluginWillInstall:(NSNotification *)notification {
  NSString *initializing = HGSLocalizedString(@"Initializing %@",
                                              @"A string shown at launchtime "
                                              @"to denote that we are "
                                              @"initializing a plugin.");
  NSDictionary *userInfo = [notification userInfo];
  HGSPlugin *plugin = [userInfo objectForKey:kHGSPluginLoaderPluginKey];
  NSString *name = [plugin displayName];
  initializing = [NSString stringWithFormat:initializing, name];
  [searchTextField_ setStringValue:initializing];
  [searchTextField_ displayIfNeeded];
}

- (void)pluginsDidInstall:(NSNotification *)notification {
  [searchTextField_ setStringValue:@""];
  [searchTextField_ displayIfNeeded];
  [searchTextField_ setEnabled:YES];
  [[searchTextField_ window] makeFirstResponder:searchTextField_];
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  HGSPluginLoader *sharedLoader = [HGSPluginLoader sharedPluginLoader];
  [nc removeObserver:self 
                name:kHGSPluginLoaderWillLoadPluginNotification 
              object:sharedLoader];
  [nc removeObserver:self 
                name:kHGSPluginLoaderWillInstallPluginNotification 
              object:sharedLoader];
  [nc removeObserver:self 
                name:kHGSPluginLoaderDidInstallPluginsNotification 
              object:sharedLoader];
}

- (void)selectedTableResultDidChange:(NSNotification *)notification {
  [thumbnailView_ unbind:NSValueBinding];
  QSBTableResult *tableResult 
    = [[notification userInfo] objectForKey:kQSBSelectedTableResultKey];
  if (tableResult) {
    [thumbnailView_ bind:NSValueBinding 
                toObject:tableResult 
             withKeyPath:@"displayThumbnail" 
                 options:nil];
    [thumbnailView_ setHidden:NO];
  } else {
    [thumbnailView_ setHidden:YES];
  }
  [searchTextFieldEditor_ complete:self];
  NSImage* thumbnail = [tableResult displayThumbnail];
  [logoView_ setHidden:(thumbnail != nil)];
}

#pragma mark Animations
  - (void)animationDidEnd:(QSBViewAnimation *)animation {
  HGSAssert([animation isKindOfClass:[QSBViewAnimation class]], nil);
  id<NSObject> userInfo = [animation userInfo];
  if ([userInfo isKindOfClass:[QSBSimpleInvocation class]]) {
    [(QSBSimpleInvocation *)userInfo invoke];
  }
}

- (void)updateShadows {
  // We invalidate the shadow here so that it looks right after we have adjusted
  // our tables. Note that we force a display BEFORE we invalidate, as we need
  // to be sure that our window is properly displayed before we recalculate
  // it's shadow, otherwise we will get the old shadow. The actual drawing of
  // the shadow will take place in the normal event chain.
  [resultsWindow_ display];
  [resultsWindow_ invalidateShadow];
}

// See comment at declaration regarding why we move offscreen as well as hide
- (void)hideResultsWindow {
  if (![resultsWindow_ ignoresMouseEvents]) {
    [resultsWindow_ setIgnoresMouseEvents:YES];
    NSRect newFrame = NSOffsetRect([resultsWindow_ frame], 0.0, 0.0);
    [resultWindowVisibilityAnimation_ stopAnimation];
    NSDictionary *animation 
      = [NSDictionary dictionaryWithObjectsAndKeys:
         resultsWindow_, NSViewAnimationTargetKey,
         [NSValue valueWithRect:newFrame], NSViewAnimationEndFrameKey,
         NSViewAnimationFadeOutEffect, NSViewAnimationEffectKey,
         nil];
    NSArray *animations = [NSArray arrayWithObject:animation];
    [resultWindowVisibilityAnimation_ setViewAnimations:animations];
    QSBSimpleInvocation *invocation
      = [QSBSimpleInvocation selector:@selector(hideResultsWindowAnimationCompleted:) 
                               target:self 
                               object:resultsWindow_];
    [resultWindowVisibilityAnimation_ setUserInfo:invocation];
    [resultWindowVisibilityAnimation_ setAnimationBlockingMode:NSAnimationNonblocking];
    [resultWindowVisibilityAnimation_ setDuration:kQSBHideDuration];
    [resultWindowVisibilityAnimation_ setDelegate:self];
    [resultWindowVisibilityAnimation_ startAnimation];
  }
}

- (void)hideResultsWindowAnimationCompleted:(NSWindow *)window {
  [[resultsWindow_ parentWindow] removeChildWindow:resultsWindow_];
  [resultsWindow_ orderOut:self];
}

- (void)showResultsWindow {
  NSRect frame = [resultsWindow_ frame];
  [resultsWindow_ setAlphaValue:0.0];  
  
  [resultsWindow_ setFrame:NSOffsetRect(frame, 0.0, kResultsAnimationDistance) 
                   display:YES
                   animate:YES];
  NSWindow *searchWindow = [self window];
  // Fix for stupid Apple ordering bug. By removing and re-adding all the
  // the children we keep the window list in the right order.
  // TODO(dmaclach):log a radar on this. Try removing the two
  // for loops, and doing a search with the help window showing.
  NSArray *children = [searchWindow childWindows];
  for (NSWindow *child in children) {
    [searchWindow removeChildWindow:child];
  }
  [searchWindow addChildWindow:resultsWindow_ ordered:NSWindowBelow];
  for (NSWindow *child in children) {
    [searchWindow addChildWindow:child ordered:NSWindowBelow];
  }
  [resultsWindow_ setLevel:kCGStatusWindowLevel + 1];
  [resultsWindow_ setIgnoresMouseEvents:NO];
  [resultsWindow_ makeKeyAndOrderFront:self];
  [NSObject cancelPreviousPerformRequestsWithTarget:resultsWindow_ 
                                           selector:@selector(orderOut:) 
                                             object:nil];
  
  [NSAnimationContext beginGrouping];
  [[NSAnimationContext currentContext] setDuration:kQSBShowDuration];
  [[resultsWindow_ animator] setAlphaValue:1.0];
  [self setResultsWindowHeight:NSHeight(frame) animating:YES];
  [NSAnimationContext endGrouping];
}

- (void)centerWindowOnScreen {
  NSWindow *window = [self window];
  [window center];
}

- (void)updatePivotToken {
  // Place a text box with the pivot term into the query search box.
  HGSResultArray *results = [activeSearchViewController_ results];
  NSString *pivotString = [results displayName];
  [searchMenu_ setTitle:pivotString];
  NSImage *image = [results icon];
  NSRect frame;
  if (image) {
    // We go through this instead of copying the image so we don't
    // copy a 512x512 icon needlessly.
    NSSize imageSquare = NSMakeSize(16, 16);
    NSImageRep *smallImage = [image gtm_bestRepresentationForSize:imageSquare];
    if (smallImage) {
      smallImage = [[smallImage copy] autorelease];
      image = [[[NSImage alloc] initWithSize:imageSquare] autorelease];
      [image addRepresentation:smallImage];
    }
    [searchMenu_ setImage:image];
    [searchMenu_ sizeToFit];
    frame = [searchMenu_ frame];
  } else {
    frame = [searchMenu_ frame];
    [searchMenu_ setImage:nil];
    frame.size.width = 0;
    [searchMenu_ setFrame:frame];
  }
  
  NSRect textFrame = [searchTextField_ frame];
  textFrame.origin.x = NSMaxX(frame) + kTextFieldPadding;
  textFrame.size.width = NSWidth([[searchTextField_ superview] frame])
    - NSMinX(textFrame) - kTextFieldPadding;
  
  [searchTextField_ setFrame:textFrame];
}

- (void)setActiveSearchViewController:(QSBSearchViewController *)searchViewController {
  QSBSearchController *searchController
    = [activeSearchViewController_ searchController];
  [searchController gtm_removeObserver:self
                            forKeyPath:kQSBQueryStringKey
                              selector:@selector(queryStringChanged:)];
  // We are no longer interested in the current controller producing results.
  [activeSearchViewController_ stopQuery];
  [activeSearchViewController_ autorelease];
  activeSearchViewController_ = [searchViewController retain];
  searchController = [activeSearchViewController_ searchController];
  [searchController gtm_addObserver:self
                         forKeyPath:kQSBQueryStringKey
                           selector:@selector(queryStringChanged:)
                           userInfo:nil
                            options:0];
  [activeSearchViewController_ didMakeActiveSearchViewController];
  [self updatePivotToken];
}

- (void)pushViewController:(NSViewController *)viewController {
  QSBSearchViewController *searchViewController = nil;
  if ([viewController isKindOfClass:[QSBSearchViewController class]]) {
    searchViewController = (QSBSearchViewController *)viewController;
  }
  
  [searchViewController setParentSearchViewController:activeSearchViewController_];
  
  // If there was an active controller then save the current query text
  // and push it out of the way.
  if (activeSearchViewController_) {
    NSRange queryRange = [searchTextFieldEditor_ selectedRange];
    [activeSearchViewController_ setSavedPivotQueryRange:queryRange];
    NSString *savedQueryString
      = [[searchTextFieldEditor_ string]
         substringToIndex:queryRange.location + queryRange.length];
    [activeSearchViewController_ setSavedPivotQueryString:savedQueryString];
    [searchTextFieldEditor_ resetCompletion];
    
    NSView *viewControllerView = [viewController view];
    [viewControllerView setFrame:[self rightOffscreenViewRect]];
    NSView *resultsView = [self resultsView];
    [resultsView addSubview:viewControllerView];
    
    NSView *activeSearchView = [activeSearchViewController_ view];
    
    NSRect activeSearchRect = [self leftOffscreenViewRect];
    NSValue *activeSearchRectValue = [NSValue valueWithRect:activeSearchRect];
    NSDictionary *anim1 = [NSDictionary dictionaryWithObjectsAndKeys:
                           activeSearchView, NSViewAnimationTargetKey, 
                           activeSearchRectValue, NSViewAnimationEndFrameKey,
                           nil];
    NSRect viewRect = [self mainViewRect];
    NSValue *viewRectValue = [NSValue valueWithRect:viewRect];   
    NSDictionary *anim2 = [NSDictionary dictionaryWithObjectsAndKeys:
                           viewControllerView, NSViewAnimationTargetKey, 
                           viewRectValue, NSViewAnimationEndFrameKey, 
                           nil];
    NSArray *animations = [NSArray arrayWithObjects:anim1, anim2, nil];
    [pivotingAnimation_ stopAnimation];
    [pivotingAnimation_ setDuration:kQSBPushPopDuration];
    [pivotingAnimation_ setAnimationBlockingMode:NSAnimationNonblocking];
    [pivotingAnimation_ setViewAnimations:animations];
    QSBSimpleInvocation *invocation 
      = [QSBSimpleInvocation selector:@selector(pushPopAnimationCompleted:) 
                               target:self 
                               object:activeSearchViewController_];
    [pivotingAnimation_ setUserInfo:invocation];
    [pivotingAnimation_ startAnimation];
  } else {
    [[viewController view] setFrame:[self mainViewRect]];
    [[self resultsView] addSubview:[viewController view]];
  }

  [self setActiveSearchViewController:searchViewController];
}

- (NSViewController *)popViewControllerAnimate:(BOOL)animate {
  QSBSearchViewController *parentSearchViewController
    = [activeSearchViewController_ parentSearchViewController];
  if (parentSearchViewController) {
    // Restore the previously typed query string.
    // NOTE: This happens when the 'character' in front of the text cursor
    // is a pivot frame and the user has pressed a deleteBackwards:, so 
    // insert the text to be replaced with an extra character at the end
    // so that the text engine deletes that character when it gets around
    // to processing the deleteBackwards.
    NSString *savedQueryString 
      = [parentSearchViewController savedPivotQueryString];
    [searchTextFieldEditor_ selectAll:self];
    [searchTextFieldEditor_ insertText:savedQueryString];
    NSRange savedQueryRange = [parentSearchViewController savedPivotQueryRange];
    [searchTextFieldEditor_ setSelectedRange:savedQueryRange];
        
    NSView *resultsView = [self resultsView];
    NSView *parentSearchView = [parentSearchViewController view];
    [parentSearchView setFrame:[self leftOffscreenViewRect]];
    [resultsView addSubview:parentSearchView];
    
    NSView *activeView = [activeSearchViewController_ view];

    // Slide the top controller out and the parent controller in.
    NSRect viewRect = [self mainViewRect];
    NSRect activeSearchRect = [self rightOffscreenViewRect];
    if (animate) {
      NSView *activeSearchView = [activeSearchViewController_ view];
      NSValue *activeSearchRectValue = [NSValue valueWithRect:activeSearchRect];
      NSDictionary *anim1 = [NSDictionary dictionaryWithObjectsAndKeys:
                             activeSearchView, NSViewAnimationTargetKey, 
                             activeSearchRectValue, NSViewAnimationEndFrameKey,
                             nil];
      NSValue *viewRectValue = [NSValue valueWithRect:viewRect];   
      NSDictionary *anim2 = [NSDictionary dictionaryWithObjectsAndKeys:
                             parentSearchView, NSViewAnimationTargetKey, 
                             viewRectValue, NSViewAnimationEndFrameKey, 
                             nil];
      NSArray *animations = [NSArray arrayWithObjects:anim1, anim2, nil];
      [pivotingAnimation_ stopAnimation];
      [pivotingAnimation_ setDuration:kQSBPushPopDuration];
      [pivotingAnimation_ setAnimationBlockingMode:NSAnimationNonblocking];
      [pivotingAnimation_ setViewAnimations:animations];
      QSBSimpleInvocation *invocation 
        = [QSBSimpleInvocation selector:@selector(pushPopAnimationCompleted:) 
                                 target:self 
                                 object:activeSearchViewController_];
      [pivotingAnimation_ setUserInfo:invocation];
      [pivotingAnimation_ startAnimation];
    } else {
      [activeView setFrame:activeSearchRect];
      [parentSearchView setFrame:viewRect];
      [activeView removeFromSuperview];
    }
    
    [activeSearchViewController_ setParentSearchViewController:nil];
    [self setActiveSearchViewController:parentSearchViewController];
  }
  return parentSearchViewController;
}

- (void)pushPopAnimationCompleted:(QSBSearchViewController *)controller {
  [[controller view] removeFromSuperview];
}

- (void)clearAllViewControllersAndSearchString {
  while([self popViewControllerAnimate:NO]) { }
  [activeSearchViewController_ setQueryString:nil];
  [searchTextField_ setStringValue:@""];
}


- (void)resetQuery:(NSTimer *)timer {
  queryResetTimer_ = nil;
  while([self popViewControllerAnimate:NO]) { }
  showResults_ = NO;
  [activeSearchViewController_ setQueryString:nil];
  [searchTextField_ setStringValue:@""];
}

- (void)checkFindPasteboard:(NSTimer *)timer {
  NSInteger newCount 
    = [[NSPasteboard pasteboardWithName:NSFindPboard] changeCount];
  insertFindPasteBoardString_ = newCount != findPasteBoardChangeCount_;
  findPasteBoardChangeCount_ = newCount;
}

- (void)displayResults:(NSTimer *)timer {
  showResults_ = YES;
  if ([[self window] isVisible]) {
    // Force the results view to show
    [self updateResultsView];
  }
}

- (BOOL)isOurScreenCaptured {
  BOOL captured = NO;
  NSScreen *screen = [[self window] screen];
  NSDictionary *deviceDescription = [screen deviceDescription];
  NSValue *displayIDValue = [deviceDescription objectForKey:@"NSScreenNumber"];
  if (displayIDValue) {
    CGDirectDisplayID displayID = 0;
    [displayIDValue getValue:&displayID];
    if (displayID) {
      captured = CGDisplayIsCaptured(displayID) ? YES : NO;
    }
  }
  return captured;
}

- (NSView *)resultsView {
  return [[self resultsWindow] contentView]; 
}

- (NSRect)rightOffscreenViewRect {
  NSRect bounds = [self mainViewRect];
  bounds = NSOffsetRect(bounds, NSWidth(bounds), 0);
  return bounds;
}

- (NSRect)mainViewRect {
  NSRect bounds = [[self resultsView] bounds];
  bounds.size.height -= [self resultsViewOffsetFromTop];
  return bounds;
}

- (NSRect)leftOffscreenViewRect {
  NSRect bounds = [self mainViewRect];
  bounds = NSOffsetRect(bounds, -NSWidth(bounds), 0);
  return bounds;
}

- (NSRect)fullyExposedFrameForFrame:(NSRect)proposedFrame
                     respectingDock:(BOOL)respectingDock
                           onScreen:(NSScreen *)screen {
  // If we can't find a screen for this window, use the main one.
  if (!screen) {
    screen = [NSScreen mainScreen];
  }
  NSRect screenFrame = respectingDock ? [screen visibleFrame] : [screen frame];
  if (!NSContainsRect(screenFrame, proposedFrame)) {
    if (proposedFrame.origin.y < screenFrame.origin.y) {
      proposedFrame.origin.y = screenFrame.origin.y;
    }
    if (NSMaxX(proposedFrame) > NSMaxX(screenFrame)) {
      proposedFrame.origin.x = NSMaxX(screenFrame) - NSWidth(proposedFrame);
    }    
    if (proposedFrame.origin.x < screenFrame.origin.x) {
      proposedFrame.origin.x = screenFrame.origin.x;
    }
    if (NSMaxY(proposedFrame) > NSMaxY(screenFrame)) {
      proposedFrame.origin.y = NSMaxY(screenFrame) - NSHeight(proposedFrame);
    }
  }
  return proposedFrame;
}

#pragma mark Welcome Window

- (void)showWelcomeWindow {
  QSBWelcomeController *welcomeController
    = [[[QSBWelcomeController alloc]
       initWithWindowNibName:kQSBWelcomeWindowNibName
                parentWindow:[self window]] autorelease];
  [self setWelcomeController:welcomeController];
  HGSAssert(welcomeController, @"Failed to load WelcomeWindow.nib.");
  [welcomeController window];  // Force the nib to load.
}

- (void)closeWelcomeWindow {
  QSBWelcomeController *welcomeController = [self welcomeController];
  [welcomeController close];
  [self setWelcomeController:nil];
}

- (void)setWelcomeHidden:(BOOL)hidden {
  QSBWelcomeController *welcomeController = [self welcomeController];
  [welcomeController setHidden:hidden];
}

@end
