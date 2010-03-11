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
#import "HGSGoogleAccountTypes.h"
#import <Vermilion/Vermilion.h>

static NSString *const kHGSCorporaSourceAttributeIconNameKey 
  = @"HGSCorporaSourceAttributeIconName";  // NSString
static NSString *const kHGSCorporaSourceAttributeHideCorpusKey
  = @"HGSCorporaSourceAttributeHideCorpus";  // BOOL
static NSString *const kHGSCorporaSourceAttributeHideFromDesktopKey
  = @"HGSCorporaSourceAttributeHideFromDesktop";  // BOOL
static NSString *const kHGSCorporaSourceAttributeURIStringKey
  = @"HGSCorporaSourceAttributeURIString";  //NSString
static NSString *const kHGSObjectAttributeHideFromDropdownKey
  = @"HGSObjectAttributeHideFromDropdown";  // BOOL
static NSString *const kHGSObjectAttributeHideFromResultsKey
  = @"HGSObjectAttributeHideFromResults";   // BOOL

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
    HGSExtensionPoint *accountsPoint = [HGSExtensionPoint accountsPoint];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self 
           selector:@selector(didAddOrRemoveAccount:) 
               name:kHGSExtensionPointDidAddExtensionNotification 
             object:accountsPoint];
    [nc addObserver:self 
           selector:@selector(didAddOrRemoveAccount:) 
               name:kHGSExtensionPointDidRemoveExtensionNotification 
             object:accountsPoint];
  }
  return self;
}

- (void)dealloc {
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  [nc removeObserver:self];
  [searchableCorpora_ release];
  [visibleCorpora_ release];
  [super dealloc];
}

- (NSArray *)groupedSearchableCorpora {
    return searchableCorpora_;
}

- (NSArray *)dasherDomains {
  HGSAccountsExtensionPoint *accountsPoint = [HGSExtensionPoint accountsPoint];
  NSArray *googleAppsAccounts
    = [accountsPoint accountsForType:kHGSGoogleAppsAccountType];
  NSMutableArray *domains = [NSMutableArray array];
  for (HGSAccount *account in googleAppsAccounts) {
    NSString *name = [account userName];
    NSInteger location = [name rangeOfString:@"@"].location;
    if (location != NSNotFound) {
      NSString *domain = [name substringFromIndex:location + 1]; 
      [domains addObject:domain];
    }
  }
  return domains;
}

- (HGSResult *)corpusObjectForDictionary:(NSDictionary *)corpusDict 
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
  NSString *identifier 
    = [corpusDict objectForKey:kHGSCorporaSourceAttributeURIStringKey];
  
  // Dasherize the URL and the web search template
  identifier = [NSString stringWithFormat:identifier, domain];
  [objectDict setObject:identifier
                 forKey:kHGSObjectAttributeURIKey];
  
  NSString *name = [objectDict objectForKey:kHGSObjectAttributeNameKey];
  NSBundle *bundle = [NSBundle bundleForClass:[self class]];
  NSString *localizedName = [bundle localizedStringForKey:name 
                                                    value:nil 
                                                    table:nil];
  [objectDict setObject:[NSString stringWithFormat:localizedName, domain]
                 forKey:kHGSObjectAttributeNameKey];
  
  
  NSString *webTemplate 
    = [objectDict objectForKey:kHGSObjectAttributeWebSearchTemplateKey];
  if (webTemplate) {
    [objectDict setObject:[NSString stringWithFormat:webTemplate, domain]
                   forKey:kHGSObjectAttributeWebSearchTemplateKey];
  }
  
  NSNumber *rankFlags = [NSNumber numberWithUnsignedInt:eHGSLaunchableRankFlag];  
  [objectDict setObject:rankFlags forKey:kHGSObjectAttributeRankFlagsKey];
  
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
  HGSUnscoredResult *corpus = [HGSUnscoredResult resultWithDictionary:objectDict
                                                               source:self];
  return corpus;  
}


