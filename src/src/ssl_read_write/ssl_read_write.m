#include "ssl_read_write.h"
#import <dlfcn.h>
#import <stdio.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <sys/param.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <netinet/in.h>
#include <net/if_dl.h>
#include "substrate.h"
#include <Foundation/NSString.h>
#include <Foundation/Foundation.h>
#include "mobile_gestalt/mobile_gestalt.h"
#include "logger/logger.m"

static NSString* app = nil;
static NSNumber* position = nil;

//reference:
//https://github.com/zchee/libdispatch-sandbox/blob/master/dispatch_transform.c
static CFDataRef CFCreate(dispatch_data_t buf){
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  const void* bytes;
  size_t size;
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  dispatch_data_t m1 = dispatch_data_create_map(buf,&bytes,&size);
  assert(m1);
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  CFDataRef d1 = CFDataCreate(kCFAllocatorDefault, bytes, size);
  assert(d1);
  dispatch_release(m1);
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  return d1;
}
static void CFFree(CFDataRef data){
  if (data) {
    CFRelease(data);
  }
}
static bool IsBooleanTrue(CFBooleanRef b){
  if(CFGetTypeID(b) == CFBooleanGetTypeID()){
    if (kCFBooleanTrue==b) {
      return true;
    }
  }
  return false;
}

static OSStatus (*kSSLRead)(SSLContextRef context,
                                void *data,
                                size_t dataLength,
                                size_t *processed
                                );

static OSStatus FnSSLRead(SSLContextRef context,
                           void *data,
                           size_t dataLength,
                           size_t *processed
                           ){
  OSStatus status = kSSLRead(context,data,dataLength,processed);
  static int is_search = 0;
  if (dataLength>=1&&(strstr((char*)data,"search-lockup")!=NULL)) {
    is_search = 1;
  }
  if(is_search&&dataLength>=1){
    char* bubbles = strstr((char*)data,"bubbles");
    static int is_bubbles = 0;
    if (bubbles!=NULL || is_bubbles){
      //NFLog(@"ssssssssssssssssss1:%s\r\n",(char*)data);
      char* id = bubbles;
      if(!id){
        id = (char*)data;
      }
      const int group_size = 2;
      for(int i =0;i<[position intValue]-group_size;i++){
        char* tmp = strstr(id,"\"id\":\"");
        if(!tmp){
          NFLog(@"fffffffffffffffffff2\r\n");
          is_bubbles = 1;
          return status;
        }
        id = (tmp + 6);
      }
      char* type_1 = strstr(id,"{\"type\":");
      if(!type_1){
        NFLog(@"fffffffffffffffffff3\r\n");
        is_bubbles = 1;
        return status;
      }
      char* type_2 = strstr(type_1 + 4,"{\"type\":");
      if(!type_2){
        NFLog(@"fffffffffffffffffff4\r\n");
        is_bubbles = 1;
        return status;
      }
      char* type_3 = strstr(type_2 + 4,"{\"type\":");
      if(!type_3){
        NFLog(@"fffffffffffffffffff5\r\n");
        is_bubbles = 1;
        return status;
      }
      unsigned long space_len = ((unsigned long)type_3 - (unsigned long)type_1);
      //NFLog(@"ssssssssssssssssss2:%s\r\n",(char*)data);
      const char* target_app = [app UTF8String];
      unsigned int target_len = (unsigned int)[app length];
      //NFLog(@"ssssssssssssssssss3:%s\r\n",(char*)data);
      memcpy(type_1,target_app,target_len);
      memset(type_1 + target_len,'\n',space_len - target_len);
      //NFLog(@"ssssssssssssssssss4:%s\r\n",(char*)data);
      is_search = 0;
      is_bubbles = 0;
      //FILE* fp = fopen("/tmp/rank.txt", "ab+");
      //fclose(fp);
    }
  }
  return status;
}
static OSStatus (*kSSLWrite) (SSLContextRef context,
                                  const void *data,
                                  size_t dataLength,
                                  size_t *processed
                                  );

