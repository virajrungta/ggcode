# ggpcb4 — design notes

Findings from bringing up **ggpcb3** on the bench (ESP32-D0WD rev 1.1, MAC
`f4:2d:c9:bb:9f:88`). Everything here is something that actually bit us, not
speculation.

Ordered by how much pain it caused.

---

## 1. Silkscreen pin labels — highest value, zero cost

**Problem:** ggpcb3 has *no* pin-function silkscreen anywhere. The only text on
the board is the reference designators (`J2`, `J3`…). Working out which hole was
GND required reading the KiCad netlist and falling back to the square-pad
convention.

**Fix:** print `G V S` (or `GND 3V3 SIG`) beside every sensor connector, and
`+5V` / `PUMP` beside J6.

This is free at fab time and eliminates the entire class of "which wire goes
where" mistakes — including the one that destroys sensors (VCC/GND reversed).

## 2. Populate the JST XH headers

**Problem:** the footprints are `JST_XH_B3B-XH-A` — shrouded and keyed, so a
mating housing physically cannot be inserted backwards. But they were left
unpopulated, so we had bare holes and loose DuPont wires.

The soil probe read a steady ~2260 counts when seated and `0` when the wire
shifted. Calibration was impossible: capturing a dropout as the "air" reference
would have written a permanently wrong value to NVS with no visible symptom.

**Fix:** populate them. The protection is already designed in; it just wasn't
fitted. If cost is the concern, populate J2/J3/J5 at minimum.

## 3. Water-level input doesn't match the chosen sensor

**Problem:** J4 is wired as a 3.3V analog input on GPIO34. The part selected
(DFRobot **SEN0204**, XKC-Y25-T12V) is a **5–24V digital** sensor whose output
high equals its supply rail.

Two separate failures:
- 3.3V is below its 5V minimum, so it cannot run from J4 at all;
- powered from 5V, its output would put 5V on GPIO34. ESP32 GPIOs are not 5V
  tolerant (~3.6V absolute max). That damages the chip.

**Fix — pick one:**
- **(a)** Choose a 3.3V *analog* level sensor and keep J4 as designed. Simplest.
- **(b)** Keep SEN0204: give J4 a 5V feed and put a divider (or proper level
  shifter) between its output and the GPIO. Note the pin order also changes,
  since its signal is a different wire colour.

Whichever way, the connector and the BOM need to agree. They didn't here.

## 4. Move the pump off GPIO12

**Problem:** GPIO12 is the **MTDI strapping pin** — held high at reset, the
chip selects 1.8V flash and will not boot.

It currently works: R12's 10k pulldown holds it low, and "pump off" is the same
state. But it permanently constrains the design — no pull-up may ever be added
to that net, and the pump must never be energised across a reset.

**Fix:** move the pump gate to an ordinary output (GPIO16/17/18/19/21/22/23 are
all free here). Keep a pulldown on the gate regardless, so the MOSFET is off
while the ESP32 is in reset.

## 5. Gate the soil probe power

**Problem:** J2/J3 pin 2 goes straight to 3V3 with no switching element, so the
probes are biased continuously. Continuous DC bias is what drives the
electrolytic corrosion that eventually kills capacitive probes.

**Fix:** a small N-FET or load switch on the probes' VCC, driven by a GPIO.
Power up ~50ms before sampling, off afterwards. Also cuts idle current.

## 6. Pump power comes off the USB 5V rail

**Problem:** J6 pin 1 is +5V straight from USB. A laptop port supplies 500mA;
small diaphragm pumps draw 200–500mA running with inrush over 1A. C13 (100µF)
is small for that.

Likely symptom: the ESP32 browns out and resets the instant the pump starts —
mid-watering, with GPIO12's strapping behaviour in play.

**Fix:** a separate supply for the pump (barrel jack or dedicated header), or
at minimum much more bulk capacitance on the pump rail and a documented
"wall charger, not laptop port" requirement.

## 7. Decide on the light sensor

R9 (LDR) is in the schematic and the pick-and-place but **was not fitted**. R10
still ties LIGHT to GND, so GPIO35 sits at 0V permanently.

Firmware now reports light as *absent* rather than `0%` — a real-looking zero
would show as "pitch dark, forever" and drag the health score down for hardware
that was never installed.

**Fix:** either fit it, or remove R9/R10 and free GPIO35. If light matters to
the product, an I²C lux sensor (BH1750/VEML7700) gives calibrated lux instead of
an uncalibrated relative estimate — but note ggpcb3 has **no I²C bus at all**,
so that means routing one.

## 8. RESET / BOOT buttons

SW1 and SW2 are in the schematic but unpopulated. Flashing still works — the
CH340C drives DTR/RTS into Q1/Q2 and pulses EN/IO0 automatically, confirmed on
this board.

The risk is that there's **no manual recovery**. If firmware ever wedges the
chip badly enough that auto-reset can't catch it, the only way back is shorting
EN to GND by hand.

**Fix:** populate at least RESET, or expose EN and IO0 as labelled test pads.

## 9. Consider a 4-pin Grove connector for the DHT

J5 is 3-pin, and the Grove DHT22 cable is 4-pin. It works — pin 3 is NC, so
only three wires carry anything — but it means cutting or re-terminating the
supplied cable.

**Fix:** if Grove sensors will be used, a 4-pin Grove connector accepts the
cable directly.

---

## What ggpcb3 got right — keep these

- **All four analog inputs on ADC1** (GPIO36/39/34/35). ADC2 is unusable while
  Wi-Fi is active; a probe wired there would read fine on the bench and fail
  permanently once the pot joined a network. The board avoids this entirely.
- **Consistent connector pin order** — every sensor connector is GND / 3V3 /
  SIGNAL. Worth preserving.
- **Correct USB-C sink implementation** — R1/R2 5.1k CC pulldowns, both CC
  lines, both sides of the receptacle wired. Any compliant source supplies 5V,
  C-to-C cables work, and the cable is reversible.
- **16MB flash** — plenty of room for two 3MB OTA slots plus ~9.8MB storage.
- **Working auto-reset circuit** (Q1/Q2 off CH340C DTR/RTS). Flashing needed no
  button presses.
- **Flyback diode and bulk cap on the pump** (D3 SS14, C13).
