//
//  DirectoryServicesSearchSource.m
//
//  Copyright (c) 2009 Google Inc. All rights reserved.
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

#import <DirectoryService/DirectoryService.h>
#import <Vermilion/Vermilion.h>
#import "GTMNSString+URLArguments.h"

#define kTypeDirectoryServices HGS_SUBTYPE(kHGSTypeContact, @"ds")

static const UInt32 kInitialBufferSize = 65535;
// The minimum number of characters for non-pivot searches required
// before we will initiate a search
static const int kMinimumCharacterThreshold = 3;
// The number of characters in a query required before we switch from
// "exact match" to "starts with" (both case-insenstive)
static const int kExactMatchThreshold = 5;
static NSString *const kHGSDSEmailKey = @"HGSDSEmailKey";
static NSString *const kHGSDSPhoneNumberKey = @"HGSDSPhoneNumberKey";
static NSString *const kHGSDSMobileNumberKey = @"HGSDSMobileNumberKey";
static NSString *const kHGSDSHomeNumberKey = @"HGSDSHomeNumberKey";

// A list of account attributes that we want returned by our search
#define USER_ACCOUNT_ATTRIBUTES \
  kDS1AttrDistinguishedName, \
  "dsAttrTypeNative:cn", \
  "dsAttrTypeNative:uid", \
  kDSNAttrPhoneNumber, \
  "dsAttrTypeNative:telephoneNumber", \
  kDSNAttrMobileNumber, \
  "dsAttrTypeNative:mobile", \
  kDSNAttrHomePhoneNumber, \
  "dsAttrTypeNative:homePhone", \
  kDSNAttrEMailAddress, \
  "dsAttrTypeNative:mail", \
  kDSNAttrJobTitle, \
  "dsAttrTypeNative:title"

@interface DirectoryServicesSearchSource : HGSCallbackSearchSource
- (tDirNodeReference)openSearchNodeRef:(tDirReference)ref;
- (HGSResult *)resultForUserRecord:(tRecordEntry *)record
                       attrListRef:(tAttributeListRef)attrListRef
                        dataBuffer:(tDataBuffer *)dataBuffer
                        searchNode:(tDirNodeReference)searchNode
                               ref:(tDirReference)ref;
- (HGSResult *)pivotResultForDetail:(NSString *)detail
                               type:(NSString *)type
                               name:(NSString *)name;
@end

@implementation DirectoryServicesSearchSource

- (BOOL)isValidSourceForQuery:(HGSQuery *)query {
  BOOL isValidSource = NO;
  HGSResult *pivotObject = [query pivotObject];
  if (pivotObject) {
    if ([pivotObject isOfType:kTypeDirectoryServices]) {
      isValidSource = YES;
    }
  } else {
    if ([[query rawQueryString] length] >= kMinimumCharacterThreshold) {
      isValidSource = YES;
    }
  }
  return isValidSource;
}

- (HGSResult *)pivotResultForDetail:(NSString *)detail
                               type:(NSString *)type
                               name:(NSString *)name {
  NSImage *icon = [NSImage imageNamed:NSImageNameUser];
  NSMutableDictionary *attributes 
    = [NSMutableDictionary dictionaryWithObjectsAndKeys:
       icon, kHGSObjectAttributeIconKey,
       name, kHGSObjectAttributeSnippetKey,
       nil];
  NSString *scheme;
  if ([type isEqual:kHGSTypeTextEmailAddress]) {
    scheme = @"mailto:";
  } else {
    scheme = @"callto:";
  }
  NSString *urlString = [NSString stringWithFormat:@"%@:%@", scheme,
                         [detail gtm_stringByEscapingForURLArgument]];
  return [HGSResult resultWithURI:urlString
                             name:detail 
                             type:type 
                           source:self 
                       attributes:attributes];
}

