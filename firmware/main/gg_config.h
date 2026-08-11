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

/* Floor below which a soil reading is treated as a wiring fault rather than
 * data. A powered capacitive probe cannot approach 0 — at 3.3V a SEN0193
 * sits near 2260 counts in air and only falls to roughly 1200-1500 fully
 * submerged. A hard 0 means the signal wire has lost contact.
 *
 * This matters because of which way the maths breaks. Percentage is
 * 100*(air-raw)/(air-water), so a raw of 0 lands *below* the wet calibration
 * point and clamps to 100% — "soaking wet". The pump then refuses to run
 * (>= GG_PUMP_SOIL_WET_THRESHOLD) and the plant is quietly never watered
 * again. A disconnected probe reads as a flood, not a drought. */
#define GG_SOIL_MIN_PLAUSIBLE_RAW    200

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
// Analog input on GPIO34, expecting a 0-3.3V sensor.
//
// !! The part selected for this build (DFRobot SEN0204, XKC-Y25-T12V) does
// NOT match this input. It is a 5-24V *digital* sensor whose output high
// equals its supply rail. Two consequences:
//   1. J4 supplies 3.3V, below its 5V minimum, so it cannot run from this
//      connector at all;
//   2. powered from 5V its output would put 5V on GPIO34, and ESP32 GPIOs
//      are not 5V tolerant (~3.6V absolute max). That damages the chip.
// Either fit a 3.3V analog level sensor, or add a divider/level shifter and
// a 5V feed on the next board revision.
#define GG_WLVL_SENSOR_FITTED    0
#define GG_WLVL_EMPTY_RAW        600

// --- Sampling ------------------------------------------------------------
// Bring-up mode logs every 2s so a probe can be watched live while it is
// moved between air and water. Production sampling is 60s per
// contracts/telemetry.md — set this back to 0 before shipping.
#define GG_BRINGUP_MODE          1

#if GG_BRINGUP_MODE
#define GG_SAMPLE_INTERVAL_MS    2000
#else
#define GG_SAMPLE_INTERVAL_MS    60000     // 60s, per contracts/telemetry.md
#endif
#define GG_PUBLISH_INTERVAL_MS   300000    // 5 min

// Floor on how often a POST may be attempted, regardless of what the batch is
// doing. Without it a failed send retries every second: the batch stays full,
// so the "flush when full" condition never clears, and a backend that is down
// gets hammered while the pot burns radio power.
#define GG_PUBLISH_MIN_GAP_MS    15000
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

// --- Cloud ---------------------------------------------------------------
// Placeholder broker settings. Per-device credentials are issued at claim
// time and stored in NVS; this is the bootstrap default for bench work.
//
// HTTP, not MQTT. MQTT needs a broker plus a permanently-connected subscriber,
// and every free hosting tier sleeps after ~15 minutes idle — a sleeping
// subscriber loses telemetry outright. A POST wakes the service instead, so
// idling costs latency rather than data. The previous MQTT URI pointed at a
// broker on a network we no longer use, and the pot reported nothing for days
// without any error to show for it.
//
// The deployed backend, so the pot reports whether or not the Mac is awake.
// TLS is verified against the ESP-IDF certificate bundle (see gg_http.c);
// plain http:// here would put the device secret on the wire in clear.
#define GG_API_BASE              "https://ggcode-nkdo.onrender.com"

// Render's free tier spins down after ~15 minutes idle and takes ~35-40s to
// wake -- measured at 37s on the first request after deploy. A timeout under
// that turns every cold start into a lost batch, so this is deliberately far
// longer than a normal request needs.
#define GG_HTTP_TIMEOUT_MS       60000

// --- NVS keys ------------------------------------------------------------
#define GG_NVS_NAMESPACE         "gg"
#define GG_NVS_SOIL1_AIR         "s1_air"
#define GG_NVS_SOIL1_WATER       "s1_water"
#define GG_NVS_SOIL2_AIR         "s2_air"
#define GG_NVS_SOIL2_WATER       "s2_water"
#define GG_NVS_CALIBRATED_AT     "cal_at"
// Telemetry bearer secret from /v1/ingest/bootstrap. Name kept for NVS
// compatibility with units already flashed; the transport is HTTP now.
#define GG_NVS_MQTT_SECRET       "mqtt_sec"

// The claim code must survive reboots: it is both what the user types and the
// token the pot presents to bootstrap. Regenerating it each boot meant a pot
// could never authenticate twice.
#define GG_NVS_CLAIM_CODE        "claim"
