//
//  AppleScriptPluginsAction.h
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

#import <Vermilion/Vermilion.h>

extern NSString *const kHGSAppleScriptPListVersionKey;  // int
extern const NSInteger kHGSAppleScriptCurrentVersion;
extern NSString *const kHGSAppleScriptScriptsKey;  // array of dictionaries

// kHGSAppleScriptScriptsKey keys
extern NSString *const kHGSAppleScriptDisplayNameKey;  // format string
extern NSString *const kHGSAppleScriptIconKey;  // relative path to bundle
extern NSString *const kHGSAppleScriptDescriptionKey;  // string
extern NSString *const kHGSAppleScriptHandlerKey;  // string
extern NSString *const kHGSAppleScriptDisplayInGlobalResultsKey;  // BOOL
extern NSString *const kHGSAppleScriptSupportedTypesKey;  // Array of string
extern NSString *const kHGSAppleScriptRequiredRunningAppKey;  // string (bundleid)
extern NSString *const kHGSAppleScriptSwitchContextsKey; // BOOL (default YES)

@interface AppleScriptPluginsAction : HGSAction {
 @private
  NSAppleScript *script_;  // the script we are running
  NSString *displayName_;  // the display name
  NSString *description_;
  NSString *handler_;  // the handler that this script calls
  BOOL displayInGlobalResults_;  // do we want it displayed in global results
  NSString *requiredRunningAppBundleID_;  // only display when this app is up
  NSSet *supportedTypes_;  // set of types we support
  BOOL switchContexts_;  //  should we switch contexts when run
}

- (id)initWithScript:(NSAppleScript *)script 
                path:(NSString *)path
          attributes:(NSDictionary *)attributes;
@end

