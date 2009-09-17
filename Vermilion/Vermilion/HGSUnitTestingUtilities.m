//
//  HGSUnitTestingUtilities.m
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

#import "HGSUnitTestingUtilities.h"
#import "GTMObjectSingleton.h"
#import "GTMGarbageCollection.h"
#import "GTMDebugThreadValidation.h"
#import <objc/runtime.h>
#import <sys/param.h>

@interface HGSUnitTestingPluginLoader()
- (BOOL)loadPlugin;
@end

@implementation HGSUnitTestingPluginLoader
+ (BOOL)loadPlugin:(NSString *)plugin {
  HGSUnitTestingPluginLoader *loader 
    = [[[HGSUnitTestingPluginLoader alloc] initWithPath:plugin] autorelease];
  return [loader loadPlugin];
}

- (id)initWithPath:(NSString *)plugin {
  if ((self = [super init])) {
    HGSAssert([plugin length], @"Need a valid plugin");
    path_ = [plugin copy];
  }
  return self;
}

- (void)dealloc {
  [path_ release];
  [super dealloc];
}

- (BOOL)loadPlugin {
  // This routine messes with the delegate for the plugin loader.
  // We don't want people changing the delegate out from underneath us.
  GTMAssertRunningOnMainThread();
  HGSPluginLoader *loader = [HGSPluginLoader sharedPluginLoader];
  id oldDelegate = [loader delegate];
  [loader setDelegate:self];
  NSArray *errors = nil;
  [loader loadPluginsWithErrors:&errors];
  BOOL wasGood = YES;
  if (errors) {
    wasGood = NO;
    HGSLog(@"Unable to load plugin %@: %@", path_, errors);
  } else {
    [loader installAndEnablePluginsBasedOnPluginsState:nil];
  }
  [loader setDelegate:oldDelegate];
  return wasGood;
}

#pragma mark Delegate Methods

- (NSString*)userFolderNamed:(NSString* )name {
  NSString *workingDir = NSTemporaryDirectory();
  NSString *result = nil;    
  NSString *finalPath
    = [[[workingDir stringByAppendingPathComponent:@"Google"]
        stringByAppendingPathComponent:@"Quick Search Box Unit Testing"]
       stringByAppendingPathComponent:name];
  
  // make sure it exists
  NSFileManager *fm = [NSFileManager defaultManager];
  if ([fm fileExistsAtPath:finalPath] ||
      [fm createDirectoryAtPath:finalPath
    withIntermediateDirectories:YES
                     attributes:nil
                          error:NULL]) {
    result = finalPath;
  }
  return result;
}

- (NSString*)userApplicationSupportFolderForApp {
  return [self userFolderNamed:@"Application Support"];
}

- (NSString*)userCacheFolderForApp {
  return [self userFolderNamed:@"Cache"];
}

- (NSArray*)pluginFolders {
  return [NSArray arrayWithObject:path_];
}

- (NSString *)suggestLanguage {
  return @"en_US";
}

- (NSString *)clientID {
  return @"qsb_mac_unit_testing";
}

- (HGSPluginLoadResult)shouldLoadPluginAtPath:(NSString *)path
                                withSignature:(HGSCodeSignature *)signature {
  return YES;
}

- (id)provideValueForKey:(NSString *)key result:(HGSResult *)result {
  return nil;
}

- (NSDictionary *)getActionSaveAsInfoFor:(NSDictionary *)request {
  return nil;
}

@end

@implementation HGSExtensionTestCase 

@synthesize extension = extension_;
@synthesize extensionPoint = extensionPoint_;
@synthesize pluginName = pluginName_;
@synthesize identifier = identifier_;

- (id)initWithInvocation:(NSInvocation *)invocation
             pluginNamed:(NSString *)pluginName 
     extensionIdentifier:(NSString *)identifier
extensionPointIdentifier:(NSString *)extensionPoint {
  if ((self = [super initWithInvocation:invocation])) {
    pluginName_ = [pluginName copy];
    STAssertGreaterThan([pluginName_ length], (NSUInteger)0, nil);
    identifier_ = [identifier copy];
    STAssertGreaterThan([identifier_ length], (NSUInteger)0, nil);
    extensionPoint_ = [HGSExtensionPoint pointWithIdentifier:extensionPoint];
    STAssertNotNil(extensionPoint_, nil);
  }
  return self;
}

- (void)dealloc {
  [pluginName_ release];
  [identifier_ release];
  [super dealloc];
}

- (void)setUp {
  [super setUp];
  NSBundle *hgsBundle = HGSGetPluginBundle();
  NSString *bundlePath = [hgsBundle bundlePath];
  NSString *workingDir = [bundlePath stringByDeletingLastPathComponent];
  NSString *path 
    = [workingDir stringByAppendingPathComponent:[self pluginName]];
  path = [path stringByAppendingPathExtension:@"hgs"];
  BOOL didLoad = [HGSUnitTestingPluginLoader loadPlugin:path];
  STAssertTrue(didLoad, @"Unable to load %@", path);
  HGSExtensionPoint *sp = [self extensionPoint];
  NSString *identifier = [self identifier];
  extension_ = [sp extensionWithIdentifier:identifier];
  STAssertNotNil(extension_, @"Unable to load %@ from %@", identifier, path);
  [extension_ retain];
  STAssertNotNil(extension_, nil);
}

- (void)tearDown {
  [[extension_ protoExtension] uninstall];
  [extension_ release];
  [super tearDown];
}

- (void)testDisplayName {
  STAssertNotNil([[self extension] displayName], nil);
}

@end

@implementation HGSSearchSourceTestCase
@dynamic source;

- (id)initWithInvocation:(NSInvocation *)invocation
             pluginNamed:(NSString *)pluginName 
     extensionIdentifier:(NSString *)identifier {
  return [super initWithInvocation:invocation 
                       pluginNamed:pluginName 
               extensionIdentifier:identifier 
          extensionPointIdentifier:kHGSSourcesExtensionPoint];
}

- (HGSSearchSource *)source {
  return [self extension];
}

// Must be overridden by subclasses.
- (NSArray *)archivableResults {
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}

- (void)testArchiving {
  HGSSearchSource *source = [self source];
  if (![source cannotArchive]) {
    NSArray *results = [self archivableResults];
    for (HGSResult *result in results) {
      NSDictionary *archive = [source archiveRepresentationForResult:result];
      STAssertNotNil(archive, nil);
      HGSResult *thawedResult = [source resultWithArchivedRepresentation:archive];
      STAssertEqualObjects(result, thawedResult, nil);
    }
    
    // Expected failures
    HGSResult *tempResult = [source resultWithArchivedRepresentation:nil];
    STAssertNil(tempResult, nil);
    tempResult 
      = [source resultWithArchivedRepresentation:[NSDictionary dictionary]];
    STAssertNil(tempResult, nil);
    
    NSDictionary *archive = [source archiveRepresentationForResult:nil];
    STAssertNil(archive, nil);
  }
}

@end

@implementation HGSActionTestCase
@dynamic action;

- (id)initWithInvocation:(NSInvocation *)invocation
             pluginNamed:(NSString *)pluginName 
     extensionIdentifier:(NSString *)identifier {
  return [super initWithInvocation:invocation 
                       pluginNamed:pluginName 
               extensionIdentifier:identifier 
          extensionPointIdentifier:kHGSSourcesExtensionPoint];
}

- (HGSAction *)action {
  return [self extension];
}

// TODO(dmaclach):remove this once we have some subclasses of this thing.
+ (BOOL)isAbstractTestCase {
  return YES;
}
@end

