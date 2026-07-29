import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! The face.
//!
//! Layout, top to bottom, on a round screen:
//!   * an outer progress ring (configurable metric) hugging the bezel;
//!   * the big time, centred;
//!   * an optional date line under it;
//!   * four "spheres" across the lower half - each a circle with an icon, a
//!     value, and a thin gauge arc - which is the Apple-Watch-Ultra-style
//!     complication cluster, adapted to circles.
//!
//! Power model:
//!   onUpdate()        - full redraw, runs about once a minute when the screen
//!                       is in low-power mode, or on every wake/gesture.
//!   onPartialUpdate() - runs ~once a second ONLY when the user opted into a
//!                       live seconds display AND the device allows partial
//!                       updates. It repaints a single small region, nothing
//!                       else, to stay inside the power budget.
//!
//! On the Forerunner 165 (AMOLED) the background is pure black so most of the
//! panel draws no current, and always-on frames use the dim palette to keep the
//! lit-pixel count and brightness low, which is what protects both battery and
//! screen against burn-in.
class CirclesUltraView extends WatchUi.WatchFace {

    // Geometry, computed once in onLayout from the real screen size so the same
    // code lays out a 240px FR55 and a 390px FR165 correctly.
    private var _w as Number = 0;
    private var _h as Number = 0;
    private var _cx as Number = 0;
    private var _cy as Number = 0;
    private var _isRound as Boolean = true;

    private var _timeFont as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var _timeY as Number = 0;
    private var _dateY as Number = 0;

    private var _ringR as Number = 0;
    private var _ringPen as Number = 4;

    private var _sphereR as Number = 0;
    private var _sphereCx as Array<Number> = [0, 0, 0, 0];
    private var _sphereCy as Number = 0;

    // Low-power state.
    private var _lowPower as Boolean = false;
    private var _canBurnInProtect as Boolean = false;
    private var _secondsClip as Array<Number> or Null = null;

    // Pre-allocated readings so a redraw allocates no memory.
    private var _ring as Metrics.Reading;
    private var _cell as Array<Metrics.Reading>;

    function initialize() {
        WatchFace.initialize();
        _ring = new Metrics.Reading();
        _cell = [
            new Metrics.Reading(),
            new Metrics.Reading(),
            new Metrics.Reading(),
            new Metrics.Reading()
        ];
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;

        var settings = System.getDeviceSettings();
        _isRound = (settings.screenShape == System.SCREEN_SHAPE_ROUND);
        _canBurnInProtect = (settings has :requiresBurnInProtection)
                            && settings.requiresBurnInProtection;

        // Ring hugs the bezel.
        _ringPen = (_w * 0.028).toNumber();
        if (_ringPen < 3) { _ringPen = 3; }
        _ringR = (_w / 2) - (_ringPen / 2) - 2;

        // Time sits a little above centre to leave the lower half for spheres.
        _timeFont = Graphics.FONT_NUMBER_HOT;
        _timeY = (_h * 0.33).toNumber();
        _dateY = (_h * 0.50).toNumber();

        // Four spheres evenly spread across the lower third, sized so they never
        // touch: centre-to-centre spacing stays wider than a sphere's diameter.
        _sphereR = (_w * 0.098).toNumber();
        _sphereCy = (_h * 0.72).toNumber();
        var margin = _sphereR + (_w * 0.03).toNumber();
        var step = (_w - 2 * margin) / 3.0;
        _sphereCx = [
            margin,
            (margin + step).toNumber(),
            (margin + 2 * step).toNumber(),
            (margin + 3 * step).toNumber()
        ];

        // Clip box for the once-a-second seconds repaint. Kept small on purpose:
        // the smaller the partial-update region, the lower the power cost.
        var sw = (_w * 0.22).toNumber();
        var sh = (dc.getFontHeight(Graphics.FONT_TINY) * 1.2).toNumber();
        _secondsClip = [_cx - sw / 2, _timeY - sh - 4, sw, sh];
    }

    // ---- lifecycle ---------------------------------------------------------

    function onShow() as Void {}
    function onHide() as Void {}

    function onExitSleep() as Void {
        _lowPower = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _lowPower = true;
        WatchUi.requestUpdate();
    }

    //! Device telling us our per-second work is too expensive. Stop doing it,
    //! permanently, and never fight the watchdog again.
    function onPowerBudgetExceeded(powerInfo as WatchUi.WatchFacePowerInfo) as Void {
        Config.disablePartialUpdates();
    }

    // ---- full redraw -------------------------------------------------------

