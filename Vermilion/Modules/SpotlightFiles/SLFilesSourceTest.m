//
//  SLFilesSourceTest.m
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

#import "HGSUnitTestingUtilities.h"
#import "SLFilesSource.h"
#import <OCMock/OCMock.h>

@interface SLFilesSourceTest : HGSSearchSourceAbstractTestCase {
 @private
  NSString *testFolderPath_;
  NSString *uniqueTestString_;
}
@end

@implementation SLFilesSourceTest
  
- (id)initWithInvocation:(NSInvocation *)invocation {
  self = [super initWithInvocation:invocation 
                       pluginNamed:@"SpotlightFiles" 
               extensionIdentifier:@"com.google.qsb.spotlight.source"];
  return self;
}

- (void)setUp {
  [super setUp];
  NSFileManager *manager = [NSFileManager defaultManager];
  testFolderPath_ 
    = [[@"~/QSBMacTestFiles" stringByStandardizingPath] retain];
  BOOL isDir = YES;
  NSError *error = nil;
  BOOL goodDir = [manager fileExistsAtPath:testFolderPath_ isDirectory:&isDir];
  if (!goodDir) {
    goodDir = [manager createDirectoryAtPath:testFolderPath_
                 withIntermediateDirectories:YES attributes:nil error:&error];
    STAssertTrue(goodDir, 
                 @"Unable to create directory at %@ (%@)", 
                 testFolderPath_, error);
  } else {
    STAssertTrue(isDir, @"File at %@ isn't a directory", testFolderPath_);
  }
  // Weird split done so that spotlight doesn't find this source file for us
  // when we search for our "unique string"
  uniqueTestString_ 
    = [[NSString stringWithFormat:@"%@%@", @"aichmor", @"habdophobia"] retain];
}
  
- (void)tearDown {
  NSFileManager *manager = [NSFileManager defaultManager];
  NSError *error;
  STAssertTrue([manager removeItemAtPath:testFolderPath_ error:&error],
               @"Unable to remove folder at %@ (%@)", testFolderPath_, error);
  [testFolderPath_ release];
  [super tearDown];
}

- (NSString *)createTestFile:(NSString *)name {
  NSString *testFilePath 
    = [testFolderPath_ stringByAppendingPathComponent:name];
  NSError *error = nil;
  BOOL goodFileWrite = [uniqueTestString_ writeToFile:testFilePath 
                                           atomically:YES 
                                             encoding:NSUTF8StringEncoding 
                                                error:&error];
  [[NSWorkspace sharedWorkspace] noteFileSystemChanged:testFilePath];
  STAssertTrue(goodFileWrite, @"Unable to write file to %@ (%@)",
               testFilePath, error);
  return testFilePath;
}
  
- (void)mdimportFile:(NSString *)path {
  NSArray *args = [NSArray arrayWithObject:path];
  NSTask *mdimport = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/mdimport" 
                                              arguments:args];
  [mdimport waitUntilExit];
  STAssertEquals([mdimport terminationStatus], 0, 
                 @"mdimport for %@ exited with %d", path, 
                 [mdimport terminationStatus]);
}

- (NSArray *)performSearchFor:(NSString *)value pivotingOn:(HGSResultArray *)pivots {
  HGSQuery *query = [[[HGSQuery alloc] initWithString:value 
                                              results:pivots 
                                           queryFlags:0] autorelease];
  STAssertNotNil(query, nil);
  HGSSearchOperation *operation = [[self source] searchOperationForQuery:query];
  STAssertNotNil(operation, nil);
  [operation main];
  return [(SLFilesOperation *)operation accumulatedResults];
}

- (HGSResult *)spotlightResultForQuery:(NSString *)query path:(NSString *)path {
  Class resultClass = [[self source] resultClass];
  STAssertNotNULL(resultClass, nil);
  MDItemRef mdItem = MDItemCreate(kCFAllocatorDefault, (CFStringRef)path);
  STAssertNotNULL(mdItem, @"Unable to create mdItem for %@", path);  
  HGSResult *result = [[resultClass alloc] initWithMDItem:mdItem
                                                    query:query
                                                source:[self source]];
  STAssertNotNil(result, nil);
  CFRelease(mdItem);
  return result;
}

- (NSArray *)archivableResults {
  NSString *paths[] = {
    @"/Applications/TextEdit.app",
    @"/System"
  };
  size_t count = sizeof(paths) / sizeof(paths[0]);
  NSMutableArray *results 
    = [NSMutableArray arrayWithCapacity:count];
  for (size_t i = 0; i < count; ++i) {
    HGSResult *result = [self spotlightResultForQuery:uniqueTestString_
                                                 path:paths[i]];
    STAssertNotNil(result, nil);
    [results addObject:result];
  }
  return results;
}

