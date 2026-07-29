import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;

//! Data sources for the ring and the four spheres.
//!
//! Battery notes, since that is the whole point of this face:
//!
//!  * beginFrame() fetches ActivityMonitor.getInfo(), getSystemStats() and
//!    getDeviceSettings() ONCE per redraw. Five complications asking for the
//!    same info separately is five times the work for identical numbers.
//!  * Body Battery and Stress come from SensorHistory, which is the most
//!    expensive call on this face. They are sampled at most every 5 minutes -
//!    they physically cannot change faster than that in any meaningful way.
//!  * Weather is sampled at most every 15 minutes.
//!  * Sunrise/sunset is computed at most once per hour and only from the
//!    weather station position, so the GPS is never woken up.
//!  * A metric that is not shown is never read at all.
module Metrics {

    enum {
        NONE = 0,
        STEPS,
        CALORIES,
        HEART_RATE,
        BATTERY,
        BODY_BATTERY,
        STRESS,
        DISTANCE,
        FLOORS,
        ACTIVE_MINUTES,
        NOTIFICATIONS,
        ALTITUDE,
        TEMPERATURE,
        SUNRISE_SUNSET,
        MOVE_BAR,
        DAY_PROGRESS,
        SECONDS,
        DATE
    }

    const COUNT = 18;

    //! One complication's worth of resolved data.
    //! Instances are pre-allocated by the view and refilled in place, so a
    //! redraw allocates nothing and never triggers a garbage collection.
    class Reading {
        var text as String = "--";
        //! 0.0 - 1.0 to draw a gauge arc, or negative for "no gauge".
        var frac as Float = -1.0;
        var icon as Number = Icons.NONE;

        function reset() as Void {
            text = "--";
            frac = -1.0;
            icon = Icons.NONE;
        }
    }

    // ---- per-frame shared state ----
    private var _am as ActivityMonitor.Info or Null = null;
    private var _stats as System.Stats or Null = null;
    private var _ds as System.DeviceSettings or Null = null;
    private var _clock as System.ClockTime or Null = null;
    private var _now as Number = 0;

    // ---- slow caches ----
    private var _bbValue as Number or Null = null;
    private var _bbAt as Number = -99999;
    private var _stressValue as Number or Null = null;
    private var _stressAt as Number = -99999;
    private var _tempValue as Number or Null = null;
    private var _tempAt as Number = -99999;
    private var _sunriseMin as Number or Null = null;
    private var _sunsetMin as Number or Null = null;
    private var _sunAt as Number = -99999;
    private var _sunDay as Number = -1;

    private const SLOW_SENSOR_SEC = 300;    // 5 min
    private const WEATHER_SEC     = 900;    // 15 min
    private const SUN_SEC         = 3600;   // 1 h

    private const KEY_LAT = "lastLat";
    private const KEY_LON = "lastLon";

    //! Default icon per metric, used when the user leaves the icon on "Auto".
    function defaultIcon(metric as Number) as Number {
        switch (metric) {
            case STEPS:          return Icons.STEPS;
            case CALORIES:       return Icons.FLAME;
            case HEART_RATE:     return Icons.HEART;
            case BATTERY:        return Icons.BATTERY;
            case BODY_BATTERY:   return Icons.BOLT;
            case STRESS:         return Icons.WAVE;
            case DISTANCE:       return Icons.ROUTE;
            case FLOORS:         return Icons.STAIRS;
            case ACTIVE_MINUTES: return Icons.CLOCK;
            case NOTIFICATIONS:  return Icons.BELL;
            case ALTITUDE:       return Icons.MOUNTAIN;
            case TEMPERATURE:    return Icons.THERMO;
            case SUNRISE_SUNSET: return Icons.SUN;
            case MOVE_BAR:       return Icons.MOVE;
            case DAY_PROGRESS:   return Icons.TARGET;
            case SECONDS:        return Icons.DOT;
            case DATE:           return Icons.CALENDAR;
        }
        return Icons.NONE;
    }

    //! Call once at the top of every redraw.
    function beginFrame(clock as System.ClockTime) as Void {
        _clock = clock;
        _now = Time.now().value();
        _am = null;
        _stats = null;
        _ds = null;
    }

    private function am() as ActivityMonitor.Info or Null {
        if (_am == null) { _am = ActivityMonitor.getInfo(); }
        return _am;
    }

    private function stats() as System.Stats {
        if (_stats == null) { _stats = System.getSystemStats(); }
        return _stats;
    }

    private function ds() as System.DeviceSettings {
        if (_ds == null) { _ds = System.getDeviceSettings(); }
        return _ds;
    }

    private function clamp01(v as Float) as Float {
        if (v < 0.0) { return 0.0; }
        if (v > 1.0) { return 1.0; }
        return v;
    }

    //! Compact number: 8420 -> "8420", 12345 -> "12.3k".
    private function compact(n as Number) as String {
        if (n < 10000) { return n.toString(); }
        return (n / 1000.0).format("%.1f") + "k";
    }

