#pragma once

#include <stdbool.h>
#include <stdint.h>
#include "esp_err.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    GG_PUMP_OK = 0,
    GG_PUMP_ERR_BUSY,
    GG_PUMP_ERR_DURATION,
    GG_PUMP_ERR_TOO_SOON,
    GG_PUMP_ERR_HOUR_QUOTA,
    GG_PUMP_ERR_DAY_QUOTA,
    GG_PUMP_ERR_RESERVOIR,
    GG_PUMP_ERR_SOIL_WET,
    GG_PUMP_ERR_NOT_READY,
} gg_pump_result_t;

// reason is one of: started, completed, max_runtime, soil_wet,
// reservoir_empty, user_abort, watchdog  (see contracts/telemetry.md)
typedef void (*gg_pump_event_cb_t)(const char *reason, uint32_t duration_ms);

esp_err_t gg_pump_init(gg_pump_event_cb_t cb);

// Applies every safety interlock before energising. Never bypass this.
gg_pump_result_t gg_pump_start(uint32_t duration_ms, const char *source);

void gg_pump_abort(const char *reason);

// Lock-free, callable from any context. For panic/watchdog paths.
void gg_pump_emergency_stop(void);

bool gg_pump_is_running(void);
bool gg_pump_reservoir_empty(void);

const char *gg_pump_result_str(gg_pump_result_t r);

#ifdef __cplusplus
}
#endif
