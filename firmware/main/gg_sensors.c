#include "gg_sensors.h"
#include "gg_config.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "driver/gpio.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_rom_sys.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "gg_sensors";

static adc_oneshot_unit_handle_t s_adc = NULL;
static gg_calibration_t          s_cal = {0};

// DHT frames are cached: the sensor physically cannot be sampled faster than
// ~2s, and polling it harder returns corrupt or stale frames.
static float   s_dht_temp = 0, s_dht_rh = 0;
static bool    s_dht_valid = false;
static int64_t s_dht_last_us = 0;

// --- helpers -------------------------------------------------------------

static int cmp_u16(const void *a, const void *b) {
    return (int)(*(const uint16_t *)a) - (int)(*(const uint16_t *)b);
}

/* Median rather than mean: the pump switching on the same board throws
 * occasional wild ADC outliers, and a single spike moves a mean far enough to
 * trigger a spurious watering decision. */
static uint16_t read_adc_median(adc_channel_t ch) {
    uint16_t v[GG_ADC_SAMPLES];
    int got = 0;
    for (int i = 0; i < GG_ADC_SAMPLES; i++) {
        int raw = 0;
        if (adc_oneshot_read(s_adc, ch, &raw) == ESP_OK) {
            v[got++] = (uint16_t)raw;
        }
        esp_rom_delay_us(200);
    }
    if (got == 0) return UINT16_MAX;
    qsort(v, got, sizeof(uint16_t), cmp_u16);
    return v[got / 2];
}

// --- calibration ---------------------------------------------------------

static void load_calibration(void) {
    nvs_handle_t h;
    if (nvs_open(GG_NVS_NAMESPACE, NVS_READONLY, &h) != ESP_OK) {
        ESP_LOGW(TAG, "no calibration stored yet");
        return;
    }
    nvs_get_u16(h, GG_NVS_SOIL1_AIR, &s_cal.soil1_air_raw);
    nvs_get_u16(h, GG_NVS_SOIL1_WATER, &s_cal.soil1_water_raw);
    nvs_get_u16(h, GG_NVS_SOIL2_AIR, &s_cal.soil2_air_raw);
    nvs_get_u16(h, GG_NVS_SOIL2_WATER, &s_cal.soil2_water_raw);
    nvs_get_u32(h, GG_NVS_CALIBRATED_AT, &s_cal.calibrated_at);
    nvs_close(h);

    ESP_LOGI(TAG, "calibration: s1 air=%u water=%u | s2 air=%u water=%u | at=%lu",
             s_cal.soil1_air_raw, s_cal.soil1_water_raw,
             s_cal.soil2_air_raw, s_cal.soil2_water_raw,
             (unsigned long)s_cal.calibrated_at);
}

static bool pair_is_sane(uint16_t air, uint16_t water) {
    /* A capacitive probe reads *lower* when wet, so air must exceed water.
     * Accepting an inverted pair would invert every moisture reading the pot
     * ever reports, and the plant would be watered exactly when saturated. */
    if (air <= water) return false;
    if ((air - water) < 200) return false;  // probe probably never moved
    return true;
}

esp_err_t gg_sensors_set_calibration(const gg_calibration_t *cal) {
    if (!cal) return ESP_ERR_INVALID_ARG;

    if (!pair_is_sane(cal->soil1_air_raw, cal->soil1_water_raw)) {
        ESP_LOGE(TAG, "rejecting probe-1 calibration: air=%u water=%u",
                 cal->soil1_air_raw, cal->soil1_water_raw);
        return ESP_ERR_INVALID_ARG;
    }
    // Probe 2 is optional — a pot may only have one probe fitted.
    bool have2 = pair_is_sane(cal->soil2_air_raw, cal->soil2_water_raw);

    nvs_handle_t h;
    esp_err_t err = nvs_open(GG_NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) return err;

    nvs_set_u16(h, GG_NVS_SOIL1_AIR, cal->soil1_air_raw);
    nvs_set_u16(h, GG_NVS_SOIL1_WATER, cal->soil1_water_raw);
    if (have2) {
        nvs_set_u16(h, GG_NVS_SOIL2_AIR, cal->soil2_air_raw);
        nvs_set_u16(h, GG_NVS_SOIL2_WATER, cal->soil2_water_raw);
    }
    nvs_set_u32(h, GG_NVS_CALIBRATED_AT, cal->calibrated_at);
    err = nvs_commit(h);
    nvs_close(h);

    if (err == ESP_OK) {
        s_cal = *cal;
        ESP_LOGI(TAG, "calibration stored (probe2=%s)", have2 ? "yes" : "no");
    }
    return err;
}

