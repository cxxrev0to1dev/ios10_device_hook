#import <dlfcn.h>
#import <stdio.h>
#import "substrate.h"

#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/in.h>
#include <net/if_dl.h>
#include <pthread.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <execinfo.h>
#include <signal.h>
#include <objc/runtime.h>
#include <CoreFoundation/CFData.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreFoundation/CFString.h>
#include <Foundation/NSData.h>
#include <CoreFoundation/CFData.h>
#include <Foundation/Foundation.h>
#include "mobile_gestalt/ISDevice.h"
#include "mobile_gestalt/mobile_gestalt.h"
#include "mobile_gestalt/NSCFData.h"
#include "logger/logger.m"
#include "app_rank/HookUtil.h"
#include "app_rank/Macro.h"
#include "third_party/IOKit/IOKitLib.h"
#include "third_party/uidevice-extension/UIDevice-IOKitExtensions.h"

static NSMutableDictionary* cf_device = nil;

OBJC_EXPORT const char *object_getClassName(id obj);

CFTypeRef GUdid(void){
  pthread_mutex_lock(&var_mutex);
  static CFStringRef value_udid = nil;
  while (!value_udid) {
    value_udid = GetConfigValue(@"UDID");
  }
  pthread_mutex_unlock(&var_mutex);
  return value_udid;
}
static BOOL IsArm64()
{
  static BOOL arm64 = NO ;
  static dispatch_once_t once ;
  dispatch_once(&once, ^{
    arm64 = sizeof(int *) == 8 ;
  });
  return arm64 ;
}
static NSData* dataFromHexString(NSString* str) {
  NSString *command = str;
  NSMutableData *commandToSend= [[NSMutableData alloc] init];
  unsigned char whole_byte;
  char byte_chars[5] = {'\0','\0','\0'};
  int i;
  for (i=0; i < [command length]/2; i++) {
    byte_chars[0] = [command characterAtIndex:i*2];
    byte_chars[1] = [command characterAtIndex:i*2+1];
    whole_byte = strtol(byte_chars, NULL, 16);
    [commandToSend appendBytes:&whole_byte length:1];
  }
  //NFLog(@"%@", commandToSend);
  //<xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx xxxxxxxx>
  NSData *immutableData = [NSData dataWithData:commandToSend];
  return immutableData;
}
static CFDataRef HexToByte(const char* hex_str){
  unsigned char val[1024] = {0};
  size_t length = strlen(hex_str);
  /* WARNING: no sanitization or error-checking whatsoever */
  for(size_t index = 0; index < length; index++) {
    sscanf(&hex_str[2*index], "%2hhx", &val[index]);
  }
  unsigned long val_length = (length / 2);
  return CFDataCreate(NULL, val, val_length);
}
/*
 From Apple open source: SecTrustSettings.c (APSL license)
 Return a (hex)string representation of a CFDataRef.
 */
