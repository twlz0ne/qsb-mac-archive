//
//  QSBSearchResult.m
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

#import "QSBTableResult.h"
#import <Vermilion/Vermilion.h>
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "NSAttributedString+Attributes.h"
#import "GTMNSString+HTML.h"
#import "QSBQueryController.h"
#import "QSBMoreResultsViewDelegate.h"
#import "NSString+ReadableURL.h"
#import "QSBTopResultsViewControllers.h"
#import "QSBMoreResultsViewControllers.h"
#import "GTMNSObject+KeyValueObserving.h"
#import "GTMMethodCheck.h"

typedef enum {
  kQSBResultDescriptionTitle = 0,
  kQSBResultDescriptionSnippet,
  kQSBResultDescriptionSourceURL
} QSBResultDescriptionItemType;

@interface QSBTableResult ()

- (void)addAttributes:(NSMutableAttributedString*)string
          elementType:(QSBResultDescriptionItemType)itemType;

- (NSMutableAttributedString *)mutableAttributedStringWithString:(NSString*)string;

- (NSMutableAttributedString *)mutableAttributedStringFromHTMLString:(NSString*)item 
                                                     prettyPrintPath:(BOOL)prettyPrintPath;

- (NSMutableAttributedString *)mutableAttributedStringFromHTMLString:(NSString*)item;

- (NSMutableAttributedString *)mutableAttributedStringFromHTMLPath:(NSString*)item;

// TODO(mrossetti): Some of the mocks show the partial match string as being
// bolded or otherwise highlighted.  Investigate and implement as appropriate.

// Return a mutable string containin the title to be presented for a result.
- (NSMutableAttributedString*)genericTitleLine;

// Return a string containing the snippet, if any, to be presented for a result,
// otherwise return nil.
- (NSAttributedString*)snippetString;

// Return a string containing the sourceURL/URL, if any, to be presented for a
// result, otherwise return nil.
- (NSAttributedString*)sourceURLString;
@end


@interface NSString(QSBDisplayPathAdditions)
// Converts a path to a pretty, localized, arrow separated version
// Returns autoreleased string with beautified path
- (NSString*)qsb_displayPath;
@end


@implementation QSBTableResult

GTM_METHOD_CHECK(NSMutableAttributedString, addAttribute:value:);
GTM_METHOD_CHECK(NSMutableAttributedString, addAttributes:);
GTM_METHOD_CHECK(NSMutableAttributedString, 
                 addAttributes:fontTraits:toTextDelimitedBy:postDelimiter:);
GTM_METHOD_CHECK(NSString, qsb_displayPath);
GTM_METHOD_CHECK(NSString, gtm_stringByUnescapingFromHTML);
GTM_METHOD_CHECK(NSObject, gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);

static NSDictionary *gBaseStringAttributes_ = nil;

+ (void)initialize {
  if (self == [QSBTableResult class]) {
    NSMutableParagraphStyle *style 
    = [[[NSMutableParagraphStyle alloc] init] autorelease];
    [style setLineBreakMode:NSLineBreakByTruncatingTail];
    [style setParagraphSpacing:0];
    [style setParagraphSpacingBefore:0];
    [style setLineSpacing:0];
    [style setMaximumLineHeight:14.0];
    
    gBaseStringAttributes_ 
    = [NSDictionary dictionaryWithObject:style
                                  forKey:NSParagraphStyleAttributeName];
    [gBaseStringAttributes_ retain];
  }
}

- (BOOL)isPivotable {
  return NO;
}

- (NSAttributedString *)titleSnippetSourceURLString {
  NSMutableAttributedString *fullString 
    = [[[self titleSnippetString] mutableCopy] autorelease];
  NSAttributedString *sourceURLString = [self sourceURLString];
  if (sourceURLString) {
    [fullString appendAttributedString:[[[NSAttributedString alloc]
                                         initWithString:@"\n"] autorelease]];
    [fullString appendAttributedString:sourceURLString];
  }
  return fullString;
}

- (NSAttributedString *)titleSnippetString {
  NSMutableAttributedString *resultString = [self genericTitleLine];
  [self addAttributes:resultString elementType:kQSBResultDescriptionTitle];
  NSAttributedString *resultSnippet = [self snippetString];
  if (resultSnippet) {
    [resultString appendAttributedString:[[[NSAttributedString alloc]
                                           initWithString:@"\n"] autorelease]];
    [resultString appendAttributedString:resultSnippet];
  }
  return resultString;
}

