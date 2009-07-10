//
//  StockQuoterViewController.m
//  QSB
//
//  Created by mrossetti on 7/2/09.
//  Copyright 2009 Google Inc. All rights reserved.
//

#import "StockQuoterViewController.h"
#import <GData/GData.h>
#import <Vermilion/Vermilion.h>
#import "HGSPython.h"  // Must preceed import of <Python/structmember.h>.
#import <Python/structmember.h>
#import "GTMGoogleSearch.h"
#import "GTMMethodCheck.h"
#import "GTMNSScanner+JSON.h"
#import "JSON/JSON.h"

// Keys provided in the Google Finance JSON results for a given stock.
static NSString *const kGoogleFinanceCompanyNameKey= @"name";
static NSString *const kGoogleFinanceSymbolKey = @"t";
static NSString *const kGoogleFinanceOpenMarketPriceKey = @"l";
static NSString *const kGoogleFinanceOpenMarketChangeKey = @"c";
static NSString *const kGoogleFinanceOpenMarketChangePercentageKey = @"cp";
static NSString *const kGoogleFinanceHighPriceKey = @"hi";
static NSString *const kGoogleFinanceLowPriceKey= @"lo";
static NSString *const kGoogleFinanceExchangeOpenKey= @"eo";
static NSString *const kGoogleFinanceAfterHoursPriceKey = @"el";
static NSString *const kGoogleFinanceAfterHoursChangeKey = @"ec";
static NSString *const kGoogleFinanceAfterHoursChangePercentageKey = @"ecp";


@interface StockQuoterViewController ()

@property (readwrite, nonatomic, retain)
  NSAttributedString *companyNameAndSymbol;
@property (readwrite, nonatomic, assign) CGFloat openMarketPrice;
@property (readwrite, nonatomic, retain) NSString *openMarketChangeAndPercent;
@property (readwrite, nonatomic, assign) CGFloat highPrice;
@property (readwrite, nonatomic, assign) CGFloat lowPrice;
@property (readwrite, nonatomic, assign) BOOL afterHours;
@property (readwrite, nonatomic, assign) CGFloat afterHoursPrice;
@property (readwrite, nonatomic, retain) NSString *afterHoursChangeAndPercent;
@property (readwrite, nonatomic, retain) NSImage *priceChart;
@property (nonatomic, retain) GDataHTTPFetcher *dataFetcher;
@property (nonatomic, retain) GDataHTTPFetcher *chartFetcher;
@property (readwrite, nonatomic, retain) NSColor *openMarketChangeColor;
@property (readwrite, nonatomic, retain) NSColor *afterHoursChangeColor;

- (void)fetchStockDataForSymbol:(NSString *)symbol;
- (void)fetchStockChartForSymbol:(NSString *)symbol;

@end


@interface NSImage (StockQuoterImageMethods)

// Replace the NSBitmapRep, if any, for the image with one where the
// white-ish pixels are transparent by adding an alpha channel.
- (void)makeWhiteBitmapRepTransparent;

@end

  
@interface NSString (StockQuoterStringMethods)

// Convert all instances of '\xnn' into the character with that hex value
// returning a new string.
- (NSString *)stockQuoter_stringByReplacingXEncodedCharacters;

// Return YES if there is a character at |index| and it is not multi-byte.
- (BOOL)isSingleByteCharacterAtIndex:(NSUInteger)index;

// Return a float value for a string which may contain currency symbols
// and commas.
- (CGFloat)currencyStringFloatValue;

@end

// Given a character |c|, check to see if it is [0-9a-zA-Z] and, if so,
// convert into an integer value, otherwise return -1.
NSInteger hexCharToInt(unichar c);

@implementation StockQuoterViewController

GTM_METHOD_CHECK(NSScanner, gtm_scanJSONObjectString:);

@synthesize companyNameAndSymbol = companyNameAndSymbol_;
@synthesize openMarketPrice = openMarketPrice_;
@synthesize openMarketChangeAndPercent = openMarketChangeAndPercent_;
@synthesize highPrice = highPrice_;
@synthesize lowPrice = lowPrice_;
@synthesize afterHours = afterHours_;
@synthesize afterHoursPrice = afterHoursPrice_;
@synthesize afterHoursChangeAndPercent = afterHoursChangeAndPercent_;
@synthesize priceChart = priceChart_;
@synthesize dataFetcher = dataFetcher_;
@synthesize chartFetcher = chartFetcher_;
@synthesize openMarketChangeColor = openMarketChangeColor_;
@synthesize afterHoursChangeColor = afterHoursChangeColor_;

