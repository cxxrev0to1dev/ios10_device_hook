//
//  SSLKillSwitch.m
//  SSLKillSwitch
//
//  Created by Alban Diquet on 7/10/15.
//  Copyright (c) 2015 Alban Diquet. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Security/SecureTransport.h>
#include <execinfo.h>
#include <signal.h>
#import <objc/message.h>
#include "third_party/mongoose/mongoose.h"
#include "third_party/choose/choose.h"

#if SUBSTRATE_BUILD
#import "substrate.h"

#define PREFERENCE_FILE @"/private/var/mobile/Library/Preferences/com.nablac0d3.SSLKillSwitchSettings.plist"
#define PREFERENCE_KEY @"shouldDisableCertificateValidation"

#else

#import "fishhook.h"
#import <dlfcn.h>

#endif

#include "ssl_read_write/ssl_read_write.h"
#include "mobile_gestalt/mobile_gestalt.h"
#include "app_rank/app_rank.h"
#include "logger/logger.m"
#include "OpenUDID.h"

#pragma mark Utility Functions

static void SSKLog(NSString *format, ...)
{
    NSString *newFormat = [[NSString alloc] initWithFormat:@"=== SSL Kill Switch 2: %@", format];
    va_list args;
    va_start(args, format);
    NSLogv(newFormat, args);
    va_end(args);
}


#if SUBSTRATE_BUILD
// Utility function to read the Tweak's preferences
static BOOL shouldHookFromPreference(NSString *preferenceSetting)
{
    BOOL shouldHook = NO;
    NSMutableDictionary* plist = [[NSMutableDictionary alloc] initWithContentsOfFile:PREFERENCE_FILE];
    
    if (!plist)
    {
        SSKLog(@"Preference file not found.");
    }
    else
    {
        shouldHook = [[plist objectForKey:preferenceSetting] boolValue];
        SSKLog(@"Preference set to %d.", shouldHook);
    }
    return shouldHook;
}
#endif


#pragma mark SecureTransport hooks - iOS 9 and below
// Explanation here: https://nabla-c0d3.github.io/blog/2013/08/20/ios-ssl-kill-switch-v0-dot-5-released/

static OSStatus (*original_SSLSetSessionOption)(SSLContextRef context,
                                                SSLSessionOption option,
                                                Boolean value);

static OSStatus replaced_SSLSetSessionOption(SSLContextRef context,
                                             SSLSessionOption option,
                                             Boolean value)
{
    // Remove the ability to modify the value of the kSSLSessionOptionBreakOnServerAuth option
    if (option == kSSLSessionOptionBreakOnServerAuth)
    {
        return noErr;
    }
    return original_SSLSetSessionOption(context, option, value);
}


static SSLContextRef (*original_SSLCreateContext)(CFAllocatorRef alloc,
                                                  SSLProtocolSide protocolSide,
                                                  SSLConnectionType connectionType);

static SSLContextRef replaced_SSLCreateContext(CFAllocatorRef alloc,
                                               SSLProtocolSide protocolSide,
                                               SSLConnectionType connectionType)
{
    SSLContextRef sslContext = original_SSLCreateContext(alloc, protocolSide, connectionType);
    
    // Immediately set the kSSLSessionOptionBreakOnServerAuth option in order to disable cert validation
    original_SSLSetSessionOption(sslContext, kSSLSessionOptionBreakOnServerAuth, true);
    return sslContext;
}


static OSStatus (*original_SSLHandshake)(SSLContextRef context);

static OSStatus replaced_SSLHandshake(SSLContextRef context)
{
    
    OSStatus result = original_SSLHandshake(context);
    
    // Hijack the flow when breaking on server authentication
    if (result == errSSLServerAuthCompleted)
    {
        // Do not check the cert and call SSLHandshake() again
        return original_SSLHandshake(context);
    }
    
    return result;
}


#pragma mark libsystem_coretls.dylib hooks - iOS 10
// Explanation here: https://nabla-c0d3.github.io/blog/2017/02/05/ios10-ssl-kill-switch/

static OSStatus (*original_tls_helper_create_peer_trust)(void *hdsk, bool server, SecTrustRef *trustRef);

static OSStatus replaced_tls_helper_create_peer_trust(void *hdsk, bool server, SecTrustRef *trustRef)
{
    // Do not actually set the trustRef
    return errSecSuccess;
}


#pragma mark CocoaSPDY hook
#if SUBSTRATE_BUILD

static void (*oldSetTLSTrustEvaluator)(id self, SEL _cmd, id evaluator);

static void newSetTLSTrustEvaluator(id self, SEL _cmd, id evaluator)
{
    // Set a nil evaluator to disable SSL validation
    oldSetTLSTrustEvaluator(self, _cmd, nil);
}

static void (*oldSetprotocolClasses)(id self, SEL _cmd, NSArray <Class> *protocolClasses);

static void newSetprotocolClasses(id self, SEL _cmd, NSArray <Class> *protocolClasses)
{
    // Do not register protocol classes which is how CocoaSPDY works
    // This should force the App to downgrade from SPDY to HTTPS
}

