import Toybox.Lang;
import Toybox.Math;

//! Sunrise / sunset.
//!
//! Implemented locally (the classic Almanac sunrise equation, accurate to about
//! a minute) instead of using a positioning API, because turning on GPS from a
//! watch face is exactly the kind of thing that quietly destroys battery life.
//! The position comes from whatever the weather service last reported, which
//! the watch already has for free.
module Sun {

    private const ZENITH_OFFICIAL = 90.833;   // includes refraction + solar disc
    private const DEG = 180.0 / Math.PI;

    private function sinDeg(d as Float) as Float { return Math.sin(d / DEG); }
    private function cosDeg(d as Float) as Float { return Math.cos(d / DEG); }
    private function tanDeg(d as Float) as Float { return Math.tan(d / DEG); }
    private function asinDeg(x as Float) as Float { return Math.asin(x) * DEG; }
    private function acosDeg(x as Float) as Float { return Math.acos(x) * DEG; }
    private function atanDeg(x as Float) as Float { return Math.atan(x) * DEG; }

    private function norm(v as Float, range as Float) as Float {
        var x = v;
        while (x < 0.0) { x += range; }
        while (x >= range) { x -= range; }
        return x;
    }

    //! UTC hour (0.0 - 24.0) of sunrise or sunset, or null when the sun does not
    //! cross the horizon that day (polar summer / winter).
    //!
    //! @param lat        latitude in degrees, north positive
    //! @param lon        longitude in degrees, east positive
    //! @param dayOfYear  1 - 366
    //! @param rising     true for sunrise, false for sunset
    function utcHour(lat as Float, lon as Float, dayOfYear as Number,
                     rising as Boolean) as Float or Null {

        var lngHour = lon / 15.0;
        var t = dayOfYear + (((rising ? 6.0 : 18.0) - lngHour) / 24.0);

        // Sun's mean anomaly, then true longitude.
        var m = (0.9856 * t) - 3.289;
        var l = norm(m + (1.916 * sinDeg(m)) + (0.020 * sinDeg(2.0 * m)) + 282.634, 360.0);

        // Right ascension, pushed into the same quadrant as the true longitude.
        var ra = norm(atanDeg(0.91764 * tanDeg(l)), 360.0);
        var lQuadrant  = Math.floor(l / 90.0) * 90.0;
        var raQuadrant = Math.floor(ra / 90.0) * 90.0;
        ra = (ra + (lQuadrant - raQuadrant)) / 15.0;

        // Declination.
        var sinDec = 0.39782 * sinDeg(l);
        var cosDec = cosDeg(asinDeg(sinDec));

        var cosH = (cosDeg(ZENITH_OFFICIAL) - (sinDec * sinDeg(lat)))
                   / (cosDec * cosDeg(lat));
        if (cosH > 1.0 || cosH < -1.0) {
            return null;   // sun never rises / never sets at this latitude today
        }

        var h = rising ? (360.0 - acosDeg(cosH)) : acosDeg(cosH);
        h = h / 15.0;

        var localMeanTime = h + ra - (0.06571 * t) - 6.622;
        return norm(localMeanTime - lngHour, 24.0);
    }

    //! Local time in minutes past midnight, or null if there is no event.
    //!
    //! @param tzOffsetSec timezone offset in seconds (System.getClockTime().timeZoneOffset)
    function localMinutes(lat as Float, lon as Float, dayOfYear as Number,
                          rising as Boolean, tzOffsetSec as Number) as Number or Null {
        var utc = utcHour(lat, lon, dayOfYear, rising);
        if (utc == null) { return null; }
        var local = norm(utc + (tzOffsetSec / 3600.0), 24.0);
        return (local * 60.0).toNumber();
    }

    //! Day of year for a Gregorian date, leap years included.
    function dayOfYear(year as Number, month as Number, day as Number) as Number {
        var cumulative = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334];
        var n = cumulative[month - 1] + day;
        var leap = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
        if (leap && month > 2) { n += 1; }
        return n;
    }
}
