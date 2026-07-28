#include "gg_sensors.h"
#include "gg_config.h"

#include <string.h>
#include <stdlib.h>

#include "driver/gpio.h"
#include "driver/i2c_master.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "gg_sensors";

static adc_oneshot_unit_handle_t s_adc = NULL;
static i2c_master_bus_handle_t   s_i2c_bus = NULL;
static i2c_master_dev_handle_t   s_sht4x = NULL;
static i2c_master_dev_handle_t   s_bh1750 = NULL;
static gg_calibration_t          s_cal = {0};

#define SOIL_SAMPLES 5

// --- helpers -------------------------------------------------------------

static int cmp_u16(const void *a, const void *b) {
    return (int)(*(const uint16_t *)a) - (int)(*(const uint16_t *)b);
}

/* Median of N rather than a mean: capacitive probes throw occasional wild
 * outliers when the pump's motor is switching nearby, and a single spike
 * shifts a mean enough to trigger a spurious watering. */
static uint16_t median_u16(uint16_t *v, size_t n) {
    qsort(v, n, sizeof(uint16_t), cmp_u16);
    return v[n / 2];
}

// --- calibration ---------------------------------------------------------

static esp_err_t load_calibration(void) {
    nvs_handle_t h;
    esp_err_t err = nvs_open(GG_NVS_NAMESPACE, NVS_READONLY, &h);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "no calibration stored yet");
        return err;
    }

    uint16_t air = 0, water = 0;
    uint32_t at = 0;
    esp_err_t e1 = nvs_get_u16(h, GG_NVS_SOIL_AIR, &air);
    esp_err_t e2 = nvs_get_u16(h, GG_NVS_SOIL_WATER, &water);
    nvs_get_u32(h, GG_NVS_CALIBRATED_AT, &at);
    nvs_close(h);

    if (e1 != ESP_OK || e2 != ESP_OK) return ESP_ERR_NVS_NOT_FOUND;

    s_cal.soil_air_raw = air;
    s_cal.soil_water_raw = water;
    s_cal.calibrated_at = at;
    ESP_LOGI(TAG, "calibration: air=%u water=%u at=%lu", air, water, (unsigned long)at);
    return ESP_OK;
}

esp_err_t gg_sensors_set_calibration(const gg_calibration_t *cal) {
    if (!cal) return ESP_ERR_INVALID_ARG;

    /* A capacitive probe reads *lower* when wet (higher capacitance pulls the
     * output down), so air must exceed water. Accepting an inverted pair would
     * silently invert every moisture reading the pot ever reports, and the
     * plant would be watered exactly when it is already saturated. */
    if (cal->soil_air_raw <= cal->soil_water_raw) {
        ESP_LOGE(TAG, "rejecting inverted calibration: air=%u must exceed water=%u",
                 cal->soil_air_raw, cal->soil_water_raw);
        return ESP_ERR_INVALID_ARG;
    }
    if ((cal->soil_air_raw - cal->soil_water_raw) < 200) {
        ESP_LOGE(TAG, "rejecting calibration: span %u too small, probe likely not moved",
                 (unsigned)(cal->soil_air_raw - cal->soil_water_raw));
        return ESP_ERR_INVALID_ARG;
    }

    nvs_handle_t h;
    esp_err_t err = nvs_open(GG_NVS_NAMESPACE, NVS_READWRITE, &h);
    if (err != ESP_OK) return err;

    nvs_set_u16(h, GG_NVS_SOIL_AIR, cal->soil_air_raw);
    nvs_set_u16(h, GG_NVS_SOIL_WATER, cal->soil_water_raw);
    nvs_set_u32(h, GG_NVS_CALIBRATED_AT, cal->calibrated_at);
    err = nvs_commit(h);
    nvs_close(h);

    if (err == ESP_OK) {
        s_cal = *cal;
        ESP_LOGI(TAG, "calibration stored: air=%u water=%u",
                 cal->soil_air_raw, cal->soil_water_raw);
    }
    return err;
}

esp_err_t gg_sensors_get_calibration(gg_calibration_t *out) {
    if (!out) return ESP_ERR_INVALID_ARG;
    *out = s_cal;
    return ESP_OK;
}

bool gg_sensors_is_calibrated(void) {
    return s_cal.calibrated_at != 0 && s_cal.soil_air_raw > s_cal.soil_water_raw;
}

// --- soil moisture -------------------------------------------------------

