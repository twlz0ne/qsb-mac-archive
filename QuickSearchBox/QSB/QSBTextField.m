//
//  QSBTextField.m
//
//  Copyright (c) 2006-2008 Google Inc. All rights reserved.
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

#import "QSBTextField.h"
#import "GTMMethodCheck.h"
#import "GTMNSEnumerator+Filter.h"
#import "NSString+CaseInsensitive.h"

@implementation QSBTextFieldEditor

GTM_METHOD_CHECK(NSEnumerator,
                 gtm_enumeratorByMakingEachObjectPerformSelector:withObject:);
GTM_METHOD_CHECK(NSString, qsb_hasPrefix:options:)

- (void)awakeFromNib {
  [self setEditable:YES];
  [self setFieldEditor:YES];
  [self setSelectable:YES];
}

- (void)deleteCompletion {
  if (lastCompletionRange_.length > 0) {
    NSTextStorage *storage = [self textStorage];
    NSRange intersection = NSIntersectionRange(lastCompletionRange_, 
                                               NSMakeRange(0, [storage length]));
    
    if (intersection.length > 0) {
      [storage beginEditing];
      [storage deleteCharactersInRange:intersection];
      [storage endEditing];
    }
    lastCompletionRange_ = NSMakeRange(0,0);
  }
}

- (void)resetCompletion {
  [self deleteCompletion];
  lastCompletionRange_ = NSMakeRange(0,0);
}

- (void)keyDown:(NSEvent *)theEvent {
  [self deleteCompletion];
  [super keyDown:theEvent];
}

