//
//  GoogleCorporaSource.m
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

#import "GoogleCorporaSource.h"
#import "GTMMethodCheck.h"
#import "NSString+ReadableURL.h"
#import <Vermilion/Vermilion.h>

static NSString *const kHGSCorporaSourceAttributeIconNameKey 
  = @"kHGSCorporaSourceAttributeIconNameKey";  // NSString
static NSString *const kHGSCorporaSourceAttributeHideCorpusKey
  = @"kHGSCorporaSourceAttributeHideCorpus";  // BOOL
static NSString *const kHGSCorporaSourceAttributeHideFromDesktopKey
  = @"kHGSCorporaSourceAttributeHideFromDesktop";  // BOOL
static NSString *const kHGSCorporaSourceAttributeURIStringKey
  = @"kHGSCorporaSourceAttributeURIString";  //NSString

@interface GoogleCorporaSource ()
- (BOOL)loadCorpora;
@end

@implementation GoogleCorporaSource

GTM_METHOD_CHECK(NSString, readableURLString);

- (id)init {
  self = [self initWithConfiguration:nil];
  return self;
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super initWithConfiguration:configuration])) {
    if (![self loadCorpora]) {
      HGSLogDebug(@"Unable to load corpora");
      [self release];
      self = nil;
    }
  }
  return self;
}

- (void)dealloc {
  [searchableCorpora_ release];
  [visibleCorpora_ release];
  [super dealloc];
}

- (NSArray *)groupedSearchableCorpora {
    return searchableCorpora_;
}

- (NSArray *)dasherDomains {
  HGSAccountsExtensionPoint *aep
    = [HGSAccountsExtensionPoint accountsExtensionPoint];
  NSEnumerator *accountEnum
    = [aep accountsEnumForType:@"Google"];
  NSMutableArray *domains = [NSMutableArray array];
  for (id<HGSAccount> account in accountEnum) {
    NSString *name = [account accountName];
    NSInteger location = [name rangeOfString:@"@"].location;
    if (location != NSNotFound) {
      NSString *domain = [name substringFromIndex:location + 1]; 
      if (![domain isEqualToString:@"gmail.com"]) {
        [domains addObject:domain];
      }
    }
  }
  return domains;
}

- (HGSObject *)corpusObjectForDictionary:(NSDictionary *)corpusDict 
                                inDomain:(NSString *)domain {
  if ([corpusDict objectForKey:kHGSCorporaSourceAttributeHideCorpusKey]) {
    return nil;
  }
#if !TARGET_OS_IPHONE
  if ([corpusDict objectForKey:kHGSCorporaSourceAttributeHideFromDesktopKey]) {
    return nil;
  }
#endif
  
  NSMutableDictionary *objectDict 
    = [NSMutableDictionary dictionaryWithDictionary:corpusDict];
  NSString *identifier = [corpusDict objectForKey:kHGSCorporaSourceAttributeURIStringKey];
  
  // Dasherize the URL and the web search template
  identifier = [NSString stringWithFormat:identifier, domain];
  [objectDict setObject:identifier
                 forKey:kHGSObjectAttributeURIKey];
  
  NSString *name = [objectDict objectForKey:kHGSObjectAttributeNameKey];
  [objectDict setObject:[NSString stringWithFormat:name, domain]
                 forKey:kHGSObjectAttributeNameKey];
  
  
  NSString *webTemplate = [objectDict objectForKey:kHGSObjectAttributeWebSearchTemplateKey];
  if (webTemplate) {
    [objectDict setObject:[NSString stringWithFormat:webTemplate, domain]
                                  forKey:kHGSObjectAttributeWebSearchTemplateKey];
  }
  
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSLaunchableRankFlag
                                                       | eHGSNameMatchRankFlag];  
  [objectDict setObject:rankFlags forKey:kHGSObjectAttributeRankFlagsKey];
  [objectDict setObject:[NSNumber numberWithFloat:0.9f]
                 forKey:kHGSObjectAttributeRankKey];
  
  NSString *details = identifier;
  if (details) {
    [objectDict setObject:details
                   forKey:kHGSObjectAttributeSourceURLKey];
  } else {
    HGSLog(@"Unable to get readable URL for %@ from corpora %@", 
           identifier, corpusDict);
  }  
  
  [objectDict setObject:kHGSTypeWebApplication
                 forKey:kHGSObjectAttributeTypeKey];
  
  NSString *iconName 
    = [objectDict objectForKey:kHGSCorporaSourceAttributeIconNameKey];
  if (iconName) {
#if TARGET_OS_IPHONE
    // For mobile, we must append .png
    iconName = [iconName stringByAppendingPathExtension:@"png"];
#endif
    NSImage *icon = [NSImage imageNamed:iconName];
    if (icon) {
      icon = [[icon copy] autorelease];
      [objectDict setObject:icon forKey:kHGSObjectAttributeIconKey];
    } else {
      HGSLog(@"Unable to load an icon for corpus %@", corpusDict);
    }
    [objectDict removeObjectForKey:kHGSCorporaSourceAttributeIconNameKey];
  }
  HGSObject *corpus = [HGSObject objectWithDictionary:objectDict
                                              source:self];
  return corpus;  
}


