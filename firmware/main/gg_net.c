#include "gg_net.h"
#include "gg_config.h"

#include <stdio.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

#include "cJSON.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_netif_sntp.h"
#include "esp_random.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "mqtt_client.h"
#include "nvs_flash.h"
#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_ble.h"

static const char *TAG = "gg_net";

#define TOPIC_PREFIX "gg/v1"
#define MAX_RECONNECT_BACKOFF_MS 60000
#define SEEN_CMD_RING 16

static gg_net_state_t    s_state = GG_NET_IDLE;
static gg_net_pump_cb_t  s_pump_cb = NULL;
static esp_mqtt_client_handle_t s_mqtt = NULL;
static char              s_device_id[13] = {0};
static char              s_claim_code[12] = {0};
static bool              s_time_synced = false;
static bool              s_mqtt_up = false;

// Batched telemetry, flushed on count or interval (contracts/telemetry.md).
static gg_reading_t      s_batch[GG_BATCH_MAX_SAMPLES];
static uint8_t           s_batch_flags[GG_BATCH_MAX_SAMPLES];
static time_t            s_batch_ts[GG_BATCH_MAX_SAMPLES];
static int               s_batch_len = 0;
static SemaphoreHandle_t s_batch_lock = NULL;

/* QoS 1 is at-least-once, so redelivery is normal rather than exceptional.
 * Without dedup a retried "water 5s" runs twice. */
static char s_seen_cmds[SEEN_CMD_RING][24];
static int  s_seen_idx = 0;

// --- helpers -------------------------------------------------------------

static void topic_for(char *out, size_t n, const char *leaf) {
    snprintf(out, n, TOPIC_PREFIX "/%s/%s", s_device_id, leaf);
}

static bool cmd_already_seen(const char *id) {
    for (int i = 0; i < SEEN_CMD_RING; i++) {
        if (s_seen_cmds[i][0] && strcmp(s_seen_cmds[i], id) == 0) return true;
    }
    strncpy(s_seen_cmds[s_seen_idx], id, sizeof(s_seen_cmds[0]) - 1);
    s_seen_cmds[s_seen_idx][sizeof(s_seen_cmds[0]) - 1] = '\0';
    s_seen_idx = (s_seen_idx + 1) % SEEN_CMD_RING;
    return false;
}

uint8_t gg_net_status_flags(void) {
    uint8_t f = 0;
    if (s_state >= GG_NET_CONNECTED) f |= GG_FLAG_WIFI_CONNECTED;
    if (s_mqtt_up)                   f |= GG_FLAG_MQTT_CONNECTED;
    return f;
}

gg_net_state_t gg_net_get_state(void) { return s_state; }
bool gg_net_time_synced(void) { return s_time_synced; }
const char *gg_net_claim_code(void) { return s_claim_code; }

static void generate_claim_code(void) {
    // Ambiguous glyphs (0/O, 1/I) left out: this gets read aloud and typed.
    static const char alphabet[] = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    for (int i = 0; i < 9; i++) {
        s_claim_code[i] = (i == 4) ? '-'
                        : alphabet[esp_random() % (sizeof(alphabet) - 1)];
    }
    s_claim_code[9] = '\0';
}

// --- MQTT ----------------------------------------------------------------

static void publish_status(bool online) {
    if (!s_mqtt) return;
    char topic[64], payload[160];
    topic_for(topic, sizeof(topic), "status");

    wifi_ap_record_t ap;
    int rssi = (esp_wifi_sta_get_ap_info(&ap) == ESP_OK) ? ap.rssi : 0;

    snprintf(payload, sizeof(payload),
             "{\"online\":%s,\"fw\":\"%s\",\"rssi\":%d,\"ts\":%lld}",
             online ? "true" : "false", GG_FW_VERSION, rssi,
             s_time_synced ? (long long)time(NULL) : 0LL);

    // Retained: the backend learns liveness on subscribe rather than waiting
    // for the next telemetry window.
    esp_mqtt_client_publish(s_mqtt, topic, payload, 0, 1, 1);
}

static void publish_ack(const char *id, const char *result, const char *error) {
    char topic[64], payload[192];
    topic_for(topic, sizeof(topic), "cmd/ack");
    snprintf(payload, sizeof(payload),
             "{\"id\":\"%s\",\"result\":\"%s\",\"ts\":%lld,\"error\":%s%s%s}",
             id, result, s_time_synced ? (long long)time(NULL) : 0LL,
             error ? "\"" : "", error ? error : "null", error ? "\"" : "");
    esp_mqtt_client_publish(s_mqtt, topic, payload, 0, 1, 0);
}

