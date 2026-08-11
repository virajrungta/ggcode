#pragma once

/// HTTP transport to the backend, replacing MQTT.
///
/// MQTT needs a broker and a permanently-connected subscriber, which no free
/// hosting tier provides — a service that sleeps after 15 minutes idle drops
/// telemetry outright. A POST wakes the service instead, so the cost of
/// sleeping is latency rather than data loss. See docs/HOSTING_PLAN.md.
///
/// Downlink rides in the telemetry response: pending commands come back in
/// the same round trip, so there is no second connection and no polling.

#include <stdbool.h>
#include <stddef.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Returned when the backend rejects the device secret. The caller is
/// expected to re-bootstrap rather than give up: a pot that goes silent on a
/// stale credential needs a reflash to recover, which is not acceptable for
/// something sitting in a plant pot.
#define GG_ERR_HTTP_UNAUTHORIZED  (ESP_ERR_INVALID_STATE)

/// Exchanges the token printed on the pot for a telemetry secret.
/// `secret_out` receives a NUL-terminated string on success.
esp_err_t gg_http_bootstrap(const char *device_id, const char *token,
                            const char *fw_version,
                            char *secret_out, size_t secret_len);

/// POSTs a telemetry batch. `resp` receives the JSON body, which carries any
/// pending commands.
esp_err_t gg_http_post_telemetry(const char *device_id, const char *secret,
                                 const char *json,
                                 char *resp, size_t resp_len);

/// Reports the outcome of a command. Best-effort: a lost ack leaves the
/// command marked `sent` server-side, which is visible rather than silent.
esp_err_t gg_http_ack(const char *device_id, const char *secret,
                      const char *cmd_id, const char *result,
                      const char *error);

#ifdef __cplusplus
}
#endif
