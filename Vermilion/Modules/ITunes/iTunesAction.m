//
//  iTunesAction.m
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

#import "ITunesSource.h"
#import "GTMMethodCheck.h"
#import "GTMNSAppleScript+Handler.h"
#import "GTMObjectSingleton.h"
#import "GTMNSWorkspace+Running.h"

static NSString *const kITunesAppleScriptHandlerKey = @"kITunesAppleScriptHandlerKey";
static NSString *const kITunesAppleScriptParametersKey = @"kITunesAppleScriptParametersKey";
static NSString *const kiTunesBundleID = @"com.apple.iTunes";

@interface ITunesPlayAction : HGSAction
@end

@interface ITunesPlayInPartyShuffleAction : HGSAction
@end

@interface ITunesAddToPartyShuffleAction : HGSAction
@end

@interface ITunesAppAction : HGSAction {
 @private
  NSString *command_;
}
- (BOOL)isPlaying;

@end

@interface ITunesActionSupport : NSObject {
  NSAppleScript *script_; // STRONG
  BOOL iTunesIsRunning_;
}
- (NSAppleScript *)appleScript;
@end

@implementation ITunesActionSupport

GTMOBJECT_SINGLETON_BOILERPLATE(ITunesActionSupport, sharedSupport);

- (id)init {
  self = [super init];
  if (self) {
    NSNotificationCenter *workSpaceNC = [[NSWorkspace sharedWorkspace] notificationCenter];
    [workSpaceNC addObserver:self
                    selector:@selector(didLaunchApp:)
                        name:NSWorkspaceDidLaunchApplicationNotification
                      object:nil];
    [workSpaceNC addObserver:self
                    selector:@selector(didTerminateApp:)
                        name:NSWorkspaceDidTerminateApplicationNotification
                      object:nil];
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    iTunesIsRunning_ = [ws gtm_isAppWithIdentifierRunning:kiTunesBundleID];
  }
  return self;
}

- (NSAppleScript *)appleScript {
  @synchronized(self) {
    if (!script_) {
      NSBundle *bundle = HGSGetPluginBundle();
      NSString *path = [bundle pathForResource:@"iTunes"
                                        ofType:@"scpt"
                                   inDirectory:@"Scripts"];
      NSURL *url = [NSURL fileURLWithPath:path];
      NSDictionary *error = nil;
      script_ = [[NSAppleScript alloc] initWithContentsOfURL:url error:&error];
      if (!script_) {
        HGSLogDebug(@"Unable to load script: %@ error: %@", url, error);
      }
    }
  }
  return script_;
}

- (void)dealloc {
  [script_ release];
  [super dealloc];
}

- (NSAppleEventDescriptor *)execute:(NSDictionary *)params {
  NSDictionary *errorDictionary = nil;
  NSAppleEventDescriptor *result;
  NSString *handler = [params valueForKey:kITunesAppleScriptHandlerKey];
  NSArray *args = [params valueForKey:kITunesAppleScriptParametersKey];
  result = [[self appleScript] gtm_executePositionalHandler:handler
                                                 parameters:args
                                                      error:&errorDictionary];
  if (errorDictionary) {
    HGSLog(@"iTunes script failed %@(%@): %@", handler, args, errorDictionary);
  }
  return result;
}

- (void)didLaunchApp:(NSNotification *)notification {
  if (!iTunesIsRunning_) {
    NSDictionary *userInfo = [notification userInfo];
    NSString *bundleID = [userInfo objectForKey:@"NSApplicationBundleIdentifier"];
    if ([bundleID isEqualToString:kiTunesBundleID]) {
      iTunesIsRunning_ = YES;
    }
  }
}

- (void)didTerminateApp:(NSNotification *)notification {
  if (iTunesIsRunning_) {
    NSDictionary *userInfo = [notification userInfo];
    NSString *bundleID = [userInfo objectForKey:@"NSApplicationBundleIdentifier"];
    if ([bundleID isEqualToString:kiTunesBundleID]) {
      iTunesIsRunning_ = NO;
    }
  }
}

- (BOOL)iTunesIsRunning {
  return iTunesIsRunning_;
}

@end

// "Play in iTunes" action for iTunes search results
@implementation ITunesPlayAction

GTM_METHOD_CHECK(NSAppleScript, gtm_executePositionalHandler:parameters:error:);


- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *directObject = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *handler = nil;
  NSString *directObjectKey = nil;
  id extraArg = nil;
  if ([directObject isOfType:kTypeITunesTrack]) {
    extraArg = [directObject valueForKey:kITunesAttributePlaylistIdKey];
    if (extraArg) {
      handler = @"playTrackIDInPlaylistID";
      directObjectKey = kITunesAttributeTrackIdKey;
    } else {
      handler = @"playTrackID";
      directObjectKey = kITunesAttributeTrackIdKey;
    }
  } else if ([directObject isOfType:kTypeITunesArtist]) {
    handler = @"playArtist";
    directObjectKey = kITunesAttributeArtistKey;
  } else if ([directObject isOfType:kTypeITunesAlbum]) {
    handler = @"playAlbum";
    directObjectKey = kITunesAttributeAlbumKey;
  } else if ([directObject isOfType:kTypeITunesComposer]) {
    handler = @"playComposer";
    directObjectKey = kITunesAttributeComposerKey;
  } else if ([directObject isOfType:kTypeITunesGenre]) {
    handler = @"playGenre";
    directObjectKey = kITunesAttributeGenreKey;
  } else if ([directObject isOfType:kTypeITunesPlaylist]) {
    handler = @"playPlaylist";
    directObjectKey = kITunesAttributePlaylistKey;
  }
  if (handler && directObjectKey) {
    id directObjectVal = [directObject valueForKey:directObjectKey];
    NSArray *parameters 
      = [NSArray arrayWithObjects:directObjectVal, extraArg, nil];
    NSDictionary *scriptParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                  handler, kITunesAppleScriptHandlerKey, 
                                  parameters, kITunesAppleScriptParametersKey, 
                                  nil];
    ITunesActionSupport *support = [ITunesActionSupport sharedSupport];
    [support performSelectorOnMainThread:@selector(execute:)
                              withObject:scriptParams
                           waitUntilDone:NO];
  }
  return YES;
}

@end

// "Play in iTunes Party Shuffle" action for iTunes search results
@implementation ITunesPlayInPartyShuffleAction

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *directObject = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *trackID = [directObject valueForKey:kITunesAttributeTrackIdKey];
  NSDictionary *scriptParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"playInPartyShuffle", kITunesAppleScriptHandlerKey,
                                [NSArray arrayWithObject:trackID],
                                kITunesAppleScriptParametersKey, nil];
  ITunesActionSupport *support = [ITunesActionSupport sharedSupport];  
  [support performSelectorOnMainThread:@selector(execute:)
                            withObject:scriptParams
                         waitUntilDone:NO];
  return YES;
}

@end

// "Add to iTunes Party Shuffle" action for iTunes search results
@implementation ITunesAddToPartyShuffleAction

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *directObject = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *trackID = [directObject valueForKey:kITunesAttributeTrackIdKey];
  NSDictionary *scriptParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"addToPartyShuffle", kITunesAppleScriptHandlerKey,
                                [NSArray arrayWithObject:trackID],
                                kITunesAppleScriptParametersKey, nil];
  ITunesActionSupport *support = [ITunesActionSupport sharedSupport];
  [support performSelectorOnMainThread:@selector(execute:)
                            withObject:scriptParams
                         waitUntilDone:NO];
  return YES;
}

@end

// Actions that are applied to the iTunes application rather than
// iTunes search results
@implementation ITunesAppAction

GTM_METHOD_CHECK(NSWorkspace, gtm_isAppWithIdentifierRunning:);

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    command_ = [[configuration objectForKey:@"iTunesCommand"] retain];
  }
  return self;
}

- (void)dealloc {
  [command_ release];
  [super dealloc];
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  NSDictionary *scriptParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                command_, kITunesAppleScriptHandlerKey,
                                nil];
  ITunesActionSupport *support = [ITunesActionSupport sharedSupport];
  [support performSelectorOnMainThread:@selector(execute:)
                            withObject:scriptParams
                         waitUntilDone:NO];
  return YES;
}

- (BOOL)isPlaying {
  NSDictionary *scriptParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                @"isPlaying", kITunesAppleScriptHandlerKey,
                                 nil];
  ITunesActionSupport *support = [ITunesActionSupport sharedSupport];
  NSAppleEventDescriptor *result = [support execute:scriptParams];
  return [result booleanValue];
}

- (BOOL)showActionInGlobalSearchResults {
  return [[ITunesActionSupport sharedSupport] iTunesIsRunning];
}

@end