esp_err_t gg_sensors_get_calibration(gg_calibration_t *out) {
    if (!out) return ESP_ERR_INVALID_ARG;
    *out = s_cal;
    return ESP_OK;
}

bool gg_sensors_is_calibrated(void) {
    return s_cal.calibrated_at != 0 &&
           pair_is_sane(s_cal.soil1_air_raw, s_cal.soil1_water_raw);
}

static bool soil_to_pct(uint16_t raw, uint16_t air, uint16_t water, float *out) {
    if (raw == UINT16_MAX || !pair_is_sane(air, water)) return false;
    float pct = 100.0f * ((float)air - (float)raw) / ((float)air - (float)water);
    if (pct < 0.0f) pct = 0.0f;
    if (pct > 100.0f) pct = 100.0f;
    *out = pct;
    return true;
}

// --- DHT22 (single-wire) -------------------------------------------------

/* Bit-banged because the DHT protocol has no hardware peripheral on ESP32.
 * Timing is tight (26us = 0, 70us = 1), so the sampling loop runs with
 * interrupts disabled; at 1ms FreeRTOS ticks a preemption mid-frame corrupts
 * the read. The critical section is ~5ms, which is long but bounded and only
 * happens once per sampling interval. */
static bool dht_read_raw(float *temp_c, float *rh) {
    uint8_t data[5] = {0};

    gpio_set_direction(GG_DHT_GPIO, GPIO_MODE_OUTPUT);
    gpio_set_level(GG_DHT_GPIO, 0);
    // DHT22 needs >=1ms low; DHT11 needs >=18ms.
#if GG_DHT_TYPE_DHT22
    esp_rom_delay_us(1500);
#else
    vTaskDelay(pdMS_TO_TICKS(20));
#endif
    gpio_set_level(GG_DHT_GPIO, 1);
    esp_rom_delay_us(30);
    gpio_set_direction(GG_DHT_GPIO, GPIO_MODE_INPUT);

    portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;
    portENTER_CRITICAL(&mux);

    int timeout = 0;
    #define WAIT_FOR(level)                                    \
        do {                                                   \
            timeout = 0;                                       \
            while (gpio_get_level(GG_DHT_GPIO) != (level)) {   \
                if (++timeout > 1000) {                        \
                    portEXIT_CRITICAL(&mux);                   \
                    return false;                              \
                }                                              \
                esp_rom_delay_us(1);                           \
            }                                                  \
        } while (0)

    WAIT_FOR(0);   // sensor pulls low  (~80us)
    WAIT_FOR(1);   // sensor pulls high (~80us)
    WAIT_FOR(0);   // start of first bit

    for (int i = 0; i < 40; i++) {
        WAIT_FOR(1);
        // 26-28us high = 0, ~70us high = 1. 45us splits them safely.
        esp_rom_delay_us(45);
        if (gpio_get_level(GG_DHT_GPIO)) {
            data[i / 8] |= (uint8_t)(1 << (7 - (i % 8)));
            WAIT_FOR(0);
        }
    }
    #undef WAIT_FOR
    portEXIT_CRITICAL(&mux);

    uint8_t sum = (uint8_t)(data[0] + data[1] + data[2] + data[3]);
    if (sum != data[4]) {
        ESP_LOGW(TAG, "DHT checksum mismatch - discarding frame");
        return false;
    }

#if GG_DHT_TYPE_DHT22
    *rh = ((data[0] << 8) | data[1]) / 10.0f;
    int16_t t = (int16_t)(((data[2] & 0x7F) << 8) | data[3]);
    *temp_c = t / 10.0f;
    if (data[2] & 0x80) *temp_c = -*temp_c;  // sign bit, not two's complement
#else
    *rh = (float)data[0];
    *temp_c = (float)data[2];
#endif

    if (*rh < 0.0f || *rh > 100.0f) return false;
    if (*temp_c < -40.0f || *temp_c > 80.0f) return false;
    return true;
}

