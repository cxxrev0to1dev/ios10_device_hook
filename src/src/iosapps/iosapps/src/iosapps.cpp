#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <unistd.h>
#include <copyfile.h>
#include <sys/stat.h>
#include <errno.h>
#include <sys/types.h>
#include <pthread.h>
#include <assert.h>
#include <sys/sysctl.h>
#include <spawn.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/fcntl.h>
#include "mongoose.h"
#include "mongoose.c"

static const char *s_http_port = "localhost:80";
static struct mg_serve_http_opts s_http_server_opts;
static pthread_mutex_t global_mutex = {0};

const char* kHostFile = "/private/etc/hosts";
const char* kHostFileBak = "/private/etc/hosts.bak";
const int kMaxBufLength  = 8196;
const int kMaxSocketBufferSize = 1024 * 1024;
char* socket_buffer = NULL;

struct content_range{
  int status_code;
  unsigned long long content_start_count;
  unsigned long long content_end_count;
  unsigned long long content_total;
  char junk[1024];
};
static bool GetContentRange(char* http_proto,struct content_range* out){
  out->status_code = 0;
  out->content_start_count = 0;
  out->content_end_count = 0;
  out->content_total = 0;
  sscanf (http_proto,"%*s %d %*s",&out->status_code);
  if (out->status_code==206) {
    printf("Partial Content!!!!!!!!!!!!!!!!!!!\r\n");
    char* p = strstr(http_proto,"Content-Range:");
    if (p) {
      sscanf (p,"Content-Range: %*s %llu-%llu/%llu",
              &out->content_start_count,
              &out->content_end_count,
              &out->content_total);
      printf("Partial Content:%llu-%llu/%llu\r\n",
             out->content_start_count,
             out->content_end_count,
             out->content_total);
      return (out->content_start_count>0&&out->content_end_count>0&&out->content_total>0);
    }
  }
  return false;
}

