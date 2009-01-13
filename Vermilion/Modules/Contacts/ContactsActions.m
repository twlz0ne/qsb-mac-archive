//
//  ContactsActions.m
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
#import <AddressBook/AddressBook.h>

@interface ContactEmailAction : HGSAction
@end

@interface ContactChatAction : HGSAction
@end

@interface ContactTextChatAction : ContactChatAction
@end

@interface ContactVideoChatAction : ContactChatAction
@end

@interface ContactAudioChatAction : ContactChatAction
@end


@implementation ContactEmailAction 

- (BOOL)doesActionApplyTo:(HGSObject*)result {
  // just check for an email address (since the directObjectType filter will
  // do the rest).
  NSString *emailAddress 
    = [result valueForKey:kHGSObjectAttributeContactEmailKey];
  return emailAddress != nil;
}

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *emailAddress 
    = [object valueForKey:kHGSObjectAttributeContactEmailKey];
  
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSString *urlString = [NSString stringWithFormat:@"mailto:%@", emailAddress];
  NSURL *url = [NSURL URLWithString:urlString];
  return [ws openURL:url];
}

@end

@implementation ContactChatAction

- (BOOL)doesActionApplyTo:(HGSObject*)result {
  // just check for a chat. We only check for Jabber and AIM because that's
  // what iChat handles.
  BOOL isGood = NO;
  NSString *recordIdentifier 
    = [result valueForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  if (recordIdentifier) {
    ABAddressBook *addressBook = [ABAddressBook sharedAddressBook];
    ABRecord *person = [addressBook recordForUniqueId:recordIdentifier];
    if (person) {
      ABMultiValue *chatAddresses
        = [person valueForProperty:kABAIMInstantProperty];
      if ([chatAddresses count] == 0) {
        chatAddresses = [person valueForProperty:kABJabberInstantProperty];
      }
      isGood = [chatAddresses count] > 0;
    }
  }
  return isGood;
}

@end


@implementation ContactTextChatAction


- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *abID 
    = [object valueForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  // TODO(alcor): add support for ichat:compose?service=AIM&id=Somebody style 
  // urls so they don't have to be in your address book (google contacts, etc.)
  NSString *urlString 
    = [NSString stringWithFormat:@"iChat:compose?card=%@&style=im", abID];
  NSURL *url = [NSURL URLWithString:urlString];
  return [ws openURL:url];
}

@end


@implementation ContactVideoChatAction

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *abID 
    = [object valueForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  // TODO(alcor): add support for ichat:compose?service=AIM&id=Somebody style 
  // urls so they don't have to be in your address book (google contacts, etc.)
  NSString *urlString 
    = [NSString stringWithFormat:@"iChat:compose?card=%@&style=videochat", 
       abID];
  NSURL *url = [NSURL URLWithString:urlString];
  return [ws openURL:url];
}

@end



@implementation ContactAudioChatAction

- (BOOL)performActionWithInfo:(NSDictionary*)info {
  HGSObject *object = [info valueForKey:kHGSActionPrimaryObjectKey];
  NSString *abID 
    = [object valueForKey:kHGSObjectAttributeAddressBookRecordIdentifierKey];
  
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  // TODO(alcor): add support for ichat:compose?service=AIM&id=Somebody style 
  // urls so they don't have to be in your address book (google contacts, etc.)
  NSString *urlString 
    = [NSString stringWithFormat:@"iChat:compose?card=%@&style=audiochat", 
       abID];
  NSURL *url = [NSURL URLWithString:urlString];
  return [ws openURL:url];
}

@end
