#include "mongoose.h"


static void handle_file_request(struct mg_connection *conn, const char *path,
                                struct mgstat *stp);
