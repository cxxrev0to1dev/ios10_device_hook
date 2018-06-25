#ifndef MOBILE_GESTALT_H_
#define MOBILE_GESTALT_H_

#include <pthread.h>


static NSString* kPref =
  @"/private/var/preferences/corehook.plist";
static const char* kInitDylib =
  "/Library/MobileSubstrate/MobileSubstrate.dylib";
static const char* kLibMobileGestalt =
  "/usr/lib/libMobileGestalt.dylib";

static FILE* log_file = NULL;
static NSDictionary *fake_device;
static NSArray* executables = nil;
static CFBooleanRef add_executables_filter;
static pthread_mutex_t config_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t var_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t thread_safe_mg = PTHREAD_MUTEX_INITIALIZER;
static NSString* executable = nil;

static CFTypeRef GetConfigValue(NSString* key){
  CFTypeRef result = nil;
  pthread_mutex_lock(&config_mutex);
  while ([fake_device count]==0) {
    NSString *path = kPref;
    fake_device = [NSDictionary dictionaryWithContentsOfFile:path];
  }
  result = CFBridgingRetain([fake_device objectForKey:key]);
  pthread_mutex_unlock(&config_mutex);
  return result;
}
static CFTypeRef GetDeviceId(){
  CFTypeRef result = nil;
  pthread_mutex_lock(&config_mutex);
  NSDictionary *ddddd;
  while ([ddddd count]==0) {
    NSString *path = kPref;
    ddddd =[NSDictionary dictionaryWithContentsOfFile:path];
  }
  NSString* key = @"UDID";
  result = CFBridgingRetain([ddddd objectForKey:key]);
  pthread_mutex_unlock(&config_mutex);
  return result;
}
static bool IsFound(NSString* path){
  NSFileManager *fileManager = [NSFileManager defaultManager];
  BOOL fileExists = [fileManager fileExistsAtPath:path];
  return (fileExists==TRUE);
}
static void SaveUdid(NSData* data){
  NSString* path = kPref;
  NSMutableDictionary *infoDict;
  infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
  if (infoDict==nil) {
    infoDict = [[NSMutableDictionary alloc] init];
  }
  [infoDict setObject:data forKey:@"CFDataUDID"];
  [infoDict writeToFile:path atomically:YES];
}
static NSMutableDictionary* GetPlist(NSString* path){
  NSMutableDictionary *infoDict;
  infoDict = [NSMutableDictionary dictionaryWithContentsOfFile:path];
  return [infoDict mutableCopy];
}
static bool IsUserProcess(){
  NSString* execute_path = [[NSBundle mainBundle] bundlePath];
  return ([execute_path rangeOfString:@"/mobile/"].location!=NSNotFound);
}
static bool IsTargetProcess(){
  if (add_executables_filter) {
    if ([executables indexOfObject:executable]!=NSNotFound){
      return true;
    }
    else{
      return false;
    }
  }
  return true;
}
static void Initialize(){
  static bool is_initia = false;
  if (!is_initia) {
    add_executables_filter = kCFBooleanFalse;
    dlopen(kInitDylib, RTLD_LAZY);
    dlopen(kLibMobileGestalt, RTLD_LAZY);
    //pthread_mutex_init(&config_mutex,NULL);
    //pthread_mutex_init(&var_mutex,NULL);
    //pthread_mutex_init(&thread_safe_mg,NULL);
    executable = [[NSBundle mainBundle] bundleIdentifier];
    executables = GetConfigValue(@"Executables");
    CFBooleanRef b = GetConfigValue(@"AddExecutablesFilter");
    add_executables_filter = b;
    is_initia = true;
  }
}

static bool IsRequireUdidString(const char* data){
  const char aaa[] = "UniqueDeviceID";
  return (strncmp(data,aaa,(sizeof(aaa)-sizeof(char)))==0);
}

static bool IsRequireUdidData(const char* data){
  const char aaa[] = "UniqueDeviceIDData";
  const char bbb[] = "nFRqKto/RuQAV1P+0/qkBA";
  bool is_b = (strncmp(data,aaa,(sizeof(aaa)-sizeof(char)))==0);
  bool is_c = (strncmp(data,bbb,(sizeof(bbb)-sizeof(char)))==0);
  return (is_b||is_c);
  //return (strcmp(data,"UniqueDeviceIDData")==0);
}

CFTypeRef GUdid(void);
static CFTypeRef GSerialNumber(){
  CFTypeRef value = nil;
  pthread_mutex_lock(&var_mutex);
  value = GetConfigValue(@"SERIAL");
  pthread_mutex_unlock(&var_mutex);
  return value;
}
static CFTypeRef GChip(){
  CFTypeRef value = nil;
  pthread_mutex_lock(&var_mutex);
  value = GetConfigValue(@"CHIP");
  pthread_mutex_unlock(&var_mutex);
  return value;
}
static CFTypeRef GMacAddr(){
  CFTypeRef value = nil;
  pthread_mutex_lock(&var_mutex);
  value = GetConfigValue(@"MACADDRESS");
  pthread_mutex_unlock(&var_mutex);
  return value;
}
static CFTypeRef GBlueAddr(){
  CFTypeRef value = nil;
  pthread_mutex_lock(&var_mutex);
  value = GetConfigValue(@"BLUEADDRESS");
  pthread_mutex_unlock(&var_mutex);
  return value;
}

typedef struct CTResult {
  int flag;
  int a;
} CTResult;

typedef const struct __CTServerConnection * CTServerConnectionRef;

void InitCFDevice(int arg_warring);
void MobileGestaltHooker(int arg_warring);

#endif
