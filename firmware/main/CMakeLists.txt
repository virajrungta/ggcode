idf_component_register(
    SRCS "main.cpp"
         "gg_sensors.c"
         "gg_pump.c"
         "gg_net.c"
    INCLUDE_DIRS "."
    REQUIRES nvs_flash esp_wifi esp_netif esp_event mqtt json wifi_provisioning
             esp_adc
             esp_driver_i2c
             esp_driver_gpio
             esp_timer
             h2zero__esp-nimble-cpp
)