- (NSAttributedString *)titleSourceURLString {
  NSMutableAttributedString *resultString = [self genericTitleLine];
  [self addAttributes:resultString elementType:kQSBResultDescriptionTitle];
  NSAttributedString *resultSourceURL = [self sourceURLString];
  if (resultSourceURL) {
    [resultString appendAttributedString:[[[NSAttributedString alloc]
                                           initWithString:@"\n"] autorelease]];
    [resultString appendAttributedString:resultSourceURL];
  }
  return resultString;
}

- (CGFloat)rank {
  return -1.0;
}

- (Class)topResultsRowViewControllerClass {
  HGSLogDebug(@"Need to handle [%@ %s] result %@.", [self class], _cmd, self);
  return nil;
}

- (Class)moreResultsRowViewControllerClass {
  HGSLogDebug(@"Need to handle [%@ %s] result %@.", [self class], _cmd, self);
  return nil;
}

- (BOOL)performDefaultActionWithQueryController:(QSBQueryController*)controller {
  return NO;
}

- (NSString *)displayName {
  return nil;
}

- (NSString *)displayPath {
  return nil;
}

- (void)addAttributes:(NSMutableAttributedString*)string
          elementType:(QSBResultDescriptionItemType)itemType {
  // Note: nothing should be done here that changes the string metrics,
  // since computations may already have been done based on string sizes.
  [string addAttributes:gBaseStringAttributes_];
  if (itemType == kQSBResultDescriptionSnippet) {
    [string addAttribute:NSForegroundColorAttributeName 
                   value:[NSColor grayColor]];
  } else if (itemType == kQSBResultDescriptionSourceURL) {
    [string addAttribute:NSForegroundColorAttributeName 
                   value:[NSColor colorWithCalibratedRed:0.609375  // 0x9C
                                                   green:0.671875  // 0xAC
                                                    blue:0.527344  // 0x87
                                                   alpha:1.0]];
  } else if (itemType == kQSBResultDescriptionTitle) {
    [string addAttribute:NSForegroundColorAttributeName 
                   value:[NSColor blackColor]];
  } else {
    HGSLogDebug(@"Unknown itemType: %d", itemType);
  }
}

- (NSMutableAttributedString*)mutableAttributedStringWithString:(NSString*)string {
  CGFloat startingSize = 12.0;
  const CGFloat maxLineHeight = 200;
  NSDictionary *attributes = nil;
  NSMutableAttributedString *attrString = nil;
  NSRect bounds;
  NSStringDrawingOptions options = (NSStringDrawingUsesLineFragmentOrigin 
                                    | NSStringDrawingUsesFontLeading);
  do {
    // For some fonts (like Devangari) we have to shrink down a bit. We try to
    // do the minimum shrinkage needed to fit under 14 points. The smallest we
    // will shrink to is 8 points. It may look ugly but at least it still should
    // be readable at 8 points. Anything smaller than that is unreadable.
    // http://b/issue?id=661705
    NSFont *font = [NSFont menuFontOfSize:startingSize];
    attributes = [NSDictionary dictionaryWithObject:font
                                             forKey:NSFontAttributeName];
    attrString = [NSMutableAttributedString attrStringWithString:string
                                                      attributes:attributes];
    bounds = [attrString boundingRectWithSize:[attrString size]
                                      options:options];
    startingSize -= 1.0;
  } while (bounds.size.height > maxLineHeight && startingSize >= 8.0);
  return attrString;
}

- (NSMutableAttributedString *)mutableAttributedStringFromHTMLString:(NSString*)item 
                                                     prettyPrintPath:(BOOL)prettyPrintPath {
  NSMutableString *mutableItem = [NSMutableString stringWithString:item];
  
  NSString* boldPrefix = @"%QSB_MAC_BOLD_PREFIX%";
  NSString* boldSuffix = @"%QSB_MAC_BOLD_SUFFIX%";
  [mutableItem replaceOccurrencesOfString:@"<b>" 
                               withString:boldPrefix 
                                  options:NSCaseInsensitiveSearch 
                                    range:NSMakeRange(0, [mutableItem length])];
  [mutableItem replaceOccurrencesOfString:@"</b>" 
                               withString:boldSuffix 
                                  options:NSCaseInsensitiveSearch 
                                    range:NSMakeRange(0, [mutableItem length])];
  if (prettyPrintPath) {
    mutableItem = [[[mutableItem qsb_displayPath] mutableCopy] autorelease];
  }
  NSString *unescapedItem = [mutableItem gtm_stringByUnescapingFromHTML];
  NSMutableAttributedString* mutableAttributedItem =
  [self mutableAttributedStringWithString:unescapedItem];
  [mutableAttributedItem addAttributes:nil 
                            fontTraits:NSBoldFontMask 
                     toTextDelimitedBy:boldPrefix 
                         postDelimiter:boldSuffix];
  return mutableAttributedItem;
}