- (void)performSearchOperation:(HGSSearchOperation*)operation {
  NSMutableArray *results = [NSMutableArray array];
  
  NSString *queryString = [[operation query] rawQueryString];
  HGSResult *pivotObject = [[operation query] pivotObject];
  if ([pivotObject conformsToType:kTypeDirectoryServices]) {
    NSMutableArray *unfilteredResults = [NSMutableArray array];
    
    NSString *email = [pivotObject valueForKey:kHGSDSEmailKey];
    if (email) {
      NSString *name
        = HGSLocalizedString(@"Email",
                             @"The display name of the email address account "
                             @"attribute");
      HGSResult *result = [self pivotResultForDetail:email
                                                type:kHGSTypeTextEmailAddress 
                                                name:name];
      [unfilteredResults addObject:result];
    }
    
    NSString *phoneNumber = [pivotObject valueForKey:kHGSDSPhoneNumberKey];
    if (phoneNumber) {
      NSString *name
        = HGSLocalizedString(@"Office",
                             @"The display name of the business phone number "
                             @"account attribute");
      HGSResult *result = [self pivotResultForDetail:phoneNumber
                                                type:kHGSTypeTextPhoneNumber 
                                                name:name];
      [unfilteredResults addObject:result];
    }
    
    NSString *mobileNumber = [pivotObject valueForKey:kHGSDSMobileNumberKey];
    if (mobileNumber) {
      NSString *name
        = HGSLocalizedString(@"Mobile",
                             @"The display name of the mobile phone number "
                             @"account attribute");
      HGSResult *result = [self pivotResultForDetail:mobileNumber
                                                type:kHGSTypeTextPhoneNumber 
                                                name:name];
      [unfilteredResults addObject:result];
    }
    
    NSString *homeNumber = [pivotObject valueForKey:kHGSDSPhoneNumberKey];
    if (homeNumber) {
      NSString *name
        = HGSLocalizedString(@"Home",
                             @"The display name of the home phone number "
                             @"account attribute");
      HGSResult *result = [self pivotResultForDetail:homeNumber
                                                type:kHGSTypeTextPhoneNumber 
                                                name:name];
      [unfilteredResults addObject:result];
    }
    
    if ([queryString length]) {
      for (HGSResult *result in unfilteredResults) {
        NSString *stringValue = [result displayName];
        if ([stringValue hasPrefix:queryString]) {
          [results addObject:result];
        }
      }
    } else {
      results = unfilteredResults;
    }
  } else {
    tDirReference ref;
    tDirStatus err = dsOpenDirService(&ref);
    if (err == eDSNoErr) {
      tDirNodeReference searchNode = [self openSearchNodeRef:ref];
      if (searchNode) {
        UInt32 dataBufferSize = kInitialBufferSize;
        tDataBuffer *dataBuffer = dsDataBufferAllocate(ref, dataBufferSize);
        if (dataBuffer) {
          tDataListPtr recordName
            = dsBuildListFromStrings(ref, [queryString UTF8String], NULL);
          if (recordName) {
            tDataListPtr recordType
              = dsBuildListFromStrings(ref, kDSStdRecordTypeUsers, NULL);
            if (recordType) {
              tDataListPtr attrType
                = dsBuildListFromStrings(ref, USER_ACCOUNT_ATTRIBUTES, NULL);
              if (attrType) {
                do {
                  UInt32 count;
                  tContextData context = 0;
                  tDirPatternMatch match 
                    = ([queryString length] >= kExactMatchThreshold) ?
                       eDSiStartsWith : eDSiExact;
                  err = dsGetRecordList(searchNode, dataBuffer, recordName,
                                        match, recordType, attrType,
                                        FALSE, &count, &context);
                  if (err == eDSNoErr) {
                    // DirectoryService indices are 1-based. No, really.
                    for (UInt32 recordIndex = 1; err == eDSNoErr;
                         ++recordIndex) {
                      tRecordEntry *recordEntry;
                      tAttributeListRef attrListRef = 0;
                      err = dsGetRecordEntry(searchNode, dataBuffer,
                                             recordIndex, &attrListRef,
                                             &recordEntry);
                      if (err == eDSNoErr) {
                        HGSResult *result
                          = [self resultForUserRecord:recordEntry
                                          attrListRef:attrListRef
                                           dataBuffer:dataBuffer
                                           searchNode:searchNode
                                                  ref:ref];
                        if (result) {
                          [results addObject:result];
                        }
                        dsCloseAttributeValueList(attrListRef);
                        dsDeallocRecordEntry(ref, recordEntry);
                      }
                    }
                    if (!context) {
                      break;
                    }
                  } else if (err == eDSBufferTooSmall) {
                    err = eDSNoErr;
                    dataBufferSize *= 2;
                    dsDataBufferDeAllocate(ref, dataBuffer);
                    dataBuffer = dsDataBufferAllocate(ref, dataBufferSize);
                    if (!dataBuffer) {
                      err = eMemoryAllocError;
                    }
                  }
                } while (err == eDSNoErr);
                dsDataListDeallocate(ref, attrType);
                free(attrType);
              }
              dsDataListDeallocate(ref, recordType);
              free(recordType);
            }
            dsDataListDeallocate(ref, recordName);
            free(recordName);
          }
          if (dataBuffer) {
            dsDataBufferDeAllocate(ref, dataBuffer);
          }
        }
        dsCloseDirNode(searchNode);
      }
      dsCloseDirService(ref);
    }
  }
  [operation setResults:results];
}

