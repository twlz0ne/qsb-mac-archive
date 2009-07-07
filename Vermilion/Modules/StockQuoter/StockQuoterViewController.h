//
//  StockQuoterViewController.h
//  QSB
//
//  Created by mrossetti on 7/2/09.
//  Copyright 2009 Google Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@class GDataHTTPFetcher;
@class HGSResult;

@interface StockQuoterViewController : NSViewController {
 @private
  HGSResult *result_;
  NSAttributedString *companyNameAndSymbol_;
  CGFloat openMarketPrice_;
  NSString *openMarketChangeAndPercent_;
  CGFloat highPrice_;
  CGFloat lowPrice_;
  BOOL afterHours_;
  CGFloat afterHoursPrice_;
  NSString *afterHoursChangeAndPercent_;
  NSImage *priceChart_;
  GDataHTTPFetcher *dataFetcher_;
  GDataHTTPFetcher *chartFetcher_;
  NSColor *openMarketChangeColor_;
  NSColor *afterHoursChangeColor_;
}

@property (readonly, nonatomic, retain) NSAttributedString *companyNameAndSymbol;
@property (readonly, nonatomic, assign) CGFloat openMarketPrice;
@property (readonly, nonatomic, retain) NSString *openMarketChangeAndPercent;
@property (readonly, nonatomic, assign) CGFloat highPrice;
@property (readonly, nonatomic, assign) CGFloat lowPrice;
@property (readonly, nonatomic, assign) BOOL afterHours;
@property (readonly, nonatomic, assign) CGFloat afterHoursPrice;
@property (readonly, nonatomic, retain) NSString *afterHoursChangeAndPercent;
@property (readonly, nonatomic, retain) NSImage *priceChart;
@property (readonly, nonatomic, retain) NSColor *openMarketChangeColor;
@property (readonly, nonatomic, retain) NSColor *afterHoursChangeColor;

@end
