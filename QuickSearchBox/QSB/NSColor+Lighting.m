//
//  NSColor+Lighting.m
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

#import "NSColor+Lighting.h"


@implementation NSColor (ColorAndLighting)

-(NSColor *)colorWithLighting:(CGFloat)light {
  return [self colorWithLighting:light plasticity:0];
}

-(NSColor *)colorWithLighting:(CGFloat)light plasticity:(CGFloat)plastic {
  if (plastic > 1) plastic = 1.0;
  if (plastic < 0) plastic = 0.0;
  NSColor *color = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  CGFloat h, s, b, a;
  
  [color getHue:&h
     saturation:&s brightness:&b alpha:&a];
  
  
  b += light;//*(1-plastic);
  //  float overflow=MAX(b-1.0,0);
  //  s=s-overflow*plastic;
  //QSLog(@"%f %f %f",brightness,saturation,overflow);
  
  color=[NSColor colorWithCalibratedHue:h
                             saturation:s
                             brightness:b
                                  alpha:a];  
  
  if (plastic > 0) { 
    CGFloat alpha = [color alphaComponent];
    NSColor *white = [NSColor colorWithCalibratedWhite:1.0 alpha:alpha];
    color = [color blendedColorWithFraction:plastic * light ofColor:white];
  }
  return color;
}

-(NSColor *)legibleTextColor {
  NSColor *textColor = nil;
  NSColor *calColor = [self colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
  if ([calColor brightnessComponent] > 0.5) {
    textColor = [NSColor blackColor];
  } else {
    textColor = [NSColor whiteColor];
  }
  return textColor;
}

@end
