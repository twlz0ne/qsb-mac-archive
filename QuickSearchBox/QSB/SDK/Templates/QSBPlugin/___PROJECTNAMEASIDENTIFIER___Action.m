//
//  ___PROJECTNAMEASIDENTIFIER___Action.m
//  ___PROJECTNAME___
//
//  Created by ___FULLUSERNAME___ on ___DATE___.
//  Copyright ___ORGANIZATIONNAME___ ___YEAR___. All rights reserved.
//

#import <Vermilion/Vermilion.h>

@interface ___PROJECTNAMEASIDENTIFIER___Action : HGSAction
@end

@implementation  ___PROJECTNAMEASIDENTIFIER___Action

// Perform an action given a dictionary of info. For now, we are just passing
// in an array of direct objects, but there may be more keys added to future
// SDKs

- (BOOL)performWithInfo:(NSDictionary*)info {
  HGSResultArray *directObjects
    = [info objectForKey:kHGSActionDirectObjectsKey];
  BOOL success = NO;
  if (directObjects) {
    NSString *name = [directObjects displayName];
    [NSAlert alertWithMessageText:NSStringFromClass([self class])
                    defaultButton:HGSLocalizedString(@"OK", nil);
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:@"Action performed on %@", name];
    success = YES;
  }
  return success;
}
@end
