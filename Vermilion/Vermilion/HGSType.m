//
//  HGSType.m
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

#import "HGSType.h"

NSString *HGSTypeForPath(NSString *path) {
  // TODO(dmaclach): probably need some way for third parties to muscle their
  // way in here and improve this map for their types.
  // TODO(dmaclach): combine this code with the SLFilesSource code so we
  // are only doing this in one place.
  FSRef ref;
  Boolean isDir = FALSE;
  OSStatus err = FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation],
                               &ref, 
                               &isDir);
  if (err != noErr) return nil;
  CFStringRef cfUTType = NULL;
  err = LSCopyItemAttribute(&ref, kLSRolesAll, 
                            kLSItemContentType, (CFTypeRef*)&cfUTType);
  if (err != noErr || !cfUTType) return nil;
  NSString *outType = nil;
  // Order of the map below is important as it's most specific first.
  // We don't want things matching to directories when they are packaged docs.
  struct {
    CFStringRef uttype;
    NSString *hgstype;
  } typeMap[] = {
    { kUTTypeContact, kHGSTypeContact },
    { kUTTypeMessage, kHGSTypeEmail },
    { CFSTR("com.apple.safari.history"), kHGSTypeWebHistory },
    { kUTTypeHTML, kHGSTypeWebpage },
    { kUTTypeApplication, kHGSTypeFileApplication },
    { kUTTypeAudio, kHGSTypeFileMusic },
    { kUTTypeImage, kHGSTypeFileImage },
    { kUTTypeMovie, kHGSTypeFileMovie },
    { kUTTypePlainText, kHGSTypeTextFile },
    { kUTTypePackage, kHGSTypeFile },
    { kUTTypeDirectory, kHGSTypeDirectory },
    { kUTTypeItem, kHGSTypeFile },
  };
  for (size_t i = 0; i < sizeof(typeMap) / sizeof(typeMap[0]); ++i) {
    if (UTTypeConformsTo(cfUTType, typeMap[i].uttype)) {
      outType = typeMap[i].hgstype;
      break;
    }
  }
  if (outType == kHGSTypeFile) {
    NSString *extension = [path pathExtension];
    if ([extension caseInsensitiveCompare:@"webloc"] == NSOrderedSame) {
      outType = kHGSTypeWebBookmark;
    }
  }  
  CFRelease(cfUTType);
  return outType;
}

BOOL HGSTypeConformsToType(NSString *type1, NSString *type2) {
  // Must have the exact prefix
  NSUInteger type2Len = [type2 length];
  BOOL result = type2Len > 0 && [type1 hasPrefix:type2];
  if (result &&
      ([type1 length] > type2Len)) {
    // If it's not an exact match, it has to have a '.' after the base type (we
    // don't count "foobar" as of type "foo", only "foo.bar" matches).
    unichar nextChar = [type1 characterAtIndex:type2Len];
    result = (nextChar == '.');
  }
  return result;
}
