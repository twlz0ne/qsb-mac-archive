//
//  KeychainItem.mm
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

#import "KeychainItem.h"
#import "HGSLog.h"

@interface KeychainItem()
- (KeychainItem*)initWithRef:(SecKeychainItemRef)ref;
- (void)loadKeychainData;
@end

@implementation KeychainItem
+ (KeychainItem*)keychainItemForService:(NSString*)serviceName
                               username:(NSString*)username {
  SecKeychainItemRef itemRef;
  const char* serviceCString = [serviceName UTF8String];
  UInt32 serviceLength = serviceCString ? (UInt32)strlen(serviceCString) : 0;
  const char* accountCString = [username UTF8String];
  UInt32 accountLength = accountCString ? (UInt32)strlen(accountCString) : 0;
  OSStatus result = SecKeychainFindGenericPassword(NULL,
                                                   serviceLength, serviceCString,
                                                   accountLength, accountCString,
                                                   0, NULL,
                                                   &itemRef);
  if (reportIfKeychainError(result)) {
      return nil;
  }

  return [[[KeychainItem alloc] initWithRef:itemRef] autorelease];
}

+ (KeychainItem*)keychainItemForHost:(NSString*)host
                            username:(NSString*)username {
  SecKeychainItemRef itemRef;
  const char* serverCString = [host UTF8String];
  UInt32 serverLength = serverCString ? (UInt32)strlen(serverCString) : 0;
  const char* accountCString = [username UTF8String];
  UInt32 accountLength = accountCString ? (UInt32)strlen(accountCString) : 0;
  OSStatus result = SecKeychainFindInternetPassword(NULL, serverLength, serverCString,
                                                    0, NULL, accountLength, accountCString,
                                                    0, NULL, kAnyPort, 0, 0,
                                                    NULL, NULL, &itemRef);
  if (reportIfKeychainError(result)) {
    return nil;
  }

  return [[[KeychainItem alloc] initWithRef:itemRef] autorelease];
}

+ (NSArray*)allKeychainItemsForService:(NSString*)serviceName
{
  SecKeychainAttribute attributes[1];

  const char* serviceCString = [serviceName UTF8String];
  attributes[0].tag = kSecServiceItemAttr;
  attributes[0].data = (void*)(serviceCString);
  attributes[0].length = (UInt32)strlen(serviceCString);

  SecKeychainAttributeList searchCriteria;
  searchCriteria.count = 1;
  searchCriteria.attr = attributes;

  SecKeychainSearchRef searchRef;
  OSStatus result = SecKeychainSearchCreateFromAttributes(NULL,
                                                          kSecGenericPasswordItemClass,
                                                          &searchCriteria,
                                                          &searchRef);
  if (reportIfKeychainError(result)) {
    return nil;
  }
  
  NSMutableArray* matchingItems = [NSMutableArray array];
  SecKeychainItemRef keychainItemRef;
  while (SecKeychainSearchCopyNext(searchRef, &keychainItemRef) == noErr) {
    [matchingItems addObject:[[[KeychainItem alloc] initWithRef:keychainItemRef] autorelease]];
  }
  CFRelease(searchRef);

  return matchingItems;
}

+ (KeychainItem*)addKeychainItemForService:(NSString*)serviceName
                              withUsername:(NSString*)username
                                  password:(NSString*)password
{
  const char* serviceCString = [serviceName UTF8String];
  UInt32 serviceLength = serviceCString ? (UInt32)strlen(serviceCString) : 0;
  const char* accountCString = [username UTF8String];
  UInt32 accountLength = accountCString ? (UInt32)strlen(accountCString) : 0;
  const char* passwordData = [password UTF8String];
  UInt32 passwordLength = passwordData ? (UInt32)strlen(passwordData) : 0;
  SecKeychainItemRef keychainItemRef;
  OSStatus result = SecKeychainAddGenericPassword(NULL, serviceLength, serviceCString,
                                                  accountLength, accountCString,
                                                  passwordLength, passwordData, &keychainItemRef);
  if (reportIfKeychainError(result)) {
    return nil;
  }

  return [[[KeychainItem alloc] initWithRef:keychainItemRef] autorelease];
}

