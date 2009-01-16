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

typedef enum {
  kQSBResultDescriptionTitle = 0,
  kQSBResultDescriptionSnippet,
  kQSBResultDescriptionSourceURL
} QSBResultDescriptionItemType;

@interface QSBTableResult (QSBTableResultPrivateMethods)

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

- (NSString *)topResultsRowViewNibName {
  HGSLogDebug(@"Need to handle QSBTableResult result %@.", self);
  return nil;
}

- (NSString *)moreResultsRowViewNibName {
  HGSLogDebug(@"Need to handle QSBTableResult result %@.", self);
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

@end


@implementation QSBTableResult (QSBTableResultPrivateMethods)
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

@synthesize representedObject = representedObject_;
@synthesize categoryName = categoryName_;

+ (id)resultWithObject:(HGSObject *)object {
  return [[[[self class] alloc] initWithObject:object] autorelease];
}

- (id)initWithObject:(HGSObject *)object {
  if ((self = [super init])) {
    representedObject_ = [object retain];
    [representedObject_ addObserver:self
                         forKeyPath:kHGSObjectAttributeIconKey
                            options:0
                            context:NULL];
  }
  return self;
}
- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
  if ([keyPath isEqualToString:kHGSObjectAttributeIconKey]) {
    [self willChangeValueForKey:@"displayIcon"];
    [self didChangeValueForKey:@"displayIcon"]; 
    [self willChangeValueForKey:@"displayThumbnail"];
    [self didChangeValueForKey:@"displayThumbnail"];
  }
}

- (void)dealloc {
  [representedObject_ removeObserver:self 
                          forKeyPath:kHGSObjectAttributeIconKey];
  [representedObject_ release];
  [super dealloc];
}

- (BOOL)isPivotable {
  // We want to pivot on non-suggestions, non-qsb stuff, and non-actions.
  HGSObject *object = [self representedObject];
  return (![object conformsToType:kHGSTypeGoogleSuggest] 
          && ![object conformsToType:kHGSTypeAction]);
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

- (NSString *)topResultsRowViewNibName {
  NSString *rowViewNibName = nil;
  HGSObject *result = [self representedObject];
  if ([result conformsToType:kHGSTypeSuggest]) {
    rowViewNibName = @"TopStandardResultView";
  } else if ([result isKindOfClass:[HGSObject class]]) {
    rowViewNibName = @"TopStandardResultView";
  }
  return rowViewNibName;
}

- (NSString *)moreResultsRowViewNibName {
  NSString *rowViewNibName = nil;
  HGSObject *result = [self representedObject];
  if (!([result conformsToType:kHGSTypeSuggest]
        || [result conformsToType:kHGSTypeSearch])) {
    if ([self categoryName]) {
      rowViewNibName = @"MoreCategoryResultView";
    } else {
      rowViewNibName = @"MoreStandardResultView";
    }
  }
  return rowViewNibName;
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
  HGSObject *object = [[[HGSObject alloc] initWithIdentifier:[NSURL URLWithString:urlString] 
                                                        name:name 
                                                        type:kHGSTypeGoogleSearch
                                                      source:nil
                                                  attributes:nil] autorelease];
  return [super initWithObject:object];
}

- (NSString *)topResultsRowViewNibName {
  return @"TopStandardResultView";
}

// We want to inherit the google logo, so don't return an icon
- (NSImage *)displayIcon {
  return [NSImage imageNamed:@"blue-google-white"]; 
}

- (NSImage *)displayThumbnail {
  return nil;
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

- (NSString *)topResultsRowViewNibName {
  return @"TopSeparatorResultView";
}

- (NSString *)moreResultsRowViewNibName {
  return @"MoreSeparatorResultView";
}

@end


@implementation QSBFoldTableResult

+ (id)result {
  return [[[[self class] alloc] init] autorelease];
}

- (NSString *)topResultsRowViewNibName {
  return @"TopFoldResultView";
}

- (NSString *)moreResultsRowViewNibName {
  return @"MoreFoldResultView";
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

- (NSString *)topResultsRowViewNibName {
  return @"TopSearchStatusResultView";
}

- (NSString *)moreResultsRowViewNibName {
  return @"TopSearchStatusResultView";
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

- (NSString *)moreResultsRowViewNibName {
  return @"MoreShowAllTableResultView";
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

- (NSString *)topResultsRowViewNibName {
  return @"TopMessageResultView";
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
