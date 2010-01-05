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
#import <QSBPluginUI/QSBPluginUI.h>
#import "GTMMethodCheck.h"
#import "GTMNSString+URLArguments.h"
#import "NSAttributedString+Attributes.h"
#import "GTMNSString+HTML.h"
#import "QSBSearchViewController.h"
#import "QSBMoreResultsViewController.h"
#import "NSString+ReadableURL.h"
#import "QSBTopResultsRowViewControllers.h"
#import "QSBMoreResultsRowViewControllers.h"
#import "GTMNSObject+KeyValueObserving.h"
#import "GTMMethodCheck.h"
#import "GTMGoogleSearch.h"
#import "ClipboardSearchSource.h"

typedef enum {
  kQSBResultDescriptionTitle = 0,
  kQSBResultDescriptionSnippet,
  kQSBResultDescriptionSourceURL
} QSBResultDescriptionItemType;

static NSString *const kClipboardCopyActionIdentifier
  = @"com.google.qsb.clipboard.action.copy";

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

- (void)willPivot {
  HGSLogDebug(@"Tried to pivot on result %@ that doesn't pivot", self);
}

- (NSAttributedString *)titleString {
  NSMutableAttributedString *resultString = [self genericTitleLine];
  [self addAttributes:resultString elementType:kQSBResultDescriptionTitle];
  return resultString;
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
  NSMutableAttributedString *resultString
    = [[[self titleString] mutableCopy] autorelease];
  NSAttributedString *resultSnippet = [self snippetString];
  if (resultSnippet) {
    [resultString appendAttributedString:[[[NSAttributedString alloc]
                                           initWithString:@"\n"] autorelease]];
    [resultString appendAttributedString:resultSnippet];
  }
  return resultString;
}

- (NSAttributedString *)titleSourceURLString {
  NSMutableAttributedString *resultString
    = [[[self titleString] mutableCopy] autorelease];
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

- (BOOL)performDefaultActionWithSearchViewController:(QSBSearchViewController*)controller {
  return NO;
}

- (NSString *)displayName {
  return nil;
}

- (NSArray *)displayPath {
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
                   value:[NSColor colorWithCalibratedRed:(float)0x00/0xFF
                                                   green:(float)0x4c/0xFF
                                                    blue:(float)0x00/0xFF
                                                   alpha:0.5]];
  } else if (itemType == kQSBResultDescriptionTitle) {
    [string addAttribute:NSForegroundColorAttributeName
                   value:[NSColor blackColor]];
  } else {
    HGSLogDebug(@"Unknown itemType: %d", itemType);
  }
}

