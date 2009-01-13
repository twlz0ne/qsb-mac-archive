//
//  QSBDetailedRowViewController.m
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

#import "QSBDetailedRowViewController.h"
#import "HGSLog.h"
#import "QSBTableResult.h"

@implementation QSBDetailedRowViewController

- (void)awakeFromNib {
  // Remember our standard view height and text view y offset.
  defaultViewHeight_ = NSHeight([[self view] frame]);
  defaultTextYOffset_ = [detailView_ frame].origin.y;
  defaultTextHeight_ = NSHeight([detailView_ frame]);
  
  HGSAssert(detailView_, @"Broken connection in nib file '%@'."
            @"   Connect detailView_ to the result description NSTextField.",
            [self nibName]);
}

- (void)setRepresentedObject:(id)object {
  [super setRepresentedObject:object];
  BOOL isTableResult = [object isKindOfClass:[QSBTableResult class]];
  if (isTableResult) {
    // Reset the defaults.
    NSView *mainView = [self view];
    CGFloat mainWidth = NSWidth([mainView frame]);
    NSSize newViewSize = NSMakeSize(mainWidth, defaultViewHeight_);
    CGFloat originX = [detailView_ frame].origin.x;
    NSPoint textOrigin = NSMakePoint(originX, defaultTextYOffset_);
    CGFloat textWidth = NSWidth([detailView_ frame]);
    NSSize textSize = NSMakeSize(textWidth, defaultTextHeight_);
    
    // Adjust our view height and text position as necessary to accommodate
    // the title/snippet/description.
    QSBTableResult *result = object;
    NSAttributedString *resultDescription 
      = [self titleSourceURLStringForResult:result];
    CGFloat stringHeight = [resultDescription size].height;
    
    // If the height is less than the standard then we need to center the text
    // vertically in the containing view.  If the height is more than the
    // standard then we need to increase the height of the containing view.
    if (stringHeight < (defaultTextHeight_ - 0.5)) {
      CGFloat newOriginY = defaultTextYOffset_
        + ((defaultTextHeight_ - stringHeight) / 2.0);
      textOrigin = NSMakePoint(originX, newOriginY);
      textSize = NSMakeSize(textWidth, stringHeight);
    } else if (stringHeight > (defaultTextHeight_ + 0.5)) {
      CGFloat newViewHeight = stringHeight
        + (defaultViewHeight_ - defaultTextHeight_);
      newViewSize = NSMakeSize(mainWidth, newViewHeight);
      textSize = NSMakeSize(textWidth, stringHeight);
    }
    [mainView setFrameSize:newViewSize];
    [detailView_ setFrameOrigin:textOrigin];
    [detailView_ setFrameSize:textSize];
    
  } else {
    HGSLogDebug(@"The represented object must be a QSBTableResult.");
  }
}

- (NSAttributedString *)titleSourceURLStringForResult:(QSBTableResult *)result {
  HGSLogDebug(@"titleSourceURLStringForResult should be overridden by subclasses");
  return nil;
}
@end
