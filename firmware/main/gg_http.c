#include "gg_http.h"
#include "gg_config.h"

#include <stdio.h>
#include <string.h>

#include "esp_crt_bundle.h"
#include "esp_http_client.h"
#include "esp_log.h"

static const char *TAG = "gg_http";

/* The synchronous open/write/read API is used rather than the event-callback
 * one. The callback form hands out response bodies in arbitrary chunks, so
 * every caller has to reassemble them into a buffer anyway, and getting that
 * wrong truncates a command payload in a way that only shows up under load. */
static esp_err_t post_json(const char *path, const char *bearer,
                           const char *body, char *resp, size_t resp_len,
                           int *status_out) {
    char url[256];
    snprintf(url, sizeof(url), "%s%s", GG_API_BASE, path);

    esp_http_client_config_t cfg = {
        .url = url,
        .method = HTTP_METHOD_POST,
        .timeout_ms = GG_HTTP_TIMEOUT_MS,
        /* Attaching the bundle unconditionally is harmless over plaintext and
         * means the https:// case cannot be forgotten when the API base moves
         * from a LAN address to a hosted one. */
        .crt_bundle_attach = esp_crt_bundle_attach,
        .keep_alive_enable = false,
    };

    esp_http_client_handle_t c = esp_http_client_init(&cfg);
    if (!c) return ESP_ERR_NO_MEM;

    esp_http_client_set_header(c, "Content-Type", "application/json");
    if (bearer && bearer[0]) {
        char auth[128];
        snprintf(auth, sizeof(auth), "Bearer %s", bearer);
        esp_http_client_set_header(c, "Authorization", auth);
    }

    int len = body ? (int)strlen(body) : 0;
    esp_err_t err = esp_http_client_open(c, len);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "POST %s: connect failed: %s", path, esp_err_to_name(err));
        esp_http_client_cleanup(c);
        return err;
    }

    if (len && esp_http_client_write(c, body, len) < 0) {
        ESP_LOGW(TAG, "POST %s: write failed", path);
        esp_http_client_close(c);
        esp_http_client_cleanup(c);
        return ESP_FAIL;
    }

    if (esp_http_client_fetch_headers(c) < 0) {
        ESP_LOGW(TAG, "POST %s: no response headers", path);
        esp_http_client_close(c);
        esp_http_client_cleanup(c);
        return ESP_FAIL;
    }

    int status = esp_http_client_get_status_code(c);
    if (status_out) *status_out = status;

    /* Read the body even when it will be discarded: leaving it unread on a
     * non-2xx keeps the socket half-consumed. */
    int got = 0;
    if (resp && resp_len) {
        got = esp_http_client_read_response(c, resp, (int)resp_len - 1);
        resp[got > 0 ? got : 0] = '\0';
    }

    esp_http_client_close(c);
    esp_http_client_cleanup(c);

    if (status == 401) {
        ESP_LOGW(TAG, "POST %s: 401, device secret rejected", path);
        return GG_ERR_HTTP_UNAUTHORIZED;
    }
    if (status < 200 || status >= 300) {
        ESP_LOGW(TAG, "POST %s: HTTP %d", path, status);
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t gg_http_bootstrap(const char *device_id, const char *token,
                            const char *fw_version,
                            char *secret_out, size_t secret_len) {
    if (!device_id || !token || !secret_out || secret_len < 8) {
        return ESP_ERR_INVALID_ARG;
    }

    char body[192];
    snprintf(body, sizeof(body),
             "{\"device_id\":\"%s\",\"token\":\"%s\",\"fw_version\":\"%s\"}",
             device_id, token, fw_version ? fw_version : GG_FW_VERSION);

    char resp[320];
    int status = 0;
    esp_err_t err = post_json("/v1/ingest/bootstrap", NULL, body,
                              resp, sizeof(resp), &status);
    if (err != ESP_OK) {
        /* A 401 here means the token on the pot is not the one the backend
         * has. Reporting it as unauthorized would send the caller into a
         * re-bootstrap loop against the same rejected token. */
        return (err == GG_ERR_HTTP_UNAUTHORIZED) ? ESP_ERR_INVALID_RESPONSE : err;
    }

    /* Hand-parsed rather than pulling cJSON in for one field: the response
     * has exactly one string worth reading and the shape is fixed by
     * BootstrapOut. */
    const char *p = strstr(resp, "\"secret\"");
    if (!p) return ESP_ERR_INVALID_RESPONSE;
    p = strchr(p + 8, '"');
    if (!p) return ESP_ERR_INVALID_RESPONSE;
    p++;
    const char *end = strchr(p, '"');
    if (!end) return ESP_ERR_INVALID_RESPONSE;

    size_t n = (size_t)(end - p);
    if (n == 0 || n >= secret_len) return ESP_ERR_INVALID_SIZE;
    memcpy(secret_out, p, n);
    secret_out[n] = '\0';
    return ESP_OK;
}

esp_err_t gg_http_post_telemetry(const char *device_id, const char *secret,
                                 const char *json,
                                 char *resp, size_t resp_len) {
    (void)device_id;  // travels in the body, which the backend authenticates
    return post_json("/v1/ingest/telemetry", secret, json, resp, resp_len, NULL);
}

esp_err_t gg_http_ack(const char *device_id, const char *secret,
                      const char *cmd_id, const char *result,
                      const char *error) {
    char path[128];
    snprintf(path, sizeof(path), "/v1/ingest/ack?device_id=%s", device_id);

    char body[256];
    snprintf(body, sizeof(body),
             "{\"id\":\"%s\",\"result\":\"%s\",\"error\":%s%s%s}",
             cmd_id, result,
             error ? "\"" : "", error ? error : "null", error ? "\"" : "");

    return post_json(path, secret, body, NULL, 0, NULL);
}