- (NSMutableAttributedString*)mutableAttributedStringWithString:(NSString*)string {
  CGFloat startingSize = 13.0;
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
    NSString *displayString = [mutableItem qsb_displayPath];
    mutableItem = [NSMutableString stringWithString:displayString];
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

- (NSImage *)flagIcon {
  return nil;
}

- (NSImage *)displayThumbnail {
  return nil;
}

- (BOOL)copyToPasteboard:(NSPasteboard *)pb {
  return NO;
}

@end


@implementation QSBSourceTableResult : QSBTableResult

GTM_METHOD_CHECK(NSObject, gtm_addObserver:forKeyPath:selector:userInfo:options:);
GTM_METHOD_CHECK(NSObject, gtm_removeObserver:forKeyPath:selector:);

@synthesize representedResult = representedResult_;
@synthesize categoryName = categoryName_;

+ (id)tableResultWithResult:(HGSResult *)result {
  return [[[[self class] alloc] initWithResult:result] autorelease];
}

- (id)initWithResult:(HGSResult *)result {
  if ((self = [super init])) {
    representedResult_ = [result retain];
    [representedResult_ gtm_addObserver:self
                             forKeyPath:kHGSObjectAttributeIconKey
                               selector:@selector(objectIconChanged:)
                               userInfo:nil
                                options:0];
  }
  return self;
}

- (void)dealloc {
  [representedResult_ gtm_removeObserver:self
                              forKeyPath:kHGSObjectAttributeIconKey
                                selector:@selector(objectIconChanged:)];
  [representedResult_ release];
  [super dealloc];
}

- (BOOL)isEqual:(id)val {
  BOOL equal = NO;
  if ([val isKindOfClass:[self class]]) {
    equal = [[self representedResult] isEqual:[val representedResult]];
  }
  return equal;
}

- (NSUInteger)hash {
  return [[self representedResult] hash];
}

- (void)objectIconChanged:(GTMKeyValueChangeNotification *)notification {
  [self willChangeValueForKey:@"displayIcon"];
  [self didChangeValueForKey:@"displayIcon"];
  [self willChangeValueForKey:@"displayThumbnail"];
  [self didChangeValueForKey:@"displayThumbnail"];
}

- (BOOL)isPivotable {
  // We want to pivot on non-suggestions, non-qsb stuff, and non-actions.
  HGSResult *result = [self representedResult];
  BOOL pivotable = YES;
  if ([result conformsToType:kHGSTypeGoogleSuggest]) pivotable = YES;
  if ([result conformsToType:kHGSTypeAction]) pivotable = NO;
  return pivotable;
}

- (void)willPivot {
  // Let the result know that we were interested in it.
  HGSResult *result = [self representedResult];
  [result promote];
}

- (void)addAttributes:(NSMutableAttributedString*)string
          elementType:(QSBResultDescriptionItemType)itemType {
  [super addAttributes:string elementType:itemType];
  if (itemType == kQSBResultDescriptionTitle) {
    HGSResult *result = [self representedResult];
    if ([result conformsToType:kHGSTypeAction]) {
      [string addAttribute:NSForegroundColorAttributeName
                     value:[NSColor colorWithCalibratedRed:(float)0x33/0xFF
                                                     green:(float)0x77/0xFF
                                                      blue:(float)0xAA/0xFF
                                                     alpha:1.0]];
    }
  }
}

- (CGFloat)rank {
  return [[self representedResult] rank];
}

- (Class)topResultsRowViewControllerClass {
  Class rowViewClass = Nil;
  HGSResult *result = [self representedResult];
  if ([result conformsToType:kHGSTypeSuggest]) {
    rowViewClass = [QSBTopSearchForRowViewController class];
  } else if ([result isKindOfClass:[HGSResult class]]) {
    rowViewClass = [QSBTopStandardRowViewController class];
  }
  return rowViewClass;
}

- (Class)moreResultsRowViewControllerClass {
  Class rowViewClass = Nil;
  HGSResult *result = [self representedResult];
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

- (BOOL)performDefaultActionWithSearchViewController:(QSBSearchViewController*)controller {
  HGSResult *result = [self representedResult];
  HGSAction *action
    = [result valueForKey:kHGSObjectAttributeDefaultActionKey];
  if (action) {
    HGSResultArray *results = [HGSResultArray arrayWithResult:result];
    [controller performAction:action withResults:results];
  } else {
    HGSLog(@"Unable to get default action for %@", result);
  }
  return YES;
}

- (NSArray *)displayPath {
  HGSResult *result = [self representedResult];
  return [result valueForKey:kQSBObjectAttributePathCellsKey];
}

- (NSString *)displayName {
  HGSResult *result = [self representedResult];
  return [result displayName];
}

- (NSImage *)flagIcon {
  HGSResult *result = [self representedResult];
  NSString *iconName = [result valueForKey:kHGSObjectAttributeFlagIconNameKey];
  NSImage *image = nil;
  if (iconName) image = [NSImage imageNamed:iconName];
  return image;
}

- (NSImage *)displayIcon {
  HGSResult *result = [self representedResult];
  return [result valueForKey:kHGSObjectAttributeIconKey];
}

- (NSString*)displayToolTip {
  NSString *displayString = nil;
#if DEBUG
  NSString *sourceName = [[[self representedResult] source] displayName];
  if (!sourceName) {
    NSBeep();
  }
  displayString = [NSString stringWithFormat:@"%@ (Rank: %.2f, Source: %@)",
                   displayString, [self rank], sourceName];
#else  // DEBUG
  displayString = [self displayName];
  HGSResult *result = [self representedResult];
  NSString *snippetString
    = [result valueForKey:kHGSObjectAttributeSnippetKey];
  if ([snippetString length]) {
    displayString = [displayString stringByAppendingFormat:@" — %@",
                     snippetString];
  }
  NSString *resultSourceURL = [[self sourceURLString] string];
  if ([resultSourceURL length]) {
    displayString = [displayString stringByAppendingFormat:@" — %@",
                     resultSourceURL];
  }
#endif  // DEBUG
  return displayString;
}

- (NSImage *)displayThumbnail {
  HGSResult *result = [self representedResult];
  return [result valueForKey:kHGSObjectAttributeImmediateIconKey];
}

- (NSMutableAttributedString*)genericTitleLine {
  // Title is rendered as 12 pt black.
  HGSResult *result = [self representedResult];
  NSString *html = [result valueForKey:kHGSObjectAttributeNameKey];
  NSMutableAttributedString *title
    = [self mutableAttributedStringWithString:html];
  if ([title length] == 0) {
    // If we don't have a title, we'll just use a canned string
    NSString *titleString = NSLocalizedString(@"<No Title>", @"");
    title =  [self mutableAttributedStringWithString:titleString];
  }

  return title;
}

- (NSAttributedString*)snippetString {
  // Snippet is rendered as 12 pt gray (50% black).
  NSMutableAttributedString *snippetString = nil;
  HGSResult *result = [self representedResult];
  NSString *snippet = [result valueForKey:kHGSObjectAttributeSnippetKey];
  if (snippet) {
    snippetString = [self mutableAttributedStringFromHTMLString:snippet];
    [self addAttributes:snippetString elementType:kQSBResultDescriptionSnippet];
  }
  return snippetString;
}

- (NSAttributedString*)sourceURLString {
  // SourceURL is rendered as 12 pt green.
  NSMutableAttributedString *sourceURLString = nil;
  HGSResult *result = [self representedResult];
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
          [self class], self, representedResult_];
}

- (BOOL)copyToPasteboard:(NSPasteboard *)pb {
  BOOL didCopy = NO;
  HGSResult *result = [self representedResult];
  HGSAction *action = [[HGSExtensionPoint actionsPoint]
                       extensionWithIdentifier:kClipboardCopyActionIdentifier];
  if (result && action) {
    HGSResultArray *resultArray = [HGSResultArray arrayWithResult:result];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          resultArray, kHGSActionDirectObjectsKey,
                          pb, kClipboardAttributePasteboardKey,
                          nil];
    didCopy = [action performWithInfo:info];
  }
  return didCopy;
}