- (BOOL)loadCorpora {
  // TODO(dmaclach): mumble
  // TODO(mrossetti): mumble
  //  -- If/When we get support for config info in the module registration, it
  // might make sense for the DefaultCorp info to go into the normal module
  // registation make config it's own source instead of having this one source
  // cycle through them.  That would also allow those individual configs to be
  // enabled/disabled.

  // Initialization code
  NSMutableArray *allCorpora = [NSMutableArray array];
  NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"DefaultCorpora"
                                                        ofType:@"plist"];
  NSArray *corporaPlist = [NSArray arrayWithContentsOfFile:plistPath];
  
  for (NSDictionary *corpusDict in corporaPlist) {
    HGSObject *corpus = [self corpusObjectForDictionary:corpusDict
                                               inDomain:nil];
    if (corpus) [allCorpora addObject:corpus];
  }
  
  plistPath = [[NSBundle mainBundle] pathForResource:@"DasherCorpora"
                                              ofType:@"plist"];
  corporaPlist = [NSArray arrayWithContentsOfFile:plistPath];
  
  
  for (NSString *domain in [self dasherDomains]) {
    for (NSDictionary *corpusDict in corporaPlist) {
      HGSObject *corpus = [self corpusObjectForDictionary:corpusDict 
                                                 inDomain:domain];
      if (corpus) [allCorpora addObject:corpus];
    }
  }
  
  plistPath = [[NSBundle mainBundle] pathForResource:@"InternalCorpora"
                                              ofType:@"plist"];
  corporaPlist = [NSArray arrayWithContentsOfFile:plistPath];
  
  for (NSDictionary *corpusDict in corporaPlist) {
    HGSObject *corpus = [self corpusObjectForDictionary:corpusDict
                                               inDomain:nil];
    if (corpus) [allCorpora addObject:corpus];
  }  
  
  NSMutableArray *visibleCorpora = [NSMutableArray array];
  NSMutableArray *searchableCorpora = [NSMutableArray array];
  
  for (HGSObject *corpus in allCorpora) {
    if ([corpus valueForKey:kHGSObjectAttributeWebSearchTemplateKey]
    && ![[corpus valueForKey:@"kHGSObjectAttributeHideFromDropdown"] boolValue]) {
      [searchableCorpora addObject:corpus];
    }
    if (![[corpus valueForKey:@"kHGSObjectAttributeHideFromResults"] boolValue]) {
      [visibleCorpora addObject:corpus];
    } 
  }
  
  visibleCorpora_ = [visibleCorpora retain];
  searchableCorpora_ = [searchableCorpora retain];
 
  [self clearResultIndex];
  
  for (HGSObject *corpus in visibleCorpora_) {
    [self indexResult:corpus
           nameString:[corpus displayName]
          otherString:nil];
  }
  
  return YES;
}

- (NSMutableDictionary *)archiveRepresentationForObject:(HGSObject*)result {
  return [NSMutableDictionary
            dictionaryWithObject:[result valueForKey:kHGSObjectAttributeURIKey]
                          forKey:kHGSObjectAttributeURIKey];
}

- (HGSObject *)objectWithArchivedRepresentation:(NSDictionary *)representation {
  NSString *identifier = [representation objectForKey:kHGSObjectAttributeURIKey];
  for (HGSObject *corpus in searchableCorpora_) {
    NSURL *url = [corpus valueForKey:kHGSObjectAttributeURIKey];
    if ([url isEqual:identifier])
      return corpus;
  }
  
  return nil;
}

@end
