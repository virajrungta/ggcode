#pragma once

// Board pinout and tuning constants for the GreenGenius PCB (ggpcb-r1).
//
// >>> VERIFY AGAINST THE SCHEMATIC BEFORE THE BOARDS SHIP. <<<
//
// The soil probe MUST land on an ADC1 channel. ADC2 is shared with the WiFi
// radio on the ESP32: any adc2_get_raw() while WiFi is started returns
// ESP_ERR_TIMEOUT, so a probe wired to ADC2 reads fine on the bench and then
// fails permanently once the pot joins a network -- the exact configuration
// the product ships in. After fabrication this is a trace-cut fix.
//
// ADC1 channels are GPIO32-39 on the classic ESP32.

#define GG_FW_VERSION            "1.0.0"
#define GG_HW_REVISION           "ggpcb-r1"
#define GG_MODEL                 "GG-POT-1"

// --- Soil moisture (capacitive, analog) ----------------------------------
#define GG_SOIL_ADC_UNIT         ADC_UNIT_1
#define GG_SOIL_ADC_CHANNEL      ADC_CHANNEL_6   // GPIO34 - ADC1, input-only
#define GG_SOIL_ADC_ATTEN        ADC_ATTEN_DB_12 // full ~0-3.1V span

// Powering the probe only while sampling roughly halves its idle draw and
// dramatically slows the electrolytic corrosion that kills these probes.
#define GG_SOIL_POWER_GPIO       25
#define GG_SOIL_SETTLE_MS        50

// --- I2C bus (temp/humidity + light) -------------------------------------
#define GG_I2C_PORT              I2C_NUM_0
#define GG_I2C_SDA_GPIO          21
#define GG_I2C_SCL_GPIO          22
#define GG_I2C_FREQ_HZ           100000

#define GG_SHT4X_ADDR            0x44
#define GG_BH1750_ADDR           0x23

// --- Pump ----------------------------------------------------------------
// Drives a MOSFET gate, never the pump directly. The pump needs its own supply
// rail: switching an inductive load on the 3.3V rail browns out the ESP32
// mid-cycle, and a reset during watering can leave the pump latched on.
#define GG_PUMP_GPIO             26
#define GG_PUMP_ACTIVE_HIGH      1

// Optional float switch / current sense. Set to -1 if unpopulated.
#define GG_RESERVOIR_GPIO        27

// --- Sampling ------------------------------------------------------------
#define GG_SAMPLE_INTERVAL_MS    60000     // 60s, per contracts/telemetry.md
#define GG_PUBLISH_INTERVAL_MS   300000    // 5 min
#define GG_BATCH_MAX_SAMPLES     12
#define GG_LIVE_INTERVAL_MS      1000      // BLE live view only

// --- Safety interlocks ---------------------------------------------------
// Enforced in firmware because they must hold when the cloud is unreachable,
// wrong, or compromised. The backend duplicates them for better UX, but these
// are the ones that actually prevent a flood.
#define GG_PUMP_MAX_RUNTIME_MS       30000     // hard cap, single run
#define GG_PUMP_MAX_PER_HOUR_MS      120000    // 2 min/hour cumulative
#define GG_PUMP_MAX_PER_DAY_MS       600000    // 10 min/day cumulative
#define GG_PUMP_MIN_INTERVAL_MS      600000    // 10 min between runs
#define GG_PUMP_SOIL_WET_THRESHOLD   70.0f     // refuse above this
#define GG_PUMP_WATCHDOG_MS          35000     // > max runtime; catches hangs

// --- NVS keys ------------------------------------------------------------
#define GG_NVS_NAMESPACE         "gg"
#define GG_NVS_SOIL_AIR          "soil_air"
#define GG_NVS_SOIL_WATER        "soil_water"
#define GG_NVS_CALIBRATED_AT     "cal_at"
#define GG_NVS_MQTT_SECRET       "mqtt_sec"
#define GG_NVS_PUMP_DAY_MS       "pump_day"
#define GG_NVS_PUMP_HOUR_MS      "pump_hr"
