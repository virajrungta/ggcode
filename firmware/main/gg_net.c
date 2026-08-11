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
#include "gg_http.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "wifi_provisioning/manager.h"
#include "wifi_provisioning/scheme_ble.h"

static const char *TAG = "gg_net";

#define MAX_RECONNECT_BACKOFF_MS 60000
#define SEEN_CMD_RING 16

static gg_net_state_t    s_state = GG_NET_IDLE;
static gg_net_pump_cb_t  s_pump_cb = NULL;
static char              s_device_id[13] = {0};
static char              s_claim_code[12] = {0};
static bool              s_time_synced = false;
static bool              s_cloud_ok = false;

/* Issued by /v1/ingest/bootstrap and persisted, so a reboot does not need a
 * round trip before the pot can report. */
static char              s_secret[80] = {0};

// Batched telemetry, flushed on count or interval (contracts/telemetry.md).
static gg_reading_t      s_batch[GG_BATCH_MAX_SAMPLES];
static uint8_t           s_batch_flags[GG_BATCH_MAX_SAMPLES];
static time_t            s_batch_ts[GG_BATCH_MAX_SAMPLES];
static int               s_batch_len = 0;
static SemaphoreHandle_t s_batch_lock = NULL;

/* HTTP ingest marks commands sent as it hands them out, so redelivery should
 * not happen — but a response lost after the server committed would look
 * exactly like a new command. Without dedup that reruns "water 5s". */
static char s_seen_cmds[SEEN_CMD_RING][24];
static int  s_seen_idx = 0;

// --- helpers -------------------------------------------------------------

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
    if (s_cloud_ok)                  f |= GG_FLAG_MQTT_CONNECTED;
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

/* The code must survive a reboot. Regenerating it every boot was circular in
 * practice: reading the code required resetting the board over serial, and
 * the reset changed it — one reset invalidated a code mid-pairing. It is also
 * the token the pot presents to /v1/ingest/bootstrap, so a code that changes
 * is a device that can never authenticate twice. */
static void load_or_create_claim_code(void) {
    nvs_handle_t h;
    if (nvs_open(GG_NVS_NAMESPACE, NVS_READWRITE, &h) != ESP_OK) {
        ESP_LOGW(TAG, "NVS unavailable; claim code will not persist");
        generate_claim_code();
        return;
    }

    size_t len = sizeof(s_claim_code);
    if (nvs_get_str(h, GG_NVS_CLAIM_CODE, s_claim_code, &len) == ESP_OK
            && s_claim_code[0]) {
        nvs_close(h);
        return;
    }

    generate_claim_code();
    if (nvs_set_str(h, GG_NVS_CLAIM_CODE, s_claim_code) == ESP_OK) {
        nvs_commit(h);
        ESP_LOGI(TAG, "generated and stored a new claim code");
    }
    nvs_close(h);
}

static void load_secret(void) {
    nvs_handle_t h;
    if (nvs_open(GG_NVS_NAMESPACE, NVS_READONLY, &h) != ESP_OK) return;
    size_t len = sizeof(s_secret);
    if (nvs_get_str(h, GG_NVS_MQTT_SECRET, s_secret, &len) != ESP_OK) {
        s_secret[0] = '\0';
    }
    nvs_close(h);
}

