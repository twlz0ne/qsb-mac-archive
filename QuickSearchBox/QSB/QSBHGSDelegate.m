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
#import "QSBPluginVerifyWindowController.h"

// This constant is the name for the app that should be used w/in the a Google
// folder (for w/in Application Support, etc.)
static NSString *const kQSBFolderNameWithGoogleFolder = @"Quick Search Box";

@interface QSBHGSDelegate () 
- (NSArray *)pathCellArrayForResult:(HGSResult *)result;
- (NSArray *)pathCellArrayForFileURL:(NSURL *)url;
- (NSArray *)pathCellArrayForNonFileURL:(NSURL *)url;
@end

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
  [pluginVerifyWindowController_ release];
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
    
    // The current working directory (to support plugin development)
    [buildPaths addObject:[fm currentDirectoryPath]];
    
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

- (HGSPluginLoadResult)shouldLoadPluginAtPath:(NSString *)path
                                withSignature:(HGSCodeSignature *)signature {
  if (!pluginVerifyWindowController_) {
    pluginVerifyWindowController_ =
      [[QSBPluginVerifyWindowController alloc] init];
  }
  return [pluginVerifyWindowController_ runForPluginAtPath:path
                                             withSignature:signature];
}

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  id value = nil;
  if ([key isEqualToString:kQSBObjectAttributePathCellsKey]) {
    value = [self pathCellArrayForResult:result];
  } else if ([key isEqualToString:kHGSObjectAttributeDefaultActionKey]) {
    HGSExtensionPoint *actionPt = [HGSExtensionPoint actionsPoint];
    value = [actionPt extensionWithIdentifier:kFileSystemOpenActionIdentifier];
  }
  return value;
}

- (NSArray *)pathCellArrayForResult:(HGSResult *)result {
  NSArray *cellArray = nil;
  NSURL *url = [result url];
  if ([url isFileURL]) {
    cellArray = [self pathCellArrayForFileURL:url];
  } else {
    cellArray = [self pathCellArrayForNonFileURL:url];
  }
  return cellArray;
}

- (NSArray *)pathCellArrayForFileURL:(NSURL *)url {
  NSMutableArray *cellArray = nil;
  
  // Provide a cellArray for the path control assuming that we are
  // a file and our identifier is a file URL.
  if (url) {
    // Generate a list of display components and then walk backwards
    // through it generating URLs for each component.
    NSString *targetPath = [url path];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *displayComponents = [fm componentsToDisplayForPath:targetPath];
    if (displayComponents) {
      cellArray = [NSMutableArray arrayWithCapacity:[displayComponents count]];
      NSEnumerator *reverseEnum = [displayComponents reverseObjectEnumerator];
      NSString *component;
      NSString *subPath = targetPath;
      while ((component = [reverseEnum nextObject])) {
        NSURL *subUrl = [NSURL fileURLWithPath:subPath];
        NSDictionary *cellDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                  component, kQSBPathCellDisplayTitleKey,
                                  subUrl, kQSBPathCellURLKey,
                                  nil];
        [cellArray insertObject:cellDict atIndex:0];
        subPath = [subPath stringByDeletingLastPathComponent];
      }
      // Determine if we can abbreviate the path presentation.
      
      // First, see if this is in the user's home directory structure
      // and, if so, abbreviated it with 'Home'.  If not, then check
      // to see if we're on the root volume and if so, don't show
      // the volume name.
      NSString *homeDirectory = NSHomeDirectory();
      NSString *homeDisplay = [fm displayNameAtPath:homeDirectory];
      NSUInteger compCount = 0;
      NSDictionary *componentToAdd = nil;
      NSDictionary *firstCell = [cellArray objectAtIndex:0];
      NSString *firstCellTitle 
        = [firstCell objectForKey:kQSBPathCellDisplayTitleKey];
      if ([firstCellTitle isEqualToString:homeDisplay]) {
        compCount = 1;
        componentToAdd 
          = [NSDictionary dictionaryWithObjectsAndKeys:
             HGSLocalizedString(@"Home", nil), kQSBPathCellDisplayTitleKey,
             [NSURL fileURLWithPath:homeDirectory], kQSBPathCellURLKey,
             nil];
      } else {
        NSString *rootDisplay = [fm displayNameAtPath:@"/"];
        if ([firstCellTitle isEqualToString:rootDisplay]) {
          compCount = 1;
        }
      }
      if (compCount) {
        [cellArray removeObjectsInRange:NSMakeRange(0, compCount)];
      }
      if (componentToAdd) {
        [cellArray insertObject:componentToAdd atIndex:0];
      }
    } else {
      HGSLogDebug(@"Unable to get path components for path '%@'.", targetPath);
    }
  }
  
  return cellArray;
}

- (NSArray *)pathCellArrayForNonFileURL:(NSURL *)url {
  NSMutableArray *cellArray = nil;
  
  // See if we have a regular URL.
  NSString *absolutePath = [url absoluteString];
  if (absolutePath) {
    // Build up two path cells, one with the domain, and the second
    // with the location within the domain.  Do this by finding the
    // first and second occurrence of the slash separator.
    NSString *hostString = [url host];
    if ([hostString length]) {
      cellArray = [NSMutableArray arrayWithCapacity:2];
      NSURL *pathURL = [NSURL URLWithString:absolutePath];
      NSString *pathString = [url path];
      
      if ([pathString length] == 0 || [pathString isEqualToString:@"/"]) {
        // We just have a host cell.
        NSDictionary *hostCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                  hostString, kQSBPathCellDisplayTitleKey,
                                  pathURL, kQSBPathCellURLKey,
                                  nil];
        [cellArray addObject: hostCell];
      } else {          
        // NOTE: Attempts to use -[NSURL initWithScheme:host:path:] were 
        //       unsuccessful using (nil|@""|@"/") for the path.  Each fails to 
        //       produce an acceptable URL or throws an exception.
        // NSURL *hostURL = [[[NSURL alloc] initWithScheme:[url scheme]
        //                                            host:hostString
        //                                            path:???] autorelease];
        NSURL *hostURL 
          = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@/",
                                  [url scheme], hostString]];
        NSDictionary *hostCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                  hostString, kQSBPathCellDisplayTitleKey,
                                  hostURL, kQSBPathCellURLKey,
                                  nil];
        [cellArray addObject: hostCell];
        NSDictionary *pathCell = [NSDictionary dictionaryWithObjectsAndKeys:
                                  pathString, kQSBPathCellDisplayTitleKey,
                                  pathURL, kQSBPathCellURLKey,
                                  nil];
        [cellArray addObject: pathCell];
      }
    }
  }
  return cellArray;
}

@end