- (void)dealloc {
  [dataFetcher_ stopFetching];
  [dataFetcher_ release];
  [chartFetcher_ stopFetching];
  [chartFetcher_ release];
  [super dealloc];
}

- (HGSResult *)result {
  return [[result_ retain] autorelease];
}

- (NSNumber *)setResult:(HGSResult *)result {
  [result_ autorelease];
  result_ = [result retain];
  
  BOOL useCustomView = NO;
  // Determine the stock symbol from the result's URL.  It'll always be
  // the last portion of the string following the last '='.
  NSURL *resultURL = [result url];
  NSString *symbol = [resultURL absoluteString];
  NSRange symbolRange = [symbol rangeOfString:@"=" options:NSBackwardsSearch];
  if (symbolRange.location != NSNotFound) {
    symbol = [symbol substringFromIndex:symbolRange.location + 1];
    if ([symbol length]) {
      // Fetch the various stock quote components.
      [self fetchStockDataForSymbol:symbol];
      
      // Fetch an image for the graph.
      [self fetchStockChartForSymbol:symbol];
      useCustomView = YES;
    }
  }
  if (!useCustomView) {
    HGSLogDebug(@"Failed to find stock symbol in result url '%@'.", resultURL);
  }
  return [NSNumber numberWithBool:useCustomView];
}

#pragma mark Stock Data Methods

- (void)fetchStockDataForSymbol:(NSString *)symbol {
  GTMGoogleSearch *googleSearch = [GTMGoogleSearch sharedInstance];
  NSMutableDictionary *args
    = [NSMutableDictionary dictionaryWithObject:@"infoquoteall"
                                         forKey:@"infotype"];
  NSString *dataURLString = [googleSearch searchURLFor:symbol 
                                                ofType:@"finance/info" 
                                             arguments:args];
  NSURL *dataURL = [NSURL URLWithString:dataURLString];
  NSURLRequest *request = [NSURLRequest requestWithURL:dataURL];
    GDataHTTPFetcher *dataFetcher
    = [GDataHTTPFetcher httpFetcherWithRequest:request];
  [self setDataFetcher:dataFetcher];
  [dataFetcher beginFetchWithDelegate:self
                     didFinishSelector:@selector(dataFetcher:
                                                 finishedWithData:)
                       didFailSelector:@selector(dataFetcher:
                                                 failedWithError:)];
}