- (void)testNilOperation {
  HGSSearchOperation *operation = [[self source] searchOperationForQuery:nil];
  STAssertNil(operation, nil);
}

- (void)testSimpleOperation {
  NSString *testFilePath = [self createTestFile:@"testSimpleOperation.txt"];
  [self mdimportFile:testFilePath];
  NSArray *results = [self performSearchFor:uniqueTestString_ pivotingOn:nil];
  STAssertGreaterThan([results count], (NSUInteger)0,  
                      @"QueryString: %@", uniqueTestString_);  

}

- (void)testSearchingFinderComments {  
  NSString *commentString 
    = [NSString stringWithFormat:@"%@%@", @"arachi", @"butyrophobia"];
  NSString *testFilePath 
    = [self createTestFile:@"testSearchingFinderComments.txt"];
  NSString *scriptSource 
    = @"tell app \"Finder\"\r"
      @"set QSBFile to POSIX file \"%@\"\r"
      @"set failCount to 3\r"
      @"repeat while failCount > 0\r"
      @"try\r"
      @"update QSBFile\r"
      @"set failCount to 0\r"
      @"on error\r"
      @"delay 1\r"
      @"set failCount to failCount - 1\r"
      @"end\r"
      @"end\r"
      @"set comment of item QSBFile to \"%@\"\r"
      @"end tell\r";
  scriptSource = [NSString stringWithFormat:scriptSource, 
                  testFilePath, commentString];
  NSAppleScript *script 
    = [[[NSAppleScript alloc] initWithSource:scriptSource] autorelease];
  NSDictionary *error = nil;
  NSAppleEventDescriptor *desc = [script executeAndReturnError:&error];
  STAssertNotNil(desc, @"Script %@ returned %@ for expression '%@'", 
                 scriptSource, 
                 error, 
                 [scriptSource substringWithRange:
                  [[error objectForKey:@"NSAppleScriptErrorRange"] rangeValue]]);
  [self mdimportFile:testFilePath];
  NSArray *results = [self performSearchFor:uniqueTestString_ pivotingOn:nil];
  STAssertGreaterThan([results count], (NSUInteger)0,  
                      @"QueryString: %@", uniqueTestString_);  

}

- (void)testUtiFilter {
  NSString *testFilePath = [self createTestFile:@"testSimpleOperation.txt"];
  OCMockObject *bundleMock = [OCMockObject mockForClass:[NSBundle class]];
  NSDictionary *config = 
    [NSDictionary dictionaryWithObjectsAndKeys:
     bundleMock, kHGSExtensionBundleKey,
     @"SLFilesSourceTest.testUtiFilter.identifier", kHGSExtensionIdentifierKey,
     @"testUtiFilter", kHGSExtensionUserVisibleNameKey,
     @"testPath", kHGSExtensionIconImagePathKey,
     (NSString*)kUTTypeData, kHGSSearchSourceUTIsToExcludeFromDiskSources,
     nil];
  [[[bundleMock stub] andReturn:@"testUtiFilter"] 
   localizedStringForKey:@"testUtiFilter" value:@"NOT_FOUND" table:@"InfoPlist"];
  [[[bundleMock stub] andReturn:@"imagePath"] pathForImageResource:@"testPath"];
  HGSSearchSource *source 
    = [[[HGSSearchSource alloc] initWithConfiguration:config] autorelease];
  HGSExtensionPoint *sourcesPoint = [HGSExtensionPoint sourcesPoint];
  [sourcesPoint extendWithObject:source];
  [self mdimportFile:testFilePath];
  NSArray *results = [self performSearchFor:uniqueTestString_ pivotingOn:nil];
  STAssertEquals([results count], (NSUInteger)0, @"Got results %@", results);
  [sourcesPoint removeExtension:source];
}

