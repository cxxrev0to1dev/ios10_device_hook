#import <AdSupport/ASIdentifierManager.h>
#include "mobile_gestalt/mobile_gestalt.h"
#include <sys/sysctl.h>
#include <objc/runtime.h>

%hook ASIdentifierManager

- (NSUUID*)advertisingIdentifier {
    NSString* idfa = nil;
    if (cf_device&&[cf_device count]>0)
        idfa = [cf_device objectForKey:@"IDFA"];
    else
        InitCFDevice(0);
    NSLog(@"hook_IDFA: %@",idfa);
    return [[NSUUID alloc] initWithUUIDString:idfa];
}
%end
%hook UIDevice
-(NSUUID*)identifierForVendor{
    NSString* idfv = nil;
    if (cf_device&&[cf_device count]>0)
        idfv = [fake_device objectForKey:@"IDFV"];
    else
        InitCFDevice(0);
    NSLog(@"hook_IDFV: %@",idfv);
    return [[NSUUID alloc] initWithUUIDString:idfv];
}
%end