static bool dht_read_cached(float *temp_c, float *rh) {
    int64_t now = esp_timer_get_time();
    if (s_dht_valid &&
        (now - s_dht_last_us) < (int64_t)GG_DHT_MIN_INTERVAL_MS * 1000LL) {
        *temp_c = s_dht_temp;
        *rh = s_dht_rh;
        return true;
    }

    float t = 0, h = 0;
    if (dht_read_raw(&t, &h)) {
        s_dht_temp = t;
        s_dht_rh = h;
        s_dht_valid = true;
        s_dht_last_us = now;
        *temp_c = t;
        *rh = h;
        return true;
    }

    s_dht_last_us = now;  // don't hammer a failing sensor
    return false;
}

// --- light (LDR divider) -------------------------------------------------

/* R9 (LDR) from 3V3 to LIGHT, R10 (10k) LIGHT to GND. Brighter light lowers
 * the LDR's resistance and raises the node voltage.
 *
 * Reported as a 0-100 relative brightness, not lux. An LDR is non-linear,
 * has wide part-to-part tolerance, and is uncalibrated here; converting to a
 * lux figure would put a precise-looking number on a guess. */
static float light_to_estimate(uint16_t raw) {
    float ratio = (float)raw / 4095.0f;
    if (ratio < 0.0f) ratio = 0.0f;
    if (ratio > 0.999f) ratio = 0.999f;
    // Perceptual-ish curve; the eye's response is closer to log than linear.
    float est = 100.0f * powf(ratio, 0.45f);
    if (est > 100.0f) est = 100.0f;
    return est;
}

// --- water level ---------------------------------------------------------

bool gg_sensors_reservoir_empty(void) {
    if (!s_adc) return false;
    uint16_t raw = read_adc_median(GG_WLVL_ADC_CHANNEL);
    if (raw == UINT16_MAX) return false;  // unknown != empty
    return raw < GG_WLVL_EMPTY_RAW;
}

// --- status LED ----------------------------------------------------------

void gg_status_led(bool on) {
    gpio_set_level(GG_STATUS_LED_GPIO, on ? 1 : 0);
}

// --- init + read ---------------------------------------------------------

esp_err_t gg_sensors_init(void) {
    adc_oneshot_unit_init_cfg_t unit_cfg = { .unit_id = GG_ADC_UNIT };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit_cfg, &s_adc));

    adc_oneshot_chan_cfg_t chan = {
        .bitwidth = GG_ADC_BITWIDTH,
        .atten = GG_ADC_ATTEN,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, GG_SOIL1_ADC_CHANNEL, &chan));
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, GG_SOIL2_ADC_CHANNEL, &chan));
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, GG_WLVL_ADC_CHANNEL, &chan));
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, GG_LIGHT_ADC_CHANNEL, &chan));

    gpio_config_t led = {
        .pin_bit_mask = 1ULL << GG_STATUS_LED_GPIO,
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_ERROR_CHECK(gpio_config(&led));
    gg_status_led(false);

    // The board fits R8 (4.7k) as the DHT pull-up, so no internal one.
    gpio_config_t dht = {
        .pin_bit_mask = 1ULL << GG_DHT_GPIO,
        .mode = GPIO_MODE_INPUT_OUTPUT_OD,
    };
    ESP_ERROR_CHECK(gpio_config(&dht));
    gpio_set_level(GG_DHT_GPIO, 1);

    load_calibration();

    ESP_LOGI(TAG, "sensors ready: soil1=GPIO36 soil2=GPIO39 wlvl=GPIO34 "
                  "light=GPIO35 dht=GPIO%d (all ADC1), calibrated=%s",
             GG_DHT_GPIO, gg_sensors_is_calibrated() ? "yes" : "NO");
    return ESP_OK;
}

