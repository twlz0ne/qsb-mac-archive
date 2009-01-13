//
//  QSBPreferences.h
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


#import "GTMHotKeyTextField.h"

@interface QSBPreferences : NSObject
+ (BOOL)registerDefaults; // register the default w/ NSUserDefaults
@end

// Number of suggestions
#define kQSBSuggestCountKey @"suggestCount" // int
#define kQSBNavSuggestCountKey @"navSuggestCount" // int

// int - QSB number of results in the menu
#define kQSBResultCountKey                    @"QSBResultCount"
#define kQSBResultCountMin                    5
#define kQSBResultCountMax                    15
#define kQSBResultCountDefault                5

// int - QSB number of more results shown per category
#define kQSBMoreCategoryResultCountKey        @"QSBMoreCategoryResultCount"
#define kQSBMoreCategoryResultCountMin        1
#define kQSBMoreCategoryResultCountMax        5
#define kQSBMoreCategoryResultCountDefault    3

// BOOL - QSB snippet display
#define kQSBSnippetsKey                       @"QSBSnippets"
#define kQSBSnippetsDefault                   YES

// Dictionary - Hot key information, see GMHotKeyUtils for keys
#define kQSBHotKeyKey                         @"QSBHotKey"
// Default hotkey is Command + Command
#define kQSBHotKeyDefault                     [NSDictionary dictionaryWithObjectsAndKeys: \
                                                 [NSNumber numberWithUnsignedInt:NSCommandKeyMask], \
                                                 kGTMHotKeyModifierFlagsKey, \
                                                 [NSNumber numberWithUnsignedInt:0], \
                                                 kGTMHotKeyKeyCodeKey, \
                                                 [NSNumber numberWithBool:YES], \
                                                 kGTMHotKeyDoubledModifierKey, \
                                                 nil]

#define kQSBIconInMenubarKey                  @"QSBIconInMenubar"
#define kQSBIconInMenubarDefault              NO
#define kQSBIconInDockKey                     @"QSBIconInDock"
#define kQSBIconInDockDefault                 YES