static void (*oldRegisterOrigin)(id self, SEL _cmd, NSString *origin);

static void newRegisterOrigin(id self, SEL _cmd, NSString *origin)
{
    // Do not register protocol classes which is how CocoaSPDY works
    // This should force the App to downgrade from SPDY to HTTPS
}
#endif

static void SSLKillSwitchHooker(){
#if SUBSTRATE_BUILD
  // Should we enable the hook ?
  if (shouldHookFromPreference(PREFERENCE_KEY))
      {
    // Substrate-based hooking; only hook if the preference file says so
    SSKLog(@"Subtrate hook enabled.");
    
    // SecureTransport hooks - works up to iOS 9
    MSHookFunction((void *) SSLHandshake,(void *)  replaced_SSLHandshake, (void **) &original_SSLHandshake);
    MSHookFunction((void *) SSLSetSessionOption,(void *)  replaced_SSLSetSessionOption, (void **) &original_SSLSetSessionOption);
    MSHookFunction((void *) SSLCreateContext,(void *)  replaced_SSLCreateContext, (void **) &original_SSLCreateContext);
    
    // libsystem_coretls.dylib hook - works on iOS 10
    // TODO: Enable this hook for the fishhook-based hooking so it works on OS X too
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    if ([processInfo respondsToSelector:@selector(isOperatingSystemAtLeastVersion:)] && [processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 0, 0}])
        {
      // This function does not exist before iOS 10
      void *tls_helper_create_peer_trust = dlsym(RTLD_DEFAULT, "tls_helper_create_peer_trust");
      MSHookFunction((void *) tls_helper_create_peer_trust, (void *) replaced_tls_helper_create_peer_trust,  (void **) &original_tls_helper_create_peer_trust);
        }
    
    
    // CocoaSPDY hooks - https://github.com/twitter/CocoaSPDY
    // TODO: Enable these hooks for the fishhook-based hooking so it works on OS X too
    Class spdyProtocolClass = NSClassFromString(@"SPDYProtocol");
    if (spdyProtocolClass)
        {
      // Disable trust evaluation
      MSHookMessageEx(object_getClass(spdyProtocolClass), NSSelectorFromString(@"setTLSTrustEvaluator:"), (IMP) &newSetTLSTrustEvaluator, (IMP *)&oldSetTLSTrustEvaluator);
      
      // CocoaSPDY works by getting registered as a NSURLProtocol; block that so the Apps switches back to HTTP as SPDY is tricky to proxy
      Class spdyUrlConnectionProtocolClass = NSClassFromString(@"SPDYURLConnectionProtocol");
      MSHookMessageEx(object_getClass(spdyUrlConnectionProtocolClass), NSSelectorFromString(@"registerOrigin:"), (IMP) &newRegisterOrigin, (IMP *)&oldRegisterOrigin);
      
      MSHookMessageEx(NSClassFromString(@"NSURLSessionConfiguration"), NSSelectorFromString(@"setprotocolClasses:"), (IMP) &newSetprotocolClasses, (IMP *)&oldSetprotocolClasses);
        }
      }
  else
      {
    SSKLog(@"Subtrate hook disabled.");
      }
  
#else
  // Fishhook-based hooking, for OS X builds; always hook
  SSKLog(@"Fishhook hook enabled.");
  original_SSLHandshake = dlsym(RTLD_DEFAULT, "SSLHandshake");
  if ((rebind_symbols((struct rebinding[1]){{(char *)"SSLHandshake", (void *)replaced_SSLHandshake}}, 1) < 0))
      {
    SSKLog(@"Hooking failed.");
      }
  
  original_SSLSetSessionOption = dlsym(RTLD_DEFAULT, "SSLSetSessionOption");
  if ((rebind_symbols((struct rebinding[1]){{(char *)"SSLSetSessionOption", (void *)replaced_SSLSetSessionOption}}, 1) < 0))
      {
    SSKLog(@"Hooking failed.");
      }
  
  original_SSLCreateContext = dlsym(RTLD_DEFAULT, "SSLCreateContext");
  if ((rebind_symbols((struct rebinding[1]){{(char *)"SSLCreateContext", (void *)replaced_SSLCreateContext}}, 1) < 0))
      {
    SSKLog(@"Hooking failed.");
      }
#endif
}

