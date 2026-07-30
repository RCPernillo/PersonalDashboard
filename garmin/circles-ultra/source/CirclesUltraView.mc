import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

//! The face.
//!
//! Apple Watch Ultra "modular" arrangement, rebuilt with circular spheres:
//!   * a dense minute tick ring frames the whole screen;
//!   * a big thin time sits in the centre;
//!   * six spheres frame it - three across the top, three across the bottom -
//!     each a dark disc with its own gauge arc, an icon or value, and (for the
//!     date sphere) a weekday + day stack.
//!
//! Power model:
//!   onUpdate()        - full redraw, about once a minute in low-power mode, or
//!                       on every wake/gesture.
//!   onPartialUpdate() - ~once a second, ONLY when the user opted into live
//!                       seconds AND the device allows partial updates. Repaints
//!                       one small region near the bottom, nothing else.
//!
//! On the Forerunner 165 (AMOLED) the background is pure black so most of the
//! panel draws no current, and always-on frames use the dim palette to keep the
//! lit-pixel count low, protecting both battery and screen against burn-in.
class CirclesUltraView extends WatchUi.WatchFace {

    private var _w as Number = 0;
    private var _h as Number = 0;
    private var _cx as Number = 0;
    private var _cy as Number = 0;
    private var _isRound as Boolean = true;

    private var _timeFont as Graphics.FontType = Graphics.FONT_NUMBER_HOT;
    private var _timeY as Number = 0;

    // Tick ring geometry.
    private var _tickOuter as Number = 0;
    private var _tickMinorIn as Number = 0;
    private var _tickMajorIn as Number = 0;

    // Six spheres: parallel x/y arrays, top row then bottom row.
    private var _sphereR as Number = 0;
    private var _sphereX as Array<Number> = [0, 0, 0, 0, 0, 0];
    private var _sphereY as Array<Number> = [0, 0, 0, 0, 0, 0];

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
            new Metrics.Reading(), new Metrics.Reading(), new Metrics.Reading(),
            new Metrics.Reading(), new Metrics.Reading(), new Metrics.Reading()
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

        // Tick ring hugs the bezel.
        _tickOuter   = (_w * 0.485).toNumber();
        _tickMinorIn = (_w * 0.455).toNumber();
        _tickMajorIn = (_w * 0.435).toNumber();

        // Big thin time, vertically centred between the two sphere rows.
        _timeFont = Graphics.FONT_NUMBER_HOT;
        _timeY = _cy;

        // Six spheres: three columns, a top row and a bottom row. Sized and
        // spaced so they never touch each other, clear the tick ring, and leave
        // the centre open for the time: radius 0.098*w with wide columns gives
        // an even gap between neighbours and a few px of margin to the ticks.
        _sphereR = (_w * 0.098).toNumber();
        var colL = (_w * 0.27).toNumber();
        var colM = (_w * 0.50).toNumber();
        var colR = (_w * 0.73).toNumber();
        var rowTop = (_h * 0.24).toNumber();
        var rowBot = (_h * 0.76).toNumber();
        _sphereX = [colL, colM, colR, colL, colM, colR];
        _sphereY = [rowTop, rowTop, rowTop, rowBot, rowBot, rowBot];

        // Seconds repaint region: small, centred, in the clear band between the
        // bottom-middle sphere and the bottom of the tick ring.
        var sw = (_w * 0.20).toNumber();
        var sh = (dc.getFontHeight(Graphics.FONT_TINY) * 1.1).toNumber();
        _secondsClip = [_cx - sw / 2, (_h * 0.895).toNumber() - sh / 2, sw, sh];
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
        var dim = (_lowPower && _canBurnInProtect) || Config.batterySaver;
        var pal = Theme.build(Config.themeId, night, dim);

        dc.setColor(pal.text, pal.background);
        dc.clear();

        // The tick ring is the frame; skip it in always-on to save pixels.
        if (!dim) {
            drawTickRing(dc, pal);
        }
        // Optional thin progress arc just inside the ticks.
        if (Config.ringMetric != Metrics.NONE) {
            drawRingArc(dc, pal);
        }

        drawTime(dc, pal, clock);

