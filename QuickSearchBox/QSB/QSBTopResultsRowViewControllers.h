//
//  QSBTopResultsRowViewControllers.h
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

/*!
 @header
 @discussion QSBTopResultsRowViewControllers
*/

#import "QSBDetailedRowViewController.h"

@class QSBTableResult;

/*!
 A row view controller for standard results showm in the Top results
 view.  When the result is assigned to the row the view layout is
 adjusted based on how much text is shown in the description.
 */
@interface QSBTopDetailedRowViewController : QSBDetailedRowViewController {
 @private
  /*! Remembers the default height of the main view. */
  CGFloat defaultViewHeight_;
  /*! Remembers the initial position of the text. */
  CGFloat defaultTextYOffset_;
  /*! Remembers the standard height of the text. */
  CGFloat defaultTextHeight_;
}

/*!
 The adjustments to the view metrics is performed when the results
 object is assigned to the view controller.
*/
- (void)setRepresentedObject:(id)object;

/*!
 Returns the detail string for a given result.
 Must be overridden by subclasses.
*/
- (NSAttributedString *)titleSourceURLStringForResult:(QSBTableResult *)result;

@end

@interface QSBTopStandardRowViewController : QSBTopDetailedRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
- (NSAttributedString *)titleSourceURLStringForResult:(QSBTableResult *)result;
@end

@interface QSBTopSeparatorRowViewController : QSBResultRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
@end

@interface QSBTopSearchForRowViewController : QSBResultRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
@end

@interface QSBTopSearchIconViewController : QSBResultRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
@end

@interface QSBTopFoldRowViewController : QSBResultRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
@end

@interface QSBTopSearchStatusRowViewController : QSBResultRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
@end

@interface QSBTopMessageRowViewController : QSBResultRowViewController
- (id)initWithController:(QSBSearchViewController *)controller;
@end