- (tDirNodeReference)openSearchNodeRef:(tDirReference)ref {
  tDirNodeReference searchNode = 0;
  tDirStatus err;
  UInt32 dataBufferSize = kInitialBufferSize;
  tDataBuffer *buffer = 0;
  if ((buffer = dsDataBufferAllocate(ref, dataBufferSize)) != NULL) {
    do {
      UInt32 count = 0;
      err = dsFindDirNodes(ref, buffer, NULL, eDSSearchNodeName, &count, NULL);
      if (err == eDSNoErr) {
        if (count == 1) {
          tDataList *dataList = NULL;
          err = dsGetDirNodeName(ref, buffer, 1, &dataList);
          if (err == eDSNoErr) {
            err = dsOpenDirNode(ref, dataList, &searchNode);
            dsDataListDeallocate(ref, dataList);
          }
        } else {
          err = eDSNodeNotFound;
        }
      }
      if (err == eDSBufferTooSmall) {
        err = eDSNoErr;
        dataBufferSize *= 2;
        dsDataBufferDeAllocate(ref, buffer);
        buffer = dsDataBufferAllocate(ref, dataBufferSize);
        if (!buffer) {
          HGSLogDebug(@"Directory Service plugin out of memory");
          break;
        }
      }
    } while (err == eDSBufferTooSmall);
  } else {
    HGSLogDebug(@"Directory Service plugin out of memory");
  }

  if (buffer) {
    dsDataBufferDeAllocate(ref, buffer);
  }
  
  return searchNode;
}

