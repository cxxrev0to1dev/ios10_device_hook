#include "mongoose-gzip.h"
#include "mongoose.c"


//#############################################################################
//
#define SERVE_GZ
//
// Version:		0.1
// Start date:	2012/06/26
// Purpose:		Transparenlty serve a static gzipped content file 'path.gz'
//				instead of the requested file 'path' if 'Accept-Encoding' 
//				has 'gzip' in the request header. If the file 'path.gz' 
//				does not exist, then the normal uncompressed file 'path' 
//				will be served.
// Author:		Stephen Dyble (stephen.dyble at yahoo.co.uk)
// Upside:		Compression is already done by gzip.exe, so it doesn't use
//				any cpu resources or external libraries to achieve the end 
//				result.
// Downside:	You have to have two copies of each file, one normal and one 
//				gzipped on the server.
// Modification:Replace the 'handle_file_request' routine with this one in
//				the file 'mongoose.c'
// Enable:		To enable just define SERVE_GZ somewhere in the file before
//				the patch.
//
// Notes:	1)	I am not sure if this is the best place to implement it but 
//				it is currently in 'handle_file_request()' so that the mime 
//				type is not altered in any way by the patch.
//			2)	It is not implemented in 'handle_ssi_file_request()' so ssi 
//				will always send the uncompressed file.
//			3)	strstr() test will fail if the 'Accept-Encoding' parameter 
//				'gzip' in the request header is not lowercase.
//
//#############################################################################
static void handle_file_request(struct mg_connection *conn, const char *path,
                                struct mgstat *stp){
  char date[64], lm[64], etag[64], range[64];
  const char *msg = "OK", *hdr;
  time_t curtime = time(NULL);
  int64_t cl, r1, r2;
  //struct vec mime_vec;
  FILE *fp;
  int n;
  
#ifdef SERVE_GZ // = Steve start === define variables =======================
  const char *encoding;
  int	gzip_content;
#endif // SERVE_GZ = Steve end ==============================================
       //
  //get_mime_type(conn->ctx, path, &mime_vec);
  cl = stp->size;
  conn->request_info.status_code = 200;
  range[0] = '\0';
  
#ifdef SERVE_GZ // = Steve start === check header and open file =============
  fp			= NULL;
  gzip_content	= 0;
  // Fetch 'Accept-Encoding' value from the header
  if((encoding=mg_get_header(conn,"Accept-Encoding"))!=NULL){
    if(strstr(encoding,"gzip")!=NULL){
      int   path_len = strlen(path);
      char *path_gz;
      struct mgstat mgs;
      // Append ".gz" to the path
      if((path_gz=(char*)malloc(path_len+4))!=NULL)
          {
        snprintf(path_gz,path_len+4,"%s.gz",path);
        // Get the file stats to update 'Content-Length' correctly
        if(mg_stat((const char *)path_gz, &mgs)==0)
            {
          // If file opens, adjust content length and serve it...
          if((fp=mg_fopen(path_gz,"rb"))!=NULL){
            gzip_content = 1;
            cl = mgs.size;
            }
          }
          free(path_gz);
          }
        }
      }
  // Only allow normal file open if file not already open
  if (fp==NULL)
#endif // SERVE_GZ = Steve end ==============================================
    
    if ((fp = mg_fopen(path, "rb")) == NULL)
        {
      send_http_error(conn, 500, http_500_error,
                      "fopen(%s): %s", path, strerror(ERRNO));
      return;
        }
  
  mg_set_close_on_exec(fileno(fp));
  
  // If Range: header specified, act accordingly
  r1 = r2 = 0;
  hdr = mg_get_header(conn, "Range");
  if (hdr != NULL && (n = parse_range_header(hdr, &r1, &r2)) > 0)
      {
    conn->request_info.status_code = 206;
    (void) fseeko(fp, (off_t) r1, SEEK_SET);
    cl = n == 2 ? r2 - r1 + 1: cl - r1;
    (void) mg_snprintf(conn, range, sizeof(range),
                       "Content-Range: bytes "
                       "%" INT64_FMT "-%"
                       INT64_FMT "/%" INT64_FMT "\r\n",
                       r1, r1 + cl - 1, stp->size);
    msg = "Partial Content";
      }
  
  // Prepare Etag, Date, Last-Modified headers. Must be in UTC, according to
  // http://www.w3.org/Protocols/rfc2616/rfc2616-sec3.html#sec3.3
  mg_gmt_time_string(date, sizeof(date), &curtime);
  mg_gmt_time_string(lm, sizeof(lm), &stp->mtime);
  (void) mg_snprintf(conn, etag, sizeof(etag), "%lx.%lx",
                     (unsigned long) stp->mtime, (unsigned long) stp->size);
  
#ifdef SERVE_GZ // = Steve start === modify response header =================
  if(gzip_content)
      {
    (void) mg_printf(conn,
                     "HTTP/1.1 %d %s\r\n"
                     "Date: %s\r\n"
                     "Last-Modified: %s\r\n"
                     "Etag: \"%s\"\r\n"
                     "Content-Type: %.*s\r\n"
                     "Content-Length: %" INT64_FMT "\r\n"
                     "Content-Encoding: gzip\r\n"			// <-- Added here ...
                     "Connection: %s\r\n"
                     "Accept-Ranges: bytes\r\n"
                     "%s\r\n",
                     conn->request_info.status_code, msg, date, lm, etag, (int) mime_vec.len,
                     mime_vec.ptr, cl, suggest_connection_header(conn), range);
      }
  else
#endif // SERVE_GZ = Steve end ==============================================
    
    (void) mg_printf(conn,
                     "HTTP/1.1 %d %s\r\n"
                     "Date: %s\r\n"
                     "Last-Modified: %s\r\n"
                     "Etag: \"%s\"\r\n"
                     "Content-Type: %.*s\r\n"
                     "Content-Length: %" INT64_FMT "\r\n"
                     "Connection: %s\r\n"
                     "Accept-Ranges: bytes\r\n"
                     "%s\r\n",
                     conn->request_info.status_code, msg, date, lm, etag, (int) mime_vec.len,
                     mime_vec.ptr, cl, suggest_connection_header(conn), range);
  
  if (strcmp(conn->request_info.request_method, "HEAD") != 0){
    FILE *fp = mg_fopen(path_gz,"rb");
    mg_send_file_data(conn, fp, cl);
    fclose(fp);
  }
  (void) fclose(fp);
}
