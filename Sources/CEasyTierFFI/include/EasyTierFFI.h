#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct KeyValuePair {
  const char *key;
  const char *value;
} KeyValuePair;

typedef void (*ConfigServerEventCallback)(const char *event_json, void *user_data);

int32_t parse_config(const char *cfg_str);
int32_t run_network_instance(const char *cfg_str);
int32_t retain_network_instance(const char **inst_names, uintptr_t length);
int32_t delete_network_instance(const char **inst_names, uintptr_t length);
int32_t list_instance(KeyValuePair *infos, uintptr_t max_length);
int32_t collect_network_infos(KeyValuePair *infos, uintptr_t max_length);
int32_t call_json_rpc(const char *service_name, const char *method_name, const char *domain_name, const char *payload_json, const char **out_response_json);
int32_t start_config_server_client(const char *config_server_url, const char *hostname, const char *machine_id, bool secure_mode, ConfigServerEventCallback callback, void *user_data);
int32_t stop_config_server_client(void);
int32_t is_config_server_client_connected(void);
void get_error_msg(const char **out);
void free_string(const char *s);
