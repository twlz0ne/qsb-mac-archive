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
    
    CGFloat openMarketPrice = [openMarketPriceString floatValue];
    [self setOpenMarketPrice:openMarketPrice];
    
    openMarketChangeString
      = [openMarketChangeString stringByAppendingFormat:@" (%@%%)",
         openMarketChangePercentageString];
    [self setOpenMarketChangeAndPercent:openMarketChangeString];
    // Set the color red if the change is negative.
    CGFloat openMarketChange = [openMarketChangeString floatValue];
    if (openMarketChange < 0.0) {
      [self setOpenMarketChangeColor:[NSColor redColor]];
    } else {
      [self setOpenMarketChangeColor:[NSColor blackColor]];
    }
    
    CGFloat highPrice = [highPriceString floatValue];
    [self setHighPrice:highPrice];
    CGFloat lowPrice = [lowPriceString floatValue];
    [self setLowPrice:lowPrice];
    
    if (afterHours) {
      NSString *afterHoursPriceString
        = [stockData objectForKey:kGoogleFinanceAfterHoursPriceKey];
      NSString *afterHoursChangeString
        = [stockData objectForKey:kGoogleFinanceAfterHoursChangeKey];
      NSString *afterHoursChangePercentageString
        = [stockData objectForKey:kGoogleFinanceAfterHoursChangePercentageKey];
      CGFloat afterHoursPrice = [afterHoursPriceString floatValue];
      [self setAfterHoursPrice:afterHoursPrice];
      
      if ([afterHoursChangeString length]
          && [afterHoursChangePercentageString length]) {
        afterHoursChangeString
          = [afterHoursChangeString stringByAppendingFormat:@" (%@%%)",
             afterHoursChangePercentageString];
        [self setAfterHoursChangeAndPercent:afterHoursChangeString];
        // Set the color red if the change is negative.
        CGFloat afterHoursChange = [afterHoursChangeString floatValue];
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
                [[self companyNameAndSymbol] string], jsonResponse);
  }
}

- (void)dataFetcher:(GDataHTTPFetcher *)fetcher
    failedWithError:(NSError *)error {
  [self setDataFetcher:nil];
  HGSLogDebug(@"Failed to retrieve stock data for '%@' with error %@",
              [[self companyNameAndSymbol] string], error);
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
  NSImage *chart = [[[NSImage alloc] initWithData:chartData] autorelease];
  [self setPriceChart:chart];
}

- (void)chartFetcher:(GDataHTTPFetcher *)fetcher
     failedWithError:(NSError *)error {
  [self setChartFetcher:nil];
  HGSLogDebug(@"Failed to retrieve stock chart for '%@' with error %@",
              [[self companyNameAndSymbol] string], error);
}

@end