- (void)dataFetcher:(GDataHTTPFetcher *)fetcher
   finishedWithData:(NSData *)retrievedData {
  [self setDataFetcher:nil];
  NSString *jsonResponse = [[[NSString alloc] initWithData:retrievedData
                                                  encoding:NSUTF8StringEncoding]
                            autorelease];
  // The JSON returned by the finance feed may bave improperly encoded
  // \xnn characters in it.  Scan and convert such characters.
  // TODO(mrossetti): Remove this once 1970437 has been corrected.
  jsonResponse = [jsonResponse stockQuoter_stringByReplacingXEncodedCharacters];
  NSScanner *jsonScanner = [NSScanner scannerWithString:jsonResponse];
  NSCharacterSet *set = [[NSCharacterSet illegalCharacterSet] invertedSet];
  [jsonScanner setCharactersToBeSkipped:set];
  NSString *jsonString = nil;
  BOOL validJSON = [jsonScanner gtm_scanJSONObjectString:&jsonString];
  if (validJSON) {
    NSDictionary *stockData = [jsonString JSONValue];

    // Collect all quote information and determine if we have enough.
    NSString *nameString = [stockData objectForKey:kGoogleFinanceCompanyNameKey];
    NSString *symbolString = [stockData objectForKey:kGoogleFinanceSymbolKey];
    NSString *openMarketPriceString 
      = [stockData objectForKey:kGoogleFinanceOpenMarketPriceKey];
    NSString *openMarketChangeString
      = [stockData objectForKey:kGoogleFinanceOpenMarketChangeKey];
    NSString *openMarketChangePercentageString
      = [stockData objectForKey:kGoogleFinanceOpenMarketChangePercentageKey];
    NSString *highPriceString
      = [stockData objectForKey:kGoogleFinanceHighPriceKey];
    NSString *lowPriceString = [stockData objectForKey:kGoogleFinanceLowPriceKey];
    NSString *exchangeOpenString
      = [stockData objectForKey:kGoogleFinanceExchangeOpenKey];
    BOOL afterHours = [exchangeOpenString isEqualToString:@"0"];
    
    // Make the company name bold with the symbol regular.
    NSFont *boldSystem18Font = [NSFont boldSystemFontOfSize:18.0];
    NSDictionary *companyNameAttr
      = [NSDictionary dictionaryWithObject:boldSystem18Font
                                    forKey:NSFontAttributeName];
    NSMutableAttributedString *nameAttrString
      = [[[NSMutableAttributedString alloc] initWithString:nameString
                                                attributes:companyNameAttr]
         autorelease];
    NSString *nameSymbolString = [NSString stringWithFormat:@" (%@)",
                                  symbolString];
    NSFont *system18Font = [NSFont systemFontOfSize:18.0];
    NSDictionary *symbolAttr
      = [NSDictionary dictionaryWithObjectsAndKeys:
         system18Font, NSFontAttributeName,
         nil];
    NSAttributedString *symbolAttrString
      = [[[NSAttributedString alloc] initWithString:nameSymbolString
                                         attributes:symbolAttr] autorelease];
    [nameAttrString appendAttributedString:symbolAttrString];
    NSMutableParagraphStyle *lineBreakStyle 
      = [[[NSParagraphStyle defaultParagraphStyle] mutableCopy] autorelease];
    [lineBreakStyle setLineBreakMode:NSLineBreakByTruncatingMiddle];
    NSRange fullRange = NSMakeRange(0, [nameAttrString length]);
    [nameAttrString addAttribute:NSParagraphStyleAttributeName
                           value:lineBreakStyle
                           range:fullRange];
    [self setCompanyNameAndSymbol:nameAttrString];

    CGFloat openMarketPrice = [openMarketPriceString currencyStringFloatValue];
    [self setOpenMarketPrice:openMarketPrice];
    
    openMarketChangeString
      = [openMarketChangeString stringByAppendingFormat:@" (%@%%)",
         openMarketChangePercentageString];
    [self setOpenMarketChangeAndPercent:openMarketChangeString];
    // Set the color red if the change is negative.
    CGFloat openMarketChange = [openMarketChangeString currencyStringFloatValue];
    if (openMarketChange < 0.0) {
      [self setOpenMarketChangeColor:[NSColor redColor]];
    } else {
      [self setOpenMarketChangeColor:[NSColor blackColor]];
    }
    
    CGFloat highPrice = [highPriceString currencyStringFloatValue];
    [self setHighPrice:highPrice];
    CGFloat lowPrice = [lowPriceString currencyStringFloatValue];
    [self setLowPrice:lowPrice];
    
    if (afterHours) {
      NSString *afterHoursPriceString
        = [stockData objectForKey:kGoogleFinanceAfterHoursPriceKey];
      NSString *afterHoursChangeString
        = [stockData objectForKey:kGoogleFinanceAfterHoursChangeKey];
      NSString *afterHoursChangePercentageString
        = [stockData objectForKey:kGoogleFinanceAfterHoursChangePercentageKey];
      CGFloat afterHoursPrice = [afterHoursPriceString currencyStringFloatValue];
      [self setAfterHoursPrice:afterHoursPrice];
      
      if ([afterHoursChangeString length]
          && [afterHoursChangePercentageString length]) {
        afterHoursChangeString
          = [afterHoursChangeString stringByAppendingFormat:@" (%@%%)",
             afterHoursChangePercentageString];
        [self setAfterHoursChangeAndPercent:afterHoursChangeString];
        // Set the color red if the change is negative.
        CGFloat afterHoursChange = [afterHoursChangeString currencyStringFloatValue];
        if (afterHoursChange < 0.0) {
          [self setAfterHoursChangeColor:[NSColor redColor]];
        } else {
          [self setAfterHoursChangeColor:[NSColor blackColor]];
        }
      }
    }
    [self setAfterHours:afterHours];
  } else {
    HGSLogDebug(@"Invalid JSON returned for stock query '%@'.  "
                @"JSON response: '%@'.",
                [[self result] displayName], jsonResponse);
  }
}