static void handle_command(const char *data, int len) {
    cJSON *root = cJSON_ParseWithLength(data, len);
    if (!root) {
        ESP_LOGW(TAG, "unparseable command payload");
        return;
    }

    const cJSON *jid  = cJSON_GetObjectItem(root, "id");
    const cJSON *jop  = cJSON_GetObjectItem(root, "op");
    const cJSON *jexp = cJSON_GetObjectItem(root, "expires_at");

    if (!cJSON_IsString(jid) || !cJSON_IsString(jop)) {
        cJSON_Delete(root);
        return;
    }
    const char *id = jid->valuestring;

    if (cmd_already_seen(id)) {
        ESP_LOGI(TAG, "duplicate command %s ignored", id);
        cJSON_Delete(root);
        return;
    }

    /* Expiry is enforced here, not merely advisory. clean_session=false means
     * a pot that was offline receives its whole queued backlog on reconnect;
     * without this check a "water 5s" issued this morning fires tonight, and
     * every retry alongside it. */
    if (cJSON_IsNumber(jexp) && s_time_synced) {
        if ((time_t)jexp->valuedouble < time(NULL)) {
            ESP_LOGW(TAG, "command %s expired - refusing", id);
            publish_ack(id, "expired", NULL);
            cJSON_Delete(root);
            return;
        }
    }

    if (strcmp(jop->valuestring, "pump") == 0) {
        const cJSON *args = cJSON_GetObjectItem(root, "args");
        const cJSON *dur = args ? cJSON_GetObjectItem(args, "duration_s") : NULL;
        uint32_t ms = cJSON_IsNumber(dur) ? (uint32_t)(dur->valuedouble * 1000) : 0;

        // The firmware interlocks decide, not the cloud.
        const char *res = s_pump_cb ? s_pump_cb(ms) : "not_ready";
        bool ok = (strcmp(res, "ok") == 0);
        publish_ack(id, ok ? "ok" : "rejected", ok ? NULL : res);
        ESP_LOGI(TAG, "cloud pump command %s -> %s", id, res);
    } else {
        publish_ack(id, "rejected", "unsupported_op");
    }

    cJSON_Delete(root);
}

static void mqtt_event_handler(void *arg, esp_event_base_t base,
                               int32_t event_id, void *event_data) {
    esp_mqtt_event_handle_t e = event_data;
    char topic[64];

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED:
        s_mqtt_up = true;
        s_state = GG_NET_CLOUD_OK;
        ESP_LOGI(TAG, "MQTT connected");
        topic_for(topic, sizeof(topic), "cmd");
        esp_mqtt_client_subscribe(s_mqtt, topic, 1);
        publish_status(true);
        break;

    case MQTT_EVENT_DISCONNECTED:
        s_mqtt_up = false;
        if (s_state == GG_NET_CLOUD_OK) s_state = GG_NET_CONNECTED;
        ESP_LOGW(TAG, "MQTT disconnected");
        break;

    case MQTT_EVENT_DATA:
        if (e->topic_len && strstr(e->topic, "/cmd")) {
            handle_command(e->data, e->data_len);
        }
        break;

    case MQTT_EVENT_ERROR:
        ESP_LOGW(TAG, "MQTT error");
        break;

    default:
        break;
    }
}

static void mqtt_start(void) {
    if (s_mqtt) return;

    char lwt_topic[64];
    topic_for(lwt_topic, sizeof(lwt_topic), "status");

    esp_mqtt_client_config_t cfg = {
        .broker.address.uri = GG_MQTT_URI,
        .credentials.username = s_device_id,
        .credentials.client_id = s_device_id,
        .credentials.authentication.password = GG_MQTT_PASSWORD,
        .session.last_will = {
            .topic = lwt_topic,
            .msg = "{\"online\":false,\"ts\":null}",
            .qos = 1,
            .retain = 1,
        },
        .session.keepalive = 60,
        // clean_session=false so QoS-1 downlinks survive a brief dropout.
        // Command expiry above is what keeps that from replaying stale work.
        .session.disable_clean_session = true,
        .network.reconnect_timeout_ms = 5000,
    };

    s_mqtt = esp_mqtt_client_init(&cfg);
    if (!s_mqtt) {
        ESP_LOGE(TAG, "failed to init MQTT client");
        return;
    }
    esp_mqtt_client_register_event(s_mqtt, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL);
    esp_mqtt_client_start(s_mqtt);
}