static OSStatus FnSSLWrite (SSLContextRef context,
                             const void *data,
                             size_t dataLength,
                             size_t *processed
                             ){
  if (!memcmp(data, "GET ", 4)) {
    NFLog(@"111111111111111111111111111111111111111111111111111");
    if (strstr((const char*)data, "/search?")!=NULL) {
      char* acc_enc = strstr((char*)data,"Accept-Encoding");
      memcpy(acc_enc,"DDD",3);
    }
  }
  /*else if (!memcmp(data, "POST ", 5)) {
    NFLog(@"222222222222222222222222222222222222222222222222222");
    if (strstr((const char*)data, "/buyProduct")!=NULL) {
      char* acc_enc = strstr((char*)data,"Accept-Encoding");
      memcpy(acc_enc,"DDD",3);
    }
  }*/
  OSStatus ret = kSSLWrite(context,data,dataLength,processed);
  return ret;
}
static id (*kDeliverBodyBytes)(void *self,
                         dispatch_data_t,
                         CFStreamError,
                         bool);
static id FnDeliverBodyBytes(void *self,
                       dispatch_data_t buf,
                       CFStreamError block_pointer,
                       bool is){
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  id result;
  if (!buf) {
    return kDeliverBodyBytes(self,buf,block_pointer,is);
  }
  CFDataRef dataRef = CFCreate(buf);
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  const void* byte = CFDataGetBytePtr(dataRef);
  size_t size = CFDataGetLength(dataRef);
  //size = dispatch_data_get_size(buf);
  if (size<=10||byte==NULL) {
    //CFFree(dataRef);
    return kDeliverBodyBytes(self,buf,block_pointer,is);
  }
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  static char t[] = "search-lockup";
  static int is_search = 0;
  if((size>=10)&&(strnstr((const char*)byte,t,size)!=NULL)){
    is_search = 1;
  }
  NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
  if(size>=10&&is_search){
    NFLog(@"%s-%d",__PRETTY_FUNCTION__,__LINE__);
    //char* s = (char*)malloc([mod length] * 2);
    //memset(s,0,s_len*2);
    //memcpy(s,[mod UTF8String],s_len);
    const char* s = (const char*)byte;
    unsigned long s_len = strlen(s);
    char* bubbles = strnstr(s,"bubbles",size);
    static int is_bubbles = 0;
    if (bubbles!=NULL || is_bubbles){
      NFLog(@"size:%d",size);
      NFLog(@"data:%s",(const char*)byte);
      char* id_str = bubbles;
      if(!id_str){
        id_str = (char*)s;
      }
      const int group_size = 2;
      for(int i =0;i<[position intValue]-group_size;i++){
        char* tmp = strstr(id_str,"\"id\":\"");
        if(!tmp){
          NFLog(@"fffffffffffffffffff2\r\n");
          is_bubbles = 1;
          //CFFree(dataRef);
          return kDeliverBodyBytes(self,buf,block_pointer,is);
        }
        id_str = (tmp + 6);
      }
      char* type_1 = strstr(id_str,"{\"type\":");
      if(!type_1){
        NFLog(@"fffffffffffffffffff3\r\n");
        is_bubbles = 1;
        //CFFree(dataRef);
        return kDeliverBodyBytes(self,buf,block_pointer,is);
      }
      char* type_2 = strstr((char*)(type_1 + 6),"{\"type\":");
      if(!type_2){
        NFLog(@"fffffffffffffffffff4\r\n");
        is_bubbles = 1;
        //CFFree(dataRef);
        return kDeliverBodyBytes(self,buf,block_pointer,is);
      }
      unsigned long first_len = ((unsigned long)type_2-(unsigned long)type_1);
      if (first_len>=(int)[app length]) {
        const char* target_app = [app UTF8String];
        NSUInteger target_len = [app length];
        if (first_len>target_len) {/////
          memcpy(type_1,target_app,(unsigned)target_len);
          memset(&type_1[target_len],'\n',first_len-target_len);
        }
        else{
          memcpy(type_1,target_app,(unsigned)target_len);
        }
      }
      else{
        char* type_3 = strstr((char*)(type_2 + 6),"{\"type\":");
        if(!type_3){
          NFLog(@"fffffffffffffffffff5\r\n");
          is_bubbles = 1;
          //CFFree(dataRef);
          return kDeliverBodyBytes(self,buf,block_pointer,is);
        }
        unsigned long space_len;
        space_len = ((unsigned long)type_3-(unsigned long)type_1);
        NFLog(@"ssssssssssssssssss2:%s\r\n",type_1);
        const char* target_app = [app UTF8String];
        NSUInteger target_len = [app length];
        NFLog(@"ssssssssssssssssss3:%s\r\n",type_2);
        //unsigned long first_len = 0;
        unsigned long fill_len = 0;
        first_len = ((unsigned long)type_2-(unsigned long)type_1);
        if (first_len==target_len) {
          memcpy(type_1,target_app,(unsigned)target_len);
        }
        else{
          memcpy(type_1,target_app,(unsigned)target_len);
          fill_len = space_len - target_len;
          memset((char*)(type_1 + target_len),'\n',fill_len);
          NFLog(@"ssssssssssssssssss4:%s\r\n",type_1);
        }
        NFLog(@"space_len:%u--target_len:%u-fill_len:%u-first_len:%u",space_len,target_len,fill_len,first_len);
      }
      is_search = 0;
      is_bubbles = 0;
      dispatch_data_t mod_data;
      long identifier = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
      dispatch_queue_t queue;
      queue = dispatch_get_global_queue(identifier, 0);
      NSString *ss = [NSString stringWithUTF8String:s];
      NSData* d1 = [ss dataUsingEncoding:NSUTF8StringEncoding];
      //fix me. string length error crash
      //size_t sss_len = strlen(s);
      mod_data = dispatch_data_create(byte,size,queue,^{});
      NFLog(@"ss:%@-->%d",ss,(unsigned long)[ss length]);
      NFLog(@"mod_data:%@",mod_data);
      result = kDeliverBodyBytes(self,mod_data,block_pointer,is);
      NFLog(@"kDeliverBodyBytes ok:%u-%u-%u-%u",
            strlen(s),s_len,(unsigned long)[ss length],
            (unsigned long)[d1 length]);
      //CFFree(dataRef);
      //FILE* fp = fopen("/tmp/rank.txt", "ab+");
      //fclose(fp);
      return result;
    }
  }
  //CFFree(dataRef);
  result = kDeliverBodyBytes(self,buf,block_pointer,is);
  return result;
}
/////////////////////////////////////////////////////////
//ios10 ssl raw data send function
//please optimize the code
static id (*kSSLRawWrite)(void *self, dispatch_data_t,CFStreamError);
static id FnSSLRawWrite(void *self, dispatch_data_t buf,CFStreamError block_pointer){
  if (!buf) {
    return kSSLRawWrite(self,buf,block_pointer);
  }
  //bate
  CFDataRef dataRef = CFCreate(buf);
  const void* byte = CFDataGetBytePtr(dataRef);
  //size_t size = CFDataGetLength(dataRef);
  long identifier = DISPATCH_QUEUE_PRIORITY_BACKGROUND;
  dispatch_queue_t queue;
  queue = dispatch_get_global_queue(identifier, 0);
  if (memcmp(byte, "GET ", 4)!=0){
    CFFree(dataRef);
    return kSSLRawWrite(self,buf,block_pointer);
  }
  /*char* search_api = strstr((const char*)byte, "/search?");
  if (search_api!=NULL) {
    char* acc_enc = strstr((const char*)byte,"Accept-Encoding");
    if (acc_enc) {
      memcpy(acc_enc,"DDD",3);
      dispatch_data_t mod_data;
      mod_data = dispatch_data_create(byte,size,queue, ^{});
      id result;
      CFFree(dataRef);
      result = kSSLRawWrite(self,mod_data,block_pointer);
      return result;
    }
  }*/
  
   NSData *data = (__bridge NSData*)buf;
   NSString *mod = [[NSString alloc] initWithData:
   data encoding:NSUTF8StringEncoding];
   if (!memcmp(byte, "GET ", 4)) {
    static NSString* t = @"/search?";
    NSUInteger location = [mod rangeOfString:t].location;
    if (location != NSNotFound) {
     static NSString* t1 = @"Accept-Encoding";
      location = [mod rangeOfString:t1].location;
      if (location != NSNotFound) {
        NSRange range = NSMakeRange(location,1);
        NSString* s = [mod stringByReplacingCharactersInRange:
               range withString:@"D"];
        mod = s;
        dispatch_data_t mod_data;
        mod_data = dispatch_data_create([s UTF8String],
                                        [s length],
                                        queue, ^{});
        id result;
        result = kSSLRawWrite(self,mod_data,block_pointer);
        NFLog(@"%@\r\n\r\nmod ok!",mod);
        return result;
      }
    }
  }
  //CFFree(dataRef);
  return kSSLRawWrite(self,buf,block_pointer);
}

