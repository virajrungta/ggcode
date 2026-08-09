#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"
#include "gg_sensors.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    GG_NET_IDLE = 0,
    GG_NET_PROVISIONING,   // BLE provisioning active, waiting for credentials
    GG_NET_CONNECTING,     // joining Wi-Fi
    GG_NET_CONNECTED,      // Wi-Fi up, MQTT not yet established
    GG_NET_CLOUD_OK,       // MQTT connected
    GG_NET_FAILED,
} gg_net_state_t;

/// Invoked when a pump command arrives from the cloud. Returns the ack string
/// ("ok", "rejected", ...) which is published to gg/v1/{id}/cmd/ack.
typedef const char *(*gg_net_pump_cb_t)(uint32_t duration_ms);

esp_err_t gg_net_init(gg_net_pump_cb_t pump_cb);

/// True when NVS already holds Wi-Fi credentials. Determines whether the
/// device comes up in provisioning mode or goes straight to connecting.
bool gg_net_is_provisioned(void);

/// Starts ESP-IDF's wifi_provisioning manager over BLE (Security2/SRP6a).
///
/// Deliberately not a hand-rolled characteristic: shipping Wi-Fi passwords
/// over a custom GATT attribute is the easiest way to put a real
/// vulnerability in this product. The IDF implementation is audited and has
/// matching phone SDKs.
esp_err_t gg_net_start_provisioning(const char *service_name,
                                    const char *proof_of_possession);

esp_err_t gg_net_start(void);

/// Erases stored credentials and reboots into provisioning.
esp_err_t gg_net_factory_reset(void);

gg_net_state_t gg_net_get_state(void);
bool gg_net_time_synced(void);

/// Queues a reading for publication. Batched per contracts/telemetry.md:
/// flushed at GG_BATCH_MAX_SAMPLES or GG_PUBLISH_INTERVAL_MS, whichever first.
esp_err_t gg_net_queue_reading(const gg_reading_t *r, uint8_t flags);

/// Publishes to gg/v1/{device_id}/event immediately (QoS 1).
esp_err_t gg_net_publish_event(const char *kind, const char *data_json);

/// One-time claim code the app reads over BLE and POSTs to /v1/devices/claim.
const char *gg_net_claim_code(void);

/// Bit flags for the telemetry frame (GG_FLAG_WIFI_CONNECTED etc).
uint8_t gg_net_status_flags(void);

#ifdef __cplusplus
}
#endif
