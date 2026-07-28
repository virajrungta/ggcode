/* Host-compilable probe for the telemetry wire struct.
 *
 * Prints the packed bytes as hex so the Python contract test can compare the
 * real C layout against contracts/vectors/telemetry.json. Catches struct
 * padding, field ordering, and endianness mismatches between firmware and
 * backend -- the failure mode that turns into silently wrong sensor readings
 * rather than an obvious crash.
 *
 *   cc -o pack_probe pack_probe.c
 *   ./pack_probe <uptime> <temp_x100> <rh_x100> <soil_x100> <lux_x10> <flags>
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <assert.h>

typedef struct __attribute__((packed)) {
    uint32_t uptime_s;
    int16_t  temp_c_x100;
    uint16_t rh_x100;
    uint16_t soil_pct_x100;
    uint32_t lux_x10;
    uint8_t  flags;
} gg_telemetry_t;

_Static_assert(sizeof(gg_telemetry_t) == 15, "telemetry struct must stay 15 bytes");

int main(int argc, char **argv) {
    if (argc == 2 && argv[1][0] == '-') {   /* -size */
        printf("%zu\n", sizeof(gg_telemetry_t));
        return 0;
    }
    if (argc != 7) {
        fprintf(stderr, "usage: %s <uptime> <temp_x100> <rh_x100> "
                        "<soil_x100> <lux_x10> <flags>\n", argv[0]);
        return 2;
    }

    gg_telemetry_t t;
    t.uptime_s      = (uint32_t)strtoul(argv[1], NULL, 10);
    t.temp_c_x100   = (int16_t)strtol(argv[2], NULL, 10);
    t.rh_x100       = (uint16_t)strtoul(argv[3], NULL, 10);
    t.soil_pct_x100 = (uint16_t)strtoul(argv[4], NULL, 10);
    t.lux_x10       = (uint32_t)strtoul(argv[5], NULL, 10);
    t.flags         = (uint8_t)strtoul(argv[6], NULL, 10);

    const unsigned char *p = (const unsigned char *)&t;
    for (size_t i = 0; i < sizeof(t); i++) printf("%02x", p[i]);
    printf("\n");
    return 0;
}
