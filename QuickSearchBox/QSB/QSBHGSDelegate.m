//
//  QSBHGSDelegate.m
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

#import "QSBHGSDelegate.h"
#import "GTMGarbageCollection.h"
#import "FilesystemActions.h"

// This constant is the name for the app that should be used w/in the a Google
// folder (for w/in Application Support, etc.)
static NSString *const kQSBFolderNameWithGoogleFolder = @"Quick Search Box";

@implementation QSBHGSDelegate
- (id)init {
  if ((self = [super init])) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSArray *langs = [ud objectForKey:@"AppleLanguages"];
    if ([langs count] > 0) {
      preferredLanguage_ = [langs objectAtIndex:0];
    }
    if (!preferredLanguage_) {
      preferredLanguage_ = @"en";
    }        
  }
  return self;
}

- (void)dealloc {
  [preferredLanguage_ release];
  [pluginPaths_ release];
  [super dealloc];
}

- (NSString*)userFolderForType:(OSType)type {
  NSString *result = nil;
  FSRef folderRef;
  if (FSFindFolder(kUserDomain, type, YES,
                   &folderRef) == noErr) {
    NSURL *folderURL
      = GTMCFAutorelease(CFURLCreateFromFSRef(kCFAllocatorSystemDefault,
                                              &folderRef));
    if (folderURL) {
      NSString *folderPath = [folderURL path];
      
      // we want Google/[App Name] with the folder
      NSString *finalPath
        = [[folderPath stringByAppendingPathComponent:@"Google"]
           stringByAppendingPathComponent:kQSBFolderNameWithGoogleFolder];
      
      // make sure it exists
      NSFileManager *fm = [NSFileManager defaultManager];
      if ([fm fileExistsAtPath:finalPath] ||
          [fm createDirectoryAtPath:finalPath
        withIntermediateDirectories:YES
                         attributes:nil
                              error:NULL]) {
        result = finalPath;
      }
    }
  }
  return result;
}

- (NSString*)userApplicationSupportFolderForApp {
  return [self userFolderForType:kApplicationSupportFolderType];
}

- (NSString*)userCacheFolderForApp {
  return [self userFolderForType:kCachedDataFolderType];
}

- (NSArray*)pluginFolders {
  if (!pluginPaths_) {
    NSMutableArray *buildPaths = [NSMutableArray array];
    NSFileManager *fm = [NSFileManager defaultManager];
    
    // The bundled folder
    [buildPaths addObject:[[NSBundle mainBundle] builtInPlugInsPath]];
    
    // The plugins w/in the user's home dir
    NSString *pluginsDir
      = [[self userApplicationSupportFolderForApp]
         stringByAppendingPathComponent:@"PlugIns"];
    if ([fm fileExistsAtPath:pluginsDir] ||
        [fm createDirectoryAtPath:pluginsDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:NULL]) {
      // it exists or we created it
      [buildPaths addObject:pluginsDir];
    }
    
    // Any system wide plugins (we use the folder if it exists, but we don't
    // create it.
    FSRef folderRef;
    if (FSFindFolder(kLocalDomain, kApplicationSupportFolderType, YES,
                     &folderRef) == noErr) {
      NSURL *folderURL
        = GTMCFAutorelease(CFURLCreateFromFSRef(kCFAllocatorSystemDefault,
                                                &folderRef));
      if (folderURL) {
        NSString *folderPath = [folderURL path];
        
        folderPath
          = [[[folderPath stringByAppendingPathComponent:@"Google"]
              stringByAppendingPathComponent:kQSBFolderNameWithGoogleFolder]
             stringByAppendingPathComponent:@"PlugIns"];
        
        if ([fm fileExistsAtPath:folderPath]) {
          [buildPaths addObject:folderPath];
        }
      }
    }
    
    // save it
    pluginPaths_ = [buildPaths copy];
  }
  
  return pluginPaths_;
}

- (NSString *)navSuggestHost {
  return @"http://clients1.google.com";
}

- (NSString *)suggestHost {
  return @"http://clients1.google.com";
}

- (NSString *)suggestLanguage {
  return preferredLanguage_;
}

- (NSString *)defaultActionID {
  return kFileSystemOpenActionIdentifier;
}
@end