        for (var i = 0; i < 6; i += 1) {
            drawSphere(dc, pal, i, dim);
        }
    }

    private function drawTickRing(dc as Graphics.Dc, pal as Theme.Palette) as Void {
        if (!Config.showHourMarks) { return; }
        // 60 ticks; every 5th is longer + brighter, the four cardinals get the
        // accent colour. Cheap on AMOLED - thin lines on black.
        for (var i = 0; i < 60; i += 1) {
            var a = i * Math.PI / 30.0;
            var s = Math.sin(a);
            var c = Math.cos(a);
            var major = (i % 5 == 0);
            var inner = major ? _tickMajorIn : _tickMinorIn;
            if (i % 15 == 0) {
                dc.setColor(pal.accent, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(3);
            } else if (major) {
                dc.setColor(pal.textDim, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
            } else {
                dc.setColor(pal.track, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(1);
            }
            dc.drawLine(_cx + s * inner, _cy - c * inner,
                        _cx + s * _tickOuter, _cy - c * _tickOuter);
        }
        dc.setPenWidth(1);
    }

    private function drawRingArc(dc as Graphics.Dc, pal as Theme.Palette) as Void {
        Metrics.fill(Config.ringMetric, _ring);
        if (_ring.frac < 0.0) { return; }
        var r = _tickMajorIn - 6;
        dc.setPenWidth(4);
        dc.setColor(pal.accent, Graphics.COLOR_TRANSPARENT);
        drawGaugeArc(dc, _cx, _cy, r, _ring.frac);
        dc.setPenWidth(1);
    }

    //! Clockwise gauge from 12 o'clock. Centralised so the angle wrap-around
    //! (drawArc wants 0-360) and the full-circle case live in one place.
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
            return Config.secondsMode == Config.SECONDS_ALWAYS
                   && Config.partialUpdatesAllowed;
        }
        return true;
    }

    private function drawSecondsText(dc as Graphics.Dc, pal as Theme.Palette,
                                     sec as Number, color as Number) as Void {
        var clip = _secondsClip;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_cx, clip[1] + clip[3] / 2, Graphics.FONT_TINY,
                    sec.format("%02d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- spheres -----------------------------------------------------------

    private function drawSphere(dc as Graphics.Dc, pal as Theme.Palette,
                                slot as Number, dim as Boolean) as Void {
        var metric = Config.sphereMetric[slot];
        if (metric == Metrics.NONE) { return; }

        var cx = _sphereX[slot];
        var cy = _sphereY[slot];
        var r = _sphereR;

        // Disc so the complication reads as a sphere. Skipped when the palette
        // says pure black (always-on / night), which also saves pixels.
        if (pal.disc != pal.background) {
            dc.setColor(pal.disc, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(cx, cy, r);
        }

        // Always-on: icon only, dim, no gauge/disc. Fewest lit pixels.
        if (dim) {
            var iconDim = Config.iconFor(slot);
            if (metric == Metrics.DATE) {
                drawDateStack(dc, pal, cx, cy, r, pal.textDim);
            } else {
                Icons.draw(dc, iconDim, cx, cy, (r * 0.62).toNumber(),
                           pal.textDim, pal.background);
            }
            return;
        }

        Metrics.fill(metric, _cell[slot]);
        var color = Theme.sphereColor(pal, metric, Config.multicolor);

        // Gauge track + value arc around the sphere edge.
        dc.setPenWidth(3);
        dc.setColor(pal.track, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, r);
        if (_cell[slot].frac >= 0.0) {
            dc.setColor(color, Graphics.COLOR_TRANSPARENT);
            drawGaugeArc(dc, cx, cy, r, _cell[slot].frac);
        }
        dc.setPenWidth(1);

        // The date sphere gets a weekday + day stack, like "MI 11".
        if (metric == Metrics.DATE) {
            drawDateStack(dc, pal, cx, cy, r, color);
            return;
        }

        // Everyone else: icon in the top half, value below.
        Icons.draw(dc, Config.iconFor(slot), cx, cy - (r * 0.30).toNumber(),
                   (r * 0.60).toNumber(), color, pal.background);
        if (Config.showValues) {
            dc.setColor(pal.text, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + (r * 0.34).toNumber(), Graphics.FONT_XTINY,
                        _cell[slot].text,
                        Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    //! Weekday abbreviation over the day number, filling a sphere.
    private function drawDateStack(dc as Graphics.Dc, pal as Theme.Palette,
                                   cx as Number, cy as Number, r as Number,
                                   accent as Number) as Void {
        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dow = weekdayShort(g.day_of_week);

        dc.setColor(accent, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - (r * 0.34).toNumber(), Graphics.FONT_XTINY, dow,
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(pal.text, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + (r * 0.16).toNumber(), Graphics.FONT_MEDIUM,
                    g.day.format("%d"),
                    Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // ---- once-a-second partial update -------------------------------------

    function onPartialUpdate(dc as Graphics.Dc) as Void {
        if (!secondsVisibleNow()) { return; }

        var clock = System.getClockTime();
        var night = Config.isNightNow(clock.hour);
        var pal = Theme.build(Config.themeId, night, _lowPower);
        var color = _lowPower ? pal.accentDim : pal.accent;

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
}
