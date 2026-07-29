# Circles Ultra · Garmin watch face

An **Apple Watch Ultra–inspired** face for Garmin, rebuilt around **circle
spheres** instead of Apple's square complications. Designed **battery-first** for
the **Forerunner 165 / 165 Music** (390×390 AMOLED), and built to run on a wide
range of other Connect IQ watches from one binary.

- **Accent-colour system** just like the Ultra's colour picker — 12 colours,
  plus a *multicolour* mode that tints each sphere by the metric it shows.
- **Customizable icons** — every sphere's icon is user-selectable (22 vector
  icons), independent of the metric.
- **Battery-first** — true-black AMOLED background, once-per-minute redraws, a
  tight once-a-second seconds region, cached slow sensors, a one-switch battery
  saver, and an auto-dim always-on mode with burn-in protection.

> **Why not the Forerunner 15?** The FR15 (2014) has no Connect IQ support at
> all — it can't run watch faces or apps, so nothing can be installed or
> published to it. The **Forerunner 165** *is* a Connect IQ device and is the
> primary target here. Everything is validated against it first.

---

## Layout

The Apple Watch Ultra "modular" arrangement, rebuilt with circular spheres:

```
          ·  ·  ·  ·  ·  ·  ·           60-tick minute ring frames the face
       ·   (o)  (o)  (o)   ·            top row:  3 spheres
       ·                   ·
       |      10:42        |            big thin time, 24h/12h per system
       ·                   ·
       ·   (o)  (o)  (o)   ·            bottom row: 3 spheres
          ·  ·  ·  ·  ·  ·  ·
```

Each **sphere** is a dark disc with a thin gauge arc, a user-chosen icon, and
the metric's value (the date sphere shows a `WED 29` weekday+day stack). All six
are independently assignable from: steps, calories, heart rate, battery, Body
Battery, stress, distance, floors, active minutes, notifications, altitude,
temperature, sunrise/sunset, move bar, day progress, date.

Defaults — top: Body Battery · Date · Sunrise/Sunset; bottom: Steps · Heart
rate · Calories. The **tick ring** is the frame (cardinals in the accent color);
turning on a ring metric adds a thin progress arc just inside it.

---

## The battery story (this is the point)

On the FR165's AMOLED panel a black pixel is an *off* pixel, so power tracks how
much you light up. The face is built around that:

| Technique | Where | Why it saves power |
|---|---|---|
| True-black background | `Theme` / `onUpdate` clears to `0x000000` | Off pixels draw ~no current on AMOLED |
| Once-a-minute full redraw | `onUpdate` | Watch faces only redraw each minute unless woken |
| Tight seconds region | `onPartialUpdate` + `_secondsClip` | Per-second repaint touches ~5 % of the screen, not all of it |
| Power-budget guard | `onPowerBudgetExceeded` → `Config.disablePartialUpdates` | If the device says our per-second work is too costly, we stop it **permanently** and remember it |
| One-shot data fetch | `Metrics.beginFrame` | `ActivityMonitor`/stats/settings read once per frame, shared by all complications |
| Throttled slow sensors | `Metrics` caches | Body Battery & stress ≤ every 5 min, weather ≤ 15 min, sun ≤ 1 h |
| No GPS | `Sun.mc` | Sunrise/sunset is computed from the last weather position — the GPS is never woken |
| Read settings once | `Config.load` | Properties are read on start / change only, never inside `onUpdate` |
| Auto-dim always-on | `Theme.build(dim)` + `drawSpheresMinimal` | Fewer lit pixels + dim palette in always-on → less power **and** less burn-in |
| Battery-saver switch | `Config.batterySaver` | One toggle: dim palette, no live seconds, minimal always-on |
| Night mode | `Config.isNightNow` | Red-on-black, optionally on a schedule — the cheapest thing to show |

No allocation happens inside a redraw: `Reading` objects are pre-allocated once
and refilled in place, so the garbage collector never runs mid-frame.

The only permission requested is `SensorHistory` (for Body Battery / stress). No
positioning, no background, no network.

---

## Colours (the Ultra-style picker)

12 accent colours, chosen to survive Garmin's palette quantization without
shifting hue. Set **Accent color** in the Connect IQ app / Garmin Express, or in
the simulator's settings editor.

`Ultra Orange` · `Trail Yellow` · `Ocean Blue` · `Alpine Green` · `Night Red` ·
`Flamingo` · `Violet` · `Glacier` · `Mint` · `Mono White` · `Graphite` ·
`Nautical`

Turn on **Multicolor spheres** to colour each sphere by its metric instead
(steps green, calories orange, heart rate red, …) — the Ultra's Infograph look.

## Icons

22 vector icons, drawn in code so they tint to any colour and scale to any
screen. Each sphere has its own icon setting; leave it on **Auto** to match the
metric, or pick any icon you like (a flame on your steps sphere is your call).

---

## Building & publishing

The Garmin **Connect IQ SDK** is required (`monkeyc`, the simulator, and a
developer key). It could not be fetched in the environment where this was
authored, so build locally:

1. Install the SDK via the [Connect IQ SDK Manager](https://developer.garmin.com/connect-iq/sdk/)
   and add the `fr165` device.
2. Create a developer key once:
   ```bash
   openssl genrsa -out developer_key.pem 4096
   openssl pkcs8 -topk8 -inform PEM -outform DER -nocrypt \
           -in developer_key.pem -out developer_key
   ```
3. Build / simulate / package:
   ```bash
   export CIQ_SDK=~/.Garmin/ConnectIQ/Sdks/connectiq-sdk-lin-*/
   ./build.sh sim fr165        # build + open in the simulator
   ./build.sh build fr165      # debug .prg for one device
   ./build.sh package          # store-ready .iq for every product
   ```
4. **Publish**: upload `bin/CirclesUltra.iq` at
   [apps.garmin.com](https://apps.garmin.com/) → *Upload an App* → Watch Face.
   The store listing needs a name, description, and screenshots (grab them from
   the simulator). Publishing is free once you have a Garmin developer account.

`developer_key*` and `bin/` are git-ignored — never commit your signing key.

### Supported devices

FR165/165 Music (reference), plus FR55/245/255/265/745/945/955/965, Venu &
Vivoactive families, and fenix 6/7 / epix 2. The full list is in `manifest.xml`.
If your installed SDK is missing a device in that list, `monkeyc` will name it —
remove that one `<iq:product>` line and rebuild; it doesn't affect the others.

## Project layout

```
manifest.xml            products, permissions, languages
monkey.jungle           build config (source + resource paths)
build.sh                build / sim / package helper
source/
  CirclesUltraApp.mc    app entry, settings load
  CirclesUltraView.mc   the face: layout, onUpdate, onPartialUpdate, power hooks
  Theme.mc              accent palette, night/dim/multicolour resolution
  Icons.mc              22 vector icons drawn with dc primitives
  Metrics.mc            data sources, per-frame + slow-sensor caching
  Config.mc             cached settings, night/battery logic
  Sun.mc                local sunrise/sunset (no GPS)
resources/              strings (EN), properties, settings UI, launcher icon
resources-spa/          Spanish strings
tools/make_launcher.py  regenerates the launcher PNG (stdlib only)
```