void bail(const char *on_what){
    if(errno!=0){
     fputs(strerror(errno),stderr);
     fputs(": ",stderr);
    }
    fputs(on_what,stderr);
    fputc('\n',stderr);
}
void RedirectTargetHost(){
  if (access(kHostFileBak, 0)==-1){
    copyfile_state_t s = copyfile_state_alloc();
    copyfile(kHostFile, kHostFileBak, s, COPYFILE_DATA | COPYFILE_XATTR);
    copyfile_state_free(s);
  }
  char domain[] = "iosapps.itunes.apple.com";
  char redirect_domain[] = "127.0.0.1  iosapps.itunes.apple.com\r\n";
  char local_path[] = "/private/etc/hosts";
  FILE* fp = fopen(local_path, "rb");
  int is_exist = -1;
  char buf[100] = {0};
  while(fgets(buf, 99, fp)!=NULL) {
    if(strstr(buf, domain)!=NULL) {
      is_exist = 0;
      break;
    }
    memset(buf,0,100);
  }
  fclose(fp);
  if(is_exist==-1){
    fp = fopen(local_path, "ab+");
    fseek(fp, 0L, SEEK_END);
    fwrite(redirect_domain, sizeof(redirect_domain) - 1, 1, fp);
    fclose(fp);
  }
}
void EnableHostfile(){
  remove(kHostFile);
  copyfile_state_t s = copyfile_state_alloc();
  copyfile(kHostFileBak, kHostFile, s, COPYFILE_DATA | COPYFILE_XATTR);
  copyfile_state_free(s);
}
/*void HTTPHeadersParse(int sock,char* http_header_buffer,int buffer_len,char* residue_data,int* residue_len){
  *residue_len = 0;
  int len=read(sock, http_header_buffer, buffer_len - 1);
  if (len > 0){
    char* pos = strstr(http_header_buffer,"\r\n\r\n");
    if(pos!=NULL){
      if (!memcmp(pos,"\r\n\r\n",4)){
        pos += (sizeof("\r\n\r\n") - sizeof(char));
        if (pos[0]){
          printf("---------------------------------------------------------------------------ParseResponseHeadersInitial---------------------------------------------------------------------------\r\n");
          char* buf_end = (char*)((unsigned long)http_header_buffer + len);
          *residue_len = ((unsigned long)buf_end - (unsigned long)pos);
          memcpy(residue_data, pos, *residue_len);
          memset(pos,0,*residue_len);
          printf("buffer size %d byte,socket read http headers length %d byte\r\n",buffer_len,len);
          printf("http content length %d bytes\r\n",*residue_len);
          printf("---------------------------------------------------------------------------ParseResponseHeadersOK---------------------------------------------------------------------------\r\n");
        }
        printf("%s\r\n",http_header_buffer);
      }
    }
  }
}*/
void HTTPHeadersParse(int sock,char* http_header_buffer,int buffer_len,char* residue_data,int* residue_len){
  *residue_len = 0;
  int recv_len = 0;
  bool is_ok = false;
  char buf[2] = {0};
  int len=read(sock, buf, 1);
  for (int i=0;len>0;i++){
    http_header_buffer[recv_len] = buf[0];
    recv_len += len;
    if (recv_len>10&&!memcmp(&http_header_buffer[recv_len-4],"\r\n\r\n",4)){
      is_ok = true;
      break;
    }
    buf[0] = 0;
    len=read(sock, buf, 1);
  }
  printf("---------------------------------------------------------------------------ParseResponseHeadersInitial---------------------------------------------------------------------------\r\n");
  printf("buffer size %d byte,socket read http headers length %d byte\r\n",buffer_len,recv_len);
  printf("%s",http_header_buffer);
  printf("---------------------------------------------------------------------------ParseResponseHeadersOK---------------------------------------------------------------------------\r\n");
}
void SetSocketBuf(int s){
  struct timeval timeout;      
  timeout.tv_sec = 5;
  timeout.tv_usec = 0;
  if (setsockopt (s, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout,sizeof(timeout)) < 0){
    printf("setsockopt failed\n");
  }
  if (setsockopt (s, SOL_SOCKET, SO_SNDTIMEO, (char *)&timeout,sizeof(timeout)) < 0){
    printf("setsockopt failed\n");
  }
  socklen_t optlen;
  int sndbuf=0;    /* Send buffer size */
  int rcvbuf=0;    /* Receive buffer size */
  sndbuf = kMaxSocketBufferSize;   /* Send buffer size */
  int z = setsockopt(s,SOL_SOCKET,SO_SNDBUF,&sndbuf,sizeof sndbuf);
  if(z)
     bail("setsockopt(s,SOL_SOCKET,""SO_SNDBUF)");
  rcvbuf = kMaxSocketBufferSize;   /* Receive buffer size */
  z = setsockopt(s,SOL_SOCKET,SO_RCVBUF,&rcvbuf,sizeof rcvbuf);
  if(z)
     bail("setsockopt(s,SOL_SOCKET,""SO_RCVBUF)");
  optlen = sizeof sndbuf;
  z = getsockopt(s,SOL_SOCKET,SO_SNDBUF,&sndbuf,&optlen);
  if(z)
    bail("getsockopt(s,SOL_SOCKET,""SO_SNDBUF)");
  assert(optlen == sizeof sndbuf);
  optlen = sizeof rcvbuf;
  z = getsockopt(s,SOL_SOCKET,SO_RCVBUF,&rcvbuf,&optlen);
  if(z)
    bail("getsockopt(s,SOL_SOCKET,""SO_RCVBUF)");
  assert(optlen == sizeof rcvbuf);
  //printf("Send buf: %d bytes\n",sndbuf);
  //printf("Recv buf: %d bytes\n",rcvbuf);
}
void GetOriginServerCache(struct mg_connection *nc,struct http_message *hm,
                          const char* host,int port,const char* msg,
                          int msg_len,const char* cache_file){
  EnableHostfile();
  int sock = socket(AF_INET, SOCK_STREAM, 0) ;
  SetSocketBuf(sock);
  SetSocketBuf(nc->sock);
  struct sockaddr_in server_addr ;
  bzero(&server_addr, sizeof(server_addr)) ;
  server_addr.sin_port = htons(port) ;
  struct hostent *lh = gethostbyname(host);
  memcpy (&server_addr.sin_addr.s_addr, lh->h_addr_list[0], lh->h_length);
  server_addr.sin_family = AF_INET;
  int i = connect(sock, (const struct sockaddr *)&server_addr, sizeof(server_addr)) ;
  RedirectTargetHost();
  if (i >= 0) {
    long w = write(sock, msg, msg_len);
    if (w > 0) {
      char residue_data[kMaxBufLength] = {0};
      int residue_len = 0;
      char http_header_cache[kMaxBufLength] = {0};
      HTTPHeadersParse(sock,http_header_cache,kMaxBufLength,residue_data,&residue_len);
      struct content_range out;
      bool is_already_down = (access(cache_file, 0)!=-1);
      if (is_already_down) {
        struct stat buf;
        size_t cl = 0;
        char* p = strstr(http_header_cache,"Content-Length:");
        if (p) {
          sscanf (p,"Content-Length: %lu\r\n",&cl);
          printf("anslysis Content-Length: %lu\r\n",cl);
        }
        if (stat(cache_file,&buf)==0) {
          printf("Content-Length:%lu-%lld\r\n",cl,buf.st_size);
          if (cl!=buf.st_size){
            is_already_down = false;
          }
        }
      }
      if (!is_already_down||GetContentRange(http_header_cache,&out)){
        mg_send(nc, http_header_cache, strlen(http_header_cache));
        FILE* fp = NULL;
        if (out.content_start_count>0&&out.content_end_count>0) {
          //resume an interrupted download
          fp = fopen(cache_file,"ab");
          fseek(fp,out.content_start_count,SEEK_SET);
        }
        else{
          fp = fopen(cache_file,"wb");
        }
        if (fp!=NULL) {
          while (ftrylockfile(fp)) {
            sleep(1);
          }
          if (residue_len){
            fwrite(residue_data, residue_len, 1, fp);
            mg_send(nc,residue_data,residue_len);
          }
          //char buffer[kMaxSocketBufferSize] = {0};
          for(int len=0;((len=read(sock, socket_buffer, kMaxSocketBufferSize))>0);){
            fwrite(socket_buffer, len, 1, fp);
            fflush(fp);
            mg_send(nc,socket_buffer,len);
            memset(socket_buffer,0,len);
          }
          funlockfile(fp);
          fclose(fp);
        }
      }
      else{
        //char buffer[kMaxSocketBufferSize] = {0};
        //mg_send_file()
        //handle_file_request
        //http://comments.gmane.org/gmane.comp.lib.mongoose/1539
        cs_stat_t stp;
        mg_stat(cache_file,&stp);
        if (stp.st_size<0) {
          mg_http_send_error(nc,404,"File Found!");
          return;
        }
        struct mg_str *hdr = mg_get_http_header(hm, "Range");
        if (hdr != NULL){
          //FixMe
          printf("-----------send file status code 206-----------\t\n");
          const struct mg_str mime_type = mg_mk_str("application/octet-stream");
          mg_http_serve_file(nc,hm,cache_file,mime_type,mg_mk_str(http_header_cache));
          return;
        }
        FILE* fp = fopen(cache_file,"rb");
        if (fp==NULL) {
          mg_http_send_error(nc,500,"GetOriginServerCache");
          return;
        }
        printf("-----------send file status code 200-----------\t\n");
        mg_send(nc, http_header_cache, strlen(http_header_cache));
        while (ftrylockfile(fp)!=0) {
          sleep(1);
        }
        fseek(fp,0,SEEK_SET);
        //mg_send_file_data(nc, fp);
        while(!feof(fp)){
          char buf[kMaxBufLength] = {0};
          int len = fread(buf,1,kMaxBufLength,fp);
          if(len<=0){
            perror(cache_file);
            break;
          }
          mg_send(nc,buf,len);
          //printf("mg_send!\r\n");
        }
        funlockfile(fp);
        fclose(fp);
      }
    }
    else{
      printf("write failed!\r\n");
    }
  }
  else{
    printf("connect failed!\r\n");
  }
  close(sock);
}

