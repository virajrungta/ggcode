#include "gg_pump.h"
#include "gg_config.h"
#include "gg_sensors.h"

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "nvs.h"

static const char *TAG = "gg_pump";

static esp_timer_handle_t s_stop_timer = NULL;
static SemaphoreHandle_t  s_lock = NULL;

static volatile bool s_running = false;
static int64_t s_started_at_us = 0;
static int64_t s_last_stop_us = -1;   // -1 = never run this boot

static uint32_t s_used_this_hour_ms = 0;
static uint32_t s_used_today_ms = 0;
static int64_t  s_hour_window_start_us = 0;
static int64_t  s_day_window_start_us = 0;

static gg_pump_event_cb_t s_event_cb = NULL;

static inline void pump_gpio_set(bool on) {
#if GG_PUMP_ACTIVE_HIGH
    gpio_set_level(GG_PUMP_GPIO, on ? 1 : 0);
#else
    gpio_set_level(GG_PUMP_GPIO, on ? 0 : 1);
#endif
}

static void emit(const char *reason, uint32_t duration_ms) {
    if (s_event_cb) s_event_cb(reason, duration_ms);
}

/* Runs in the esp_timer task. Kept minimal and allocation-free: this is the
 * path that must work when everything else is wedged. */
static void stop_timer_cb(void *arg) {
    const char *reason = (const char *)arg;
    pump_gpio_set(false);

    int64_t now = esp_timer_get_time();
    uint32_t ran_ms = (uint32_t)((now - s_started_at_us) / 1000);

    s_running = false;
    s_last_stop_us = now;
    s_used_this_hour_ms += ran_ms;
    s_used_today_ms += ran_ms;

    ESP_LOGI(TAG, "pump stopped after %lums (%s)", (unsigned long)ran_ms, reason);
    emit(reason, ran_ms);
}

static void roll_windows(int64_t now) {
    if (now - s_hour_window_start_us > 3600LL * 1000000LL) {
        s_hour_window_start_us = now;
        s_used_this_hour_ms = 0;
    }
    if (now - s_day_window_start_us > 86400LL * 1000000LL) {
        s_day_window_start_us = now;
        s_used_today_ms = 0;
    }
}

esp_err_t gg_pump_init(gg_pump_event_cb_t cb) {
    s_event_cb = cb;
    s_lock = xSemaphoreCreateMutex();
    if (!s_lock) return ESP_ERR_NO_MEM;

    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << GG_PUMP_GPIO,
        .mode = GPIO_MODE_OUTPUT,
    };
    ESP_ERROR_CHECK(gpio_config(&cfg));

    /* Off before anything else can run. A reset while the pump was energised
     * leaves the GPIO floating through the bootloader; without this the pump
     * can stay latched on across a reboot loop, which is the flood scenario. */
    pump_gpio_set(false);


    const esp_timer_create_args_t targs = {
        .callback = stop_timer_cb,
        .arg = (void *)"completed",
        .name = "pump_stop",
        .dispatch_method = ESP_TIMER_TASK,
    };
    ESP_ERROR_CHECK(esp_timer_create(&targs, &s_stop_timer));

    int64_t now = esp_timer_get_time();
    s_hour_window_start_us = now;
    s_day_window_start_us = now;

    ESP_LOGI(TAG, "pump ready on GPIO%d (max %dms/run)",
             GG_PUMP_GPIO, GG_PUMP_MAX_RUNTIME_MS);
    return ESP_OK;
}

bool gg_pump_reservoir_empty(void) {
    // ggpcb3 has an analog water-level sensor on GPIO34, not a float switch,
    // so the reading lives with the other ADC channels.
    return gg_sensors_reservoir_empty();
}

bool gg_pump_is_running(void) { return s_running; }

