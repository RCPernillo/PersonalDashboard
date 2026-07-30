import Toybox.Application;
import Toybox.Lang;
import Toybox.System;

//! Settings snapshot.
//!
//! Every user setting is read from Application.Properties exactly once - at
//! startup and again on onSettingsChanged() - and cached in module variables.
//!
//! This is deliberate. Properties.getValue() hits the persisted settings store,
//! and a watch face that reads a dozen keys inside onUpdate() pays that cost
//! every single minute, forever. Reading them once turns a recurring cost into
//! a one-off.
module Config {

    // ---- seconds display mode ----
    enum {
        SECONDS_OFF = 0,     // never draw seconds (cheapest, the default)
        SECONDS_AWAKE,       // only while the watch is awake / gesture-lit
        SECONDS_ALWAYS       // also in low-power mode, where supported
    }

    // ---- date format ----
    enum {
        DATE_OFF = 0,
        DATE_DAY_NUM,        // WED 29
        DATE_NUM_MONTH,      // 29 JUL
        DATE_FULL            // WED 29 JUL
    }

    // ---- cached values ----
    var themeId       as Number  = Theme.ULTRA_ORANGE;
    var multicolor    as Boolean = false;

    var nightMode     as Boolean = false;   // force night palette all the time
    var nightAuto     as Boolean = false;   // ...or only inside a time window
    var nightStart    as Number  = 22;
    var nightEnd      as Number  = 6;

    var batterySaver  as Boolean = false;
    var secondsMode   as Number  = SECONDS_OFF;
    var showHourMarks as Boolean = true;
    var showValues    as Boolean = true;
    var dateFormat    as Number  = DATE_DAY_NUM;

    //! Optional "liquid swirl" background. Off by default: on AMOLED every lit
    //! pixel costs power, so this trades a little battery for texture. Never
    //! drawn in night / always-on / battery-saver frames.
    var bgPattern     as Boolean = false;
    //! Swirl line colour. 0 = match the accent colour; 1..12 pick a specific
    //! colour from the accent palette (red, blue, aqua, ...), so the background
    //! can be a different colour from the rest of the face.
    var bgColorId     as Number  = 0;

    //! Optional thin progress arc just inside the tick ring. Defaults off so the
    //! face matches the Ultra "modular" look, where the frame is the tick ring
    //! and each sphere carries its own gauge.
    var ringMetric    as Number  = Metrics.NONE;

    //! Six spheres, laid out three across the top and three across the bottom,
    //! framing the central time.
    var sphereMetric  as Array<Number> = [
        Metrics.BODY_BATTERY, Metrics.DATE, Metrics.SUNRISE_SUNSET,   // top row
        Metrics.STEPS,        Metrics.HEART_RATE, Metrics.CALORIES    // bottom row
    ];
    //! 0 means "auto" - use the icon the metric suggests. Anything else is a
    //! direct Icons.* id, which is what makes the icons user-customizable.
    var sphereIcon    as Array<Number> = [0, 0, 0, 0, 0, 0];

    //! Set to false permanently once the device tells us our per-second
    //! rendering blew the power budget. See CirclesUltraView.onPowerBudgetExceeded.
    var partialUpdatesAllowed as Boolean = true;

    private const KEY_PARTIAL_DISABLED = "partialDisabled";