- (BOOL)loadCorpora {
  // TODO(dmaclach): mumble
  // TODO(mrossetti): mumble
  //  -- If/When we get support for config info in the plugin registration, it
  // might make sense for the DefaultCorp info to go into the normal plugin
  // registation make config it's own source instead of having this one source
  // cycle through them.  That would also allow those individual configs to be
  // enabled/disabled.

  // Initialization code
  NSMutableArray *allCorpora = [NSMutableArray array];
  NSBundle *pluginBundle = [self bundle];
  NSString *plistPath = [pluginBundle pathForResource:@"DefaultCorpora"
                                               ofType:@"plist"];
  NSArray *corporaPlist = [NSArray arrayWithContentsOfFile:plistPath];
  
  for (NSDictionary *corpusDict in corporaPlist) {
    HGSResult *corpus = [self corpusObjectForDictionary:corpusDict
                                               inDomain:nil];
    if (corpus) [allCorpora addObject:corpus];
  }
  
  plistPath = [pluginBundle pathForResource:@"DasherCorpora"
                                     ofType:@"plist"];
  corporaPlist = [NSArray arrayWithContentsOfFile:plistPath];
  
  
  for (NSString *domain in [self dasherDomains]) {
    for (NSDictionary *corpusDict in corporaPlist) {
      HGSResult *corpus = [self corpusObjectForDictionary:corpusDict 
                                                 inDomain:domain];
      if (corpus) [allCorpora addObject:corpus];
    }
  }
  
  plistPath = [pluginBundle pathForResource:@"InternalCorpora"
                                     ofType:@"plist"];
  corporaPlist = [NSArray arrayWithContentsOfFile:plistPath];
  
  for (NSDictionary *corpusDict in corporaPlist) {
    HGSResult *corpus = [self corpusObjectForDictionary:corpusDict
                                               inDomain:nil];
    if (corpus) [allCorpora addObject:corpus];
  }  
  
  NSMutableArray *visibleCorpora = [NSMutableArray array];
  NSMutableArray *searchableCorpora = [NSMutableArray array];
  
  for (HGSResult *corpus in allCorpora) {
    if ([corpus valueForKey:kHGSObjectAttributeWebSearchTemplateKey]
    && ![[corpus valueForKey:kHGSObjectAttributeHideFromDropdownKey] boolValue]) {
      [searchableCorpora addObject:corpus];
    }
    if (![[corpus valueForKey:kHGSObjectAttributeHideFromResultsKey] boolValue]) {
      [visibleCorpora addObject:corpus];
    } 
  }
  
  visibleCorpora_ = [visibleCorpora retain];
  searchableCorpora_ = [searchableCorpora retain];
 
  [self clearResultIndex];
  
  for (HGSResult *corpus in visibleCorpora_) {
    [self indexResult:corpus];
  }
  
  return YES;
}

- (NSMutableDictionary *)archiveRepresentationForResult:(HGSResult *)result {
  return [NSMutableDictionary
            dictionaryWithObject:[result uri]
                          forKey:kHGSObjectAttributeURIKey];
}

- (HGSResult *)resultWithArchivedRepresentation:(NSDictionary *)representation {
  HGSResult *result = nil;
  NSString *identifier = [representation objectForKey:kHGSObjectAttributeURIKey];
  NSArray *totalCorpora 
    = [searchableCorpora_ arrayByAddingObjectsFromArray:visibleCorpora_];
  for (HGSResult *corpus in totalCorpora) {
    NSString *uri = [corpus uri];
    if ([uri isEqual:identifier]) {
      result = corpus;
      break;
    }
  }
  return result;
}

- (void)didAddOrRemoveAccount:(NSNotification *)notification {
  NSDictionary *userInfo = [notification userInfo];
  HGSAccount *account = [userInfo objectForKey:kHGSExtensionKey];
  NSString *accountType = [account type];
  if ([accountType isEqualToString:kHGSGoogleAppsAccountType]) {
    [self loadCorpora];
  }
}

@end
