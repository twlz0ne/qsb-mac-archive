//
//  HGSExtension.m
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

#import "HGSExtension.h"
#import "HGSProtoExtension.h"
#import "HGSLog.h"
#import "HGSBundle.h"

// Extension keys

NSString *const kHGSExtensionClassKey = @"HGSExtensionClass";
NSString *const kHGSExtensionPointKey = @"HGSExtensionPoint";
NSString *const kHGSExtensionIdentifierKey = @"HGSExtensionIdentifier";
NSString *const kHGSExtensionUserVisibleNameKey 
  = @"HGSExtensionUserVisibleName";
NSString *const kHGSExtensionIconImageKey = @"HGSExtensionIconImage";
NSString *const kHGSExtensionIconImagePathKey = @"HGSExtensionIconImagePath";
NSString *const kHGSExtensionEnabledKey = @"HGSExtensionEnabled";
NSString *const kHGSExtensionBundleKey = @"HGSExtensionBundle";
NSString *const kHGSExtensionDesiredAccountTypes
  = @"HGSExtensionDesiredAccountTypes";
NSString *const kHGSExtensionOfferedAccountType
  = @"HGSExtensionOfferedAccountType";
NSString *const kHGSExtensionOfferedAccountClass
  = @"HGSExtensionOfferedAccountClass";
NSString *const kHGSExtensionIsUserVisible = @"HGSExtensionIsUserVisible";
NSString *const kHGSExtensionIsEnabledByDefault 
  = @"HGSExtensionIsEnabledByDefault";
NSString *const kHGSExtensionAccount = @"HGSExtensionAccount";

// Notifications

NSString *const kHGSUserMessageNotification = @"HGSUserMessageNotification";

// Notification content keys
NSString *const kHGSSummaryMessageKey = @"HGSTextMessageKey";
NSString *const kHGSDescriptionMessageKey = @"HGSDescriptionMessageKey";
NSString *const kHGSImageMessageKey = @"HGSImageMessageKey";
NSString *const kHGSSuccessCodeMessageKey = @"HGSSuccessCodeMessageKey";

@implementation HGSExtension

@synthesize protoExtension = protoExtension_;
@synthesize displayName = displayName_;
@synthesize identifier = identifier_;
@synthesize bundle = bundle_;
@synthesize userVisible = userVisible_;

- (id)init {
  return [self initWithConfiguration:nil];
}