    private function num(key as String, def as Number, lo as Number, hi as Number) as Number {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            return def;
        }
        var n = def;
        if (v instanceof Lang.Number) {
            n = v;
        } else if (v instanceof Lang.Float || v instanceof Lang.Double) {
            n = v.toNumber();
        } else if (v instanceof Lang.String) {
            var parsed = v.toNumber();
            n = (parsed == null) ? def : parsed;
        }
        if (n < lo || n > hi) { return def; }
        return n;
    }

    private function bool(key as String, def as Boolean) as Boolean {
        var v = null;
        try {
            v = Application.Properties.getValue(key);
        } catch (e) {
            return def;
        }
        if (v instanceof Lang.Boolean) { return v; }
        if (v instanceof Lang.Number) { return v != 0; }
        return def;
    }

    //! Re-read every setting. Called from the app on start and on settings change.
    function load() as Void {
        themeId       = num("themeId", Theme.ULTRA_ORANGE, 0, Theme.ACCENT.size() - 1);
        multicolor    = bool("multicolor", false);

        nightMode     = bool("nightMode", false);
        nightAuto     = bool("nightAuto", false);
        nightStart    = num("nightStart", 22, 0, 23);
        nightEnd      = num("nightEnd", 6, 0, 23);

        batterySaver  = bool("batterySaver", false);
        secondsMode   = num("secondsMode", SECONDS_OFF, 0, 2);
        showHourMarks = bool("showHourMarks", true);
        showValues    = bool("showValues", true);
        dateFormat    = num("dateFormat", DATE_DAY_NUM, 0, 3);
        bgPattern     = bool("bgPattern", false);
        bgColorId     = num("bgColor", 0, 0, Theme.ACCENT.size());

        ringMetric    = num("ringMetric", Metrics.NONE, 0, Metrics.COUNT - 1);

        sphereMetric = [
            num("sphere1Metric", Metrics.BODY_BATTERY,   0, Metrics.COUNT - 1),
            num("sphere2Metric", Metrics.DATE,           0, Metrics.COUNT - 1),
            num("sphere3Metric", Metrics.SUNRISE_SUNSET, 0, Metrics.COUNT - 1),
            num("sphere4Metric", Metrics.STEPS,          0, Metrics.COUNT - 1),
            num("sphere5Metric", Metrics.HEART_RATE,     0, Metrics.COUNT - 1),
            num("sphere6Metric", Metrics.CALORIES,       0, Metrics.COUNT - 1)
        ];
        sphereIcon = [
            num("sphere1Icon", 0, 0, Icons.COUNT),
            num("sphere2Icon", 0, 0, Icons.COUNT),
            num("sphere3Icon", 0, 0, Icons.COUNT),
            num("sphere4Icon", 0, 0, Icons.COUNT),
            num("sphere5Icon", 0, 0, Icons.COUNT),
            num("sphere6Icon", 0, 0, Icons.COUNT)
        ];

        // Battery saver overrides the expensive options rather than hiding them,
        // so the user can flip one switch and flip it back without losing setup.
        if (batterySaver) {
            secondsMode = SECONDS_OFF;
        }

        var disabled = false;
        try {
            var stored = Application.Storage.getValue(KEY_PARTIAL_DISABLED);
            disabled = (stored instanceof Lang.Boolean) ? stored : false;
        } catch (e) {
            disabled = false;
        }
        partialUpdatesAllowed = !disabled;
    }

    //! Remember that per-second updates are too expensive on this device so we
    //! never try again, even after a restart.
    function disablePartialUpdates() as Void {
        partialUpdatesAllowed = false;
        try {
            Application.Storage.setValue(KEY_PARTIAL_DISABLED, true);
        } catch (e) {
            // Storage full or unavailable - the in-memory flag still holds for
            // this session, which is the part that protects the battery.
        }
    }

    //! Resolve the swirl-background colour. 0 means "match accent" (passed in);
    //! otherwise it's a 1-based index into the accent palette.
    function bgColor(accent as Number) as Number {
        if (bgColorId <= 0) { return accent; }
        return Theme.ACCENT[Theme.clampId(bgColorId - 1)];
    }

    //! Resolve the icon for a sphere: explicit choice wins, otherwise the
    //! metric's default.
    function iconFor(slot as Number) as Number {
        var chosen = sphereIcon[slot];
        if (chosen > 0) { return chosen - 1; }   // 1-based in settings, 0 = auto
        return Metrics.defaultIcon(sphereMetric[slot]);
    }

    //! True when the night palette should be used right now.
    function isNightNow(hour as Number) as Boolean {
        if (nightMode) { return true; }
        if (!nightAuto) { return false; }
        if (nightStart == nightEnd) { return false; }
        if (nightStart < nightEnd) {
            return hour >= nightStart && hour < nightEnd;
        }
        // Window wraps midnight, e.g. 22:00 -> 06:00.
        return hour >= nightStart || hour < nightEnd;
    }
}