static CFStringRef APCopyHexStringFromData(CFDataRef data)
{
  CFIndex ix, length;
  const UInt8 *bytes;
  CFMutableStringRef string;
  
  if (data) {
    length = CFDataGetLength(data);
    bytes = CFDataGetBytePtr(data);
  } else {
    length = 0;
    bytes = NULL;
  }
  string = CFStringCreateMutable(kCFAllocatorDefault, length * 2);
  for (ix = 0; ix < length; ++ix)
    CFStringAppendFormat(string, NULL, CFSTR("%02X"), bytes[ix]);
  
  return string;
}
/* Adapted from StackOverflow: */
/* http://stackoverflow.com/a/12535482 */
static CFDataRef APCopyDataFromHexString(CFStringRef string)
{
  CFIndex length = CFStringGetLength(string);
  CFIndex maxSize =CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8);
  char *cString = (char *)malloc(maxSize);
  CFStringGetCString(string, cString, maxSize, kCFStringEncodingUTF8);
  
  
  /* allocate the buffer */
  UInt8 * buffer = malloc((strlen(cString) / 2));
  
  char *h = cString; /* this will walk through the hex string */
  UInt8 *b = buffer; /* point inside the buffer */
  
  /* offset into this string is the numeric value */
  char translate[] = "0123456789abcdef";
  
  for ( ; *h; h += 2, ++b) /* go by twos through the hex string */
    *b = ((strchr(translate, *h) - translate) * 16) /* multiply leading digit by 16 */
    + ((strchr(translate, *(h+1)) - translate));
  
  CFDataRef data = CFDataCreate(kCFAllocatorDefault, buffer, (strlen(cString) / 2));
  free(cString);
  free(buffer);
  
  return data;
}
static int NumberCountOfString(NSString* str,const char a){
  int count=0;
  int len = (int)[str length];
  for(int i=0;i<len;i++){
    unsigned char c = [str characterAtIndex:0];
    if(c==a){
      count++;
    }
  }
  return count;
}
//////////////////////////////////////////////////////////
//MGCopyAnswer
//////////////////////////////////////////////////////////
static CFTypeRef (*HookNextMGCopyAnswer)(CFTypeRef prop,unsigned long);
static CFTypeRef (*HookMGCopyAnswer)(CFTypeRef prop);
static CFTypeRef CallHookFunc(CFTypeRef prop,unsigned long value,bool is_show){
  CFTypeRef result = nil;
  if (IsArm64()) {
    result = HookNextMGCopyAnswer(prop,value);
    if (is_show) {
      AFLog(@"hook_FN_MGCopyAnswer_prop_arm64:%@---value:%@",
            prop,result);
      if (result != nil) {
        AFLog(@"hook_FN_MGCopyAnswer_prop_arm64:%@---value:%@-type:%s",
              prop,result,object_getClassName(result));
      }
    }
  }
  else{
    result = HookMGCopyAnswer(prop);
    if (is_show) {
      AFLog(@"hook_FN_MGCopyAnswer_prop_armv7:%@---value:%@",
            prop,result);
      if (result != nil) {
        AFLog(@"hook_FN_MGCopyAnswer_prop_armv7:%@---value:%@-type:%s",
              prop,result,object_getClassName(result));
      }
    }
  }
  return result;
}
static void CFShowType(CFTypeRef err_test){
  if (err_test) {
    AFLog(@"CFShowType:%@!!!!!!!!!!!!!!!!",
          CFCopyTypeIDDescription(CFGetTypeID(err_test)));
  }
}
static bool IsNil(NSString* aString) {
  return !(aString && aString.length);
}
static bool IsCFData(CFTypeRef data){
  return (CFGetTypeID(data)==CFDataGetTypeID());
}
static bool IsCFString(CFTypeRef data){
  return (CFGetTypeID(data)==CFStringGetTypeID());
}
static CFStringRef ComToStrRef(CFTypeRef data){
  CFStringRef va = nil;
  if (data) {
    va = CFStringCreateWithFormat(NULL,NULL,CFSTR("%@"),data);
  }
  return va;
}
static int GetIdLength(CFTypeRef data){
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  CFShowType(data);
  if (!data) {
    NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    return 0;
  }
  if (CFGetTypeID(data)==CFStringGetTypeID()){
    NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    CFIndex len = CFStringGetLength((__bridge CFStringRef)data);
    return (int)len;
  }
  else if (CFGetTypeID(data) == CFDataGetTypeID()){
    NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    CFIndex len = CFDataGetLength((__bridge CFDataRef)data);
    return (int)len;
  }
  else{
    NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    return 0;
  }
}
static CFTypeRef MobileDeviceProp(NSString* ns_prop,
                                  CFTypeRef result){
  NFLog(@"hook_device_info: %@--->%@",ns_prop,result);
  bool is_eq = [ns_prop isEqual:@"SerialNumber"];
  bool is_eq_a = [ns_prop isEqual:@"VasUgeSzVyHdB27g2XpN0g"];
  NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
  if (is_eq||is_eq_a) {
    NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
    CFStringRef data = nil;
    NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
    data = ComToStrRef(GSerialNumber());
    NFLog(@"CFProp:%s-%d-%@",__PRETTY_FUNCTION__,__LINE__,
          data);
    CFShowType(data);
    NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
    if (data&&GetIdLength(data)>0) {
      NFLog(@"hook_serial_number:%@--->%@!!!!!!",result,data);
      CFRelease(result);
      result = data;
    }
    else{
      NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
    }
    
    return result;
  }
  NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
  is_eq = [ns_prop isEqual:@"TF31PAB6aO8KAbPyNKSxKA"];
  if (is_eq) {
    int64_t i1 = 0;
    CFNumberRef chip = nil;
    chip = GChip();
    CFShowType(chip);
    if (chip) {
      CFNumberGetValue(chip, kCFNumberSInt64Type, &i1);
      if (i1>0) {
        NFLog(@"hook_chip_identificati:%@--->%@!!!!",result,chip);
        CFRelease(result);
        result = chip;
      }
    }
    
    return result;
  }
  NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
  is_eq = [ns_prop isEqual:@"gI6iODv8MZuiP0IA+efJCw"];
  if (is_eq) {
    CFStringRef data = nil;
    data = ComToStrRef(GMacAddr());
    CFShowType(data);
    if (data&&GetIdLength(data)>0) {
      NFLog(@"hook_wifi_address:%@--->%@!!!!!!",result,data);
      CFRelease(result);
      result = data;
    }
    
    return result;
  }
  NFLog(@"CFProp:%s-%d",__PRETTY_FUNCTION__,__LINE__);
  is_eq = [ns_prop isEqual:@"k5lVWbXuiZHLA17KGiVUAA"];
  if (is_eq) {
    CFStringRef data = nil;
    data = ComToStrRef(GBlueAddr());
    CFShowType(data);
    if (data&&GetIdLength(data)>0) {
      NFLog(@"hook_blue_address:%@--->%@!!!!!!",result,data);
      CFRelease(result);
      result = data;
    }
    
    return result;
  }
  else{
    NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    return result;
  }
}
static void Show(NSString* title,NSString* msg){
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title
                                                  message:msg
                                                 delegate:nil
                                        cancelButtonTitle:@"OK"
                                        otherButtonTitles:nil];
  [alert show];
  [alert release];
}
void InitCFDevice(int arg_warring){
  cf_device = [[NSMutableDictionary alloc] init];
  for (int i=0;i<3;i++) {
    NSString *path = kPref;
    NSMutableDictionary* aa = [[NSMutableDictionary alloc] init];
    aa = [[NSMutableDictionary alloc] initWithContentsOfFile:path];
    NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* bundle_id = [[NSBundle mainBundle] bundleIdentifier];
    if ([bundle_id isEqual:@"com.apple.AppStore"]) {
      NSString* documents = [paths objectAtIndex:0];
      NSString* tt1 = @"Library/Caches/com.apple.AppStore";
      NSString* tt2 = @"Documents";
      documents = [documents stringByReplacingOccurrencesOfString:tt2 withString:tt1];
      FILE* fp = fopen("/tmp/appstore.sh","wb");
      fwrite("rm -rf ", 1, (sizeof("rm -rf ") - sizeof(char)), fp);
      fwrite([documents UTF8String], 1, [documents length], fp);
      fwrite("/Cache.db", 1, (sizeof("/Cache.db") - sizeof(char)), fp);
      fclose(fp);
      system("chmod +x /tmp/appstore.sh");
      //AFLog(@"debug:%@-%@",bundle_id,documents);
    }
    cf_device = [[NSMutableDictionary alloc] initWithDictionary:aa];
    if ([cf_device count]) {
      CFDataRef a;
      NSString* device_id = (NSString*)[cf_device objectForKey:@"UDID"];
      if (!device_id) {
        break;
      }
      a = APCopyDataFromHexString((__bridge CFStringRef)device_id);
      const UInt8* b = CFDataGetBytePtr(a);
      CFIndex c = CFDataGetLength(a);
      NSData* d = [[NSData alloc] initWithBytes:b length:c];
      //refences:http://blog.timac.org/?tag=mgcopyanswer
      CFBooleanRef bb = (CFBooleanRef)[aa objectForKey:@"UniqueDeviceID"];
      CFBooleanRef cc = (CFBooleanRef)[aa objectForKey:@"UniqueDeviceIDData"];
      if (CFBooleanGetValue(bb)==true||CFBooleanGetValue(cc)==true) {
        [cf_device setValue:device_id forKey:@"UniqueDeviceID"];
      }
      else{
        [cf_device setValue:nil forKey:@"UniqueDeviceID"];
      }
      if (CFBooleanGetValue(cc)==true) {
        [cf_device setValue:d forKey:@"UniqueDeviceIDData"];
      }
      else{
        [cf_device setValue:nil forKey:@"UniqueDeviceIDData"];
      }
      CFBooleanRef dd = (CFBooleanRef)[aa objectForKey:@"WifiAddressData"];
      CFBooleanRef ee = (CFBooleanRef)[aa objectForKey:@"BluetoothAddressData"];
      if (dd!=nil&&CFBooleanGetValue(dd)==true) {
        NSString* mac = (NSString*)[cf_device objectForKey:@"WifiAddress"];
        if (mac!=nil&&([mac length]>0)) {
          mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
          NSData* data = dataFromHexString(mac);
          [cf_device setValue:data forKey:@"WifiAddressData"];
        }
      }
      else{
        [cf_device setValue:nil forKey:@"WifiAddressData"];
      }
      if (ee!=nil&&CFBooleanGetValue(ee)==true) {
        NSString* ss1 = @"BluetoothAddress";
        NSString* buletooth = (NSString*)[cf_device objectForKey:ss1];
        if (buletooth!=nil&&([buletooth length]>0)) {
          buletooth = [buletooth stringByReplacingOccurrencesOfString:
                       @":" withString:@""];
          NSData* data = dataFromHexString(buletooth);
          [cf_device setValue:data forKey:@"BluetoothAddressData"];
        }
      }
      else{
        [cf_device setValue:nil forKey:@"BluetoothAddressData"];
      }
      CFRelease(a);
      break;
    }
  }
  if (![cf_device count]) {
    NFLog(@"cf_device init failed.");
  }
  else{
    NFLog(@"cf_device init ok:%@.",cf_device);
  }
}
static CFTypeRef HookDevice(CFTypeRef prop,unsigned long value){
  /*NSLog(@"debug:%s!!!!!!!!!!!!!!!!",__func__);
  NSString* ns_prop = (__bridge NSString*)prop;
  CFTypeRef result = CallHookFunc(prop,value,false);
  if (result == nil) {
    return result;
  }
  if(CFGetTypeID(result)==CFStringGetTypeID()&&
     [ns_prop isEqual:@"UniqueDeviceID"]){
    CFTypeRef uuid = GetConfigValue(@"UDID");
    if (GetIdLength(uuid)==0) {
      return CallHookFunc(prop,value,false);
    }
    if (CFGetTypeID(uuid)==CFStringGetTypeID()){
      NSLog(@"hook_udid_nsstring: %@--->%@",result,uuid);
      return CFStringCreateCopy(kCFAllocatorDefault,uuid);
    }
    else{
      return CallHookFunc(prop,value,false);
    }
  }
  if (CFGetTypeID(result) == CFDataGetTypeID()&&
      ([ns_prop isEqual:@"UniqueDeviceIDData"]||
       [ns_prop isEqual:@"nFRqKto/RuQAV1P+0/qkBA"])) {
        CFTypeRef uuid = GetConfigValue(@"UDID");
        if (GetIdLength(uuid)==0) {
          return CallHookFunc(prop,value,false);
        }
        if (CFGetTypeID(uuid) == CFStringGetTypeID()){
          NSData* data = dataFromHexString(uuid);
          NSLog(@"hook_udid_nsdata_a1: %@--->%@",result,data);
          return CFDataCreate(NULL, [data bytes],[data length]);
        }
        else if (CFGetTypeID(uuid) == CFDataGetTypeID()){
          NSLog(@"hook_udid_nsdata_b1: %@--->%@",result,uuid);
          return CFDataCreate(NULL,
                              CFDataGetBytePtr(uuid),
                              CFDataGetLength(uuid));
        }
        else{
          return CallHookFunc(prop,value,false);
        }
      }
  return result;*/
  CFTypeRef return_value = nil;
  return_value = CallHookFunc(prop,value,false);
  if (return_value==nil) {
    return return_value;
  }
  //AFLog(@"hook_key_no:%@=%@",prop,return_value);
  CFStringRef pkey = CFStringCreateCopy(kCFAllocatorDefault, prop);
  NSString* key = (NSString*)CFBridgingRelease(pkey);
  id aaaaa = [cf_device objectForKey:key];
  if (aaaaa==nil) {
    NSMutableDictionary *ud_key = nil;
    ud_key = [cf_device objectForKey:@"UniqueDeviceKey"];
    if (!ud_key) {
      return return_value;
    }
    id bbbbb = [ud_key objectForKey:key];
    if (bbbbb!=nil) {
      NSString* bbb = (NSString*)bbbbb;
      if ([cf_device objectForKey:bbb]) {
        //AFLog(@"hook_key_obfuscated:%@-%@-%@",key,return_value,
        //      [cf_device objectForKey:bbb]);
        return CFBridgingRetain([cf_device objectForKey:bbb]);
      }
    }
    return return_value;
  }
  //AFLog(@"hook_key:%@=%@--->%@",key,return_value,aaaaa);
  return CFBridgingRetain(aaaaa);
  //type:2
  //AFLog(@"function %s line:%d",__PRETTY_FUNCTION__,__LINE__);
  /*if (CFEqual(prop,CFSTR("UniqueDeviceID"))) {
    is_cfstring_udid = true;
    //AFLog(@"hook_UniqueDeviceID:%@ %@",key,aaa);
  }
  else if(CFEqual(prop,CFSTR("UniqueDeviceIDData"))){
    is_cfdata_udid = true;
    //AFLog(@"hook_UniqueDeviceIDData:%@ %@",key,aaa);
  }
  else if(CFEqual(prop, CFSTR("nFRqKto/RuQAV1P+0/qkBA"))){
    is_cfdata_udid = true;
    aaa = [cf_device objectForKey:@"UniqueDeviceIDData"];
    //AFLog(@"hook_UniqueDeviceIDData:%@ %@",key,aaa);
  }
  return CFBridgingRetain(aaa);
  /*if(IsCFString(return_value)&&is_cfstring_udid){
    while (udid_ref==nil) {
      udid_ref = GetConfigValue(@"UDID");
    }
    AFLog(@"hook_udid_cfstring: %@",udid_ref);
    return CFStringCreateCopy(kCFAllocatorDefault, udid_ref);
  }
  if (IsCFData(return_value)&&is_cfdata_udid) {
    while (udid_ref==nil) {
      udid_ref = GetConfigValue(@"UDID");
    }
    NSString* udid = (__bridge NSString*)udid_ref;
    NSData* data = dataFromHexString(udid);
    CFDataRef r = nil;
    r = CFDataCreate(kCFAllocatorDefault, [data bytes],[data length]);
    if (CFGetTypeID(r)==CFDataGetTypeID()) {
      if (CFDataGetLength(r)==20) {
        AFLog(@"hook_udid_nsdata_a1: %@",data);
        return r;
      }
    }
    AFLog(@"hook_udid_nsdata_failed");
    return return_value;
  }
  return return_value;*/
}
static CFTypeRef FN_NextMGCopyAnswer(
                                     CFTypeRef prop,
                                     unsigned long value){
  @autoreleasepool {
    CFTypeRef result;
    if (value!=0||prop==NULL||prop==nil) {
      result = HookNextMGCopyAnswer(prop,value);
    }
    else{
      result = HookDevice(prop,value);
    }
    return result;
  }
}
static CFTypeRef FN_MGCopyAnswer(CFTypeRef prop){
  @autoreleasepool {
    CFTypeRef result;
    if (prop==NULL||prop==nil) {
      result = HookMGCopyAnswer(prop);
    }
    else{
      result = HookDevice(prop,0);
    }
    return result;
  }
}