static bool IsBooleanTrue(CFBooleanRef b){
  if(CFGetTypeID(b) == CFBooleanGetTypeID()){
    if (kCFBooleanTrue==b) {
      return true;
    }
  }
  return false;
}
static int NewDJB2Hash(const char *str,int key)
{
  if(!(*str))
    return 0;
  int hash = key;
  for (int i=0; i<strlen(str); i++) {
    hash = ((hash*25)+str[i])%100000;
  }
  return hash;
}
static CFTypeRef ForMGCopyAnswer(CFTypeRef prop){
  static CFTypeRef (*MGCopyAnswer)(CFTypeRef prop);
  if (!MGCopyAnswer) {
    const char* name = "MGCopyAnswer";
    MSImageRef image = MSGetImageByName("/usr/lib/libMobileGestalt.dylib");
    void* ptr = MSFindSymbol(image, name);
    if (!ptr) {
      ptr = MSFindSymbol(image, "_MGCopyAnswer");
      if (!ptr) {
        ptr = MSFindSymbol(NULL, "_MGCopyAnswer");
      }
    }
    if (ptr==NULL) {
      return CFSTR("");
    }
    MGCopyAnswer = (CFTypeRef(*)(CFTypeRef))ptr;
  }
  return MGCopyAnswer(prop);
}
static void TestLogger(const char* c){
  if (c==NULL) {
    return;
  }
  if (!c[0]) {
    return;
  }
  FILE* fp = fopen("/tmp/11111.txt", "ab+");
  fwrite(c, strlen(c), 1, fp);
  fwrite("\r\n", 2, 1, fp);
  fclose(fp);
}
void MySignalHandler(int signo){
  void *buffer[30] = {0};
  size_t size;
  char **strings = NULL;
  size_t i = 0;
  size = backtrace(buffer, 30);
  AFLog(@"Process:%s",getprogname());
  AFLog(@"#################Obtained stack frames#################");
  AFLog(@"Obtained %zd stack frames.nm\n", size);
  strings = backtrace_symbols(buffer, size);
  if (strings == NULL){
    AFLog(@"backtrace_symbols.");
    exit(EXIT_FAILURE);
  }
  for (i = 0; i < size; i++){
    AFLog(@"%s\n", strings[i]);
  }
  free(strings);
  strings = NULL;
}
static void InstallUncaughtExceptionHandler(){
  signal(SIGABRT, MySignalHandler);
  signal(SIGILL, MySignalHandler);
  signal(SIGSEGV, MySignalHandler);
  signal(SIGFPE, MySignalHandler);
  signal(SIGBUS, MySignalHandler);
  signal(SIGPIPE, MySignalHandler);
}
#pragma mark Dylib Constructor
__attribute__((constructor))
static void init(int argc,char** argv)
{
  const char* t1 = getprogname();
  if (t1==NULL) {
    return;
  }
  if(access("/tmp/corehook_start.txt", 0)!=0) {
    return;
  }
  InstallUncaughtExceptionHandler();
  char* aaa[] = {
    "mobactivationd",
    "MobileActivation",
    "mobileactivationd",
    "cfprefsd","identityservicesd",
    "afc2d","ReportCrash","awdd",
    "matd","com.apple.datamigrator",
    "com.apple.uifoundation-bundle-helper","ifccd",
    "gputoolsd","DTFetchSymbols","wirelessproxd",
    "aggregated","lockbot","MobileGestaltHelper",
    "lockdownd","wifiFirmwareLoaderLegacy","lsd","keybagd",
    "CrashHousekeeping","wifid","pfd","configd","backboardd",
    NULL
  };
  for (int i = 0; aaa[i]!=NULL; i++) {
    const char* t = getprogname();
    if (strcasecmp(t,aaa[i])==0){
      return;
    }
    if (strcasestr(t,"substrate")!=NULL) {
      return;
    }
  }
  Initialize();
  InitAppRank(0);
  CFTypeRef wifiMac_a = ForMGCopyAnswer(CFSTR("WifiAddress"));
  if (wifiMac_a==nil) {
    return;
  }
  NSString* wifiMac = (NSString*)CFBridgingRelease(wifiMac_a);
  if ([wifiMac length]<=0) {
    return;
  }
  wifiMac = [wifiMac lowercaseString];
  const char* wifi_mac = [wifiMac UTF8String];
  int hash = NewDJB2Hash(wifi_mac,8879);
  NSString* key_src = [NSString stringWithFormat:@"%d", hash];
  NSString* key_dst = (NSString*)GetConfigValue(@"KEY");
  if (![key_dst isEqualToString:key_src]) {
    return;
  }
  if (IsUserProcess()) {
    [OpenUDID value];
  }
  CFBooleanRef ssl_rw = kCFBooleanFalse;
  ssl_rw = GetConfigValue(@"SSL_RW_HOOK");
  if(IsBooleanTrue(ssl_rw)){
    NFLog(@"SSLReadWriteHooker start.");
    SSLReadWriteHooker(0);
    NFLog(@"SSLReadWriteHooker done.");
  }
  CFBooleanRef mobile_gestalt = kCFBooleanFalse;
  mobile_gestalt = GetConfigValue(@"MOBILE_GESTALT_HOOK");
  if(IsBooleanTrue(mobile_gestalt)){
    NFLog(@"MobileGestaltHooker start.");
    MobileGestaltHooker(0);
    NFLog(@"MobileGestaltHooker done.");
  }
  CFBooleanRef ssl_kill = kCFBooleanFalse;
  ssl_kill = GetConfigValue(@"SSL_KILL_HOOK");
  if(IsBooleanTrue(ssl_kill)){
    NFLog(@"SSLKillSwitchHooker start.");
    SSLKillSwitchHooker();
    NFLog(@"SSLKillSwitchHooker done.");
  }
}
