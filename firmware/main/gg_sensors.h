#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

// Sentinels matching contracts/ble_gatt.md. A failed read must never be
// indistinguishable from a real zero.
#define GG_TEMP_FAULT   INT16_MIN
#define GG_RH_FAULT     UINT16_MAX
#define GG_SOIL_FAULT   UINT16_MAX
#define GG_LUX_FAULT    UINT32_MAX

#define GG_FLAG_PUMP_ON        (1 << 0)
#define GG_FLAG_RESERVOIR_LOW  (1 << 1)
#define GG_FLAG_SENSOR_FAULT   (1 << 2)
#define GG_FLAG_UNCALIBRATED   (1 << 3)
#define GG_FLAG_WIFI_CONNECTED (1 << 4)
#define GG_FLAG_MQTT_CONNECTED (1 << 5)

// The 15-byte wire struct. Layout is contractual - see contracts/ble_gatt.md
// and contracts/vectors/telemetry.json.
typedef struct __attribute__((packed)) {
    uint32_t uptime_s;
    int16_t  temp_c_x100;
    uint16_t rh_x100;
    uint16_t soil_pct_x100;
    uint32_t lux_x10;
    uint8_t  flags;
} gg_telemetry_t;

_Static_assert(sizeof(gg_telemetry_t) == 15, "telemetry struct must stay 15 bytes");

// Decoded form used inside the firmware.
typedef struct {
    float   temp_c;
    float   rh;
    float   soil_pct;
    float   lux;
    uint16_t soil_raw;
    bool    temp_valid;
    bool    rh_valid;
    bool    soil_valid;
    bool    lux_valid;
} gg_reading_t;

typedef struct {
    uint16_t soil_air_raw;    // probe in air (driest)
    uint16_t soil_water_raw;  // probe in water (wettest)
    uint32_t calibrated_at;   // unix seconds; 0 = never
} gg_calibration_t;

esp_err_t gg_sensors_init(void);

// Reads every sensor. Always returns ESP_OK and populates the per-field
// validity flags; an I2C failure is a data condition, not a control-flow error.
esp_err_t gg_sensors_read(gg_reading_t *out);

esp_err_t gg_sensors_get_calibration(gg_calibration_t *out);
esp_err_t gg_sensors_set_calibration(const gg_calibration_t *cal);
bool      gg_sensors_is_calibrated(void);

// Raw ADC read, for the app's calibration flow.
esp_err_t gg_sensors_read_soil_raw(uint16_t *raw_out);

// Pack a reading into the wire struct.
void gg_sensors_pack(const gg_reading_t *r, uint32_t uptime_s, uint8_t extra_flags,
                     gg_telemetry_t *out);

#ifdef __cplusplus
}
#endif