#define HOOK_IOKIT(RET, ...) \
  HOOK_FUNCTION(RET, /System/Library/Frameworks/IOKit.framework/Versions/A/IOKit, __VA_ARGS__)
HOOK_IOKIT(CFTypeRef,IORegistryEntrySearchCFProperty,
           io_registry_entry_t entry,
           const io_name_t plane,
           CFStringRef key,
           CFAllocatorRef allocator,
           IOOptionBits options){
  CFTypeRef daaa = _IORegistryEntrySearchCFProperty(entry,plane,
                                                    key,allocator,options);
  NFLog(@"%s:hook: %@",__func__,key);
  if (key!=nil&&(CFStringGetLength(key)>0)) {
    unsigned int mask = NSCaseInsensitiveSearch;
    NSString *key_str = (__bridge NSString*)key;
    if ([key_str compare:@"device-imei" options:mask]==NSOrderedSame) {
      //AFLog(@"%s:hook_serial: %@--->%@",__func__,key,daaa);
      NSString* ss1 = @"InternationalMobileEquipmentIdentity";
      CFTypeRef imei = [cf_device objectForKey:ss1];
      if (imei!=nil&&(GetIdLength(imei)>0)&&IsCFString(imei)) {
        return CFStringCreateCopy(kCFAllocatorDefault,imei);
      }
    }
    if ([key_str compare:@"local-mac-address" options:mask]==NSOrderedSame) {
      //AFLog(@"%s:hook_serial: %@--->%@",__func__,key,daaa);
      NSString* mac = (NSString*)[cf_device objectForKey:@"BluetoothAddress"];
      if (mac!=nil&&([mac length]>0)) {
        mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
        NSData* data = dataFromHexString(mac);
        return CFDataCreate(NULL, [data bytes],[data length]);
      }
    }
  }
  return daaa;
}
HOOK_IOKIT(CFTypeRef,IORegistryEntryCreateCFProperty,
           io_registry_entry_t entry,
           CFStringRef key,
           CFAllocatorRef allocator,
           IOOptionBits options){
  CFTypeRef result = nil;
  result = _IORegistryEntryCreateCFProperty(entry,key,allocator,options);
  if (result==nil){
    return result;
  }
  NSString* key_str = (__bridge NSString*)key;
  const char* ssss = [key_str UTF8String];
  const char target_key_a[] = "mac-address-wifi";
  const char target_key_b[] = "mac-address-bluetooth";
  unsigned int mask = NSCaseInsensitiveSearch;
  //AFLog(@"%s:hook_%@=%@",__func__,key,result);
  if([key_str compare:@"IOPlatformSerialNumber" options:mask]==NSOrderedSame){
    //AFLog(@"hook_%@--->%@!!!!!!",result,key);
    NSString* data = [[NSString alloc] init];
    data = [cf_device objectForKey:@"SerialNumber"];
    if (data!=nil&&[data length]>0) {
      result = (__bridge CFStringRef*)data;
    }
  }
  else if([key_str compare:@"IOMacAddress" options:mask]==NSOrderedSame){
    //AFLog(@"hook_%@--->%@!!!!!!",result,key);
    NSString* mac = (NSString*)[cf_device objectForKey:@"WifiAddress"];
    if (mac!=nil&&([mac length]>0)) {
      mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
      NSData* data = dataFromHexString(mac);
      return CFDataCreate(NULL, [data bytes],[data length]);
    }
  }
  else if([key_str compare:@"local-mac-address" options:mask]==NSOrderedSame){
    //AFLog(@"hook_%@--->%@!!!!!!",result,key);
    NSString* data = [[NSString alloc] init];
    data = [cf_device objectForKey:@"BluetoothAddress"];
    if (data!=nil&&[data length]>0) {
      NFLog(@"%s:hook_blue_address: %@=%@--->%@",__func__,key,result,data);
      result = (__bridge CFStringRef*)data;
    }
  }
  else if(!memcmp(ssss,target_key_a,sizeof(target_key_a)-sizeof(char))){
    //AFLog(@"hook_%@--->%@!!!!!!",result,key);
    NSString* mac = (NSString*)[cf_device objectForKey:@"WifiAddress"];
    if (mac!=nil&&([mac length]>0)) {
      mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
      NSData* data = dataFromHexString(mac);
      NFLog(@"hook_mac_address_b:%@--->%@!!!!!!",result,data);
      return CFDataCreate(NULL, [data bytes],[data length]);
    }
    return result;
  }
  else if(!memcmp(ssss,target_key_b,sizeof(target_key_b)-sizeof(char))){
    //AFLog(@"hook_%@--->%@!!!!!!",result,key);
    NSString* mac = (NSString*)[cf_device objectForKey:@"BluetoothAddress"];
    if (mac!=nil&&([mac length]>0)) {
      mac = [mac stringByReplacingOccurrencesOfString:@":" withString:@""];
      NSData* data = dataFromHexString(mac);
      NFLog(@"hook_bule_address_a:%@--->%@!!!!!!",result,data);
      return CFDataCreate(NULL, [data bytes],[data length]);
    }
    return result;
  }
  return result;
}