- (void)testValidSourceForQuery {
  HGSSearchSource *source = [self source];
  HGSQuery *query = [[[HGSQuery alloc] initWithString:@"happ" 
                                              results:nil 
                                           queryFlags:0] autorelease]; 
  STAssertFalse([source isValidSourceForQuery:query], 
                @"Queries < 5 characters should be ignored");
  query = [[[HGSQuery alloc] initWithString:@"happy" 
                                    results:nil 
                                 queryFlags:0] autorelease]; 
  STAssertTrue([source isValidSourceForQuery:query], 
                @"Queries >= 5 characters should be accepted");
  
  NSDictionary *badTypeDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"http://www.google.com", kHGSObjectAttributeURIKey,
       @"badTypeDict", kHGSObjectAttributeNameKey,
       kHGSTypeFile, kHGSObjectAttributeTypeKey,
       nil];
  HGSResult *badTypeResult = [HGSResult resultWithDictionary:badTypeDict 
                                                      source:source];
  query 
    = [[[HGSQuery alloc] initWithString:@"happy" 
                                results:[NSArray arrayWithObject:badTypeResult] 
                             queryFlags:0] autorelease]; 
  STAssertFalse([source isValidSourceForQuery:query],
                @"Queries with pivot of type kHGSTypeFile should fail.");
  
  NSDictionary *goodTypeDict
    = [NSDictionary dictionaryWithObjectsAndKeys:
       @"http://www.google.com", kHGSObjectAttributeURIKey,
       @"goodTypeDict", kHGSObjectAttributeNameKey,
       kHGSTypeContact, kHGSObjectAttributeTypeKey,
       nil];
  HGSResult *goodTypeResult = [HGSResult resultWithDictionary:goodTypeDict 
                                                       source:source];
  query 
    = [[[HGSQuery alloc] initWithString:@"happy" 
                                results:[NSArray arrayWithObject:goodTypeResult] 
                             queryFlags:0] autorelease]; 
  STAssertTrue([source isValidSourceForQuery:query],
               @"Queries with pivot of type kHGSTypeContact should succeed.");
}

- (void)testSLHGSResult {
  // Have to load these dynamically from the plugin.
  Class resultClass = NSClassFromString(@"SLHGSResult");
  STAssertNotNil(resultClass, nil);
  
  id result = [[[resultClass alloc] 
                initWithMDItem:NULL query:nil source:nil] 
               autorelease];
  STAssertNil(result, nil);
  
  NSString *finderPath 
    = [[NSWorkspace sharedWorkspace] 
       absolutePathForAppBundleWithIdentifier:@"com.apple.Finder"];
  MDItemRef mdItem = MDItemCreate(kCFAllocatorDefault, (CFStringRef)finderPath);
  STAssertNotNULL(mdItem, nil);
  result = [[resultClass alloc] initWithMDItem:mdItem query:nil source:nil];
  STAssertNil(result, nil);
  
  result = [self spotlightResultForQuery:uniqueTestString_
                                    path:finderPath];
  STAssertNotNil(result, nil);
  NSURL *url = [result url];
  STAssertEqualObjects(url, [NSURL fileURLWithPath:finderPath], nil);
}

- (void)testMailPivots {
  HGSSearchSource *source = [self source];
  NSBundle *pluginBundle = HGSGetPluginBundle();
  NSString *mailFilePath = [pluginBundle pathForResource:@"SampleEmail"
                                                  ofType:@"emlx"];
  STAssertNotNil(mailFilePath, nil);
  [self mdimportFile:mailFilePath];
  HGSResult *mailResult = [HGSResult resultWithFilePath:mailFilePath 
                                                 source:source
                                             attributes:nil];
  STAssertNotNil(mailResult, nil);
  HGSResultArray *array = [HGSResultArray arrayWithResult:mailResult];
  STAssertThrows([self performSearchFor:@"sender" pivotingOn:array], nil);
  NSDictionary *attributes 
    = [NSDictionary dictionaryWithObject:@"willy_wonka@wonkamail.com"
                                  forKey:kHGSObjectAttributeContactEmailKey];
  HGSResult *contactResult = [HGSResult resultWithURI:@"test:contact" 
                                                 name:@"Willy Wonka" 
                                                 type:kHGSTypeContact 
                                               source:source 
                                           attributes:attributes];
  STAssertNotNil(contactResult, nil);
  array = [HGSResultArray arrayWithResult:contactResult];
  NSArray *results = [self performSearchFor:@"vermicious" pivotingOn:array];
  BOOL foundResult = NO;
  for (HGSResult *result in results) {
    if ([[result filePath] isEqualToString:mailFilePath]) {
      foundResult = YES;
      NSArray *emailArray
        = [source provideValueForKey:kHGSObjectAttributeEmailAddressesKey 
                              result:result];
      NSSet *emailSet = [NSSet setWithArray:emailArray];
      NSSet *expectedEmailSet = [NSSet setWithObjects:
                                 @"deeproy_oompaloopa@wonkamail.com", 
                                 @"willy_wonka@wonkamail.com", 
                                 @"charles_bucket@wonkamail.com", 
                                 nil];
      STAssertEqualObjects(emailSet, expectedEmailSet, nil);
      NSArray *contactsArray
        = [source provideValueForKey:kHGSObjectAttributeContactsKey 
                              result:result];
      NSSet *contactsSet = [NSSet setWithArray:contactsArray];
      NSSet *expectedContacts = [NSSet setWithObjects:
                                 @"Deep Roy Oompa Loompa",
                                 @"Willy Wonka",
                                 @"Charlie Bucket",
                                 nil];
      STAssertEqualObjects(contactsSet, expectedContacts, nil);
      
      NSImage *icon = [source provideValueForKey:kHGSObjectAttributeIconKey 
                                          result:result];
      STAssertNil(icon, @"We only expect source to return icons for Web stuff");
      break;
    }
  }
  STAssertTrue(foundResult, nil);
}

