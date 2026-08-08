// GreenGenius pot firmware.
//
// Replaces the original bring-up sketch, which advertised a fixed name with a
// hardcoded string on a reserved 16-bit UUID. See contracts/ble_gatt.md.

#include <cstdio>
#include <cstring>

#include "NimBLEDevice.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"

extern "C" {
#include "gg_config.h"
#include "gg_pump.h"
#include "gg_sensors.h"
}

static const char *TAG = "gg_main";

// contracts/ble_gatt.md
static constexpr const char *SVC_UUID        = "67670000-9622-433e-b3ab-bd248af9434c";
static constexpr const char *CHR_DEVICE_INFO = "67670001-9622-433e-b3ab-bd248af9434c";
static constexpr const char *CHR_TELEMETRY   = "67670002-9622-433e-b3ab-bd248af9434c";
static constexpr const char *CHR_CLAIM_TOKEN = "67670003-9622-433e-b3ab-bd248af9434c";
static constexpr const char *CHR_CALIBRATION = "67670004-9622-433e-b3ab-bd248af9434c";
static constexpr const char *CHR_COMMAND     = "67670005-9622-433e-b3ab-bd248af9434c";

static char s_device_id[13] = {0};
static NimBLECharacteristic *s_telemetry_chr = nullptr;
static volatile bool s_live_subscribed = false;

// --- identity ------------------------------------------------------------

static void derive_device_id() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    snprintf(s_device_id, sizeof(s_device_id), "%02x%02x%02x%02x%02x%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

/* A fleet-wide passkey (the original firmware used a literal 123456) means
 * anyone who has seen one pot can pair with every pot. Deriving it from the
 * MAC gives each unit a distinct value; production should burn a random
 * passkey into eFuse at manufacture and print it on the base of the pot. */
static uint32_t derive_passkey() {
    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    uint32_t k = (uint32_t)mac[2] << 24 | (uint32_t)mac[3] << 16 |
                 (uint32_t)mac[4] << 8  | (uint32_t)mac[5];
    return 100000 + (k % 900000);  // always 6 digits
}

// --- BLE callbacks -------------------------------------------------------

static void fill_telemetry(gg_telemetry_t *out) {
    gg_reading_t r;
    gg_sensors_read(&r);

    uint8_t flags = gg_pump_is_running() ? GG_FLAG_PUMP_ON : 0;
    if (gg_pump_reservoir_empty()) flags |= GG_FLAG_RESERVOIR_LOW;

    gg_sensors_pack(&r, (uint32_t)(esp_timer_get_time() / 1000000), flags, out);
}

class TelemetryCallbacks : public NimBLECharacteristicCallbacks {
    void onSubscribe(NimBLECharacteristic *, NimBLEConnInfo &, uint16_t subValue) override {
        s_live_subscribed = (subValue > 0);
        ESP_LOGI(TAG, "live telemetry %s", s_live_subscribed ? "subscribed" : "unsubscribed");
    }

    void onRead(NimBLECharacteristic *chr, NimBLEConnInfo &) override {
        gg_telemetry_t packed;
        fill_telemetry(&packed);
        chr->setValue((uint8_t *)&packed, sizeof(packed));
    }
};

class CalibrationCallbacks : public NimBLECharacteristicCallbacks {
    void onRead(NimBLECharacteristic *chr, NimBLEConnInfo &) override {
        gg_calibration_t cal;
        gg_sensors_get_calibration(&cal);

        uint16_t s1 = 0, s2 = 0;
        gg_sensors_read_raw(&s1, &s2, nullptr, nullptr);

        // Both probes are exposed: ggpcb3 fits two, and the app's calibration
        // flow has to be able to walk the user through each one.
        char json[256];
        snprintf(json, sizeof(json),
                 "{\"soil1_air_raw\":%u,\"soil1_water_raw\":%u,"
                 "\"soil2_air_raw\":%u,\"soil2_water_raw\":%u,"
                 "\"calibrated_at\":%lu,"
                 "\"soil1_current_raw\":%u,\"soil2_current_raw\":%u}",
                 cal.soil1_air_raw, cal.soil1_water_raw,
                 cal.soil2_air_raw, cal.soil2_water_raw,
                 (unsigned long)cal.calibrated_at, s1, s2);
        chr->setValue((uint8_t *)json, strlen(json));
    }

    void onWrite(NimBLECharacteristic *chr, NimBLEConnInfo &) override {
        std::string v = chr->getValue();
        unsigned a1 = 0, w1 = 0, a2 = 0, w2 = 0;
        unsigned long at = 0;

        // Minimal parse - the app sends exactly this shape.
        if (sscanf(v.c_str(),
                   "{\"soil1_air_raw\":%u,\"soil1_water_raw\":%u,"
                   "\"soil2_air_raw\":%u,\"soil2_water_raw\":%u,"
                   "\"calibrated_at\":%lu",
                   &a1, &w1, &a2, &w2, &at) < 2) {
            ESP_LOGW(TAG, "unparseable calibration write");
            return;
        }

        gg_calibration_t cal = {
            .soil1_air_raw = (uint16_t)a1,
            .soil1_water_raw = (uint16_t)w1,
            .soil2_air_raw = (uint16_t)a2,
            .soil2_water_raw = (uint16_t)w2,
            .calibrated_at = (uint32_t)at,
        };
        // set_calibration rejects inverted or implausibly narrow spans.
        esp_err_t err = gg_sensors_set_calibration(&cal);
        ESP_LOGI(TAG, "calibration write: %s", esp_err_to_name(err));
    }
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic *chr, NimBLEConnInfo &) override {
        std::string v = chr->getValue();
        ESP_LOGI(TAG, "BLE command: %s", v.c_str());

        if (v.find("\"pump\"") != std::string::npos) {
            unsigned duration = 0;
            const char *p = strstr(v.c_str(), "duration_s");
            if (p) sscanf(p, "duration_s\":%u", &duration);

            /* Proximity is not authorization to bypass the interlocks. A BLE
             * command runs through exactly the same checks as a cloud one. */
            gg_pump_result_t res = gg_pump_start(duration * 1000, "ble");
            ESP_LOGI(TAG, "pump request -> %s", gg_pump_result_str(res));
        }
    }
};