gg_pump_result_t gg_pump_start(uint32_t duration_ms, const char *source) {
    if (!s_lock) return GG_PUMP_ERR_NOT_READY;
    if (xSemaphoreTake(s_lock, pdMS_TO_TICKS(1000)) != pdTRUE) {
        return GG_PUMP_ERR_BUSY;
    }

    gg_pump_result_t result = GG_PUMP_OK;
    int64_t now = esp_timer_get_time();
    roll_windows(now);

    /* Every one of these is checked here, in firmware, rather than trusted to
     * the caller. A cloud command arrives over a network we do not control,
     * and the backend's matching checks are a UX nicety -- these are the ones
     * that hold when the backend is wrong, compromised, or unreachable. */

    if (s_running) {
        result = GG_PUMP_ERR_BUSY;
        goto done;
    }

    if (duration_ms == 0 || duration_ms > GG_PUMP_MAX_RUNTIME_MS) {
        ESP_LOGW(TAG, "rejecting %lums request (max %d)",
                 (unsigned long)duration_ms, GG_PUMP_MAX_RUNTIME_MS);
        result = GG_PUMP_ERR_DURATION;
        goto done;
    }

    if (s_last_stop_us >= 0 &&
        (now - s_last_stop_us) < (int64_t)GG_PUMP_MIN_INTERVAL_MS * 1000LL) {
        result = GG_PUMP_ERR_TOO_SOON;
        goto done;
    }

    if (s_used_this_hour_ms + duration_ms > GG_PUMP_MAX_PER_HOUR_MS) {
        result = GG_PUMP_ERR_HOUR_QUOTA;
        goto done;
    }

    if (s_used_today_ms + duration_ms > GG_PUMP_MAX_PER_DAY_MS) {
        result = GG_PUMP_ERR_DAY_QUOTA;
        goto done;
    }

    if (gg_pump_reservoir_empty()) {
        /* Running a diaphragm pump dry destroys it in minutes, so this
         * protects the hardware as much as the plant. */
        result = GG_PUMP_ERR_RESERVOIR;
        goto done;
    }

    {
        gg_reading_t reading;
        if (gg_sensors_read(&reading) == ESP_OK && reading.soil1_valid &&
            reading.soil1_pct >= GG_PUMP_SOIL_WET_THRESHOLD) {
            ESP_LOGW(TAG, "refusing: soil already at %.1f%%", reading.soil1_pct);
            result = GG_PUMP_ERR_SOIL_WET;
            goto done;
        }
        /* Note: an *invalid* soil reading does not block watering. A dead
         * probe should not mean the plant never gets water again -- the
         * runtime and quota caps still bound the worst case. */
    }

    s_started_at_us = now;
    s_running = true;
    pump_gpio_set(true);

    /* The hardware timer is the actual guarantee. A vTaskDelay in a task that
     * gets starved, blocked on I2C, or crashes would leave the pump on
     * indefinitely; esp_timer fires from its own high-priority context. */
    esp_timer_start_once(s_stop_timer, (uint64_t)duration_ms * 1000ULL);

    ESP_LOGI(TAG, "pump started for %lums (source=%s)",
             (unsigned long)duration_ms, source ? source : "?");
    emit("started", duration_ms);

done:
    xSemaphoreGive(s_lock);
    return result;
}

void gg_pump_abort(const char *reason) {
    if (!s_running) return;
    esp_timer_stop(s_stop_timer);
    pump_gpio_set(false);

    int64_t now = esp_timer_get_time();
    uint32_t ran_ms = (uint32_t)((now - s_started_at_us) / 1000);
    s_running = false;
    s_last_stop_us = now;
    s_used_this_hour_ms += ran_ms;
    s_used_today_ms += ran_ms;

    ESP_LOGW(TAG, "pump aborted after %lums (%s)", (unsigned long)ran_ms, reason);
    emit(reason ? reason : "user_abort", ran_ms);
}

void gg_pump_emergency_stop(void) {
    /* Callable from anywhere, including an ISR-adjacent context or a panic
     * handler. Touches the GPIO directly and takes no locks -- if we are here,
     * something is already wrong and blocking on a mutex could be fatal. */
    pump_gpio_set(false);
    s_running = false;
}

const char *gg_pump_result_str(gg_pump_result_t r) {
    switch (r) {
        case GG_PUMP_OK:             return "ok";
        case GG_PUMP_ERR_BUSY:       return "already_running";
        case GG_PUMP_ERR_DURATION:   return "duration_out_of_range";
        case GG_PUMP_ERR_TOO_SOON:   return "rate_limited";
        case GG_PUMP_ERR_HOUR_QUOTA: return "hourly_quota_exceeded";
        case GG_PUMP_ERR_DAY_QUOTA:  return "daily_quota_exceeded";
        case GG_PUMP_ERR_RESERVOIR:  return "reservoir_empty";
        case GG_PUMP_ERR_SOIL_WET:   return "soil_already_wet";
        case GG_PUMP_ERR_NOT_READY:  return "not_initialised";
        default:                     return "unknown";
    }
}
