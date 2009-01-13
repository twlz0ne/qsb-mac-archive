//
//  QSBUISettings.m
//
//  Copyright (c) 2007-2008 Google Inc. All rights reserved.
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

#import "QSBUISettings.h"
#import <Carbon/Carbon.h>

@implementation QSBUISettings

+ (NSShadow*)textShadow {
  NSShadow *aShadow = [[[NSShadow alloc] init] autorelease];
  [aShadow setShadowOffset:NSMakeSize(2,-2)];
  [aShadow setShadowBlurRadius:0];
  NSColor *shadowColor = [aShadow shadowColor];
  [aShadow setShadowColor:[shadowColor colorWithAlphaComponent:0.25]];
  return aShadow;
}

+ (NSShadow*)windowShadow {
  NSShadow *aShadow = [[[NSShadow alloc] init] autorelease];
  [aShadow setShadowOffset:NSMakeSize(5,-5)];
  [aShadow setShadowBlurRadius:1];
  NSColor *shadowColor = [aShadow shadowColor];
  [aShadow setShadowColor:[shadowColor colorWithAlphaComponent:0.5]];
  
  return aShadow;
}

+ (NSNumber*)obliqueness {
  return [NSNumber numberWithFloat:0.0f];
}

// Returns the text color for the "indexing" and "information" text
+ (NSColor*)bottomTextColor {
  return [[NSColor whiteColor] colorWithAlphaComponent:0.25];
}

// Returns the amount of time between two clicks to be considered a double click
+ (NSTimeInterval)doubleClickTime {
  static NSTimeInterval doubleClickThreshold = -1;
  
  if (doubleClickThreshold < 0) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    doubleClickThreshold 
      = [defaults doubleForKey:@"com.apple.mouse.doubleClickThreshold"];
    
    // if we couldn't find the value in the user defaults, take a 
    // conservative estimate
    if (doubleClickThreshold <= 0.0) {
      doubleClickThreshold = 1.0;
    }
  }
  return doubleClickThreshold;
}

@end