#define HOOK_CT(RET, ...) HOOK_FUNCTION(RET, /Symbols/System/Library/Frameworks/CoreTelephony.framework/CoreTelephony, __VA_ARGS__)

#if defined __ARM_ARCH_7__   || defined __ARM_ARCH_7A__ || \
  defined __ARM_ARCH_7R__  || defined __ARM_ARCH_7M__
HOOK_CT(void,_CTServerConnectionCopyMobileEquipmentInfo,
        CTResult* arg1,
        CTServerConnectionRef arg2,
        CFDictionaryRef *arg3){
  @autoreleasepool {
    __CTServerConnectionCopyMobileEquipmentInfo(arg1,arg2,arg3);
    if (CFDictionaryGetValue(arg3[0], CFSTR("kCTMobileEquipmentInfoIMEI"))){
      NSDictionary* ss0 = (__bridge NSDictionary*)arg3[0];
      NSString* ss1 = @"InternationalMobileEquipmentIdentity";
      NSMutableDictionary *ss3;
      ss3 = [[NSMutableDictionary alloc] initWithDictionary:ss0];
      NSString* ss4 = @"kCTMobileEquipmentInfoIMEI";
      id aaa = [cf_device objectForKey:ss1];
      if (aaa) {
        [ss3 setObject:aaa forKey:ss4];
      }
      *arg3 = ss3;
      //AFLog(@"ssssssssssss_armv7:%@",*arg2);
    }
    if (CFDictionaryGetValue(arg3[0], CFSTR("kCTMobileEquipmentInfoMEID"))){
      NSDictionary* ss0 = (__bridge NSDictionary*)arg3[0];
      NSString* ss1 = @"MobileEquipmentIdentifier";
      NSMutableDictionary *ss3;
      ss3 = [[NSMutableDictionary alloc] initWithDictionary:ss0];
      NSString* ss4 = @"kCTMobileEquipmentInfoMEID";
      id aaa = [cf_device objectForKey:ss1];
      if (aaa) {
        [ss3 setObject:aaa forKey:ss4];
      }
      *arg3 = ss3;
      //AFLog(@"ssssssssssss_armv7:%@",*arg2);
    }
  }
}
#endif

