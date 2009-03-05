//
//  HGSDelegate.h
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

@class HGSCodeSignature;

typedef enum {
  eHGSAllowAlways = 1,  // Permanently allow the plugin
  eHGSAllowOnce = 2,    // Allow the plugin for this run of the application
  eHGSDisallow = 3      // Don't allow the plugin (ask again at next launch)
} HGSPluginLoadResult;

// This protocol is used for a delegate so the core HGS code can get information
// from the application it's running in w/o knowing about the packaging.
@protocol HGSDelegate

// Returns the path to the user level app support folder for the running app.
- (NSString *)userApplicationSupportFolderForApp;

// Returns the path to the user level cache folder for the running app.
- (NSString *)userCacheFolderForApp;

// Returns an array of strings w/ the plugin folders.
- (NSArray*)pluginFolders;

// TODO(dmaclach): revisit these and see how necessary they are
- (NSString *)navSuggestHost;

- (NSString *)suggestHost;

- (NSString *)suggestLanguage;

// Return the ID for the default action 
- (NSString *)defaultActionID;

// When a new plugin is loaded, this method is called to approve it. certRef
// will contain the certificate that was used to code sign the plugin
// bundle, or nil if the plugin bundle was unsigned or has an invalid
// signature.
- (HGSPluginLoadResult)shouldLoadPluginAtPath:(NSString *)path
                                withSignature:(HGSCodeSignature *)signature;

@end
