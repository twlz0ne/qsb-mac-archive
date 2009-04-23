//
//  DeveloperDocumentationSource.m
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

#import <Vermilion/Vermilion.h>
#import "QSBHGSDelegate.h"

// Private interface that we've borrowed.
@interface DSADocSet : NSObject
- (id)initWithDocRootDirectory:(id)fp8;
@end

static NSString *const kDocSetFrameworkPath 
  = @"Library/PrivateFrameworks/DocSetAccess.framework";
static NSString *const kCoreReferenceDocSetPath
  = @"Documentation/DocSets/com.apple.ADC_Reference_Library.CoreReference.docset";
static NSString *const kiPhoneReferenceDocSetPath
  = @"Platforms/iPhoneOS.platform/Developer/Documentation/DocSets/"
    @"com.apple.adc.documentation.AppleiPhone2_2.iPhoneLibrary.docset";

@interface DeveloperDocumentationSource : HGSMemorySearchSource {
 @private
  NSCondition *condition_;
  BOOL indexed_;
  NSImage *docSetIcon_;
}
- (void)indexDocumentationOperation;
- (void)indexDocSetAtPath:(NSString *)docSetPath;
@end

@implementation DeveloperDocumentationSource

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    condition_ = [[NSCondition alloc] init];
    NSOperation *op 
      = [[[NSInvocationOperation alloc] initWithTarget:self
                                              selector:@selector(indexDocumentationOperation)
                                                object:nil]
       autorelease];
    [[HGSOperationQueue sharedOperationQueue] addOperation:op];
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    docSetIcon_ = [[ws iconForFileType:@"docset"] retain];
  }
  return self;
}

- (void)indexDocSetAtPath:(NSString *)docSetPath {
  
  if (!docSetPath) return;
  
  NSBundle *rootDirBundle = [NSBundle bundleWithPath:docSetPath];
  if (!rootDirBundle) {
    HGSLogDebug(@"Unable to get developer docs at path %@", docSetPath);
    return;
  }
  NSString *rootDirDocuments = [rootDirBundle resourcePath];
  rootDirDocuments 
    = [rootDirDocuments stringByAppendingPathComponent:@"Documents"];

  NSURL *docsURL = [NSURL fileURLWithPath:docSetPath isDirectory:YES];
  if (!docsURL) {
    HGSLogDebug(@"Unable to get developer docs URL");
    return;
  }
  NSURL *rootDirURL = [NSURL fileURLWithPath:rootDirDocuments isDirectory:YES];
  NSString *docSetName 
    = [rootDirBundle objectForInfoDictionaryKey:(NSString*)kCFBundleNameKey];
  NSDictionary *docSetCell = [NSDictionary dictionaryWithObjectsAndKeys:
                              docSetName, kQSBPathCellDisplayTitleKey,
                              docsURL, kQSBPathCellURLKey,
                              nil];
  Class dsaDocSetClass = NSClassFromString(@"DSADocSet");
  if (!dsaDocSetClass) {
    HGSLogDebug(@"Unable to get DSADocSet class");
    return;
  }
  
  // The next couple of operations allocate a lot of memory into autorelease
  // pools. We want that memory cleaned up as soon as possible, so we have
  // an autorelease pool outside the loop to clean up the array of nodes
  // and the filtered array, and an innerpool to clean up the processing
  // on the nodes themselves.
  NSAutoreleasePool *outerPool = [[NSAutoreleasePool alloc] init];
  id docSet 
    = [[[dsaDocSetClass alloc] performSelector:@selector(initWithDocRootDirectory:) 
                                    withObject:docsURL] 
       autorelease];
  
  NSArray *nodes 
    = [docSet valueForKeyPath: @"rootNode.searchableNodesInHierarchy"];
  NSPredicate *pred = [NSPredicate predicateWithFormat:@"domain == %d", 1];
  nodes = [nodes filteredArrayUsingPredicate:pred];  

  for (id node in nodes) {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    NSString *name = [node valueForKey:@"name"];
    NSString *path = [node valueForKey:@"path"];
    NSURL *url = nil;
    if (!path) {
      NSString *urlString = [node valueForKey:@"URL"];
      if (urlString) {
        url = [NSURL URLWithString:urlString];
      }
    } else {
      url = [[NSURL alloc] initWithString:path relativeToURL:rootDirURL];
    }
    if (url) {
      NSDictionary *docCell = [NSDictionary dictionaryWithObjectsAndKeys:
                               name, kQSBPathCellDisplayTitleKey,
                               url, kQSBPathCellURLKey,
                               nil];
      NSArray *docCells = [NSArray arrayWithObjects:docSetCell, docCell, nil];
      NSDictionary *attributes
        = [NSDictionary dictionaryWithObjectsAndKeys:
           docCells, kQSBObjectAttributePathCellsKey, 
           docSetIcon_, kHGSObjectAttributeIconKey,
           nil];
      HGSResult *result 
        = [HGSResult resultWithURL:url
                              name:name
                              type:HGS_SUBTYPE(kHGSTypeFile, @"developerdocs")
                            source:self
                        attributes:attributes];  
      [self indexResult:result];
    }
    [innerPool release];
  }
  [outerPool release];
}

- (void)indexDocumentationOperation {
  [condition_ lock];
  [self clearResultIndex];
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSString *xcodePath = [ws fullPathForApplication:@"Xcode"];
  if (xcodePath) {
    NSString *devAppPath = [xcodePath stringByDeletingLastPathComponent];
    NSString *developerPath = [devAppPath stringByDeletingLastPathComponent];
    Class dsaDocSetClass = NSClassFromString(@"DSADocSet");
    if (!dsaDocSetClass) {
      NSString *frameworkPath 
        = [developerPath stringByAppendingPathComponent:kDocSetFrameworkPath];
      [[NSBundle bundleWithPath:frameworkPath] load];
      HGSAssert(NSClassFromString(@"DSADocSet"), 
                @"Unable to instantiate DSADocSet");
    }
    
    // TODO(dmaclach): add support for other docsets
    // TODO(dmaclach): badge iPhone doc sets differently than OS X docsets.
    NSString *coreReference 
      = [developerPath stringByAppendingPathComponent:kCoreReferenceDocSetPath];
    NSString *iPhoneReference 
      = [developerPath stringByAppendingPathComponent:kiPhoneReferenceDocSetPath];
    [self indexDocSetAtPath:coreReference];
    [self indexDocSetAtPath:iPhoneReference];
  }
  indexed_ = YES;
  [condition_ signal];
  [condition_ unlock];
}

- (void)dealloc {
  [docSetIcon_ release];
  [condition_ release];
  [super dealloc];
}

#pragma mark -

- (void)performSearchOperation:(HGSSearchOperation *)operation {
  HGSQuery *query = [operation query];
  NSString *queryString = [query rawQueryString];
  if ([queryString length] < 4) return;
  
  // make sure we're done any parsing
  [condition_ lock];
  while (!indexed_) {
    [condition_ wait];
  }
  [condition_ signal];
  [condition_ unlock];
  
  [super performSearchOperation:operation];
}

@end