    private function fmtHm(minutes as Number, is24 as Boolean) as String {
        var h = minutes / 60;
        var m = minutes % 60;
        if (!is24) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return h.format("%d") + ":" + m.format("%02d");
    }

    // ---- slow sensors ------------------------------------------------------

    private function bodyBattery() as Number or Null {
        if (_now - _bbAt < SLOW_SENSOR_SEC) { return _bbValue; }
        _bbAt = _now;
        _bbValue = null;
        if (Toybox has :SensorHistory && Toybox.SensorHistory has :getBodyBatteryHistory) {
            try {
                var it = Toybox.SensorHistory.getBodyBatteryHistory(
                    {:period => 1, :order => Toybox.SensorHistory.ORDER_NEWEST_FIRST});
                if (it != null) {
                    var s = it.next();
                    if (s != null && s.data != null) { _bbValue = s.data.toNumber(); }
                }
            } catch (e) {
                _bbValue = null;
            }
        }
        return _bbValue;
    }

    private function stress() as Number or Null {
        if (_now - _stressAt < SLOW_SENSOR_SEC) { return _stressValue; }
        _stressAt = _now;
        _stressValue = null;
        if (Toybox has :SensorHistory && Toybox.SensorHistory has :getStressHistory) {
            try {
                var it = Toybox.SensorHistory.getStressHistory(
                    {:period => 1, :order => Toybox.SensorHistory.ORDER_NEWEST_FIRST});
                if (it != null) {
                    var s = it.next();
                    if (s != null && s.data != null) { _stressValue = s.data.toNumber(); }
                }
            } catch (e) {
                _stressValue = null;
            }
        }
        return _stressValue;
    }

    //! Current conditions, cached. Also opportunistically stores the observation
    //! position so sunrise/sunset keeps working when weather goes stale.
    private function weatherTempC() as Number or Null {
        if (_now - _tempAt < WEATHER_SEC) { return _tempValue; }
        _tempAt = _now;
        _tempValue = null;
        if (!(Toybox has :Weather)) { return null; }
        try {
            var cond = Toybox.Weather.getCurrentConditions();
            if (cond == null) { return null; }
            if (cond.temperature != null) { _tempValue = cond.temperature.toNumber(); }
            if (cond has :observationLocationPosition
                    && cond.observationLocationPosition != null) {
                var deg = cond.observationLocationPosition.toDegrees();
                Application.Storage.setValue(KEY_LAT, deg[0].toFloat());
                Application.Storage.setValue(KEY_LON, deg[1].toFloat());
            }
        } catch (e) {
            _tempValue = null;
        }
        return _tempValue;
    }

    //! [sunriseMinutes, sunsetMinutes] in local minutes-past-midnight, either
    //! entry possibly null. Recomputed at most once an hour.
    private function sunTimes() as Array {
        if (_now - _sunAt < SUN_SEC && _sunDay >= 0) {
            return [_sunriseMin, _sunsetMin];
        }
        _sunAt = _now;
        _sunriseMin = null;
        _sunsetMin = null;

        weatherTempC();   // refresh the stored position if weather is available

        var lat = null;
        var lon = null;
        try {
            lat = Application.Storage.getValue(KEY_LAT);
            lon = Application.Storage.getValue(KEY_LON);
        } catch (e) {
            lat = null;
        }
        if (!(lat instanceof Lang.Float) || !(lon instanceof Lang.Float)) {
            return [null, null];
        }

        var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var doy = Sun.dayOfYear(g.year, g.month, g.day);
        _sunDay = doy;
        var tz = (_clock != null) ? _clock.timeZoneOffset : 0;
        _sunriseMin = Sun.localMinutes(lat, lon, doy, true, tz);
        _sunsetMin  = Sun.localMinutes(lat, lon, doy, false, tz);
        return [_sunriseMin, _sunsetMin];
    }

    private function heartRate() as Number or Null {
        var act = Activity.getActivityInfo();
        if (act != null && act.currentHeartRate != null) {
            return act.currentHeartRate;
        }
        try {
            var it = ActivityMonitor.getHeartRateHistory(1, true);
            if (it != null) {
                var s = it.next();
                if (s != null && s.heartRate != null
                        && s.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    return s.heartRate;
                }
            }
        } catch (e) {
            return null;
        }
        return null;
    }

    // ---- main entry point --------------------------------------------------