    function onUpdate(dc as Graphics.Dc) as Void {
        var clock = System.getClockTime();
        Metrics.beginFrame(clock);

        var night = Config.isNightNow(clock.hour);
        // Always-on frames (low power on a burn-in screen, or the user's battery
        // saver) use the dim palette.
        var dim = (_lowPower && _canBurnInProtect) || Config.batterySaver;
        var pal = Theme.build(Config.themeId, night, dim);

        // Clear to black. On AMOLED this is the cheapest possible background.
        dc.setColor(pal.text, pal.background);
        dc.clear();

        drawRing(dc, pal);
        drawTime(dc, pal, clock);
        drawDate(dc, pal, clock);

        // Spheres are skipped entirely in dim always-on frames: fewer lit pixels,
        // less burn-in, less power. The time and ring still tell you what you
        // need at a glance.
        if (!dim) {
            drawSpheres(dc, pal);
        } else {
            drawSpheresMinimal(dc, pal);
        }

        if (!_lowPower) {
            drawHourMarks(dc, pal);
        }
    }

    //! Draw a fraction of a circle as a clockwise gauge starting at 12 o'clock.
    //! Centralised so the angle wrap-around (drawArc wants 0-360) and the
    //! full-circle edge case are handled in exactly one place.
    private function drawGaugeArc(dc as Graphics.Dc, cx as Number, cy as Number,
                                  r as Number, frac as Float) as Void {
        if (frac <= 0.0) { return; }
        if (frac >= 0.999) {
            dc.drawCircle(cx, cy, r);
            return;
        }
        var endDeg = 90.0 - (frac * 360.0);
        while (endDeg < 0.0) { endDeg += 360.0; }
        dc.drawArc(cx, cy, r, Graphics.ARC_CLOCKWISE, 90, endDeg.toNumber());
    }

    private function drawRing(dc as Graphics.Dc, pal as Theme.Palette) as Void {
        Metrics.fill(Config.ringMetric, _ring);
        dc.setPenWidth(_ringPen);

        // Track.
        dc.setColor(pal.track, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, _ringR);

        // Progress arc, clockwise from 12 o'clock.
        if (_ring.frac >= 0.0) {
            dc.setColor(pal.accent, Graphics.COLOR_TRANSPARENT);
            drawGaugeArc(dc, _cx, _cy, _ringR, _ring.frac);
        }
        dc.setPenWidth(1);
    }