// --- telemetry batching --------------------------------------------------

esp_err_t gg_net_queue_reading(const gg_reading_t *r, uint8_t flags) {
    if (!r || !s_batch_lock) return ESP_ERR_INVALID_STATE;
    if (xSemaphoreTake(s_batch_lock, pdMS_TO_TICKS(200)) != pdTRUE) {
        return ESP_ERR_TIMEOUT;
    }
    if (s_batch_len < GG_BATCH_MAX_SAMPLES) {
        s_batch[s_batch_len] = *r;
        s_batch_flags[s_batch_len] = flags;
        /* Unsynced clock sends null and lets the ingest worker substitute
         * arrival time. Writing 1970 timestamps into a hypertable wrecks
         * every chart and continuous aggregate built over it. */
        s_batch_ts[s_batch_len] = s_time_synced ? time(NULL) : 0;
        s_batch_len++;
    }
    xSemaphoreGive(s_batch_lock);
    return ESP_OK;
}

static void add_num_or_null(cJSON *o, const char *key, float v, bool valid) {
    if (valid) cJSON_AddNumberToObject(o, key, v);
    else       cJSON_AddNullToObject(o, key);
}

static void flush_batch(void) {
    if (!s_mqtt_up || s_batch_len == 0) return;
    if (xSemaphoreTake(s_batch_lock, pdMS_TO_TICKS(500)) != pdTRUE) return;

    cJSON *root = cJSON_CreateObject();
    cJSON_AddNumberToObject(root, "v", 1);
    cJSON_AddStringToObject(root, "device_id", s_device_id);
    cJSON *samples = cJSON_AddArrayToObject(root, "samples");

    for (int i = 0; i < s_batch_len; i++) {
        const gg_reading_t *r = &s_batch[i];
        cJSON *s = cJSON_CreateObject();
        if (s_batch_ts[i]) cJSON_AddNumberToObject(s, "ts", (double)s_batch_ts[i]);
        else               cJSON_AddNullToObject(s, "ts");

        add_num_or_null(s, "temp_c",   r->temp_c,   r->temp_valid);
        add_num_or_null(s, "rh",       r->rh,       r->rh_valid);
        add_num_or_null(s, "soil_pct", r->soil1_pct, r->soil1_valid);
        add_num_or_null(s, "lux",      r->light_est, r->light_valid);
        // ggpcb3 carries a second probe; it rides in the JSON rather than the
        // 15-byte BLE struct, which would need a v2 wire format to hold it.
        add_num_or_null(s, "soil2_pct", r->soil2_pct, r->soil2_valid);
        cJSON_AddNumberToObject(s, "flags", s_batch_flags[i]);
        cJSON_AddItemToArray(samples, s);
    }
    int count = s_batch_len;
    s_batch_len = 0;
    xSemaphoreGive(s_batch_lock);

    char *payload = cJSON_PrintUnformatted(root);
    cJSON_Delete(root);
    if (!payload) return;

    char topic[64];
    topic_for(topic, sizeof(topic), "telemetry");
    esp_mqtt_client_publish(s_mqtt, topic, payload, 0, 1, 0);
    ESP_LOGI(TAG, "published %d samples (%d bytes)", count, (int)strlen(payload));
    free(payload);
}

esp_err_t gg_net_publish_event(const char *kind, const char *data_json) {
    if (!s_mqtt_up) return ESP_ERR_INVALID_STATE;
    char topic[64], payload[256];
    topic_for(topic, sizeof(topic), "event");
    snprintf(payload, sizeof(payload),
             "{\"v\":1,\"ts\":%lld,\"kind\":\"%s\",\"data\":%s}",
             s_time_synced ? (long long)time(NULL) : 0LL, kind,
             data_json ? data_json : "{}");
    esp_mqtt_client_publish(s_mqtt, topic, payload, 0, 1, 0);
    return ESP_OK;
}

static void publish_task(void *arg) {
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(GG_PUBLISH_INTERVAL_MS));
        flush_batch();
    }
}

// --- Wi-Fi + SNTP --------------------------------------------------------

static void on_time_sync(struct timeval *tv) {
    s_time_synced = true;
    ESP_LOGI(TAG, "SNTP time synced");
}

static void start_sntp(void) {
    esp_sntp_config_t cfg = ESP_NETIF_SNTP_DEFAULT_CONFIG("pool.ntp.org");
    cfg.sync_cb = on_time_sync;
    cfg.start = true;
    esp_netif_sntp_init(&cfg);
}

