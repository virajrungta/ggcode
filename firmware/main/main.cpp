#include "NimBLEDevice.h"
#include "nvs_flash.h"
#include "esp_log.h"

static const char* TAG = "GG_HARD";

extern "C" void app_main() {
    // 1. Initialize NVS (Always needed for Bluetooth memory)
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    ESP_LOGI(TAG, "Starting NimBLE C++ Server for gghard...");

    // 2. Initialize the NimBLE Device (This replaces nimble_port_init)
    NimBLEDevice::init("Green Genius");
    NimBLEDevice::setSecurityPasskey(123456);
    NimBLEDevice::setSecurityAuth(true, true, true); // Bonding, MITM protection, and Secure Connections
    NimBLEDevice::setSecurityIOCap(BLE_HS_IO_DISPLAY_ONLY); // Tell the phone we can show a PIN
   
    NimBLEDevice::getAdvertising()->setName("Green Genius");
    
    

    // Force the name into the GAP service the "Easy" way
    NimBLEDevice::setDeviceName("Green Genius");
    
    // 3. Create the BLE Server
    NimBLEServer* pServer = NimBLEDevice::createServer();
    pServer->start();
    // 4. Create a Service (UUID: ABCD)
    NimBLEService* pService = pServer->createService("ABCD");

    // 5. Create a Characteristic (UUID: 1234)
    NimBLECharacteristic* pCharacteristic = pService->createCharacteristic(
                                "1234",
                                NIMBLE_PROPERTY::READ | 
                                NIMBLE_PROPERTY::WRITE |
                                NIMBLE_PROPERTY::READ_ENC | // Requires Encryption/Bonding
                                NIMBLE_PROPERTY::WRITE_ENC
                             );

    // Set the initial value your phone will read
    pCharacteristic->setValue("Hello from Ayaan's MacBook!");

    // 6. Start the service
    pService->start();
    // ... (after pService->start())
    // 7. Start Advertising (Making it visible)
    // 7. Start Advertising
    NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
    
    // We create a "Packet" and manually fill it
    NimBLEAdvertisementData advData;
    advData.setName("Green Genius");
    advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    pAdvertising->setAppearance(0x0000);
    
    // Set the data and start
    pAdvertising->setAdvertisementData(advData);
    pAdvertising->start();

    ESP_LOGI(TAG, "Bluetooth is LIVE. Scanning for GG_HARD_ESP32...");

    
    ESP_LOGI(TAG, "Broadcasting with Scan Response...");
    // 7. Start Advertising (So your phone can find it)
    

    ESP_LOGI(TAG, "Bluetooth is LIVE. Open nRF Connect on your phone.");

    while (1) {
        vTaskDelay(pdMS_TO_TICKS(1000)); 
    }
}