- (HGSResult *)resultForUserRecord:(tRecordEntry *)record
                       attrListRef:(tAttributeListRef)attrListRef
                        dataBuffer:(tDataBuffer *)dataBuffer
                        searchNode:(tDirNodeReference)searchNode
                               ref:(tDirReference)ref {
  HGSResult *result = nil;
  char *accountName = NULL;
  NSString *realName = nil;
  NSString *uid = nil;
  NSString *phoneNumber = nil;
  NSString *mobileNumber = nil;
  NSString *homeNumber = nil;
  NSString *email = nil;
  NSString *title = nil;
  
  tDirStatus err = dsGetRecordNameFromEntry(record, &accountName);
  if (err == eDSNoErr && accountName) {
    tAttributeEntry *attrEntry;
    tAttributeValueListRef valueListRef = 0;
    tDirStatus attrErr = eDSNoErr;
    for (UInt32 attrIndex = 1; attrErr == eDSNoErr; ++attrIndex) {
      attrErr = dsGetAttributeEntry(searchNode, dataBuffer,
                                    attrListRef, attrIndex, &valueListRef,
                                    &attrEntry);
      if (attrErr == eDSNoErr) {
        tAttributeValueEntry *valueEntry;
        attrErr = dsGetAttributeValue(searchNode, dataBuffer, 1,
                                      valueListRef, &valueEntry);
        if (attrErr == eDSNoErr) {
          // For the user's real name, accept kDS1AttrDistinguishedName and
          // dsAttrTypeNative:cn, preferring the former
          if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                     kDS1AttrDistinguishedName) == 0) {
            realName = [NSString stringWithUTF8String:
                        valueEntry->fAttributeValueData.fBufferData];
          } else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                            "dsAttrTypeNative:cn") == 0 && !realName) {
            realName = [NSString stringWithUTF8String:
                        valueEntry->fAttributeValueData.fBufferData];
          }

          // Username is either name on the record or dsAttrTypeNative:uid
          else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                          "dsAttrTypeNative:uid") == 0) {
            uid = [NSString stringWithUTF8String:
                   valueEntry->fAttributeValueData.fBufferData];
          }

          // Phone number can be either kDSNAttrPhoneNumber or
          // dsAttrTypeNative:telephoneNumber
          else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                          kDSNAttrPhoneNumber) == 0) {
            phoneNumber = [NSString stringWithUTF8String:
                           valueEntry->fAttributeValueData.fBufferData];
          } else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                            "dsAttrTypeNative:telephoneNumber") == 0 &&
                     !phoneNumber) {
            phoneNumber = [NSString stringWithUTF8String:
                           valueEntry->fAttributeValueData.fBufferData];
          }

          // Mobile number can be either kDSNAttrMobileNumber or
          // dsAttrTypeNative:mobile
          else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                          kDSNAttrMobileNumber) == 0) {
            mobileNumber = [NSString stringWithUTF8String:
                            valueEntry->fAttributeValueData.fBufferData];
          } else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                            "dsAttrTypeNative:mobile") == 0 &&
                     !mobileNumber) {
            mobileNumber = [NSString stringWithUTF8String:
                            valueEntry->fAttributeValueData.fBufferData];
          }

          // Home number can be either kDSNAttrHomePhoneNumber or
          // dsAttrTypeNative:homePhone
          else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                          kDSNAttrHomePhoneNumber) == 0) {
            homeNumber = [NSString stringWithUTF8String:
                          valueEntry->fAttributeValueData.fBufferData];
          } else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                            "dsAttrTypeNative:homePhone") == 0 &&
                     !homeNumber) {
            homeNumber = [NSString stringWithUTF8String:
                          valueEntry->fAttributeValueData.fBufferData];
          }

          // Email address can be either kDSNAttrEMailAddress or
          // dsAttrTypeNative:mail
          else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                          kDSNAttrEMailAddress) == 0) {
            email = [NSString stringWithUTF8String:
                     valueEntry->fAttributeValueData.fBufferData];
          } else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                            "dsAttrTypeNative:mail") == 0 && !email) {
            email = [NSString stringWithUTF8String:
                     valueEntry->fAttributeValueData.fBufferData];
          }

          // Title can be either kDSNAttrJobTitle or
          // dsAttrTypeNative:title
          else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                          kDSNAttrJobTitle) == 0) {
            title = [NSString stringWithUTF8String:
                     valueEntry->fAttributeValueData.fBufferData];
          } else if (strcmp(attrEntry->fAttributeSignature.fBufferData,
                            "dsAttrTypeNative:title") == 0 && !title) {
            title = [NSString stringWithUTF8String:
                     valueEntry->fAttributeValueData.fBufferData];
          }

          dsDeallocAttributeValueEntry(ref, valueEntry);
        }
        dsDeallocAttributeEntry(ref, attrEntry);
        dsCloseAttributeValueList(valueListRef);
      }
    }
  }
  
  if (!uid && accountName) {
    uid = [NSString stringWithUTF8String:accountName];
  }
  
  if (realName && email) {
    NSString *urlString = [NSString stringWithFormat:@"mailto:%@",
                           [email gtm_stringByEscapingForURLArgument]];
    NSString *displayName = [NSString stringWithFormat:@"%@ (%@)",
                             realName, uid];
    NSString *snippet = title ? title : email;
    NSImage *icon = [NSImage imageNamed:NSImageNameUser];
    NSMutableDictionary *attributes 
      = [NSMutableDictionary dictionaryWithObjectsAndKeys:
         icon, kHGSObjectAttributeIconKey,
         snippet, kHGSObjectAttributeSnippetKey,
         email, kHGSDSEmailKey,
         nil];
    if (phoneNumber) {
      [attributes setValue:phoneNumber forKey:kHGSDSPhoneNumberKey];
    }
    if (mobileNumber) {
      [attributes setValue:mobileNumber forKey:kHGSDSMobileNumberKey];
    }
    if (homeNumber) {
      [attributes setValue:homeNumber forKey:kHGSDSHomeNumberKey];
    }
    result = [HGSResult resultWithURI:urlString
                                 name:displayName
                                 type:kTypeDirectoryServices
                               source:self
                           attributes:attributes];
  }
  
  if (accountName) {
    free(accountName);
  }
  
  return result;
}

@end