// --- pump events ---------------------------------------------------------

static void on_pump_event(const char *reason, uint32_t duration_ms) {
    // Phase 5 forwards these to gg/v1/{id}/event; logged until then.
    ESP_LOGI(TAG, "pump event: %s (%lums)", reason, (unsigned long)duration_ms);
}

// --- telemetry task ------------------------------------------------------

/* Blinks D2. With no DHT connector, no LDR, and the pump unplugged, this is
 * the one output on the board that can be verified by eye today: it proves
 * GPIO writes work and that the firmware loop is still running. */
static void heartbeat_task(void *) {
    for (;;) {
        gg_status_led(true);
        vTaskDelay(pdMS_TO_TICKS(80));
        gg_status_led(false);
        vTaskDelay(pdMS_TO_TICKS(1920));
    }
}

static void telemetry_task(void *) {
    TickType_t last = xTaskGetTickCount();

    for (;;) {
        gg_telemetry_t packed;
        fill_telemetry(&packed);

        if (s_telemetry_chr && s_live_subscribed) {
            s_telemetry_chr->setValue((uint8_t *)&packed, sizeof(packed));
            s_telemetry_chr->notify();
        }

        // Bring-up detail: raw counts and mV alongside the packed frame, so a
        // sensor can be judged before any calibration exists for it.
        gg_reading_t raw;
        gg_sensors_read(&raw);
        ESP_LOGI(TAG,
                 "RAW soil1=%u(%dmV) soil2=%u(%dmV) light=%u(%dmV) wlvl=%u(%dmV)",
                 raw.soil1_raw, gg_sensors_raw_to_mv(raw.soil1_raw),
                 raw.soil2_raw, gg_sensors_raw_to_mv(raw.soil2_raw),
                 raw.light_raw, gg_sensors_raw_to_mv(raw.light_raw),
                 raw.wlvl_raw,  gg_sensors_raw_to_mv(raw.wlvl_raw));
        ESP_LOGI(TAG, "light_est=%.1f%%  temp=%.1fC rh=%.1f%%  flags=0x%02X",
                 raw.light_valid ? raw.light_est : -1.0f,
                 raw.temp_valid ? raw.temp_c : -99.0f,
                 raw.rh_valid ? raw.rh : -1.0f,
                 packed.flags);

        /* Fast cadence only while someone is watching. Holding 1Hz plus a 15ms
         * connection interval continuously is a real battery cost on the phone. */
        TickType_t period = pdMS_TO_TICKS(
            s_live_subscribed ? GG_LIVE_INTERVAL_MS : GG_SAMPLE_INTERVAL_MS);
        vTaskDelayUntil(&last, period);
    }
}