bool mkdirp(const char* path, mode_t mode) {
  // const cast for hack
  char* p = const_cast<char*>(path);
  // Do mkdir for each slash until end of string or error
  while (*p != '\0') {
    // Skip first character
    p++;
    // Find first slash or end
    while(*p != '\0' && *p != '/') p++;
    // Remember value from p
    char v = *p;
    // Write end of string at p
    *p = '\0';
    // Create folder from path to '\0' inserted at p
    if(mkdir(path, mode) == -1 && errno != EEXIST) {
      *p = v;
      return false;
    }
    // Restore path to it's former glory
    *p = v;
  }
  return true;
}
void ev_handler(struct mg_connection *nc, int ev, void *ev_data) {
 switch (ev) {
    case MG_EV_ACCEPT: {
      char addr[32];
      mg_sock_addr_to_str(&nc->sa, addr, sizeof(addr),
                          MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_PORT);
      printf("Connection from %s\r\n", addr);
      break;
    }
    case MG_EV_HTTP_REQUEST: {
      struct http_message *hm = (struct http_message *) ev_data;
      char addr[32];
      mg_sock_addr_to_str(&nc->sa, addr, sizeof(addr),
                          MG_SOCK_STRINGIFY_IP | MG_SOCK_STRINGIFY_PORT);
      if (strncmp(hm->method.p,"GET",hm->method.len) != 0&&strncmp(hm->method.p,"POST",hm->method.len) != 0){
        nc->flags |= MG_F_SEND_AND_CLOSE;
        mg_http_send_error(nc,400,"RequestMethodERROR");
        break;
      }
      printf("%.*s", (int) hm->message.len, hm->message.p);
      static char apple_assets_api[] = "/apple-assets-us-std-000001/";
      static char is_initial_ok_api[] = "/IsInitialOK";
      static bool is_initial_ok = false;
      if (strncmp(hm->uri.p, apple_assets_api,sizeof(apple_assets_api) - sizeof(char)) == 0) {
        pthread_mutex_lock(&global_mutex);
        is_initial_ok = false;
        struct mg_str* encoding = NULL;
        if(((encoding=mg_get_http_header(hm,"Accept-Encoding"))!=NULL)&&strstr(encoding->p,"gzip") != NULL){
          //buffer overflow
          char gz_bin[4096] = "/tmp";
          strcat(gz_bin,hm->uri.p);
          mkdirp(gz_bin,0777);
          memset(strstr(gz_bin,"?"),0,1);
          //ping iosapps.itunes.apple.com  ...........get hpcc-download.apple.cnc.ccgslb.com.cn
          GetOriginServerCache(nc,hm,"hpcc-download.apple.cnc.ccgslb.com.cn",80,hm->message.p,hm->message.len,gz_bin);
          is_initial_ok = true;
          nc->flags |= MG_F_SEND_AND_CLOSE;
          //mg_http_serve_file(nc, hm, gz_bin,mg_mk_str("application/octet-stream"),mg_mk_str(http_header_cache));
        }
        pthread_mutex_unlock(&global_mutex);
      }
      else if (strncmp(hm->uri.p, is_initial_ok_api,sizeof(is_initial_ok_api) - sizeof(char)) == 0) {
        nc->flags |= MG_F_SEND_AND_CLOSE;
        if (!is_initial_ok)
          mg_http_send_error(nc,200,"false");
        else
          mg_http_send_error(nc,200,"true");
      }
      else{
        nc->flags |= MG_F_SEND_AND_CLOSE;
        mg_http_send_error(nc,500,"APINotExist");
      }
      break;
    }
    case MG_EV_CLOSE: {
      printf("Connection closed\r\n");
      break;
    }
  }
}
bool CheckPortBindAvailable(int port){
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if(sock < 0) {
    printf("socket error\n");
    return false;
  }
  printf("Opened %d\n", sock);
  
  struct sockaddr_in serv_addr;
  bzero((char *) &serv_addr, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  serv_addr.sin_addr.s_addr = INADDR_ANY;
  serv_addr.sin_port = htons(port);
  if (bind(sock, (struct sockaddr *) &serv_addr, sizeof(serv_addr)) < 0) {
    if(errno == EADDRINUSE) {
      printf("the port is not available. already to other process\n");
      return false;
    } else {
      printf("could not bind to process (%d) %s\n", errno, strerror(errno));
      return false;
    }
  }
  
  socklen_t len = sizeof(serv_addr);
  if (getsockname(sock, (struct sockaddr *)&serv_addr, &len) == -1) {
    perror("getsockname");
  }
  
  printf("port number %d\n", ntohs(serv_addr.sin_port));
  
  
  if (close (sock) < 0 ) {
    printf("did not close: %s\n", strerror(errno));
    perror("close (sock)");
  }
  return true;
}

int main(int argc, const char **argv, const char **envp) {
  setuid(0);
  setgid(0);
  if (argc==2&&!strncmp(argv[1],"-run",4)) {
    if (CheckPortBindAvailable(80)==true) {
      pid_t pid;
      extern char **environ;
      int r = posix_spawn(&pid,argv[0],NULL,NULL,NULL,environ);
      printf("status:%d\r\n",r);
      return r;
    }
    return -1;
  }
  while(true){
    pid_t pid;
    pid = fork();
    if (pid == -1) {
      perror("Error forking");
      return -1;
    }
    else if (pid > 0){
      waitpid(-1, NULL, 0);
    }
    else {
      socket_buffer = (char*)malloc(kMaxSocketBufferSize);
      struct mg_mgr mgr;
      struct mg_connection *nc;
      pthread_mutex_init(&global_mutex, NULL);
      RedirectTargetHost();
      mg_mgr_init(&mgr, NULL);
      printf("Starting web server on port %s\n", s_http_port);
      bool is_bind_ok = false;
      while (!is_bind_ok) {
        nc = mg_bind(&mgr, s_http_port, ev_handler);
        if (nc == NULL) {
          printf("Failed to create listener\n");
          return 1;
        }
        is_bind_ok = true;
      }
      mg_set_protocol_http_websocket(nc);
      mg_enable_multithreading(nc);
      for(;;)
        mg_mgr_poll(&mgr, 1000);
      mg_mgr_free(&mgr);
    }
  }
  return 0;
}