esp_err_t gg_sensors_read_soil_raw(uint16_t *raw_out) {
    if (!s_adc || !raw_out) return ESP_ERR_INVALID_STATE;

    gpio_set_level(GG_SOIL_POWER_GPIO, 1);
    vTaskDelay(pdMS_TO_TICKS(GG_SOIL_SETTLE_MS));

    uint16_t samples[SOIL_SAMPLES];
    for (int i = 0; i < SOIL_SAMPLES; i++) {
        int raw = 0;
        esp_err_t err = adc_oneshot_read(s_adc, GG_SOIL_ADC_CHANNEL, &raw);
        if (err != ESP_OK) {
            gpio_set_level(GG_SOIL_POWER_GPIO, 0);
            /* ESP_ERR_TIMEOUT here almost certainly means the probe is on an
             * ADC2 channel and WiFi has claimed the peripheral. See the note
             * at the top of gg_config.h -- this is a wiring fault, not a
             * transient error, and no amount of retrying will clear it. */
            ESP_LOGE(TAG, "ADC read failed: %s (ADC2+WiFi conflict?)",
                     esp_err_to_name(err));
            return err;
        }
        samples[i] = (uint16_t)raw;
        vTaskDelay(pdMS_TO_TICKS(5));
    }

    gpio_set_level(GG_SOIL_POWER_GPIO, 0);
    *raw_out = median_u16(samples, SOIL_SAMPLES);
    return ESP_OK;
}

static bool soil_raw_to_pct(uint16_t raw, float *pct_out) {
    if (!gg_sensors_is_calibrated()) return false;

    int32_t span = (int32_t)s_cal.soil_air_raw - (int32_t)s_cal.soil_water_raw;
    if (span <= 0) return false;

    // Inverted: dry (high raw) -> 0%, wet (low raw) -> 100%.
    float pct = 100.0f * (float)((int32_t)s_cal.soil_air_raw - (int32_t)raw) / (float)span;

    if (pct < 0.0f) pct = 0.0f;
    if (pct > 100.0f) pct = 100.0f;
    *pct_out = pct;
    return true;
}

// --- SHT4x (temperature + humidity) --------------------------------------

static uint8_t crc8_sensirion(const uint8_t *data, size_t len) {
    uint8_t crc = 0xFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x31) : (uint8_t)(crc << 1);
        }
    }
    return crc;
}

static esp_err_t sht4x_read(float *temp_c, float *rh) {
    if (!s_sht4x) return ESP_ERR_INVALID_STATE;

    const uint8_t cmd = 0xFD;  // high-precision measurement
    esp_err_t err = i2c_master_transmit(s_sht4x, &cmd, 1, 100);
    if (err != ESP_OK) return err;

    vTaskDelay(pdMS_TO_TICKS(10));

    uint8_t buf[6];
    err = i2c_master_receive(s_sht4x, buf, sizeof(buf), 100);
    if (err != ESP_OK) return err;

    /* The CRC is why this driver is hand-rolled rather than a two-line read:
     * a marginal I2C bus (long wires, no pull-ups, pump noise) corrupts bytes
     * far more often than it fails outright, and an unchecked read turns that
     * into plausible-looking wrong data. */
    if (crc8_sensirion(&buf[0], 2) != buf[2] || crc8_sensirion(&buf[3], 2) != buf[5]) {
        ESP_LOGW(TAG, "SHT4x CRC mismatch - discarding sample");
        return ESP_ERR_INVALID_CRC;
    }

    uint16_t t_ticks = (uint16_t)((buf[0] << 8) | buf[1]);
    uint16_t rh_ticks = (uint16_t)((buf[3] << 8) | buf[4]);

    *temp_c = -45.0f + 175.0f * ((float)t_ticks / 65535.0f);
    *rh = -6.0f + 125.0f * ((float)rh_ticks / 65535.0f);

    if (*rh < 0.0f) *rh = 0.0f;
    if (*rh > 100.0f) *rh = 100.0f;
    return ESP_OK;
}

// --- BH1750 (ambient light) ----------------------------------------------

static esp_err_t bh1750_read(float *lux) {
    if (!s_bh1750) return ESP_ERR_INVALID_STATE;

    const uint8_t cmd = 0x20;  // one-time high-res mode
    esp_err_t err = i2c_master_transmit(s_bh1750, &cmd, 1, 100);
    if (err != ESP_OK) return err;

    vTaskDelay(pdMS_TO_TICKS(180));

    uint8_t buf[2];
    err = i2c_master_receive(s_bh1750, buf, sizeof(buf), 100);
    if (err != ESP_OK) return err;

    uint16_t raw = (uint16_t)((buf[0] << 8) | buf[1]);
    *lux = (float)raw / 1.2f;
    return ESP_OK;
}

// --- init + read ---------------------------------------------------------

