//
//  HGSAccountsExtensionPoint.m
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

#import "HGSAccountsExtensionPoint.h"
#import "GTMMethodCheck.h"
#import "GTMNSEnumerator+Filter.h"
#import "HGSAccount.h"
#import "HGSCoreExtensionPoints.h"
#import "HGSLog.h"


@implementation HGSAccountsExtensionPoint

GTM_METHOD_CHECK(NSEnumerator,
                 gtm_enumeratorByMakingEachObjectPerformSelector:withObject:);

- (void)dealloc {
  [accountTypes_ release];
  [super dealloc];
}

- (void)addAccountsFromArray:(NSArray *)accountsArray {
  for (NSDictionary *accountDict in accountsArray) {
    NSString *accountType = [accountDict objectForKey:kHGSAccountTypeKey];
    if (accountType) {
      Class accountClass = [self classForAccountType:accountType];
      id<HGSAccount> account = [[[accountClass alloc]
                                 initWithDictionary:accountDict]
                                autorelease];
      if (account) {
        [self extendWithObject:account];
      }
    } else {
      HGSLogDebug(@"Did not find account type for account dictionary :%@",
                  accountDict);
    }
  }
}

- (NSArray *)accountsAsArray {
  NSEnumerator *archiveAccountEnum
    = [[[self extensions] objectEnumerator]
       gtm_enumeratorByMakingEachObjectPerformSelector:@selector(dictionaryValue)
                                            withObject:nil];
  NSArray *archivableAccounts = [archiveAccountEnum allObjects];
  return archivableAccounts;
}

- (void)addAccountType:(NSString *)accountType withClass:(Class)accountClass {
  static NSString * const sVisibleAccountTypeNamesKey = @"visibleAccountTypeDisplayNames";
  [self willChangeValueForKey:sVisibleAccountTypeNamesKey];
  if (!accountTypes_) {
    accountTypes_ = [[NSMutableDictionary dictionaryWithObject:accountClass
                                                       forKey:accountType]
                     retain];
  } else {
    [accountTypes_ setObject:accountClass forKey:accountType];
  }
  [self didChangeValueForKey:sVisibleAccountTypeNamesKey];
}

- (Class)classForAccountType:(NSString *)accountType {
  Class accountClass = [accountTypes_ objectForKey:accountType];
  return accountClass;
}

- (NSArray *)visibleAccountTypeDisplayNames {
  NSMutableArray *visibleAccountTypeDisplayNames
    = [NSMutableArray arrayWithCapacity:[accountTypes_ count]];
  for (NSString *accountTypeName in accountTypes_) {
    // TODO(mrossetti): The following will not be required once we refactor
    // accounts and account types.  This is a temporary work-around.
    if (![accountTypeName isEqualToString:@"GoogleApps"]) {
      [visibleAccountTypeDisplayNames addObject:accountTypeName];
    }
  }
  return visibleAccountTypeDisplayNames;
}

- (NSArray *)accountsForType:(NSString *)type {
  NSPredicate *pred = [NSPredicate predicateWithFormat:@"type == %@", type];
  NSArray *array = [self extensions];
  array = [array filteredArrayUsingPredicate:pred];
  return array;
}

- (NSString *)description {
  NSString *description = [super description];
  description = [description stringByAppendingFormat:@"\naccountTypes: %@",
                 accountTypes_];
  return description;
}


@end

