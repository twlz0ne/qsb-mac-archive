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
    docSetIcon_ 
      = [[[NSWorkspace sharedWorkspace] iconForFileType:@"docset"] copy];
    [docSetIcon_ setSize:NSMakeSize(128, 128)];
  }
  return self;
}

- (void)indexDocSetAtPath:(NSString *)docSetPath {
  
  if (!docSetPath) return;
  
  NSBundle *rootDirBundle = [NSBundle bundleWithPath:docSetPath];
  if (!rootDirBundle) {
    HGSLogDebug(@"Unable to get developer docs");
    return;
  }
  NSString *rootDirDocuments = [rootDirBundle resourcePath];
  rootDirDocuments 
    = [rootDirDocuments stringByAppendingPathComponent:@"Documents"];
  NSURL *docsURL = [NSURL fileURLWithPath:docSetPath];
  if (!docsURL) {
    HGSLogDebug(@"Unable to get developer docs URL");
    return;
  }
  NSString *docSetName 
    = [rootDirBundle objectForInfoDictionaryKey:(NSString*)kCFBundleNameKey];
  NSDictionary *docSetCell = [NSDictionary dictionaryWithObjectsAndKeys:
                              docSetName, kHGSPathCellDisplayTitleKey,
                              docsURL, kHGSPathCellURLKey,
                              nil];
  Class dsaDocSetClass = NSClassFromString(@"DSADocSet");
  if (!dsaDocSetClass) {
    HGSLogDebug(@"Unable to get DSADocSet class");
    return;
  }

  id docSet 
    = [[[dsaDocSetClass alloc] performSelector:@selector(initWithDocRootDirectory:) 
                                    withObject:docsURL] 
       autorelease];
  
  NSArray *nodes 
    = [docSet valueForKeyPath: @"rootNode.searchableNodesInHierarchy"];
  NSPredicate *pred = [NSPredicate predicateWithFormat:@"domain == %d", 1];
  nodes = [nodes filteredArrayUsingPredicate:pred];  

  for (id node in nodes) {
    NSString *name = [node valueForKey:@"name"];
    NSString *path = [node valueForKey:@"path"];
    NSURL *url = nil;
    if (!path) {
      NSString *urlString = [node valueForKey:@"URL"];
      if (urlString) {
        url = [NSURL URLWithString:urlString];
      }
    } else {
      path = [rootDirDocuments stringByAppendingPathComponent:path];
      url = [NSURL fileURLWithPath:path];
    }
    if (!url) continue;
    NSDictionary *docCell = [NSDictionary dictionaryWithObjectsAndKeys:
                             name, kHGSPathCellDisplayTitleKey,
                             url, kHGSPathCellURLKey,
                             nil];
    NSArray *docCells = [NSArray arrayWithObjects:docSetCell, docCell, nil];
    NSDictionary *attributes
      = [NSDictionary dictionaryWithObjectsAndKeys:
         docCells, kHGSObjectAttributePathCellsKey, 
         docSetIcon_, kHGSObjectAttributeIconKey,
         nil];
    HGSObject *result 
      = [HGSObject objectWithIdentifier:url
                                   name:name
                                   type:HGS_SUBTYPE(kHGSTypeFile, @"developerdocs")
                                 source:self
                             attributes:attributes];  
    [self indexResult:result
           nameString:name
          otherString:nil];
  }
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
      dsaDocSetClass = NSClassFromString(@"DSADocSet");
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