- (NSMutableAttributedString *)mutableAttributedStringFromHTMLString:(NSString*)item {
  return [self mutableAttributedStringFromHTMLString:item prettyPrintPath:NO];
}

- (NSMutableAttributedString *)mutableAttributedStringFromHTMLPath:(NSString*)item {
  return [self mutableAttributedStringFromHTMLString:item prettyPrintPath:YES];
}

- (NSMutableAttributedString*)genericTitleLine {
  return nil;
}

- (NSAttributedString*)snippetString {
  return nil;
}

- (NSAttributedString*)sourceURLString {
  return nil;
}

- (NSImage *)displayIcon {
  return nil;
}

- (NSImage *)displayThumbnail {
  return nil;
}
@end


@implementation QSBSourceTableResult : QSBTableResult

GTM_METHOD_CHECK(NSObject, gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);

@synthesize representedObject = representedObject_;
@synthesize categoryName = categoryName_;

+ (id)resultWithObject:(HGSObject *)object {
  return [[[[self class] alloc] initWithObject:object] autorelease];
}

- (id)initWithObject:(HGSObject *)object {
  if ((self = [super init])) {
    representedObject_ = [object retain];
    [representedObject_ gtm_addObserver:self
                             forKeyPath:kHGSObjectAttributeIconKey
                               selector:@selector(objectIconChanged:)
                               userInfo:nil
                                options:0];
  }
  return self;
}

- (void)objectIconChanged:(GTMKeyValueChangeNotification *)notification {
  [self willChangeValueForKey:@"displayIcon"];
  [self didChangeValueForKey:@"displayIcon"]; 
  [self willChangeValueForKey:@"displayThumbnail"];
  [self didChangeValueForKey:@"displayThumbnail"];
}

- (void)dealloc {
  [representedObject_ gtm_removeObserver:self 
                              forKeyPath:kHGSObjectAttributeIconKey
                                selector:@selector(objectIconChanged:)];
  [representedObject_ release];
  [super dealloc];
}

- (BOOL)isPivotable {
  // We want to pivot on non-suggestions, non-qsb stuff, and non-actions.
  HGSObject *object = [self representedObject];
  BOOL pivotable = YES;
  if ([object conformsToType:kHGSTypeGoogleSuggest]) pivotable = NO;
  if ([object conformsToType:kHGSTypeAction]) pivotable = NO;
  return pivotable;
}

- (void)addAttributes:(NSMutableAttributedString*)string
          elementType:(QSBResultDescriptionItemType)itemType {
  [super addAttributes:string elementType:itemType];
  if (itemType == kQSBResultDescriptionTitle) {
    HGSObject *object = [self representedObject];
    if ([object conformsToType:kHGSTypeAction]) {
      [string addAttribute:NSForegroundColorAttributeName
                     value:[NSColor colorWithCalibratedRed:0.667
                                                     green:0.0 
                                                      blue:0.0 
                                                     alpha:1.0]];
      [string addAttribute:NSObliquenessAttributeName
                     value:[NSNumber numberWithFloat:0.1f]];
    }
  }
}

- (CGFloat)rank {
  return [[self representedObject] rank];
}

- (Class)topResultsRowViewControllerClass {
  Class rowViewClass = Nil;
  HGSObject *result = [self representedObject];
  if ([result conformsToType:kHGSTypeSuggest]) {
    rowViewClass = [QSBTopStandardRowViewController class];
  } else if ([result isKindOfClass:[HGSObject class]]) {
    rowViewClass = [QSBTopStandardRowViewController class];
  }
  return rowViewClass;
}

- (Class)moreResultsRowViewControllerClass {
  Class rowViewClass = Nil;
  HGSObject *result = [self representedObject];
  if (!([result conformsToType:kHGSTypeSuggest]
        || [result conformsToType:kHGSTypeSearch])) {
    if ([self categoryName]) {
      rowViewClass = [QSBMoreCategoryRowViewController class];
    } else {
      rowViewClass = [QSBMoreStandardRowViewController class];
    }
  } else {
    rowViewClass = [QSBMorePlaceHolderRowViewController class];
  }
  return rowViewClass;
}

- (BOOL)performDefaultActionWithQueryController:(QSBQueryController*)controller {
  HGSObject *result = [self representedObject];
  id<HGSAction> action
    = [result valueForKey:kHGSObjectAttributeDefaultActionKey];
  if (action) {
    [controller performAction:action forObject:result];
  } else {
    HGSLog(@"Unable to get default action for %@", result);
  }
  return YES;
}