@end


@implementation QSBGoogleTableResult

GTM_METHOD_CHECK(NSString, gtm_stringByEscapingForURLArgument);

+ (id)tableResultForQuery:(NSString*)query {
  return [[[[self class] alloc] initWithQuery:query] autorelease];
}

- (id)init {
  [NSException raise:NSIllegalSelectorException format:@"Call initWithQuery"];
  return nil;
}

- (id)initWithQuery:(NSString*)query {
  NSString *name = nil;
  NSString *urlString = nil;
  GTMGoogleSearch *googleSearch = [GTMGoogleSearch sharedInstance];
  if (![query length]) {
    name = NSLocalizedString(@"Google Search", @"");
    urlString = [googleSearch searchURLFor:nil ofType:@"webhp" arguments:nil];
  } else {
    name = query;
    NSString *cleanedQuery = [query gtm_stringByEscapingForURLArgument];
    urlString = [googleSearch searchURLFor:cleanedQuery
                                    ofType:GTMGoogleSearchWeb
                                 arguments:nil];
  }
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                              [self displayIcon], kHGSObjectAttributeIconKey,
                              nil];
  HGSResult *result = [HGSResult resultWithURI:urlString
                                          name:name
                                          type:kHGSTypeGoogleSearch
                                        source:nil
                                    attributes:attributes];
  return [super initWithResult:result];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopSearchForRowViewController class];
}

// We want to inherit the google logo, so don't return an icon
- (NSImage *)displayIcon {
  return [NSImage imageNamed:@"blue-google-white"];
}

- (NSImage *)displayThumbnail {
  return nil;
}

- (NSArray *)displayPath {
  NSString *string = NSLocalizedString(@"Search Google for '%@'",
                                       @"A table result label for an item that "
                                       @"allows you to search google for the "
                                       @"token represented by %@.");
  string = [NSString stringWithFormat:string, [self displayName]];
  NSURL *url = [[self representedResult] url];

  return [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                   string, kQSBPathCellDisplayTitleKey,
                                   url, kQSBPathCellURLKey,
                                   nil]];
}

- (NSAttributedString*)sourceURLString {
  NSMutableAttributedString *sourceURLString = nil;
  NSString *sourceURL = NSLocalizedString(@"Google Search", @""); ;
  if (sourceURL) {
    sourceURLString = [self mutableAttributedStringFromHTMLString:sourceURL];
    [self addAttributes:sourceURLString elementType:kQSBResultDescriptionSnippet];
  }
  return sourceURLString;
}

@end

@implementation QSBSeparatorTableResult

+ (id)tableResult {
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

+ (id)tableResult {
  return [[[[self class] alloc] init] autorelease];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopFoldRowViewController class];
}

- (Class)moreResultsRowViewControllerClass {
  return [QSBMoreFoldRowViewController class];
}

- (BOOL)performDefaultActionWithSearchViewController:(QSBSearchViewController*)controller {
  [controller toggleTopMoreViews];
  return YES;
}

@end

@implementation QSBSearchStatusTableResult

+ (id)tableResult {
  return [[[[self class] alloc] init] autorelease];
}

- (Class)topResultsRowViewControllerClass {
  return [QSBTopSearchStatusRowViewController class];
}

- (Class)moreResultsRowViewControllerClass {
  // Yes, we are using QSBTopSearchStatusRowViewController intentionally here
  return [QSBTopSearchStatusRowViewController class];
}

- (BOOL)performDefaultActionWithSearchViewController:(QSBSearchViewController*)controller {
  [controller toggleTopMoreViews];
  return YES;
}

@end

@implementation QSBShowAllTableResult

+ (id)tableResultWithCategory:(NSString *)categoryName
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
  NSString *format = NSLocalizedString(@"Show all %u %@…",
                                       @"A table result label for an item that "
                                       @"will show the user all x things where "
                                       @"x is %u and the things are %@.");
  return [NSString stringWithFormat:format, categoryCount_, [self categoryName]];
}

- (Class)moreResultsRowViewControllerClass {
  return [QSBMoreShowAllTableRowViewController class];
}

- (BOOL)performDefaultActionWithSearchViewController:(QSBSearchViewController*)controller {
  NSString *categoryName = [self categoryName];
  QSBMoreResultsViewController *viewController
    = [controller moreResultsController];
  [viewController addShowAllCategory:categoryName];
  return YES;
}

- (NSString *)description {
  return [NSString stringWithFormat:@"%@: %p - %@",
          [self class], self, [self stringValue]];
}
@end


@implementation QSBMessageTableResult

+ (id)tableResultWithString:(NSString *)message {
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