#if (defined(__aarch64__))
HOOK_CT(void,_CTServerConnectionCopyMobileEquipmentInfo,
        CTServerConnectionRef arg1,
        CFDictionaryRef* arg2,
        NSInteger* arg3){
  @autoreleasepool {
    __CTServerConnectionCopyMobileEquipmentInfo(arg1,arg2,arg3);
    if (CFDictionaryGetValue(arg2[0], CFSTR("kCTMobileEquipmentInfoIMEI"))){
      NSDictionary* ss0 = (__bridge NSDictionary*)arg2[0];
      NSString* ss1 = @"InternationalMobileEquipmentIdentity";
      NSMutableDictionary *ss3;
      ss3 = [[NSMutableDictionary alloc] initWithDictionary:ss0];
      NSString* ss4 = @"kCTMobileEquipmentInfoIMEI";
      id aaa = [cf_device objectForKey:ss1];
      if (aaa) {
        [ss3 setObject:aaa forKey:ss4];
      }
      *arg2 = ss3;
      //AFLog(@"ssssssssssss_arm64:%@",*arg2);
    }
    if (CFDictionaryGetValue(arg2[0], CFSTR("kCTMobileEquipmentInfoMEID"))){
      NSDictionary* ss0 = (__bridge NSDictionary*)arg2[0];
      NSString* ss1 = @"MobileEquipmentIdentifier";
      NSMutableDictionary *ss3;
      ss3 = [[NSMutableDictionary alloc] initWithDictionary:ss0];
      NSString* ss4 = @"kCTMobileEquipmentInfoMEID";
      id aaa = [cf_device objectForKey:ss1];
      if (aaa) {
        [ss3 setObject:aaa forKey:ss4];
      }
      *arg2 = ss3;
      //AFLog(@"ssssssssssss_arm64:%@",*arg2);
    }
  }
}
#endif

