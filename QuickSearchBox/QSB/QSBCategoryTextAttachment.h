//
//  QSBCategoryTextAttachment.h
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

#import <Cocoa/Cocoa.h>

// Used while composing the string of category names at the bottom of 
// the 'More' view.  This allows a category to be clicked in that string
// which then scrolls the first result within that category into view.
//
@interface QSBCategoryTextAttachment : NSTextAttachment

+ (id)categoryTextAttachmentWithString:(NSString*)categoryString
                                 index:(NSUInteger)index;

- (id)initWithString:(NSString *)categoryString
               index:(NSUInteger)index;  // Designated initializer.

@end

// A cell presented within an attributed string representing a category
// and its position within the 'More' results table.  This is a helper
// class for QSBCategoryTextAttachment, above, and it is exposed publicly
// only to provide information about clicks within the category string
// shown at the bottom of the 'More' results table, and it is not intended to
// be allocated or otherwise modified.
//
@interface QSBCategoryTextAttachmentCell : NSTextAttachmentCell {
 @private
  NSString *categoryString_;
  NSUInteger tableIndex_;
}

// Return the string as presented in the category string.
- (NSString *)categoryString;

// Return the index of the first item of this category within the results table.
- (NSUInteger)tableIndex;

@end