    private function drawTime(dc as Graphics.Dc, pal as Theme.Palette,
                              clock as System.ClockTime) as Void {
        var settings = System.getDeviceSettings();
        var hour = clock.hour;
        if (!settings.is24Hour) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var hh = settings.is24Hour ? hour.format("%02d") : hour.format("%d");
        var timeStr = hh + ":" + clock.min.format("%02d");

        dc.setColor(pal.text, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _timeY, _timeFont, timeStr,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Draw a seconds baseline here so the region is never blank between the
        // once-a-minute full redraws; onPartialUpdate then refreshes it each
        // second. Skipped when seconds shouldn't be shown in the current state.
        if (secondsVisibleNow()) {
            drawSecondsText(dc, pal, clock.sec, _lowPower ? pal.accentDim : pal.accent);
        }
    }

    //! Whether the seconds field should be shown given the mode and power state.
    private function secondsVisibleNow() as Boolean {
        if (Config.secondsMode == Config.SECONDS_OFF || Config.batterySaver) {
            return false;
        }
        if (_lowPower) {
            // In low power we only show seconds in ALWAYS mode, and only if the
            // device hasn't vetoed the per-second work.
            return Config.secondsMode == Config.SECONDS_ALWAYS
                   && Config.partialUpdatesAllowed;
        }
        return true;   // awake: both AWAKE and ALWAYS show seconds
    }

    private function drawSecondsText(dc as Graphics.Dc, pal as Theme.Palette,
                                     sec as Number, color as Number) as Void {
        var clip = _secondsClip;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, clip[1] + clip[3] / 2, Graphics.FONT_TINY,
                    sec.format("%02d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawDate(dc as Graphics.Dc, pal as Theme.Palette,
                              clock as System.ClockTime) as Void {
        if (Config.dateFormat == Config.DATE_OFF) { return; }
        // FORMAT_SHORT keeps day_of_week and month as numbers so they can index
        // our own localized short-name tables (FORMAT_MEDIUM would return
        // system strings and defeat the point of shipping our own).
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var day = g.day.format("%d");
        var dow = weekdayShort(g.day_of_week);
        var mon = monthShort(g.month);

        var s;
        switch (Config.dateFormat) {
            case Config.DATE_DAY_NUM:   s = dow + " " + day; break;
            case Config.DATE_NUM_MONTH: s = day + " " + mon; break;
            default:                    s = dow + " " + day + " " + mon; break;
        }

        dc.setColor(pal.textDim, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, _dateY, Graphics.FONT_TINY, s,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawSpheres(dc as Graphics.Dc, pal as Theme.Palette) as Void {
        for (var i = 0; i < 4; i += 1) {
            var metric = Config.sphereMetric[i];
            if (metric == Metrics.NONE) { continue; }

            Metrics.fill(metric, _cell[i]);
            var cx = _sphereCx[i];
            var cy = _sphereCy;
            var r = _sphereR;
            var color = Theme.sphereColor(pal, metric, Config.multicolor);

            // Gauge track ring.
            dc.setPenWidth(3);
            dc.setColor(pal.track, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);

            // Gauge arc for metrics that have a fraction.
            if (_cell[i].frac >= 0.0) {
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                drawGaugeArc(dc, cx, cy, r, _cell[i].frac);
            }
            dc.setPenWidth(1);

            // Icon in the top half of the sphere.
            var iconId = Config.iconFor(i);
            Icons.draw(dc, iconId, cx, cy - (r * 0.32).toNumber(),
                       (r * 0.7).toNumber(), color, pal.background);

            // Value in the bottom half.
            if (Config.showValues) {
                dc.setColor(pal.text, Graphics.COLOR_TRANSPARENT);
                dc.drawText(cx, cy + (r * 0.34).toNumber(), Graphics.FONT_XTINY,
                            _cell[i].text,
                            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }
    }

    //! Always-on variant: icon only, no gauge fill, dim colour. Keeps the
    //! layout recognisable while lighting as few pixels as possible.
    private function drawSpheresMinimal(dc as Graphics.Dc, pal as Theme.Palette) as Void {
        for (var i = 0; i < 4; i += 1) {
            var metric = Config.sphereMetric[i];
            if (metric == Metrics.NONE) { continue; }
            var iconId = Config.iconFor(i);
            Icons.draw(dc, iconId, _sphereCx[i], _sphereCy,
                       (_sphereR * 0.7).toNumber(), pal.textDim, pal.background);
        }
    }

    private function drawHourMarks(dc as Graphics.Dc, pal as Theme.Palette) as Void {
        if (!Config.showHourMarks) { return; }
        dc.setColor(pal.textDim, Graphics.COLOR_TRANSPARENT);
        var inner = _ringR - _ringPen - 6;
        var outer = _ringR - _ringPen - 2;
        for (var i = 0; i < 12; i += 1) {
            var a = i * Math.PI / 6.0;
            var s = Math.sin(a);
            var c = Math.cos(a);
            dc.setPenWidth(i % 3 == 0 ? 3 : 1);
            dc.drawLine(_cx + s * inner, _cy - c * inner,
                        _cx + s * outer, _cy - c * outer);
        }
        dc.setPenWidth(1);
    }

    // ---- once-a-second partial update -------------------------------------

    function onPartialUpdate(dc as Graphics.Dc) as Void {
        if (!secondsVisibleNow()) { return; }

        var clock = System.getClockTime();
        var night = Config.isNightNow(clock.hour);
        var pal = Theme.build(Config.themeId, night, _lowPower);
        var color = _lowPower ? pal.accentDim : pal.accent;

        // Repaint only the small seconds box. A tight clip is the whole point of
        // the partial-update path: it is what keeps the once-a-second cost
        // inside the device power budget.
        var clip = _secondsClip;
        dc.setClip(clip[0], clip[1], clip[2], clip[3]);
        dc.setColor(pal.background, pal.background);
        dc.clear();
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, clip[1] + clip[3] / 2, Graphics.FONT_TINY,
                    clock.sec.format("%02d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.clearClip();
    }

    // ---- small helpers -----------------------------------------------------

    private function weekdayShort(dow as Number) as String {
        var keys = [Rez.Strings.Sun, Rez.Strings.Mon, Rez.Strings.Tue,
                    Rez.Strings.Wed, Rez.Strings.Thu, Rez.Strings.Fri,
                    Rez.Strings.Sat];
        return WatchUi.loadResource(keys[(dow - 1) % 7]) as String;
    }

    private function monthShort(month as Number) as String {
        var keys = [Rez.Strings.Jan, Rez.Strings.Feb, Rez.Strings.Mar,
                    Rez.Strings.Apr, Rez.Strings.May, Rez.Strings.Jun,
                    Rez.Strings.Jul, Rez.Strings.Aug, Rez.Strings.Sep,
                    Rez.Strings.Oct, Rez.Strings.Nov, Rez.Strings.Dec];
        return WatchUi.loadResource(keys[(month - 1) % 12]) as String;
    }
}