- (void)testIcon {
  HGSSearchSource *source = [self source];
  NSBundle *pluginBundle = HGSGetPluginBundle();
  NSString *webhistoryPath = [pluginBundle pathForResource:@"SampleWeb"
                                                    ofType:@"webhistory"];
  STAssertNotNil(webhistoryPath, nil);
  [self mdimportFile:webhistoryPath];
  HGSResult *result = [self spotlightResultForQuery:@"willywonkaschocolates"
                                               path:webhistoryPath];
  // Normally this would be pulled from the app bundle. When running tests
  // we don't have an app bundle, so we'll create our own.
  NSImage *cachedImage = [[[NSImage alloc] init] autorelease];
  [cachedImage setName:@"blue-nav"];
  NSImage *icon = [source provideValueForKey:kHGSObjectAttributeIconKey 
                                      result:result];
  STAssertEqualObjects([icon name], 
                       @"blue-nav", 
                       @"Source provides icons for things with URLS");
}

- (void)testFileTypes {
  NSMutableArray *filePaths = [NSMutableArray array];
  NSMutableArray *expectedTypes = [NSMutableArray array];
  struct {
    NSString *fileName;
    NSString *fileExtension;
    NSString *expectedType;
  } fileMap[] = {
    { @"SampleMusic", @"mid", kHGSTypeFileMusic },
    { @"SampleMovie", @"mov", kHGSTypeFileMovie },
    { @"SampleImage", @"jpeg", kHGSTypeFileImage },
    { @"SamplePDF", @"pdf", kHGSTypeFile },
    { @"SampleContact", @"abcdp", kHGSTypeContact },
    { @"SampleWeb", @"webhistory", kHGSTypeWebHistory },
    { @"SampleCal", @"ics", kHGSTypeFile },
    { @"SampleText", @"txt", kHGSTypeTextFile },
    { @"SampleEmail", @"emlx", kHGSTypeEmail },
    { @"SampleBookmark", @"webloc", kHGSTypeWebBookmark }
  };
  NSBundle *bundle = HGSGetPluginBundle();
  for (size_t i = 0; i < sizeof(fileMap) / sizeof(fileMap[0]); ++i) {
    NSString *path = [bundle pathForResource:fileMap[i].fileName 
                                      ofType:fileMap[i].fileExtension];
    STAssertNotNil(path, @"Unable to find %@.%@", 
                   fileMap[i].fileName, 
                   fileMap[i].fileExtension);
    [filePaths addObject:path];
    [expectedTypes addObject:fileMap[i].expectedType];
  }
  NSString *finderPath 
    = [[NSWorkspace sharedWorkspace] 
       absolutePathForAppBundleWithIdentifier:@"com.apple.Finder"];
  STAssertNotNil(finderPath, nil);
  [filePaths addObject:finderPath];
  [expectedTypes addObject:kHGSTypeFileApplication];
  [filePaths addObject:@"/System"];
  [expectedTypes addObject:kHGSTypeDirectory];
  [filePaths addObject:@"/System/Library/Extensions.mkext"];
  [expectedTypes addObject:kHGSTypeFile];
  NSUInteger i = 0;
  for (NSString *path in filePaths) {
    HGSResult *result = [self spotlightResultForQuery:uniqueTestString_ path:path];
    STAssertNotNil(result, @"No result for %@", path);
    STAssertEqualObjects([result type], 
                         [expectedTypes objectAtIndex:i], 
                          @"Path: %@", path);
    ++i;
  }
}

@end