esp_err_t gg_sensors_read_raw(uint16_t *soil1, uint16_t *soil2,
                              uint16_t *light, uint16_t *wlvl) {
    if (!s_adc) return ESP_ERR_INVALID_STATE;
    if (soil1) *soil1 = read_adc_median(GG_SOIL1_ADC_CHANNEL);
    if (soil2) *soil2 = read_adc_median(GG_SOIL2_ADC_CHANNEL);
    if (light) *light = read_adc_median(GG_LIGHT_ADC_CHANNEL);
    if (wlvl)  *wlvl  = read_adc_median(GG_WLVL_ADC_CHANNEL);
    return ESP_OK;
}

esp_err_t gg_sensors_read(gg_reading_t *out) {
    if (!out) return ESP_ERR_INVALID_ARG;
    memset(out, 0, sizeof(*out));

    gg_sensors_read_raw(&out->soil1_raw, &out->soil2_raw,
                        &out->light_raw, &out->wlvl_raw);

    out->soil1_valid = soil_to_pct(out->soil1_raw, s_cal.soil1_air_raw,
                                   s_cal.soil1_water_raw, &out->soil1_pct);
    out->soil2_valid = soil_to_pct(out->soil2_raw, s_cal.soil2_air_raw,
                                   s_cal.soil2_water_raw, &out->soil2_pct);

    if (!out->soil1_valid && out->soil1_raw != UINT16_MAX) {
        /* Deliberately not reported as a percentage. An uncalibrated probe
         * can be off by 20+ points, and auto-watering on that number is how
         * a plant drowns. The UNCALIBRATED flag drives the app's prompt. */
        ESP_LOGW(TAG, "soil1 raw=%u but no valid calibration", out->soil1_raw);
    }

    if (out->light_raw != UINT16_MAX) {
        out->light_est = light_to_estimate(out->light_raw);
        out->light_valid = true;
    }

    if (out->wlvl_raw != UINT16_MAX) {
        out->water_level_pct = 100.0f * (float)out->wlvl_raw / 4095.0f;
        out->wlvl_valid = true;
    }

    float t = 0, h = 0;
    if (dht_read_cached(&t, &h)) {
        out->temp_c = t;
        out->rh = h;
        out->temp_valid = true;
        out->rh_valid = true;
    } else {
        ESP_LOGW(TAG, "DHT read failed");
    }

    return ESP_OK;
}

void gg_sensors_pack(const gg_reading_t *r, uint32_t uptime_s,
                     uint8_t extra_flags, gg_telemetry_t *out) {
    uint8_t flags = extra_flags;

    out->uptime_s = uptime_s;
    out->temp_c_x100 = r->temp_valid ? (int16_t)(r->temp_c * 100.0f) : GG_TEMP_FAULT;
    out->rh_x100     = r->rh_valid   ? (uint16_t)(r->rh * 100.0f)    : GG_RH_FAULT;
    out->soil_pct_x100 = r->soil1_valid
                            ? (uint16_t)(r->soil1_pct * 100.0f) : GG_SOIL_FAULT;

    // The wire field is named lux for contract compatibility, but this board
    // has an LDR, so the value is a 0-100 estimate scaled by 10.
    out->lux_x10 = r->light_valid ? (uint32_t)(r->light_est * 10.0f) : GG_LUX_FAULT;

    if (!r->temp_valid || !r->rh_valid || !r->light_valid) {
        flags |= GG_FLAG_SENSOR_FAULT;
    }
    if (!gg_sensors_is_calibrated()) flags |= GG_FLAG_UNCALIBRATED;

    out->flags = flags;
}