- (id)initWithConfiguration:(NSDictionary *)configuration {
  if ((self = [super init])) {
    bundle_ = [[configuration objectForKey:kHGSExtensionBundleKey] retain];
    if (!bundle_) {
      HGSLog(@"Extensions require bundles %@", configuration);
      [self release];
      return nil;
    }
    NSString *name 
      = [configuration objectForKey:kHGSExtensionUserVisibleNameKey];
    if (name) {
      // First check our InfoPlist.strings file
      NSString *localizedName = [bundle_ localizedStringForKey:name 
                                                         value:@"NOT_FOUND" 
                                                         table:@"InfoPlist"];
      if ([localizedName isEqualToString:@"NOT_FOUND"]) {
        // Then our Localizable.strings file
        localizedName = [bundle_ localizedStringForKey:name 
                                                 value:nil 
                                                 table:nil];
      }
      name = localizedName; 
    }
    NSString *iconPath
      = [configuration objectForKey:kHGSExtensionIconImagePathKey];
    NSString *identifier 
      = [configuration objectForKey:kHGSExtensionIdentifierKey];
    
    if ([configuration objectForKey:kHGSExtensionIconImageKey]) {
      HGSLog(@"We don't support setting kHGSExtensionIconImageKey. Use "
             @"kHGSExtensionIconImagePathKey instead.");
    }

    if (![identifier length]) {
      identifier = [self defaultObjectForKey:kHGSExtensionIdentifierKey];
     if (![identifier length]) {
        identifier = [self objectForInfoDictionaryKey:@"CFBundleIdentifier"];
        if (![identifier length]) {
          HGSLogDebug(@"Unable to get a identifier for %@", self);
          [self release];
          return nil;
        }
      }
    }
    identifier_ = [identifier copy];
    
    if (![name length]) {
      name = [self defaultObjectForKey:kHGSExtensionUserVisibleNameKey];
      if (![name length]) {
        name = [self objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        if (![name length]) {
          name = [self objectForInfoDictionaryKey:@"CFBundleName"];
          if (![name length]) {
            name = [self objectForInfoDictionaryKey:@"CFBundleExecutable"];
            if (![name length]) {
              HGSLogDebug(@"Unable to get a name for %@", self);
              name = HGSLocalizedString(@"Unknown Name", 
                                        @"A label denoting a plugin missing "
                                        @"it's name.");
            }
          }
        }
      }
    }
    displayName_ = [name copy];
    if (![iconPath length]) {
      iconPath = [self defaultObjectForKey:kHGSExtensionIconImagePathKey];
    }
    if ([iconPath length]) {
      if (![iconPath isAbsolutePath]) {
        NSString *partialIconPath = iconPath;
        iconPath = [bundle_ pathForImageResource:partialIconPath];
        if (!iconPath) {
          HGSLog(@"Unable to locate icon %@ in %@", partialIconPath, bundle_);
        }
      }
      iconPath_ = [iconPath copy];
    }
    NSNumber *userVisibleValue 
      = [configuration objectForKey:kHGSExtensionIsUserVisible];
    BOOL userVisible = (userVisibleValue) ? [userVisibleValue boolValue] : YES;
    [self setUserVisible:userVisible];
  }
  return self;
}

- (id)initWithConfiguration:(NSDictionary *)configuration
                      owner:(HGSProtoExtension *)owner {
  if ((self = [self initWithConfiguration:configuration])) {
    protoExtension_ = owner;
  }
  return self;
}

- (void)dealloc {
  [displayName_ release];
  [icon_ release];
  [iconPath_ release];
  [identifier_ release];
  [bundle_ release];
  [super dealloc];
}

- (NSString *)defaultIconName {
  return @"QSBPlugin";
}

// Return an icon that can be displayed 128x128.
- (NSImage *)icon {
  @synchronized(self) {
    if (!icon_) {
      if ([iconPath_ length]) {
        icon_ = [[NSImage alloc] initByReferencingFile:iconPath_];
        if (!icon_) {
          HGSLog(@"Unable to find image at %@", iconPath_);
        }
      } else {
        icon_ = [self defaultObjectForKey:kHGSExtensionIconImageKey];
        [icon_ retain];
      }
      [icon_ setSize:NSMakeSize(128, 128)];
    }
    if (!icon_) {
      static NSImage *defaultIcon = nil;
      @synchronized([self class]) {
        if (!defaultIcon) {
          defaultIcon = [[NSImage imageNamed:[self defaultIconName]] copy];
          [defaultIcon setSize:NSMakeSize(128,128)];
        }
      }
      icon_ = [defaultIcon retain];
    }
  }
  return [[icon_ retain] autorelease];
}

// Return a copyright string for the extension.
- (NSString *)copyright {
  return [self objectForInfoDictionaryKey:@"NSHumanReadableCopyright"];
}

// Return a description for the extension.
- (NSAttributedString *)extensionDescription {
  NSAttributedString *description = nil;
  NSString *extensions[] = {
    @"html",
    @"rtf",
    @"rtfd"
  };
  for (size_t i = 0; i < sizeof(extensions) / sizeof(NSString *); ++i) {
    NSString *path = [bundle_ pathForResource:@"Description"
                                       ofType:extensions[i]];
    if (path) {
      description 
        = [[[NSAttributedString alloc] initWithPath:path
                                 documentAttributes:nil] autorelease];
      if (description) {
        break;
      }
    }
  }
  return description;
}

// Return a version number for the extension.
- (NSString *)extensionVersion {
  return [self objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (id)objectForInfoDictionaryKey:(NSString *)key {
  id value = [bundle_ objectForInfoDictionaryKey:key];
  if (!value) {
    // We support storing strings in QSBInfo.plist files in cases where
    // using the standard Info.plist file is difficult (AppleScript).
    // We also do localization in QSBInfoPlist.strings.
    NSString *qsbPlistPath = [bundle_ pathForResource:@"QSBInfo" 
                                               ofType:@"plist"];
    if (qsbPlistPath) {
      NSDictionary *qsbPlist 
        = [NSDictionary dictionaryWithContentsOfFile:qsbPlistPath];
      value = [qsbPlist objectForKey:key];
      if ([value isKindOfClass:[NSString class]]) {
        // Attempt to localize
        value = [bundle_ localizedStringForKey:key
                                         value:value 
                                         table:@"QSBInfoPlist"];
      }
    }
  }
  return value;
}

- (id)defaultObjectForKey:(NSString *)key {
  // Override if you have a different mechanism for providing the
  // requested object.
  return nil;
}

- (NSString*)description {
  return [NSString stringWithFormat:@"%@<%p> identifier: %@, name: %@, "
          @"userVisible: %d", 
          [self class], self, [self identifier], [self displayName],
          [self userVisible]];
}

@end