    //! Fill `out` with the current value of `metric`.
    function fill(metric as Number, out as Reading) as Void {
        out.reset();
        out.icon = defaultIcon(metric);

        switch (metric) {

            case STEPS: {
                var i = am();
                if (i == null || i.steps == null) { return; }
                out.text = compact(i.steps);
                if (i.stepGoal != null && i.stepGoal > 0) {
                    out.frac = clamp01(i.steps.toFloat() / i.stepGoal.toFloat());
                }
                return;
            }

            case CALORIES: {
                var i = am();
                if (i == null || i.calories == null) { return; }
                out.text = compact(i.calories);
                // No system goal for calories; 800 kcal active-day reference.
                out.frac = clamp01(i.calories.toFloat() / 800.0);
                return;
            }

            case HEART_RATE: {
                var hr = heartRate();
                if (hr == null) { return; }
                out.text = hr.toString();
                // Fixed 50-190 bpm span. Deliberately avoids UserProfile so the
                // face needs no extra permission just to size a gauge.
                out.frac = clamp01((hr - 50).toFloat() / 140.0);
                return;
            }

            case BATTERY: {
                var s = stats();
                var pct = s.battery;
                out.text = pct.format("%d") + "%";
                out.frac = clamp01(pct / 100.0);
                if (s has :charging && s.charging) { out.icon = Icons.BOLT; }
                return;
            }

            case BODY_BATTERY: {
                var v = bodyBattery();
                if (v == null) { return; }
                out.text = v.toString();
                out.frac = clamp01(v.toFloat() / 100.0);
                return;
            }

            case STRESS: {
                var v = stress();
                if (v == null) { return; }
                out.text = v.toString();
                out.frac = clamp01(v.toFloat() / 100.0);
                return;
            }

            case DISTANCE: {
                var i = am();
                if (i == null || i.distance == null) { return; }
                var statute = ds().distanceUnits == System.UNIT_STATUTE;
                var d = i.distance / 100000.0;              // cm -> km
                if (statute) { d = d * 0.621371; }
                out.text = d.format("%.1f");
                out.frac = clamp01(d / (statute ? 6.0 : 10.0));
                return;
            }

            case FLOORS: {
                var i = am();
                if (i == null || !(i has :floorsClimbed) || i.floorsClimbed == null) { return; }
                out.text = i.floorsClimbed.toString();
                if (i has :floorsClimbedGoal && i.floorsClimbedGoal != null
                        && i.floorsClimbedGoal > 0) {
                    out.frac = clamp01(i.floorsClimbed.toFloat() / i.floorsClimbedGoal.toFloat());
                }
                return;
            }

            case ACTIVE_MINUTES: {
                var i = am();
                if (i == null || !(i has :activeMinutesWeek)
                        || i.activeMinutesWeek == null) { return; }
                var mins = i.activeMinutesWeek.total;
                if (mins == null) { return; }
                out.text = mins.toString();
                var goal = (i has :activeMinutesWeekGoal) ? i.activeMinutesWeekGoal : null;
                if (goal != null && goal > 0) {
                    out.frac = clamp01(mins.toFloat() / goal.toFloat());
                }
                return;
            }

            case NOTIFICATIONS: {
                var n = ds().notificationCount;
                out.text = (n == null) ? "0" : n.toString();
                return;
            }

            case ALTITUDE: {
                var act = Activity.getActivityInfo();
                if (act == null || !(act has :altitude) || act.altitude == null) { return; }
                var alt = act.altitude;
                if (ds().elevationUnits == System.UNIT_STATUTE) { alt = alt * 3.28084; }
                out.text = alt.format("%d");
                return;
            }

            case TEMPERATURE: {
                var c = weatherTempC();
                if (c == null) { return; }
                var t = c;
                if (ds().temperatureUnits == System.UNIT_STATUTE) {
                    t = (c * 9 / 5) + 32;
                }
                out.text = t.format("%d") + "°";
                return;
            }

            case SUNRISE_SUNSET: {
                var st = sunTimes();
                var rise = st[0];
                var set = st[1];
                if (rise == null && set == null) { return; }
                var nowMin = (_clock != null) ? (_clock.hour * 60 + _clock.min) : 0;
                var is24 = ds().is24Hour;
                // Show whichever event comes next.
                if (rise != null && nowMin < rise) {
                    out.icon = Icons.SUN;
                    out.text = fmtHm(rise, is24);
                } else if (set != null && nowMin < set) {
                    out.icon = Icons.MOON;
                    out.text = fmtHm(set, is24);
                    if (rise != null && set > rise) {
                        out.frac = clamp01((nowMin - rise).toFloat() / (set - rise).toFloat());
                    }
                } else if (rise != null) {
                    out.icon = Icons.SUN;
                    out.text = fmtHm(rise, is24);   // tomorrow's, close enough
                }
                return;
            }

            case MOVE_BAR: {
                var i = am();
                if (i == null || i.moveBarLevel == null) { return; }
                var lvl = i.moveBarLevel;
                var max = ActivityMonitor.MOVE_BAR_LEVEL_MAX;
                out.text = lvl.toString();
                out.frac = clamp01(lvl.toFloat() / max.toFloat());
                return;
            }

            case DAY_PROGRESS: {
                if (_clock == null) { return; }
                var mins = _clock.hour * 60 + _clock.min;
                out.frac = clamp01(mins.toFloat() / 1440.0);
                out.text = ((out.frac * 100).toNumber()).toString() + "%";
                return;
            }

            case SECONDS: {
                if (_clock == null) { return; }
                out.text = _clock.sec.format("%02d");
                out.frac = clamp01(_clock.sec.toFloat() / 60.0);
                return;
            }

            case DATE: {
                if (_clock == null) { return; }
                var g = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
                out.text = g.day.toString();
                return;
            }
        }
    }
}
