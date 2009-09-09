//
//  main.m
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

#import <Cocoa/Cocoa.h>
#import "HGSLog.h"
#import <GoogleBreakpad/GoogleBreakpad.h>

// Breakpad is currently not 64 bits.
// TODO: Get rid of this when we have a 64 bit breakpad.
#define QSB_BUILD_WITH_BREAKPAD !__LP64__

int main(int argc, const char *argv[]) {
  // Need a local pool for breakpad plumbing
  NSAutoreleasePool *localPool = [[NSAutoreleasePool alloc] init];
  NSDictionary *plist = [[NSBundle mainBundle] infoDictionary];
  HGSAssert(plist, @"Unable to get our Info.plist");
#if QSB_BUILD_WITH_BREAKPAD
  GoogleBreakpadRef breakpad = GoogleBreakpadCreate(plist);
  HGSAssert(breakpad, @"Unable to initialize breakpad");
#endif  // QSB_BUILD_WITH_BREAKPAD
  
  // Go!
  int appValue = NSApplicationMain(argc,  (const char **) argv);
#if QSB_BUILD_WITH_BREAKPAD
  if (breakpad) {
    GoogleBreakpadRelease(breakpad);
  }
#endif  // QSB_BUILD_WITH_BREAKPAD
  [localPool release];
  return appValue;
}
