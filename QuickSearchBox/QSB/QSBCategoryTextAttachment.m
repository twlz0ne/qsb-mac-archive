//
//  QSBCategoryTextAttachment.m
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

#import "QSBCategoryTextAttachment.h"
#import "HGSLog.h"

@interface QSBCategoryTextAttachmentCell ()

+ (id)categoryTextAttachmentCellWithString:(NSString *)categoryString
                                     index:(NSUInteger)index;
- (id)initWithString:(NSString *)categoryString
               index:(NSUInteger)index;
@end


@implementation QSBCategoryTextAttachment

+ (id)categoryTextAttachmentWithString:(NSString *)categoryString
                                 index:(NSUInteger)idx {
  QSBCategoryTextAttachment *attachment
    = [[[QSBCategoryTextAttachment alloc] initWithString:categoryString
                                                  index:idx] autorelease];
  return attachment;
}

- (id)initWithString:(NSString *)categoryString
               index:(NSUInteger)idx {
    QSBCategoryTextAttachmentCell *cell
      = [QSBCategoryTextAttachmentCell categoryTextAttachmentCellWithString:categoryString
                                                                     index:idx];
  if (cell) {
    [self setAttachmentCell:cell];
  } else {
    [self release];
    self = nil;
  }
  return self;
}
      
- (id)init {
  HGSAssert(NO, @"Do not attempt to allocate QSBCategoryTextAttachment directly.");
  return [self initWithString:nil index:0];
}

@end


@implementation QSBCategoryTextAttachmentCell

+ (id)categoryTextAttachmentCellWithString:(NSString *)categoryString
                                     index:(NSUInteger)idx {
  QSBCategoryTextAttachmentCell *cell
    = [[[QSBCategoryTextAttachmentCell alloc] initWithString:categoryString
                                                      index:idx] autorelease];
  return cell;
}

- (id)initWithString:(NSString *)categoryString
               index:(NSUInteger)idx {
  if (categoryString && [categoryString length] && (self = [super init])) {
    categoryString_ = [categoryString retain];
    tableIndex_ = idx;
  } else {
    [self release];
    self = nil;
  }
  return self;
}

- (void)dealloc {
  [categoryString_ release];
  [super dealloc];
}

- (NSString *)categoryString {
  return [[categoryString_ retain] autorelease];
}

- (NSUInteger)tableIndex {
  return tableIndex_;
}

- (NSDictionary*)attributes {
  NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
  NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
                              font, NSFontAttributeName,
                              [NSColor darkGrayColor], NSForegroundColorAttributeName,
                              nil];
  return attributes;
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)aView {
  cellFrame.origin.y += 2.0;
  [categoryString_ drawInRect:cellFrame withAttributes:[self attributes]];
}

- (NSSize)cellSize {
  NSSize size = [categoryString_ sizeWithAttributes:[self attributes]];
  size.width += 1.0;
  return size;
}

@end
