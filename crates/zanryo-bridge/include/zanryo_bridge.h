#ifndef ZANRYO_BRIDGE_H
#define ZANRYO_BRIDGE_H

typedef struct ZanryoHandle ZanryoHandle;

ZanryoHandle *zanryo_create(void);
char *zanryo_provider_discovery_json(void);
char *zanryo_cached_json(ZanryoHandle *handle);
char *zanryo_refresh_json(ZanryoHandle *handle);
char *zanryo_claude_cached_json(ZanryoHandle *handle);
char *zanryo_claude_refresh_json(ZanryoHandle *handle, const char *working_directory);
void zanryo_string_free(char *value);
void zanryo_destroy(ZanryoHandle *handle);

#endif