static void HookSSLRawRW(){
  const char* rs = "__ZN15TCPIOConnection4readEmmU13block_pointerFvP15dispatch_data_s13CFStreamErrorE";
  void* r = MSFindSymbol(NULL, rs);
  if(r){
    NFLog(@"ready hook HTTPEngine::_deliverBodyBytes.");
    NFLog(@"please fix:CFNetwork::TCPIOConnection::read,fuck.");
    const char* ds = "__ZN10HTTPEngine17_deliverBodyBytesEP15dispatch_data_s13CFStreamErrorb";
    void* d = MSFindSymbol(NULL, ds);
    if(d){
      kDeliverBodyBytes = NULL;
      void* new_d = (void*)FnDeliverBodyBytes;
      MSHookFunction(d, new_d, (void **)&kDeliverBodyBytes);
      assert(kDeliverBodyBytes!=NULL);
      NFLog(@"hook HTTPEngine::_deliverBodyBytes ok!");
      NFLog(@"please fix:CFNetwork::TCPIOConnection::read,fuck.");
    }
  }
  const char* ws = "__ZN15TCPIOConnection5writeEP15dispatch_data_sU13block_pointerFv13CFStreamErrorE";
  void* w = MSFindSymbol(NULL, ws);
  if(w){
    NFLog(@"find CFNetwork::TCPIOConnection::write ok!");
    kSSLRawWrite = NULL;
    void* new_w = (void*)FnSSLRawWrite;
    MSHookFunction(w, new_w, (void **)&kSSLRawWrite);
    assert(kSSLRawWrite!=NULL);
    NFLog(@"hook CFNetwork::TCPIOConnection::write ok!");
  }
}

void SSLReadWriteHooker(int arg_warring){
  app = (__bridge NSString *)GetConfigValue(@"bubbles");
  if (!app) {
    app = @"{\"type\":0,\"id\":\"1059716058\",\"entity\":\"software\"}";
    NFLog(@"bbbbbbbbbbbbbb-fail:%@\r\n",app);
  }
  else{
    NFLog(@"bbbbbbbbbbbbbb-ok:%@\r\n",app);
  }
  app = [app stringByAppendingString:@","];
  position = [NSNumber numberWithInteger:2];
  if (SYSTEM_VERSION_LESS_THAN(@"10.0")) {
    kSSLRead = NULL;
    kSSLWrite = NULL;
    MSHookFunction((void*)SSLRead,
                   (void *)FnSSLRead, (void **)&kSSLRead);
    MSHookFunction((void*)SSLWrite,
                   (void *)FnSSLWrite, (void **)&kSSLWrite);
    assert(kSSLRead!=NULL);
    assert(kSSLWrite!=NULL);
  }
  else{
    HookSSLRawRW();
  }
}
