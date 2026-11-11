# How Even Dimmer works

macOS's keyboard backlight controller accepts any brightness from `0.0` to `1.0`, but the brightness keys only move in fixed steps. Even Dimmer calls `KeyboardBrightnessClient` in `CoreBrightness.framework` directly and can set any value in between.

On first launch, and after each macOS update, it calibrates for that Mac:

- **Dimmest level:** macOS switches very small saved values off about a second after they're set. Even Dimmer tries values from `0.00015` upward and keeps the first one that stays on.
- **Light curve:** CoreBrightness reports an estimate of the light output. Even Dimmer reads it at two low levels and fits a straight line. On an M1 Air that line is `0.1 + 14.56 × brightness`, which has a fixed floor. The slider uses a log scale of that output, so each step looks about the same size.
- **Apple's lowest step:** this is known for the M1 Air (`0.0105`). On other models it's learned when you press brightness-down until the light turns off.

The calibration is saved in the app's preferences (`io.github.evendimmer`).

For the screen, Even Dimmer uses `DisplayServices.framework`. The brightness keys move in 16 steps, and the lowest is `1/16`. Below that, the backlight still gets dimmer down to just above `0`; exactly `0` switches it off. On an M1 Air that floor is about 2.4 nits, compared with 4 nits at Apple's lowest step. Past the floor, Even Dimmer scales the display's gamma table: it takes the table macOS is currently using, multiplies it by a factor between 0.1 and 1, and rebuilds it whenever macOS changes the table (for example when Night Shift turns on). Night Shift is controlled through `CBBlueLightClient` in `CoreBrightness.framework`.

## Compatibility notes

Even Dimmer measures each Mac's keyboard light on first launch, so it doesn't rely on numbers from one model. When you report results, include your Mac model (Apple menu → **About This Mac**) and macOS version.

Even Dimmer uses a private Apple framework (`CoreBrightness`). A future macOS update could break it. If that happens, the app tells you it can't find a keyboard backlight. It can't damage anything.