- (void)dataFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  [self setDataFetcher:nil];
  HGSLogDebug(@"Failed to retrieve stock data for '%@' with error %@",
              [[self result] displayName], error);
}

#pragma mark Stock Chart Methods

- (void)fetchStockChartForSymbol:(NSString *)symbol {
  GTMGoogleSearch *googleSearch = [GTMGoogleSearch sharedInstance];
  NSString *chartURLString = [googleSearch searchURLFor:symbol 
                                                 ofType:@"finance/chart" 
                                              arguments:nil];
  NSURL *chartURL = [NSURL URLWithString:chartURLString];
  NSURLRequest *request = [NSURLRequest requestWithURL:chartURL];
  GDataHTTPFetcher *chartFetcher
    = [GDataHTTPFetcher httpFetcherWithRequest:request];
  [self setChartFetcher:chartFetcher];
  [chartFetcher beginFetchWithDelegate:self
                     didFinishSelector:@selector(chartFetcher:
                                                 finishedWithData:)
                       didFailSelector:@selector(chartFetcher:
                                                 failedWithError:)];
}

- (void)chartFetcher:(GDataHTTPFetcher *)fetcher
  finishedWithData:(NSData *)chartData {
  [self setChartFetcher:nil];
  NSOperationQueue *queue = [HGSOperationQueue sharedOperationQueue];
  [queue addOperation:[HGSInvocationOperation
                       memoryInvocationOperationWithTarget:self
                       selector:@selector(updateChartWithData:)
                       object:chartData]];
}

- (void)chartFetcher:(GDataHTTPFetcher *)fetcher
     failedWithError:(NSError *)error {
  [self setChartFetcher:nil];
  HGSLogDebug(@"Failed to retrieve stock chart for '%@' with error %@",
              [[self result] displayName], error);
}

- (void)updateChartWithData:(NSData *)chartData {
  NSImage *chart = [[[NSImage alloc] initWithData:chartData] autorelease];
  [chart makeWhiteBitmapRepTransparent];
  [self setPriceChart:chart];
}

@end


@implementation NSImage (StockQuoterImageMethods)

- (void)makeWhiteBitmapRepTransparent {
  NSArray *chartReps = [self representations];
  for (NSImageRep *chartRep in chartReps) {
    if ([chartRep isKindOfClass:[NSBitmapImageRep class]]) {
      NSBitmapImageRep *oldBitmapRep = (NSBitmapImageRep *)chartRep;
      
      NSSize chartSize = [self size];
      NSBitmapImageRep *newBitmapRep
        = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                  pixelsWide:chartSize.width
                                                  pixelsHigh:chartSize.height
                                               bitsPerSample:8
                                             samplesPerPixel:4
                                                    hasAlpha:YES
                                                    isPlanar:NO
                                              colorSpaceName:NSCalibratedRGBColorSpace
                                                 bytesPerRow:0
                                                bitsPerPixel:0];
      
      // Create an NSGraphicsContext that draws into the new NSBitmapImageRep.
      NSGraphicsContext *nsContext
        = [NSGraphicsContext graphicsContextWithBitmapImageRep:newBitmapRep];
      [NSGraphicsContext saveGraphicsState];
      [NSGraphicsContext setCurrentContext:nsContext];
      
      // Clear the bitmap to zero alpha.
      [[NSColor clearColor] set];
      NSRectFill(NSMakeRect(0, 0, chartSize.width, chartSize.height));
      
      // Creep through pixel by pixel, setting the alpha for pixels of color.
      //
      // Let me explain how this work since there are some 'magic' numbers
      // in the following.  In an attempt to avoid as much floating
      // calculation as possible, simple limits are placed on the conversion
      // of the color for each pixel: if the pixel is 'practically' white
      // (i.e. total color > 2.9) then leave it alone (which means totally
      // transparent as set by the NSRectFill immediately above), else if
      // the pixel has enough color (i.e. total color <= 2.2) then leave
      // the color as-is and plop it into the pixel.  Otherwise, some
      // transparency is needed so calculate the distance of the pixel's
      // color from white and set that as the alpha component for the pixel.
      //
      // Since the calculation is optimized by the 2.9/2.2 limits, some
      // adjustment of the alpha range is required in order to smooth it
      // out.  With a totalColor of 2.2 the alpha comes out as 0.468 which
      // should be adjusted to 1.0 and with a totalColor of 2.9 the alpha
      // comes out at 0.052 which should be adjusted to 0.0.  Hence, the
      //    alpha = (alpha - 0.052) /0.416; (The 0.416 being 0.468 - 0.052.)
      // While this alpha ramping operation isn't perfect, it was good
      // enough to fool my eyes.
      for (NSInteger x = 0; x < chartSize.width; ++x) {
        for (NSInteger y = 0; y < chartSize.height; ++y) {
          NSColor *pixelColor = [oldBitmapRep colorAtX:x y:y];
          CGFloat red;
          CGFloat green;
          CGFloat blue;
          [pixelColor getRed:&red green:&green blue:&blue alpha:NULL];
          CGFloat totalColor = red + green + blue;
          // Simple test to avoid pixel setting.
          if (totalColor < 2.9) {
            // Simple test to avoid calculations.
            if (totalColor > 2.2) {
              // Calculate the distance from white.
              CGFloat redFactor = 1.0 - red;
              CGFloat greenFactor = 1.0 - green;
              CGFloat blueFactor = 1.0 - blue;
              CGFloat alpha = sqrt((redFactor * redFactor)
                                   + (greenFactor * greenFactor)
                                   + (blueFactor * blueFactor));
              // Adjust to the range is 0.0 to 1.0.
              alpha = (alpha - 0.052) /0.416;
              pixelColor = [pixelColor colorWithAlphaComponent:alpha];
            }
            [newBitmapRep setColor:pixelColor atX:x y:y];
          }
        }
      }
      
      // Replace the imageRep.
      [self removeRepresentation:oldBitmapRep];
      [self addRepresentation:newBitmapRep];
      break;
    }
  }
}