HOOK_MESSAGE(id,AADeviceInfo,appleIDClientIdentifier){
  NSString* ss1 = @"appleIDClientIdentifier";
  id aaa = [cf_device objectForKey:ss1];
  if (aaa==nil) {
    return _AADeviceInfo_appleIDClientIdentifier(self,sel);
  }
  return aaa;
}
//////////////////////////////////////////////////////////
//MGCopyMultipleAnswers
//////////////////////////////////////////////////////////
static CFPropertyListRef (*HookMGCopyMultipleAnswers)(CFArrayRef questions, int unknown0);
static CFPropertyListRef FnMGCopyMultipleAnswers(
                                                 CFArrayRef questions,
                                                 int unknown0){
  CFTypeRef return_val=HookMGCopyMultipleAnswers(questions,unknown0);
  NFLog(@"FnMGCopyMultipleAnswers:%@,%d return:%@",questions,unknown0,return_val);
  return return_val;
}
//////////////////////////////////////////////////////////
//hook function impl
//////////////////////////////////////////////////////////
static void MGCopyAnswerHookImpl(const void* ptr){
  HookMGCopyAnswer = NULL;
  HookNextMGCopyAnswer = NULL;
  if (IsArm64()) {
    MSHookFunction(((void*)((unsigned long)ptr + 8)),
                   (void*)FN_NextMGCopyAnswer,
                   (void**)&HookNextMGCopyAnswer);
    if(HookNextMGCopyAnswer!=NULL){
      NFLog(@"HookNextMGCopyAnswer success.");
    }
    else{
      NFLog(@"HookNextMGCopyAnswer failed.");
    }
  }
  else{
    MSHookFunction((void*)((unsigned long)ptr),
                   (void*)FN_MGCopyAnswer,
                   (void**)&HookMGCopyAnswer);
    if(HookMGCopyAnswer!=NULL){
      NFLog(@"HookMGCopyAnswer success.");
    }
    else{
      NFLog(@"HookMGCopyAnswer failed.");
    }
  }
}
static void MGCopyMultipleAnswersImpl(const void* ptr){
  HookMGCopyMultipleAnswers = NULL;
  MSHookFunction((void*)((unsigned long)ptr),
                 (void*)FnMGCopyMultipleAnswers,
                 (void**)&HookMGCopyMultipleAnswers);
  if(HookMGCopyMultipleAnswers!=NULL){
    NFLog(@"HookMGCopyMultipleAnswers success.");
  }
  else{
    NFLog(@"HookMGCopyMultipleAnswers failed.");
  }
}
//////////////////////////////////////////////////////////
//hook method impl
//////////////////////////////////////////////////////////
static void* (*old_dlsym)(void* handle,const char* symbol);
static void* newdlsym(void* handle,const char* symbol)
{
  //NFLog(@"debug:%s!!!!!!!!!!!!!!!!",__func__);
  void *p = NULL;
  if (old_dlsym!=NULL) {
    p = old_dlsym(handle,symbol);
  }
  if (p==NULL||symbol==NULL) {
    return p;
  }
  else if(!strcmp(symbol,"MGCopyAnswer")){
    NFLog(@"OK:%p!!!!!!!!!!!!!!!!!!",p);
    MGCopyAnswerHookImpl(p);
  }
  return p;
}
static void HookDlsym(){
  NFLog(@"OK_dlsym!!!!!!!!!!!!!!!!!!");
  MSHookFunction((void*)dlsym,
                 (void*)newdlsym,
                 (void**)&old_dlsym);
}
static void HookerForMGCopyAnswer(){
  const char* name = "MGCopyAnswer";
  MSImageRef image = MSGetImageByName("/usr/lib/libMobileGestalt.dylib");
  const void* ptr = MSFindSymbol(image, name);
  if (!ptr) {
    ptr = MSFindSymbol(image, "_MGCopyAnswer");
    if (!ptr) {
      ptr = MSFindSymbol(NULL, "_MGCopyAnswer");
    }
  }
  if (ptr!=NULL) {
    NFLog(@"MGCopyAnswer found:%p",ptr);
    MGCopyAnswerHookImpl(ptr);
    return;
  }
  else{
    NFLog(@"MGCopyAnswer failed:%p",ptr);
    HookDlsym();
    return;
  }
}
static void HookerForMGCopyMultipleAnswers(){
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  const char* name = "_MGCopyMultipleAnswers";
  const void* ptr = MSFindSymbol(NULL, name);
  if (ptr!=NULL) {
    NFLog(@"_MGCopyMultipleAnswers found:%p",ptr);
    MGCopyMultipleAnswersImpl(ptr);
    return;
  }
  else{
    HookDlsym();
  }
}
static void SSFormatLog(int n,NSString* format,...){
  va_list va;
  va_start(va, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:va];
  AFLog(@"n:%d %@",n,string);
  va_end(va);
}
static void SSDebugLogHookON(){
  void* aaa = MSFindSymbol(NULL, "_SSDebugLog");
  if (!aaa) {
    aaa = MSFindSymbol(NULL, "SSDebugLog");
    if (!aaa) {
      aaa = MSFindSymbol(NULL, "__SSDebugLog");
    }
  }
  if (aaa) {
    int64_t aaaaaaaaaaa = 0;
    MSHookFunction(aaa,(void*)SSFormatLog,(void**)&aaaaaaaaaaa);
  }
}
static CFTypeRef FetchDeviceAnswer(NSString* prop){
  static CFTypeRef(*MGCopyAnswer)(CFTypeRef prop) = nil;
  if (!MGCopyAnswer) {
    const char* name = "MGCopyAnswer";
    MSImageRef image = MSGetImageByName("/usr/lib/libMobileGestalt.dylib");
    const void* ptr = MSFindSymbol(image, name);
    if (!ptr) {
      ptr = MSFindSymbol(image, "_MGCopyAnswer");
      if (!ptr) {
        ptr = MSFindSymbol(NULL, "_MGCopyAnswer");
      }
    }
    MGCopyAnswer = (CFTypeRef(*)(CFTypeRef))ptr;
    if (!MGCopyAnswer) {
      return nil;
    }
  }
  return MGCopyAnswer(prop);
}
static void FetchDeviceData(){
  NSString *path = @"/private/var/preferences/system.plist";
  NSMutableDictionary* system;
  system = [NSMutableDictionary dictionaryWithContentsOfFile:path];
  NSArray* system_key = [system objectForKey:@"SystemKey"];
  for (int i = 0; i < system_key.count; i++){
    [system setValue:FetchDeviceAnswer(system_key[i]) forKey:system_key[i]];
  }
  AFLog(@"system:%@",system);
  [system writeToFile:path atomically:YES];
}
HOOK_MESSAGE(NSUUID*, ASIdentifierManager, advertisingIdentifier){
  static NSString* idfa = nil;
  if (!idfa) {
    CFStringRef idfa_s = (CFStringRef)[cf_device objectForKey:@"IDFA"];
    if ((idfa_s==nil)||(CFStringGetLength(idfa_s)==0)) {
      return _ASIdentifierManager_advertisingIdentifier(self,sel);
    }
    idfa = @(CFStringGetCStringPtr(idfa_s, kCFStringEncodingUTF8));
  }
  return [[NSUUID alloc] initWithUUIDString:[idfa copy]];
}
HOOK_MESSAGE(NSUUID*, UIDevice, identifierForVendor){
  static NSString* idfv = nil;
  if (!idfv) {
    CFStringRef idfv_s = (CFStringRef)[cf_device objectForKey:@"IDFV"];
    if ((idfv_s==nil)||(CFStringGetLength(idfv_s)==0)) {
      return _UIDevice_identifierForVendor(self,sel);
    }
    idfv = @(CFStringGetCStringPtr(idfv_s, kCFStringEncodingUTF8));
  }
  return [[NSUUID alloc] initWithUUIDString:[idfv copy]];
}
static void UpdateSystemVersion(){
  NSString *path = @"/System/Library/CoreServices/SystemVersion.plist";
  NSMutableDictionary* system_version = GetPlist(path);
  char* aa_bb[] = {"ProductVersion","ProductBuildVersion","BuildVersion",NULL};
  if ([cf_device objectForKey:@(aa_bb[0])]) {
    [system_version setValue:[cf_device objectForKey:@(aa_bb[0])] forKey:@(aa_bb[0])];
  }
  if ([cf_device objectForKey:@(aa_bb[2])]) {
    [system_version setValue:[cf_device objectForKey:@(aa_bb[1])] forKey:@(aa_bb[2])];
  }
  [system_version writeToFile:path atomically:YES];
}
//////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////

void MobileGestaltHooker(int arg_warring){
  @autoreleasepool {
    InitCFDevice(0);
    //UpdateSystemVersion();
    //FetchDeviceData();
    HookerForMGCopyAnswer();
    HookerForMGCopyMultipleAnswers();
  }
}
