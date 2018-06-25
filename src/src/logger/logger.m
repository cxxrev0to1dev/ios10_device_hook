//
//  SSLKillSwitch.m
//  SSLKillSwitch
//
//  Created by Alban Diquet on 7/10/15.
//  Copyright (c) 2015 Alban Diquet. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/SecureTransport.h>
#import "substrate.h"
#include <pthread.h>
#include <UIKit/UIKit.h>

#define SYSTEM_VERSION_EQUAL_TO(v)                  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v)              ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v)                 ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)


static NSString *_logDir = @"/tmp";
///private/var/mobile/Documents
#if __cplusplus
extern "C"
#endif
static void LogDataImpl(NSString* b,const void *data,
             size_t dataLength,void *returnAddress)
{
  if (data == nil || dataLength == 0)
    return;
  if (_logDir == nil){
    _logDir = [[NSString alloc] initWithFormat:@"/tmp/%@.req", NSProcessInfo.processInfo.processName];
    [[NSFileManager defaultManager] createDirectoryAtPath:_logDir withIntermediateDirectories:YES attributes:nil error:nil];
  }
  Dl_info info = {0};
  dladdr(returnAddress, &info);
  
  BOOL txt = !memcmp(data, "GET ", 4) || !memcmp(data, "POST ", 5);
  NSString *str = [NSString stringWithFormat:@"\r\nFROM %s(%p)-%s(%p=>%#08lx):\n<%@>\n\n", info.dli_fname, info.dli_fbase, info.dli_sname, info.dli_saddr, (long)info.dli_saddr-(long)info.dli_fbase-0x1000, [NSThread callStackSymbols]];
  NSMutableData *dat = [NSMutableData dataWithData:[str dataUsingEncoding:NSUTF8StringEncoding]];
  [dat appendBytes:data length:dataLength];
  if (txt) NSLog(@"%@", [[NSString alloc] initWithBytesNoCopy:(void *)data length:dataLength encoding:NSUTF8StringEncoding freeWhenDone:NO]);
  NSString *file = [NSString stringWithFormat:@"%@/%@.%@", _logDir, b, txt ? @"dat" : @"txt"];
  FILE* fp = fopen([file UTF8String],"a+");
  while(ftrylockfile(fp))
    sleep(1);
  fwrite([dat bytes], [dat length], 1, fp);
  fflush(fp);
  fclose(fp);
  funlockfile(fp);
}
#if __cplusplus
extern "C"
#endif
static void NFLog(NSString* format, ...)
{
#if DEBUG
  static NSDateFormatter* timeStampFormat;
  if (!timeStampFormat) {
    timeStampFormat = [[NSDateFormatter alloc] init];
    [timeStampFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    [timeStampFormat setTimeZone:[NSTimeZone systemTimeZone]];
  }
  
  NSString* timestamp = [timeStampFormat stringFromDate:[NSDate date]];
  
  va_list vargs;
  va_start(vargs, format);
  NSString* formattedMessage = [[NSString alloc] initWithFormat:format arguments:vargs];
  va_end(vargs);
  static NSString* b = nil;
  if (!b) {
    b = [[NSBundle mainBundle] bundleIdentifier];
  }
  NSString* message = [NSString stringWithFormat:@"<%@> %@", timestamp, formattedMessage];
  LogDataImpl(b,[message UTF8String], [message length], __builtin_return_address(0));
#endif
}
#if __cplusplus
extern "C"
#endif
static void AFLog(NSString* format, ...)
{
  static NSDateFormatter* timeStampFormat;
  if (!timeStampFormat) {
    timeStampFormat = [[NSDateFormatter alloc] init];
    [timeStampFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    [timeStampFormat setTimeZone:[NSTimeZone systemTimeZone]];
  }
  
  NSString* timestamp = [timeStampFormat stringFromDate:[NSDate date]];
  
  va_list vargs;
  va_start(vargs, format);
  NSString* formattedMessage = [[NSString alloc] initWithFormat:format arguments:vargs];
  va_end(vargs);
  static NSString* b = nil;
  if (!b) {
    b = [[NSBundle mainBundle] bundleIdentifier];
  }
  NSString* message = [NSString stringWithFormat:@"<%@> %@", timestamp, formattedMessage];
  LogDataImpl(b,[message UTF8String], [message length], __builtin_return_address(0));
}
static void NFAddr(const void* addr){
  Dl_info info = {0};
  dladdr(addr, &info);
  NSString *str = [NSString stringWithFormat:@"\r\nFROM %s(%p)-%s(%p=>%#08lx):\n<%@>\n\n", info.dli_fname, info.dli_fbase, info.dli_sname, info.dli_saddr, (long)info.dli_saddr-(long)info.dli_fbase-0x1000, [NSThread callStackSymbols]];
  NFLog(@"%@",str);
}
