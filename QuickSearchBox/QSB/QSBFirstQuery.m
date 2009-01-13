//
//  QSBFirstQuery.m
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

#import "QSBFirstQuery.h"
#import "QSBPreferences.h"


@implementation QSBFirstQuery

- (void)dealloc {
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  [prefs removeObserver:self 
             forKeyPath:kQSBResultCountKey];
  [super dealloc];
}

- (void)awakeFromNib {  
  NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
  [prefs addObserver:self 
          forKeyPath:kQSBResultCountKey 
             options:NSKeyValueObservingOptionNew 
             context:nil];
  totalResultDisplayCount_ = [prefs integerForKey:kQSBResultCountKey];
}

- (NSUInteger)maximumResultsToCollect {
  return totalResultDisplayCount_;
}

- (BOOL)suppressMoreIfTopShowsAll {
  return YES;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object 
                        change:(NSDictionary *)change
                       context:(void *)context {
  if (object == [NSUserDefaults standardUserDefaults]) {
    if([keyPath isEqualToString:kQSBResultCountKey]) {
      NSNumber *valueOfChange = [change valueForKey:NSKeyValueChangeNewKey];
      totalResultDisplayCount_ = [valueOfChange unsignedIntegerValue];
      [self doDesktopQuery:nil];
    }
  }
}

@end
