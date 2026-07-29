import Toybox.Graphics;
import Toybox.Lang;

//! Colour system.
//!
//! Mirrors the Apple Watch Ultra accent-colour picker: one accent colour drives
//! the whole face, with an optional "multicolour" mode where every sphere is
//! tinted by the metric it shows (the way Infograph does it).
//!
//! Background is true black (0x000000) by default. On the Forerunner 165 that
//! is not a style choice: an AMOLED pixel showing pure black is switched off,
//! so it draws no current at all.
module Theme {

    // ---- Accent palette (ids must match resources/settings/settings.xml) ----
    enum {
        ULTRA_ORANGE = 0,
        TRAIL_YELLOW,
        OCEAN_BLUE,
        ALPINE_GREEN,
        NIGHT_RED,
        FLAMINGO,
        VIOLET,
        GLACIER,
        MINT,
        MONO_WHITE,
        GRAPHITE,
        NAUTICAL
    }

    // Accent colours. Garmin MIP screens quantize to a 64-colour palette, so
    // these are picked to survive quantization without shifting hue.
    const ACCENT = [
        0xFF6600, // Ultra Orange - the signature Ultra colour
        0xFFCC00, // Trail Yellow
        0x00AAFF, // Ocean Blue
        0x00CC66, // Alpine Green
        0xFF0000, // Night Red
        0xFF5599, // Flamingo
        0xAA55FF, // Violet
        0x99DDFF, // Glacier
        0x00FFCC, // Mint
        0xFFFFFF, // Mono White
        0xAAAAAA, // Graphite
        0x0055FF  // Nautical
    ] as Array<Number>;

    // Dimmed variant of each accent, used for gauge tracks and always-on mode.
    const ACCENT_DIM = [
        0x552200,
        0x554400,
        0x003355,
        0x004422,
        0x550000,
        0x551133,
        0x331155,
        0x224455,
        0x005544,
        0x555555,
        0x333333,
        0x001155
    ] as Array<Number>;

    // Per-metric colours for multicolour mode. Index by Metrics.* id.
    const METRIC_COLOR = [
        0xAAAAAA, // NONE
        0x00CC66, // STEPS
        0xFF6600, // CALORIES
        0xFF0000, // HEART_RATE
        0xFFCC00, // BATTERY
        0x00AAFF, // BODY_BATTERY
        0xAA55FF, // STRESS
        0x00FFCC, // DISTANCE
        0xFF5599, // FLOORS
        0x00CC66, // ACTIVE_MINUTES
        0x00AAFF, // NOTIFICATIONS
        0xAAAAAA, // ALTITUDE
        0x99DDFF, // TEMPERATURE
        0xFFCC00, // SUNRISE_SUNSET
        0xFF6600, // MOVE_BAR
        0xFFFFFF, // DAY_PROGRESS
        0xFFFFFF, // SECONDS
        0xAAAAAA  // DATE
    ] as Array<Number>;

    // Neutral greys used for tracks / secondary text when not in night mode.
    const TRACK_DARK   = 0x222222;
    const TEXT_DIM     = 0x888888;
    const TEXT_BRIGHT  = 0xFFFFFF;

    //! Resolved colour set handed to the renderer once per update.
    class Palette {
        var accent    as Number = 0xFF6600;
        var accentDim as Number = 0x552200;
        var text      as Number = 0xFFFFFF;
        var textDim   as Number = 0x888888;
        var track     as Number = 0x222222;
        var background as Number = 0x000000;
        //! True when the face must stay as dark as possible (night window,
        //! battery saver, or always-on/burn-in rendering).
        var dim as Boolean = false;
    }

    function clampId(id as Number) as Number {
        if (id < 0 || id >= ACCENT.size()) { return ULTRA_ORANGE; }
        return id;
    }

    //! Build the palette for the current settings + power state.
    //!
    //! @param themeId  accent index
    //! @param night    true to force the red-on-black "night mode" look
    //! @param dim      true when we are drawing a low-power / always-on frame
    function build(themeId as Number, night as Boolean, dim as Boolean) as Palette {
        var p = new Palette();
        var id = clampId(themeId);

        if (night) {
            // Night mode: red only, nothing else lit. Same idea as the Ultra's
            // night mode, and on AMOLED it is by far the cheapest thing to show.
            p.accent     = 0xFF0000;
            p.accentDim  = 0x550000;
            p.text       = 0xFF0000;
            p.textDim    = 0x550000;
            p.track      = 0x550000;
            p.background = 0x000000;
            p.dim        = true;
            return p;
        }

        p.accent     = ACCENT[id];
        p.accentDim  = ACCENT_DIM[id];
        p.background = 0x000000;

        if (dim) {
            // Always-on / battery saver: drop the bright whites, keep the accent
            // readable but unsaturated, and use the dim accent for tracks.
            p.text     = ACCENT_DIM[id] == 0x555555 ? 0x888888 : ACCENT[id];
            p.textDim  = ACCENT_DIM[id];
            p.track    = 0x111111;
            p.dim      = true;
        } else {
            p.text     = TEXT_BRIGHT;
            p.textDim  = TEXT_DIM;
            p.track    = TRACK_DARK;
            p.dim      = false;
        }
        return p;
    }

    //! Colour for a sphere: metric-tinted in multicolour mode, accent otherwise.
    function sphereColor(p as Palette, metric as Number, multicolor as Boolean) as Number {
        if (p.dim || !multicolor) { return p.accent; }
        if (metric < 0 || metric >= METRIC_COLOR.size()) { return p.accent; }
        return METRIC_COLOR[metric];
    }
}