- (void)copy:(id)sender {
  BOOL handled = NO;
  if ([self selectedRange].length == 0) {
    NSResponder *nextResponder = [self nextResponder];
    handled = [nextResponder tryToPerform:_cmd with:sender];
  }
  if (!handled) {
    [super copy:sender];
  }
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem {
  BOOL validated = NO;
  if ([anItem action] == @selector(copy:)) {
    NSResponder *nextResponder = [self nextResponder];
    validated = [nextResponder tryToPerform:_cmd with:anItem];
  } else {
    validated = [super validateUserInterfaceItem:anItem];
  }
  return validated;
}

- (void)didChangeText {
  [super didChangeText];
  [self complete:self];
}

- (void)complete:(id)sender {
  [self deleteCompletion];
  NSTextStorage *storage = [self textStorage];
  NSRange range = NSMakeRange(0, [storage length]);
  NSInteger idx = 0;
  NSArray *completions = [self completionsForPartialWordRange:range 
                                          indexOfSelectedItem:&idx];
  if ([completions count]) {
    NSString *completion = [completions objectAtIndex:0];
    if ([completion length]) {
      [self insertCompletion:completion
         forPartialWordRange:range
                    movement:0
                     isFinal:YES];
    }
  }
}

- (void)insertCompletion:(NSString *)completion 
     forPartialWordRange:(NSRange)charRange 
                movement:(int)movement
                 isFinal:(BOOL)flag {
  if ([self hasMarkedText]) {
    return;
  }
  if ([completion length]) {
    NSTextStorage *storage = [self textStorage];
    NSArray *selection = [self selectedRanges];
    NSRange stringRange = NSMakeRange(0, [storage length]);
    [storage beginEditing];
    
    NSString *typedString = [[self string] substringWithRange:charRange];
    NSRange substringRange = [completion rangeOfString:typedString
                                               options:(NSWidthInsensitiveSearch 
                                                        | NSCaseInsensitiveSearch
                                                        | NSDiacriticInsensitiveSearch)];
    
    // If this string isn't found at the beginning or with a space prefix,
    // find the range of the last word and proceed with that.
    if (substringRange.location == NSNotFound || (substringRange.location &&
            [completion characterAtIndex:substringRange.location - 1] != ' ')) {
      NSString *lastWord =
      [[typedString componentsSeparatedByString:@" "] lastObject];
      substringRange = [completion rangeOfString:lastWord
                                         options:(NSWidthInsensitiveSearch 
                                                  | NSCaseInsensitiveSearch
                                                  | NSDiacriticInsensitiveSearch)];
    }
    
    NSString *wordCompletion = @"";
    
    // Make sure we don't capitalize what the user typed
    if (substringRange.location == 0 
        && [completion length] >= stringRange.length) {
    
      completion = [typedString stringByAppendingString:
                     [completion substringFromIndex:stringRange.length]];
      
    // if our search string appears at the beginning of a word later in the
    // string, pull the remainder of the word out as a completion
    } else if (substringRange.location != NSNotFound 
               && substringRange.location
               && [completion characterAtIndex:substringRange.location - 1] == ' ') {
      NSRange wordRange = NSMakeRange(NSMaxRange(substringRange), 
                              [completion length] - NSMaxRange(substringRange));
      // Complete the current word
      NSRange nextSpaceRange = [completion rangeOfString:@" "
                                                 options:0
                                                   range:wordRange];
      
      if (nextSpaceRange.location != NSNotFound) 
        wordRange.length = nextSpaceRange.location - wordRange.location;
      
      wordCompletion = [completion substringWithRange:wordRange];
    }
  
    NSString *textFieldString = [storage string];
    if ([completion qsb_hasPrefix:textFieldString 
                          options:(NSWidthInsensitiveSearch 
                                   | NSCaseInsensitiveSearch
                                   | NSDiacriticInsensitiveSearch)]) {
      [storage replaceCharactersInRange:charRange withString:completion];
      lastCompletionRange_ = NSMakeRange(NSMaxRange(stringRange), 
                                         [completion length] - charRange.length);
    } else {
      NSString *appendString = [NSString stringWithFormat:@"%@ (%@)",
                                                          wordCompletion, 
                                                          completion];
      NSUInteger length = [storage length];
      [storage replaceCharactersInRange:NSMakeRange(length, 0) 
                             withString:appendString];
      lastCompletionRange_ = NSMakeRange(length, [appendString length]);
    }

    [storage addAttribute:NSForegroundColorAttributeName 
                    value:[NSColor lightGrayColor] 
                    range:lastCompletionRange_];
    // Allow ligatures but then beat them into submission over 
    // the auto-completion.
    if (lastCompletionRange_.location > 0 && lastCompletionRange_.length > 0) {
      NSUInteger fullLength = NSMaxRange(lastCompletionRange_);
      NSRange ligatureRange = NSMakeRange(0, fullLength);
      [storage addAttribute:NSLigatureAttributeName 
                      value:[NSNumber numberWithInt:1] 
                      range:ligatureRange];
      // De-ligature over the typed/autocompleted transition.
      [storage addAttribute:NSLigatureAttributeName 
                      value:[NSNumber numberWithInt:0] 
                      range:lastCompletionRange_];
    }
    [storage endEditing];
    [self setSelectedRanges:selection];
  }
}

- (BOOL)isAtBeginning {
  NSRange range = [self selectedRange];
  return (range.length == 0 && range.location == 0);
}

- (BOOL)isAtEnd {
  BOOL isatEnd = NO;
  NSRange range = [self selectedRange];
  if (range.length == 0) {
    if (lastCompletionRange_.location > 0) {
      isatEnd = range.location >= lastCompletionRange_.location; 
    } else {
      isatEnd = range.location == [[self string] length]; 
    }
  }
  return isatEnd;
}

- (NSRange)removeCompletionIfNecessaryFromSelection:(NSRange)selection {
  if (lastCompletionRange_.length > 0 && 
      NSMaxRange(selection) > lastCompletionRange_.location) {
    selection.length -= lastCompletionRange_.location - selection.location;
    [self deleteCompletion];
  }
  return selection;
}

- (void)setSelectedRanges:(NSArray *)rangeValues
                 affinity:(NSSelectionAffinity)affinity
           stillSelecting:(BOOL)stillSelectingFlag {
  NSArray *outRangeValues = rangeValues;
  if (lastCompletionRange_.length != 0) {
    NSMutableArray *newRangeValues
      = [NSMutableArray arrayWithCapacity:[rangeValues count]];
    for (NSValue *rangeValue in rangeValues) {
      NSRange range = [rangeValue rangeValue];
      if (lastCompletionRange_.location < NSMaxRange(range)) {
        if (range.location >= lastCompletionRange_.location) {
          range.location = lastCompletionRange_.location;
        }
        range.length = lastCompletionRange_.location - range.location;
      }
      [newRangeValues addObject:[NSValue valueWithRange:range]];
    }
    outRangeValues = newRangeValues;
  }
  // Adjust the selection ranges to prevent mid-glyph selections.
  NSString *fullString = [self string];
  NSEnumerator *adjustedRangeValuesEnum
    = [[outRangeValues objectEnumerator]
       gtm_enumeratorByMakingEachObjectPerformSelector:
        @selector(qsb_adjustRangeForComposedCharacterSequence:)
       withObject:fullString];
  outRangeValues = [adjustedRangeValuesEnum allObjects];
  [super setSelectedRanges:outRangeValues
                  affinity:affinity
            stillSelecting:stillSelectingFlag];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
  [self deleteCompletion];
  return [super draggingEntered:sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
  [self complete:self];
  [super draggingExited:sender];
}

@end

@implementation NSValue (qsb_adjustRangeForComposedCharacterSequence)

- (NSValue *)qsb_adjustRangeForComposedCharacterSequence:(NSString *)string {
  // Insure that the selection range does not start or end in the middle of
  // a composed character sequence.  If the selection is of zero length then
  // adjust the selection start forwards, otherwise adjust the selection start
  // backwards and the selection end forwards.
  NSValue *adjustedRangeValue = self;
  NSRange proposedRange = [self rangeValue];
  if (NSMaxRange(proposedRange) < [string length]) {
    // Adjust the selection start.
    NSRange adjustedRange
      = [string rangeOfComposedCharacterSequenceAtIndex:proposedRange.location];
    if (proposedRange.length) {
      // Adjust the selection end forward.
      NSUInteger selectionEnd = NSMaxRange(proposedRange) - 1;
      NSRange newEndRange
        = [string rangeOfComposedCharacterSequenceAtIndex:selectionEnd];
      NSUInteger adjustedSelectionEnd = NSMaxRange(newEndRange);
      adjustedRange.length = adjustedSelectionEnd - adjustedRange.location;
    } else {
      // When we have an empty selection and the adjusted length
      // is more than one character and start location has changed then
      // adjust selection start forward.
      if (adjustedRange.location != proposedRange.location
          && adjustedRange.length > 1) {
        adjustedRange.location += adjustedRange.length;
      }
      adjustedRange.length = 0;
    }
    adjustedRangeValue = [NSValue valueWithRange:adjustedRange];
  }
  return adjustedRangeValue;
}

@end