@end


@implementation NSString (StockQuoterStringMethods)

- (NSString *)stockQuoter_stringByReplacingXEncodedCharacters {
  // TODO(mrossetti): Remove this once 1970437 has been corrected.
  NSString *resultString = self;
  NSUInteger length = [self length];
  if (length) {
    NSMutableString *cleanString
      = [NSMutableString stringWithCapacity:length];
    NSScanner *scanner = [NSScanner scannerWithString:self];
    [scanner setCharactersToBeSkipped:nil];
    NSString *matchString = nil;
    while ([scanner scanUpToString:@"\\x" intoString:&matchString]) {
      [cleanString appendString:matchString];
      if (![scanner isAtEnd]) {
        // See if the next two characters are hex.
        NSUInteger hexLocation = [scanner scanLocation] + 2;
        [scanner setScanLocation:hexLocation];
        NSUInteger hexValue = 0;
        // While we should get exactly two hex digits, just grab what comes
        // along and then check the location.
        [scanner scanHexInt:&hexValue];
        NSUInteger scanLocation = [scanner scanLocation];
        if (scanLocation == hexLocation + 2) {
          // Got exactly two hex digits, good.  Insert a character with
          // that value.
          unichar aUnichar = hexValue;
          [cleanString appendFormat:@"%C", aUnichar];
        } else {
          // We did not get what we expected so just ignore the '\x' and reset
          // scanner to be immediately after the '\x' and proceed from there.
          [scanner setScanLocation:hexLocation];
        }
      }
    }
    resultString = cleanString;
  }
  return resultString;
}

- (BOOL)isSingleByteCharacterAtIndex:(NSUInteger)charIndex {
  // TODO(mrossetti): Remove this once 1970437 has been corrected.
  BOOL result = NO;
  if (charIndex < [self length]) {
    NSRange charRange
      = [self rangeOfComposedCharacterSequenceAtIndex:charIndex];
    result = charRange.length == 1;
  }
  return result;
}

- (CGFloat)currencyStringFloatValue {
  NSNumberFormatter *formatter = [[[NSNumberFormatter alloc] init] autorelease];
  [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
  NSNumber *number = [formatter numberFromString:self];
  CGFloat floatValue = [number floatValue];
  return floatValue;
}

@end

NSInteger hexCharToInt(unichar c) {
  // TODO(mrossetti): Remove this once 1970437 has been corrected.
  NSInteger x = (c >= '0' && c <= '9')
                ? c - '0'
                : (c >= 'a' && c <= 'f')
                  ? (c - 'a' + 10)
                  : (c >= 'A' && c <= 'F')
                    ? (c - 'A' + 10)
                    : -1;
  return x;
}