- (NSString *)displayPath {
  HGSObject *result = [self representedObject];
  return [result displayPath];
}

- (NSString *)displayName {
  HGSObject *result = [self representedObject];
  return [result displayName];
}

- (NSImage *)displayIcon {
  HGSObject *result = [self representedObject];
  return [result displayIconWithLazyLoad:YES];
}

- (NSString*)displayToolTip {
  // TODO(alcor): for now add in rank info to help with debugging. remove.
  return [NSString stringWithFormat:@"%@ (Rank: %.2f, %d)", 
                                    [self displayName],
                                    [self rank],
                                    [[self representedObject] rankFlags]];
}

- (NSImage *)displayThumbnail {
  HGSObject *result = [self representedObject];
  return [result displayIconWithLazyLoad:NO];
}

- (NSMutableAttributedString*)genericTitleLine {
  // Title is rendered as 12 pt black.
  HGSObject *result = [self representedObject];
  NSString *html = [result valueForKey:kHGSObjectAttributeNameKey];
  NSMutableAttributedString *title 
    = [self mutableAttributedStringWithString:html];
  if (!title) {
    // If we don't have a title, we'll just use a canned string
    NSString *titleString = NSLocalizedString(@"<No Title>", @"");
    title =  [self mutableAttributedStringWithString:titleString];
  }
  
  return title;
}

- (NSAttributedString*)snippetString {
  // Snippet is rendered as 12 pt gray (50% black).
  NSMutableAttributedString *snippetString = nil;
  HGSObject *result = [self representedObject];
  NSString *snippet = [result valueForKey:kHGSObjectAttributeSnippetKey];
  if (snippet) {
    snippetString = [self mutableAttributedStringFromHTMLString:snippet];
    [self addAttributes:snippetString elementType:kQSBResultDescriptionSnippet];
  }
  return snippetString;
}

- (NSAttributedString*)sourceURLString {
  // SourceURL is rendered as 12 pt with a color of 0x9CAC87.
  NSMutableAttributedString *sourceURLString = nil;
  HGSObject *result = [self representedObject];
  NSString *sourceURL = [result valueForKey:kHGSObjectAttributeSourceURLKey];
  
  sourceURL = [sourceURL readableURLString];
  if (sourceURL) {
    sourceURLString = [self mutableAttributedStringFromHTMLString:sourceURL];
    [self addAttributes:sourceURLString elementType:kQSBResultDescriptionSourceURL];
  }
  return sourceURLString;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@: %p - %@", 
          [self class], self, representedObject_];
}
@end
 

@implementation QSBGoogleTableResult

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

+ (id)resultForQuery:(NSString*)query {
  return [[[[self class] alloc] initWithQuery:query] autorelease];
}

- (id)init {
  [NSException raise:NSIllegalSelectorException format:@"Call initWithQuery"];
  return nil;
}

- (id)initWithQuery:(NSString*)query {
  NSString *name = nil;
  NSString *urlString = nil;
  if (![query length]) {
    name = NSLocalizedString(@"Search Google", @"");
    urlString = @"http://www.google.com";
  } else {
    name = query;
    NSString *formatString = @"http://www.google.com/search?q=%@";
    NSString *cleanedQuery = [query gtm_stringByEscapingForURLArgument];
    urlString = [NSString stringWithFormat:formatString, cleanedQuery];
  }
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                              [self displayIcon], kHGSObjectAttributeIconKey, 
                              nil];
  NSURL *identifier = [NSURL URLWithString:urlString];
  HGSObject *object = [HGSObject objectWithIdentifier:identifier 
                                                 name:name 
                                                 type:kHGSTypeGoogleSearch
                                               source:nil
                                           attributes:attributes];
  return [super initWithObject:object];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopStandardRowViewController class];
}

// We want to inherit the google logo, so don't return an icon
- (NSImage *)displayIcon {
  return [NSImage imageNamed:@"blue-google-white"]; 
}

- (NSImage *)displayThumbnail {
  return [self displayIcon];
}

- (id)displayPath {
  NSString *string = NSLocalizedString(@"Search Google for “%@”", @""); 
  string = [NSString stringWithFormat:string, [self displayName]];
  NSURL *url = [[self representedObject] identifier];
  
  return [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                   string, kHGSPathCellDisplayTitleKey,
                                   url, kHGSPathCellURLKey,
                                   nil]];
}

