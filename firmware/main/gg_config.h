#pragma once

// Board configuration for ggpcb3 (ESP32-WROOM-32E).
//
// Every value below was read off the KiCad schematic + PCB netlist, not
// assumed. Source: ~/Desktop/ggpcb3/ggpcb3.kicad_sch / .kicad_pcb
//
// Net -> module pad -> GPIO:
//   SOIL1   pad 4   GPIO36 (SENSOR_VP)  ADC1_CH0
//   SOIL2   pad 5   GPIO39 (SENSOR_VN)  ADC1_CH3
//   WLVL    pad 6   GPIO34              ADC1_CH6
//   LIGHT   pad 7   GPIO35              ADC1_CH7
//   DHT     pad 10  GPIO25              1-wire, 4.7k pull-up (R8)
//   IO12_G  pad 14  GPIO12              -> R11 100R -> Q3 gate (pump)
//   STATUS  pad 16  GPIO13              -> R7 1k -> D2 blue LED

#define GG_FW_VERSION            "1.0.0"
#define GG_HW_REVISION           "ggpcb3"
#define GG_MODEL                 "GG-POT-1"

// --- Analog inputs -------------------------------------------------------
//
// All four are on ADC1. This closes the risk flagged throughout the plan:
// ADC2 is unusable while Wi-Fi is started, and a probe wired there would read
// fine on the bench and fail permanently once the pot joined a network. The
// board avoids it entirely. Do not move any of these to ADC2.
//
// GPIO34-39 are input-only and have no internal pull-ups/downs, which is
// correct for analog.

#define GG_SOIL1_ADC_CHANNEL     ADC_CHANNEL_0   // GPIO36 / SENSOR_VP
#define GG_SOIL2_ADC_CHANNEL     ADC_CHANNEL_3   // GPIO39 / SENSOR_VN
#define GG_WLVL_ADC_CHANNEL      ADC_CHANNEL_6   // GPIO34
#define GG_LIGHT_ADC_CHANNEL     ADC_CHANNEL_7   // GPIO35

#define GG_ADC_UNIT              ADC_UNIT_1
#define GG_ADC_ATTEN             ADC_ATTEN_DB_12 // ~0-3.1V full span
#define GG_ADC_BITWIDTH          ADC_BITWIDTH_12

// The probes are wired straight to 3V3 (J2/J3 pin 2) with no switching FET,
// so they are powered continuously. That rules out duty-cycling them, which
// is the usual way to slow the electrolytic corrosion that eventually kills
// capacitive probes. Worth a gate on a future revision.
#define GG_SOIL_PERMANENTLY_POWERED  1

// --- Light (LDR divider) -------------------------------------------------
// R9 (LDR) is DEPOPULATED on this prototype build — the schematic has it but
// the assembled board does not. With R9 absent and R10 (10k) still tying
// LIGHT to GND, GPIO35 is held at 0V permanently.
//
// So light is reported as *absent*, not as 0%. Sending a real-looking zero
// would render in the app as "pitch dark, forever" and would drag the plant
// health score down for a sensor that was never fitted. The fault sentinel
// makes the backend store null and the UI show "no data", which is true.
#define GG_HAS_LDR               0
#define GG_LDR_FIXED_OHMS        10000.0f

// --- Not populated on this build -----------------------------------------
// SW1 (RESET) and SW2 (BOOT) are absent. Flashing still works: the CH340C
// drives DTR/RTS into Q1/Q2, which pulses EN and IO0 automatically, and that
// path is confirmed working on this board.
//
// The consequence is that there is no manual recovery. If firmware ever wedges
// the chip badly enough that the auto-reset sequence cannot catch it, the only
// way back is to short EN to GND by hand. Keep that in mind before flashing
// anything that touches the bootloader or the EN pin.
#define GG_HAS_RESET_BUTTON      0
#define GG_HAS_BOOT_BUTTON       0

// --- DHT temperature / humidity ------------------------------------------
// Single-wire, R8 4.7k pull-up to 3V3. NOT I2C — earlier firmware assumed an
// SHT4x on an I2C bus that does not exist on this board.
#define GG_DHT_GPIO              25
#define GG_DHT_TYPE_DHT22        1      // 0 = DHT11

// DHT22 needs ~2s between reads; DHT11 ~1s. Polling faster returns a cached
// or corrupt frame, so this bounds the live-view rate too.
#define GG_DHT_MIN_INTERVAL_MS   2200

// --- Pump ----------------------------------------------------------------
// GPIO12 -> R11 (100R) -> Q3 (AO3400A N-channel) gate, R12 10k gate pulldown.
// Low-side switch: J6 pin1 = +5V, pin2 = drain. D3 (SS14) is the flyback
// diode, C13 (100uF) the bulk cap on +5V.
//
// !! GPIO12 IS THE MTDI STRAPPING PIN. It selects flash voltage at reset:
// held high at boot, the chip configures for 1.8V flash and will not start.
// R12 pulls it down, and "pump off" is the same state, so the default is
// safe. Two consequences that must be respected:
//   1. never add an external pull-up to this net;
//   2. never leave the pump energised across a reset — gg_pump_init drives
//      it low before anything else can run.
#define GG_PUMP_GPIO             12
#define GG_PUMP_ACTIVE_HIGH      1

// --- Status LED ----------------------------------------------------------
// GPIO13 -> R7 (1k) -> D2 (blue). Active high.
#define GG_STATUS_LED_GPIO       13

// --- Water level ---------------------------------------------------------
// Analog on GPIO34. Threshold is provisional until the actual sensor is
// characterised on the bench - see gg_sensors.c.
#define GG_WLVL_EMPTY_RAW        600

// --- Sampling ------------------------------------------------------------
#define GG_SAMPLE_INTERVAL_MS    60000     // 60s, per contracts/telemetry.md
#define GG_PUBLISH_INTERVAL_MS   300000    // 5 min
#define GG_BATCH_MAX_SAMPLES     12

// Bounded by the DHT, not by preference.
#define GG_LIVE_INTERVAL_MS      GG_DHT_MIN_INTERVAL_MS

#define GG_ADC_SAMPLES           9         // median-of-N per reading

// --- Safety interlocks ---------------------------------------------------
// Enforced in firmware because they must hold when the cloud is unreachable,
// wrong, or compromised. The backend duplicates them for better UX; these are
// the ones that actually prevent a flood.
#define GG_PUMP_MAX_RUNTIME_MS       30000     // hard cap, single run
#define GG_PUMP_MAX_PER_HOUR_MS      120000    // 2 min/hour cumulative
#define GG_PUMP_MAX_PER_DAY_MS       600000    // 10 min/day cumulative
#define GG_PUMP_MIN_INTERVAL_MS      600000    // 10 min between runs
#define GG_PUMP_SOIL_WET_THRESHOLD   70.0f     // refuse above this
#define GG_PUMP_WATCHDOG_MS          35000     // > max runtime; catches hangs

// --- NVS keys ------------------------------------------------------------
#define GG_NVS_NAMESPACE         "gg"
#define GG_NVS_SOIL1_AIR         "s1_air"
#define GG_NVS_SOIL1_WATER       "s1_water"
#define GG_NVS_SOIL2_AIR         "s2_air"
#define GG_NVS_SOIL2_WATER       "s2_water"
#define GG_NVS_CALIBRATED_AT     "cal_at"
#define GG_NVS_MQTT_SECRET       "mqtt_sec"
