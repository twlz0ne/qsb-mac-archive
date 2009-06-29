//
//  QSBTopResultsViewControllers.m
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

#import "QSBTopResultsViewControllers.h"
#import "QSBTableResult.h"

#define QSBVIEWCONTROLLER_INIT(name) \
  static NSNib *nib = nil; \
  if (!nib) { \
    nib = [[NSNib alloc] initWithNibNamed:name \
                                   bundle:nil];\
  } \
  return [super initWithNib:nib \
                 controller:controller];

@implementation QSBTopStandardRowViewController

- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopStandardResultView")
}

- (NSAttributedString *)titleSourceURLStringForResult:(QSBTableResult *)result {
  return [result titleSnippetSourceURLString];
}

@end

@implementation QSBTopSeparatorRowViewController
- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopSeparatorResultView")
}
@end

@implementation QSBTopSearchForRowViewController
- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopSearchForResultView")
}
@end

@implementation QSBTopSearchIconViewController
- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopSearchIconResultView")
}
@end

@implementation QSBTopFoldRowViewController
- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopFoldResultView")
}
@end

@implementation QSBTopSearchStatusRowViewController
- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopSearchStatusResultView")
}
@end

@implementation QSBTopMessageRowViewController
- (id)initWithController:(QSBSearchViewController *)controller {
  QSBVIEWCONTROLLER_INIT(@"TopMessageResultView")
}
@end