- (NSAttributedString*)sourceURLString {
  NSMutableAttributedString *sourceURLString = nil;
  NSString *sourceURL = NSLocalizedString(@"Search Google", @""); ;
  if (sourceURL) {
    sourceURLString = [self mutableAttributedStringFromHTMLString:sourceURL];
    [self addAttributes:sourceURLString elementType:kQSBResultDescriptionSnippet];
  }
  return sourceURLString;
}

@end

@implementation QSBSeparatorTableResult

+ (id)result {
  return [[[[self class] alloc] init] autorelease];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopSeparatorRowViewController class];
}

- (Class)moreResultsRowViewControllerClass {
  return [QSBMoreSeparatorRowViewController class];
}

@end


@implementation QSBFoldTableResult

+ (id)result {
  return [[[[self class] alloc] init] autorelease];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopFoldRowViewController class];
}

- (Class)moreResultsRowViewControllerClass {
  return [QSBMoreFoldRowViewController class];
}

- (BOOL)performDefaultActionWithQueryController:(QSBQueryController*)controller {
  [controller toggleTopMoreViews];
  return YES;
}

@end

@implementation QSBSearchStatusTableResult

+ (id)result {
  return [[[[self class] alloc] init] autorelease];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopSearchStatusRowViewController class];
}

- (Class)moreResultsRowViewControllerClass {
  // Yes, we are using QSBTopSearchStatusRowViewController intentionally here
  return [QSBTopSearchStatusRowViewController class];
}

- (BOOL)performDefaultActionWithQueryController:(QSBQueryController*)controller {
  [controller toggleTopMoreViews];
  return YES;
}

@end

@implementation QSBShowAllTableResult

+ (id)resultWithCategory:(NSString *)categoryName
                   count:(NSUInteger)categoryCount {
  return [[[[self class] alloc] initWithCategory:categoryName
                                           count:categoryCount] autorelease];
}

- (id)initWithCategory:(NSString *)categoryName
                 count:(NSUInteger)categoryCount {
  if ((self = [super init])) {
    categoryCount_ = categoryCount;
    categoryName_ = [categoryName copy];
  }
  return self;
}

- (void)dealloc {
  [categoryName_ release];
  [super dealloc];
}

- (NSString *)categoryName {
  return [[categoryName_ retain] autorelease];
}

- (NSString*)stringValue {
  NSString *format = NSLocalizedString(@"Show all %u %@…", @"");
  return [NSString stringWithFormat:format, categoryCount_, [self categoryName]];
}

- (Class)moreResultsRowViewControllerClass {
  return [QSBMoreShowAllTableRowViewController class];
}

- (BOOL)performDefaultActionWithQueryController:(QSBQueryController*)controller {
  NSString *categoryName = [self categoryName];
  QSBMoreResultsViewDelegate *delegate = [controller moreResultsController];
  [delegate addShowAllCategory:categoryName];
  return YES;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@: %p - %@", 
          [self class], self, [self stringValue]];
}
@end


@implementation QSBMessageTableResult

+ (id)resultWithString:(NSString *)message {
  return [[[[self class] alloc] initWithString:message] autorelease];
}

- (id)initWithString:(NSString *)message {
  if ((self = [super init])) {
    message_ = [message copy];
  }
  return self;
}

- (void)dealloc {
  [message_ release];
  [super dealloc];
}

- (NSAttributedString *)titleSnippetString {
  NSMutableAttributedString *titleSnippet 
    = [self mutableAttributedStringWithString:message_];
  [self addAttributes:titleSnippet elementType:kQSBResultDescriptionSnippet];
  return titleSnippet;
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopMessageRowViewController class];
}

- (void)addAttributes:(NSMutableAttributedString*)string
          elementType:(QSBResultDescriptionItemType)itemType {
  [super addAttributes:string elementType:itemType];
  [string setAlignment:NSCenterTextAlignment
                 range:NSMakeRange(0, [string length])];
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@: %p - %@", 
          [self class], self, message_];
}

@end

@implementation NSString(QSBDisplayPathAdditions)

- (NSString*)qsb_displayPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *displayName = [self stringByStandardizingPath];
  displayName = [fm displayNameAtPath:displayName];
  NSString *container = [self stringByDeletingLastPathComponent];
  if (!([container isEqualToString:@"/"] // Root
        || [container isEqualToString:@""] // Relative path
        || [container isEqualToString:@"/Volumes"])) {
    container = [container qsb_displayPath];
    displayName = [container stringByAppendingFormat:@" ▸ %@", displayName]; 
  }
  return displayName;
} 

@end
