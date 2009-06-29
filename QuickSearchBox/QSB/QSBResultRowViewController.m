//
//  QSBResultRowViewController.m
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

#import "QSBResultRowViewController.h"
#import "Vermilion/Vermilion.h"
#import "GTMMethodCheck.h"

@implementation QSBResultRowViewController

// We use a private method here, so let's check and make sure it exists
GTM_METHOD_CHECK(NSViewController, _setTopLevelObjects:);

@synthesize searchViewController = searchViewController_;

- (id)initWithNib:(NSNib *)nib
       controller:(QSBSearchViewController *)searchViewController {
  // Instead of passing a name and bundle into NSViewController, we actually
  // cache the nib ourselves.
  if ((self = [super initWithNibName:nil
                              bundle:nil])) {
    searchViewController_ = [searchViewController retain];
    nib_ = [nib retain];
  }
  return self;
}

- (void)dealloc {
  [searchViewController_ release];
  [nib_ release];
  [super dealloc];
}

-(void)loadView {
  // Instead of loading the view by name and bundle, we use the nib we already
  // have cached.
  NSArray *topLevelObjects;
  BOOL loaded = [nib_ instantiateNibWithOwner:self 
                              topLevelObjects:&topLevelObjects];
  if (!loaded) {
    HGSLogDebug(@"Unable to instantiate %@ for %@", nib_, [self class]);
  } else {
    [self performSelector:NSSelectorFromString(@"_setTopLevelObjects:") 
               withObject:topLevelObjects];
  }
}

@end