static void store_secret(void) {
    nvs_handle_t h;
    if (nvs_open(GG_NVS_NAMESPACE, NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_str(h, GG_NVS_MQTT_SECRET, s_secret);
    nvs_commit(h);
    nvs_close(h);
}

/* Exchanges the claim code for a telemetry secret. Called on first boot and
 * again whenever the backend rejects the stored one, which is what keeps a
 * pot recoverable without a reflash after the secret is rotated. */
static bool ensure_secret(void) {
    if (s_secret[0]) return true;

    esp_err_t err = gg_http_bootstrap(s_device_id, s_claim_code,
                                      GG_FW_VERSION, s_secret, sizeof(s_secret));
    if (err != ESP_OK) {
        s_secret[0] = '\0';
        /* The usual cause is that no `devices` row exists for this pot yet:
         * bootstrap authenticates, it deliberately does not register. Say so,
         * because the symptom is otherwise a pot that silently never reports.
         * See backend/scripts/register_device.py. */
        ESP_LOGW(TAG, "bootstrap failed (%s) - is device %s registered with "
                      "claim code %s?", esp_err_to_name(err),
                 s_device_id, s_claim_code);
        return false;
    }

    store_secret();
    ESP_LOGI(TAG, "bootstrapped telemetry credentials");
    return true;
}

// --- cloud transport (HTTP) ----------------------------------------------

static void ack_command(const char *id, const char *result, const char *error) {
    esp_err_t err = gg_http_ack(s_device_id, s_secret, id, result, error);
    if (err != ESP_OK) {
        /* Best-effort by design. A lost ack leaves the command marked `sent`
         * server-side, which is visible in the database rather than silently
         * forgotten. Retrying here would risk running the pump twice. */
        ESP_LOGW(TAG, "ack for %s not delivered: %s", id, esp_err_to_name(err));
    }
}

static void handle_command(const cJSON *root) {
    const cJSON *jid  = cJSON_GetObjectItem(root, "id");
    const cJSON *jop  = cJSON_GetObjectItem(root, "op");
    const cJSON *jexp = cJSON_GetObjectItem(root, "expires_at");

    if (!cJSON_IsString(jid) || !cJSON_IsString(jop)) return;
    const char *id = jid->valuestring;

    if (cmd_already_seen(id)) {
        ESP_LOGI(TAG, "duplicate command %s ignored", id);
        return;
    }

    /* Expiry is enforced here, not merely advisory. A pot that was offline
     * comes back to whatever is still queued; without this check a "water 5s"
     * issued this morning fires tonight. */
    if (cJSON_IsNumber(jexp) && s_time_synced) {
        if ((time_t)jexp->valuedouble < time(NULL)) {
            ESP_LOGW(TAG, "command %s expired - refusing", id);
            ack_command(id, "expired", NULL);
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
        ack_command(id, ok ? "ok" : "rejected", ok ? NULL : res);
        ESP_LOGI(TAG, "cloud pump command %s -> %s", id, res);
    } else {
        ack_command(id, "rejected", "unsupported_op");
    }
}

/* Commands ride back in the telemetry response rather than arriving on their
 * own connection. That is the whole reason this transport works on hosting
 * that sleeps: there is nothing to stay subscribed to. */
static void handle_response(const char *body) {
    cJSON *root = cJSON_Parse(body);
    if (!root) return;

    const cJSON *cmds = cJSON_GetObjectItem(root, "commands");
    if (cJSON_IsArray(cmds)) {
        const cJSON *cmd = NULL;
        cJSON_ArrayForEach(cmd, cmds) {
            handle_command(cmd);
        }
    }

    /* The server's clock, used when SNTP is unreachable. Without it
     * expires_at above cannot be evaluated and every command is applied
     * regardless of age. */
    const cJSON *st = cJSON_GetObjectItem(root, "server_time");
    if (!s_time_synced && cJSON_IsNumber(st) && st->valuedouble > 1.7e9) {
        struct timeval tv = { .tv_sec = (time_t)st->valuedouble };
        settimeofday(&tv, NULL);
        s_time_synced = true;
        ESP_LOGI(TAG, "clock set from server_time");
    }

    cJSON_Delete(root);
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
    if (s_state < GG_NET_CONNECTED || s_batch_len == 0) return;
    if (!ensure_secret()) return;
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

    /* Sized for the command downlink, not the batch: the response is an
     * accepted/rejected count plus at most 8 pending commands. */
    static char resp[1024];
    esp_err_t err = gg_http_post_telemetry(s_device_id, s_secret, payload,
                                           resp, sizeof(resp));

    if (err == GG_ERR_HTTP_UNAUTHORIZED) {
        /* The stored secret is stale — most often because the pot was
         * re-registered. Drop it and bootstrap once more; the samples are
         * already gone from the batch, so this costs one window rather than
         * leaving the pot mute until someone reflashes it. */
        ESP_LOGW(TAG, "secret rejected, re-bootstrapping");
        s_secret[0] = '\0';
        store_secret();
        s_cloud_ok = false;
        if (s_state == GG_NET_CLOUD_OK) s_state = GG_NET_CONNECTED;
        free(payload);
        return;
    }

    if (err != ESP_OK) {
        s_cloud_ok = false;
        if (s_state == GG_NET_CLOUD_OK) s_state = GG_NET_CONNECTED;
        ESP_LOGW(TAG, "telemetry POST failed: %s", esp_err_to_name(err));
        free(payload);
        return;
    }

    s_cloud_ok = true;
    s_state = GG_NET_CLOUD_OK;
    ESP_LOGI(TAG, "posted %d samples (%d bytes)", count, (int)strlen(payload));
    free(payload);

    handle_response(resp);
}

esp_err_t gg_net_publish_event(const char *kind, const char *data_json) {
    /* Events had an MQTT topic; HTTP ingest has no equivalent endpoint yet,
     * so a local watering is logged but not reported. Kept as a call site
     * rather than deleted: the pump path already produces the event, and
     * dropping it here would hide that the uplink is what is missing.
     * Tracked in docs/BACKLOG.md. */
    ESP_LOGI(TAG, "event %s %s (not uplinked: no HTTP event endpoint)",
             kind, data_json ? data_json : "{}");
    return ESP_OK;
}

static void publish_task(void *arg) {
    /* Flush when the batch is full *or* the interval elapses, whichever comes
     * first -- which is what contracts/telemetry.md specifies and what the
     * header claims, but the interval alone was doing. In bringup mode that
     * mismatch was silently lossy: sampling every 2s fills a 12-sample batch
     * in 24s, and the remaining ~4.5 minutes of readings were dropped on the
     * floor by gg_net_queue_reading. At the production 60s cadence a full
     * batch takes 12 minutes, so the interval still wins there. */
    TickType_t last = xTaskGetTickCount();
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(1000));

        TickType_t now = xTaskGetTickCount();
        TickType_t since = now - last;

        // Rate limit first, so a failing send cannot spin.
        if (since < pdMS_TO_TICKS(GG_PUBLISH_MIN_GAP_MS)) continue;

        /* Read without the lock: a stale int here costs at most one extra
         * second of latency, and taking the mutex every second to poll would
         * contend with the sampling task for no benefit. */
        bool full = s_batch_len >= GG_BATCH_MAX_SAMPLES;
        bool due  = since >= pdMS_TO_TICKS(GG_PUBLISH_INTERVAL_MS);
        if (!full && !due) continue;

        // Stamped before the attempt, so a failure backs off too.
        last = now;
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
        s_cloud_ok = false;
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
    /* The manager must be initialised with a transport scheme before it can
     * start. Missing this produced "Provisioning manager not initialized" on
     * the bench — the call returned an error and the device simply sat there
     * advertising with no way to be configured.
     *
     * scheme_ble stands up its own GATT service, which is why app_main runs
     * either this or our telemetry GATT server, never both: two owners of the
     * same BLE stack is not a supported configuration. */
    wifi_prov_mgr_config_t cfg = {
        .scheme = wifi_prov_scheme_ble,
        .scheme_event_handler = WIFI_PROV_SCHEME_BLE_EVENT_HANDLER_FREE_BTDM,
    };
    esp_err_t err = wifi_prov_mgr_init(cfg);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "wifi_prov_mgr_init failed: %s", esp_err_to_name(err));
        return err;
    }

    /* Security1 uses the claim code as a proof-of-possession. Security2
     * (SRP6a) is stronger but needs a salt/verifier pair generated per device
     * at manufacture; wire that in when there is a provisioning step in the
     * production flow. Either way the credentials are encrypted in transit —
     * this is not a plaintext characteristic. */
    ESP_LOGI(TAG, "starting BLE provisioning as %s (pop=%s)", service_name, pop);
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
    load_or_create_claim_code();
    load_secret();

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

    /* 12 KB, not the 4 KB that sufficed for MQTT. A TLS handshake plus
     * certificate-bundle verification runs on the calling task's stack, and
     * 4 KB overflowed on the first HTTPS POST -- the board reboot-looped,
     * which reads as a hang rather than as a stack problem. */
    xTaskCreate(publish_task, "gg_publish", 12288, NULL, 4, NULL);

    ESP_LOGI(TAG, "net init: device_id=%s claim_code=%s",
             s_device_id, s_claim_code);
    return ESP_OK;
}