esp_err_t gg_sensors_init(void) {
    gpio_config_t pwr = {
        .pin_bit_mask = 1ULL << GG_SOIL_POWER_GPIO,
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_ERROR_CHECK(gpio_config(&pwr));
    gpio_set_level(GG_SOIL_POWER_GPIO, 0);

    adc_oneshot_unit_init_cfg_t unit_cfg = { .unit_id = GG_SOIL_ADC_UNIT };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit_cfg, &s_adc));

    adc_oneshot_chan_cfg_t chan_cfg = {
        .bitwidth = ADC_BITWIDTH_DEFAULT,
        .atten = GG_SOIL_ADC_ATTEN,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, GG_SOIL_ADC_CHANNEL, &chan_cfg));

    i2c_master_bus_config_t bus_cfg = {
        .i2c_port = GG_I2C_PORT,
        .sda_io_num = GG_I2C_SDA_GPIO,
        .scl_io_num = GG_I2C_SCL_GPIO,
        .clk_source = I2C_CLK_SRC_DEFAULT,
        .glitch_ignore_cnt = 7,
        .flags.enable_internal_pullup = true,
    };
    ESP_ERROR_CHECK(i2c_new_master_bus(&bus_cfg, &s_i2c_bus));

    i2c_device_config_t sht_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = GG_SHT4X_ADDR,
        .scl_speed_hz = GG_I2C_FREQ_HZ,
    };
    if (i2c_master_bus_add_device(s_i2c_bus, &sht_cfg, &s_sht4x) != ESP_OK) {
        ESP_LOGW(TAG, "SHT4x not found at 0x%02X", GG_SHT4X_ADDR);
        s_sht4x = NULL;
    }

    i2c_device_config_t bh_cfg = {
        .dev_addr_length = I2C_ADDR_BIT_LEN_7,
        .device_address = GG_BH1750_ADDR,
        .scl_speed_hz = GG_I2C_FREQ_HZ,
    };
    if (i2c_master_bus_add_device(s_i2c_bus, &bh_cfg, &s_bh1750) != ESP_OK) {
        ESP_LOGW(TAG, "BH1750 not found at 0x%02X", GG_BH1750_ADDR);
        s_bh1750 = NULL;
    }

    load_calibration();

    ESP_LOGI(TAG, "sensors ready (soil=ADC%d ch%d, sht4x=%s, bh1750=%s, calibrated=%s)",
             GG_SOIL_ADC_UNIT + 1, GG_SOIL_ADC_CHANNEL,
             s_sht4x ? "yes" : "no", s_bh1750 ? "yes" : "no",
             gg_sensors_is_calibrated() ? "yes" : "NO");
    return ESP_OK;
}

esp_err_t gg_sensors_read(gg_reading_t *out) {
    if (!out) return ESP_ERR_INVALID_ARG;
    memset(out, 0, sizeof(*out));

    float temp = 0, rh = 0;
    if (sht4x_read(&temp, &rh) == ESP_OK) {
        out->temp_c = temp;
        out->rh = rh;
        out->temp_valid = true;
        out->rh_valid = true;
    } else {
        ESP_LOGW(TAG, "temp/humidity read failed");
    }

    float lux = 0;
    if (bh1750_read(&lux) == ESP_OK) {
        out->lux = lux;
        out->lux_valid = true;
    } else {
        ESP_LOGW(TAG, "light read failed");
    }

    uint16_t raw = 0;
    if (gg_sensors_read_soil_raw(&raw) == ESP_OK) {
        out->soil_raw = raw;
        float pct = 0;
        if (soil_raw_to_pct(raw, &pct)) {
            out->soil_pct = pct;
            out->soil_valid = true;
        } else {
            /* Deliberately not reported as a percentage. An uncalibrated probe
             * can be off by 20+ points, and auto-watering on that number is
             * how a plant drowns. The UNCALIBRATED flag drives the app's
             * "calibrate now" prompt. */
            ESP_LOGW(TAG, "soil raw=%u but no valid calibration", raw);
        }
    }

    return ESP_OK;
}

void gg_sensors_pack(const gg_reading_t *r, uint32_t uptime_s, uint8_t extra_flags,
                     gg_telemetry_t *out) {
    uint8_t flags = extra_flags;

    out->uptime_s = uptime_s;
    out->temp_c_x100 = r->temp_valid ? (int16_t)(r->temp_c * 100.0f) : GG_TEMP_FAULT;
    out->rh_x100     = r->rh_valid   ? (uint16_t)(r->rh * 100.0f)    : GG_RH_FAULT;
    out->soil_pct_x100 = r->soil_valid ? (uint16_t)(r->soil_pct * 100.0f) : GG_SOIL_FAULT;
    out->lux_x10     = r->lux_valid  ? (uint32_t)(r->lux * 10.0f)    : GG_LUX_FAULT;

    if (!r->temp_valid || !r->rh_valid || !r->lux_valid) flags |= GG_FLAG_SENSOR_FAULT;
    if (!gg_sensors_is_calibrated()) flags |= GG_FLAG_UNCALIBRATED;

    out->flags = flags;
}