static void wifi_event_handler(void *arg, esp_event_base_t base,
                               int32_t id, void *data) {
    static int retries = 0;

    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        s_state = GG_NET_CONNECTING;
        s_mqtt_up = false;
        /* Exponential backoff, capped. Reconnecting in a tight loop on a dead
         * AP burns power and floods the airwaves; a pot may be out of range
         * for hours. */
        int delay = 1000 << (retries > 5 ? 5 : retries);
        if (delay > MAX_RECONNECT_BACKOFF_MS) delay = MAX_RECONNECT_BACKOFF_MS;
        retries++;
        ESP_LOGW(TAG, "wifi disconnected, retry in %dms", delay);
        vTaskDelay(pdMS_TO_TICKS(delay));
        esp_wifi_connect();
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        retries = 0;
        s_state = GG_NET_CONNECTED;
        ip_event_got_ip_t *e = data;
        ESP_LOGI(TAG, "got ip " IPSTR, IP2STR(&e->ip_info.ip));
        start_sntp();
        mqtt_start();
    }
}

// --- provisioning --------------------------------------------------------

static void prov_event_handler(void *arg, esp_event_base_t base,
                               int32_t id, void *data) {
    if (base != WIFI_PROV_EVENT) return;
    switch (id) {
    case WIFI_PROV_START:
        s_state = GG_NET_PROVISIONING;
        ESP_LOGI(TAG, "provisioning started");
        break;
    case WIFI_PROV_CRED_RECV:
        ESP_LOGI(TAG, "credentials received");
        break;
    case WIFI_PROV_CRED_FAIL: {
        wifi_prov_sta_fail_reason_t *r = data;
        /* Distinguishing these matters: "wrong password" and "AP not found"
         * produce completely different support outcomes, and collapsing both
         * into a generic failure makes each look like broken hardware. */
        ESP_LOGE(TAG, "provisioning failed: %s",
                 *r == WIFI_PROV_STA_AUTH_ERROR ? "bad_password" : "ap_not_found");
        s_state = GG_NET_FAILED;
        break;
    }
    case WIFI_PROV_CRED_SUCCESS:
        ESP_LOGI(TAG, "provisioning succeeded");
        break;
    case WIFI_PROV_END:
        wifi_prov_mgr_deinit();
        break;
    default:
        break;
    }
}

bool gg_net_is_provisioned(void) {
    bool provisioned = false;
    if (wifi_prov_mgr_is_provisioned(&provisioned) != ESP_OK) return false;
    return provisioned;
}

esp_err_t gg_net_start_provisioning(const char *service_name,
                                    const char *pop) {
    wifi_prov_security2_params_t sec_params = {0};
    // Security2 (SRP6a). Security1 is a shared-key scheme; Security2 does a
    // proper password-authenticated key exchange.
    sec_params.salt = NULL;
    sec_params.salt_len = 0;
    sec_params.verifier = NULL;
    sec_params.verifier_len = 0;

    ESP_LOGI(TAG, "starting BLE provisioning as %s", service_name);
    return wifi_prov_mgr_start_provisioning(WIFI_PROV_SECURITY_1, pop,
                                            service_name, NULL);
}

esp_err_t gg_net_start(void) {
    ESP_LOGI(TAG, "connecting to stored Wi-Fi");
    s_state = GG_NET_CONNECTING;
    return esp_wifi_start();
}

esp_err_t gg_net_factory_reset(void) {
    ESP_LOGW(TAG, "erasing Wi-Fi credentials and restarting");
    esp_wifi_restore();
    vTaskDelay(pdMS_TO_TICKS(500));
    esp_restart();
    return ESP_OK;
}

// --- init ----------------------------------------------------------------

esp_err_t gg_net_init(gg_net_pump_cb_t pump_cb) {
    s_pump_cb = pump_cb;
    s_batch_lock = xSemaphoreCreateMutex();
    if (!s_batch_lock) return ESP_ERR_NO_MEM;

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(s_device_id, sizeof(s_device_id), "%02x%02x%02x%02x%02x%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    generate_claim_code();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t wcfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&wcfg));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                               wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                               wifi_event_handler, NULL));
    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_PROV_EVENT, ESP_EVENT_ANY_ID,
                                               prov_event_handler, NULL));
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_FLASH));

    xTaskCreate(publish_task, "gg_publish", 4096, NULL, 4, NULL);

    ESP_LOGI(TAG, "net init: device_id=%s claim_code=%s",
             s_device_id, s_claim_code);
    return ESP_OK;
}