- (KeychainItem*)initWithRef:(SecKeychainItemRef)ref {
  if ((self = [super init])) {
    mKeychainItemRef = ref;
    mDataLoaded = NO;
  }
  return self;
}

- (void)dealloc {
  if (mKeychainItemRef)
    CFRelease(mKeychainItemRef);
  [mUsername release];
  [mPassword release];
  [super dealloc];
}

- (void)loadKeychainData {
  if (!mKeychainItemRef)
    return;
  SecKeychainAttributeInfo attrInfo;
  UInt32 tags[1];
  tags[0] = kSecAccountItemAttr;
  attrInfo.count = (UInt32)(sizeof(tags)/sizeof(UInt32));
  attrInfo.tag = tags;
  attrInfo.format = NULL;

  SecKeychainAttributeList *attrList;
  UInt32 passwordLength;
  char* passwordData;
  OSStatus result = SecKeychainItemCopyAttributesAndData(mKeychainItemRef,
                                                         &attrInfo,
                                                         NULL,
                                                         &attrList,
                                                         &passwordLength,
                                                         (void**)(&passwordData));

  [mUsername autorelease];
  mUsername = nil;
  [mPassword autorelease];
  mPassword = nil;

  if (reportIfKeychainError(result)) {
    HGSLog(@"Couldn't load keychain data (error %d)", result);
    mUsername = [[NSString alloc] init];
    mPassword = [[NSString alloc] init];
    return;
  }

  for (unsigned int i = 0; i < attrList->count; i++) {
    SecKeychainAttribute attr = attrList->attr[i];
    if (attr.tag == kSecAccountItemAttr) {
      mUsername = [[NSString alloc] initWithBytes:(char*)(attr.data)
                                           length:attr.length
                                         encoding:NSUTF8StringEncoding];
    }
  }
  mPassword = [[NSString alloc] initWithBytes:passwordData
                                       length:passwordLength
                                     encoding:NSUTF8StringEncoding];
  reportIfKeychainError(SecKeychainItemFreeAttributesAndData(attrList,
                                                             (void*)passwordData));
  mDataLoaded = YES;
}

- (NSString*)username {
  if (!mDataLoaded)
    [self loadKeychainData];
  return mUsername;
}

- (NSString*)password {
  if (!mDataLoaded)
    [self loadKeychainData];
  return mPassword;
}

- (void)setUsername:(NSString*)username password:(NSString*)password {
  SecKeychainAttribute user;
  user.tag = kSecAccountItemAttr;
  const char* usernameString = [username UTF8String];
  user.data = (void*)usernameString;
  user.length = user.data ? (UInt32)strlen(user.data) : 0;
  SecKeychainAttributeList attrList;
  attrList.count = 1;
  attrList.attr = &user;
  const char* passwordData = [password UTF8String];
  UInt32 passwordLength = passwordData ? (UInt32)strlen(passwordData) : 0;
  if (!reportIfKeychainError(
       SecKeychainItemModifyAttributesAndData(mKeychainItemRef,
                                              &attrList,
                                              passwordLength,
                                              passwordData))) {
    [mUsername autorelease];
    mUsername = [username copy];
    [mPassword autorelease];
    mPassword = [password copy];
  }
}

- (void)removeFromKeychain {
  if (!reportIfKeychainError(SecKeychainItemDelete(mKeychainItemRef))) {
    mKeychainItemRef = nil;
  }
}

@end

BOOL reportIfKeychainError(OSStatus status) {
  BOOL wasError = NO;
  if (status != noErr) {
    if (status == wrPermErr) {
      HGSLog(@"A problem was detected while accessing the keychain (%d). "
             @"You may need to run Keychain First Aid to repair your "
             @"keychain.", status);
    } else {
      HGSLogDebug(@"A error occurred while accessing the keychain (%d).",
                  status);
    }
    wasError = YES;
  }
  return wasError;
}