// --- entry point ---------------------------------------------------------

extern "C" void app_main() {
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    derive_device_id();
    ESP_LOGI(TAG, "GreenGenius %s (%s) device_id=%s",
             GG_FW_VERSION, GG_HW_REVISION, s_device_id);

    /* Pump first: it must be driven low before anything else can fail and
     * leave it energised. */
    ESP_ERROR_CHECK(gg_pump_init(on_pump_event));
    ESP_ERROR_CHECK(gg_sensors_init());

    if (!gg_sensors_is_calibrated()) {
        ESP_LOGW(TAG, "soil probe is NOT calibrated - readings suppressed "
                      "until the app completes the air/water calibration");
    }

    // Per-device name so multiple pots are distinguishable in the app's scan
    // list. The original firmware advertised "Green Genius" on every unit.
    char adv_name[16];
    snprintf(adv_name, sizeof(adv_name), "GG-%s", s_device_id + 6);

    NimBLEDevice::init(adv_name);
    NimBLEDevice::setSecurityPasskey(derive_passkey());
    NimBLEDevice::setSecurityAuth(true, true, true);  // bond, MITM, SC
    NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY);
    ESP_LOGI(TAG, "pairing passkey: %06lu", (unsigned long)derive_passkey());

    NimBLEServer *server = NimBLEDevice::createServer();
    NimBLEService *svc = server->createService(SVC_UUID);

    // Unencrypted on purpose: the app needs to read this before pairing to
    // decide between the provisioning and claim flows. It carries no secrets.
    NimBLECharacteristic *info = svc->createCharacteristic(
        CHR_DEVICE_INFO, NIMBLE_PROPERTY::READ);
    {
        char json[192];
        snprintf(json, sizeof(json),
                 "{\"device_id\":\"%s\",\"fw\":\"%s\",\"hw\":\"%s\","
                 "\"model\":\"%s\",\"prov\":false}",
                 s_device_id, GG_FW_VERSION, GG_HW_REVISION, GG_MODEL);
        info->setValue((uint8_t *)json, strlen(json));
    }

    s_telemetry_chr = svc->createCharacteristic(
        CHR_TELEMETRY,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY | NIMBLE_PROPERTY::READ_ENC);
    s_telemetry_chr->setCallbacks(new TelemetryCallbacks());

    NimBLECharacteristic *calib = svc->createCharacteristic(
        CHR_CALIBRATION,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE |
        NIMBLE_PROPERTY::READ_ENC | NIMBLE_PROPERTY::WRITE_ENC);
    calib->setCallbacks(new CalibrationCallbacks());

    NimBLECharacteristic *cmd = svc->createCharacteristic(
        CHR_COMMAND, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC);
    cmd->setCallbacks(new CommandCallbacks());

    // Claim token is issued by gg_net once the device reaches the backend;
    // exposed here so the characteristic exists from first boot.
    svc->createCharacteristic(
        CHR_CLAIM_TOKEN, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::READ_ENC);

    svc->start();
    server->start();

    NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
    NimBLEAdvertisementData data;
    data.setName(adv_name);
    data.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    data.addServiceUUID(SVC_UUID);
    adv->setAdvertisementData(data);
    adv->start();

    ESP_LOGI(TAG, "advertising as %s", adv_name);

    /* Core 1 on purpose. The DHT driver disables interrupts for ~5ms per read,
     * and portENTER_CRITICAL only affects the calling core — keeping this off
     * core 0 leaves the Wi-Fi task and BT controller undisturbed. */
    xTaskCreatePinnedToCore(telemetry_task, "telemetry", 4096, nullptr, 5,
                            nullptr, 1);
    xTaskCreate(heartbeat_task, "heartbeat", 2048, nullptr, 2, nullptr);
}
