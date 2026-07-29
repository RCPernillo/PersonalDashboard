import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

//! Vector icon set.
//!
//! Everything is drawn with dc primitives instead of shipping PNGs. Three
//! reasons, all of which matter on a watch face:
//!   * an icon can be tinted to any colour at draw time, so the accent-colour
//!     picker and multicolour mode work without N copies of every bitmap;
//!   * it costs code space instead of the much scarcer resource/graphics-pool
//!     memory, which is what actually runs out on a Forerunner;
//!   * it scales to any screen size from the 240px FR55 to the 390px FR165.
//!
//! Each icon is drawn inside a square box of side `size` centred on (cx, cy)
//! and uses at most ~12 draw calls.
module Icons {

    enum {
        NONE = 0,
        STEPS,
        FLAME,
        HEART,
        BATTERY,
        BOLT,
        WAVE,
        ROUTE,
        STAIRS,
        CLOCK,
        BELL,
        MOUNTAIN,
        THERMO,
        SUN,
        MOON,
        MOVE,
        PHONE,
        DOT,
        DROP,
        TARGET,
        ALARM,
        CALENDAR
    }

    //! Number of selectable icons, used to validate the settings value.
    const COUNT = 22;

    private function pen(size as Number) as Number {
        var p = (size / 8).toNumber();
        return p < 1 ? 1 : p;
    }

    //! Draw icon `id` centred on (cx, cy) in a `size`-px box using `color`.
    //! `bg` is needed by the icons that punch a hole in themselves (MOON).
    function draw(dc as Graphics.Dc, id as Number, cx as Number, cy as Number,
                  size as Number, color as Number, bg as Number) as Void {
        if (id == NONE || size < 5) { return; }

        var h = size / 2;
        var p = pen(size);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(p);

        switch (id) {
            case STEPS: {
                // Two offset footprints.
                var fw = (size * 0.28).toNumber();
                var fh = (size * 0.44).toNumber();
                if (fw < 2) { fw = 2; }
                if (fh < 3) { fh = 3; }
                dc.fillRoundedRectangle(cx - h + p, cy - fh / 2 - p, fw, fh, fw / 2);
                dc.fillRoundedRectangle(cx + h - fw - p, cy - fh / 2 + p, fw, fh, fw / 2);
                break;
            }

            case FLAME: {
                dc.fillPolygon([
                    [cx, cy - h],
                    [cx + h * 0.75, cy + h * 0.15],
                    [cx + h * 0.45, cy + h],
                    [cx - h * 0.45, cy + h],
                    [cx - h * 0.75, cy + h * 0.15]
                ] as Array< Array<Numeric> >);
                break;
            }

            case HEART: {
                var r = (size * 0.27).toNumber();
                if (r < 2) { r = 2; }
                dc.fillCircle(cx - r + 1, cy - r / 2, r);
                dc.fillCircle(cx + r - 1, cy - r / 2, r);
                dc.fillPolygon([
                    [cx - 2 * r + 1, cy - r / 2],
                    [cx + 2 * r - 1, cy - r / 2],
                    [cx, cy + h]
                ] as Array< Array<Numeric> >);
                break;
            }

            case BATTERY: {
                var bw = size;
                var bh = (size * 0.6).toNumber();
                dc.drawRoundedRectangle(cx - bw / 2, cy - bh / 2, bw - 2, bh, 2);
                dc.fillRectangle(cx + bw / 2 - 2, cy - bh / 4, 2, bh / 2);
                break;
            }

            case BOLT: {
                dc.fillPolygon([
                    [cx + h * 0.35, cy - h],
                    [cx - h * 0.6, cy + h * 0.15],
                    [cx - h * 0.05, cy + h * 0.15],
                    [cx - h * 0.35, cy + h],
                    [cx + h * 0.6, cy - h * 0.15],
                    [cx + h * 0.05, cy - h * 0.15]
                ] as Array< Array<Numeric> >);
                break;
            }

            case WAVE: {
                // Heart-rate style trace.
                var y = cy;
                dc.drawLine(cx - h, y, cx - h * 0.4, y);
                dc.drawLine(cx - h * 0.4, y, cx - h * 0.15, y - h * 0.7);
                dc.drawLine(cx - h * 0.15, y - h * 0.7, cx + h * 0.1, y + h * 0.7);
                dc.drawLine(cx + h * 0.1, y + h * 0.7, cx + h * 0.35, y);
                dc.drawLine(cx + h * 0.35, y, cx + h, y);
                break;
            }

            case ROUTE: {
                dc.drawLine(cx - h * 0.7, cy + h, cx - h * 0.7, cy - h * 0.3);
                dc.drawLine(cx - h * 0.7, cy - h * 0.3, cx + h * 0.7, cy - h * 0.3);
                dc.drawLine(cx + h * 0.7, cy - h * 0.3, cx + h * 0.7, cy + h * 0.4);
                dc.fillCircle(cx - h * 0.7, cy + h, p + 1);
                dc.fillCircle(cx + h * 0.7, cy + h * 0.4, p + 1);
                break;
            }

            case STAIRS: {
                var s = size / 3;
                for (var i = 0; i < 3; i += 1) {
                    var x = cx - h + i * s;
                    var y = cy + h - (i + 1) * s;
                    dc.drawLine(x, y, x + s, y);
                    dc.drawLine(x + s, y, x + s, y + s);
                }
                break;
            }

            case CLOCK: {
                dc.drawCircle(cx, cy, h - p);
                dc.drawLine(cx, cy, cx, cy - h * 0.5);
                dc.drawLine(cx, cy, cx + h * 0.4, cy);
                break;
            }

            case BELL: {
                dc.drawArc(cx, cy + h * 0.2, (h * 0.75).toNumber(),
                           Graphics.ARC_COUNTER_CLOCKWISE, 0, 180);
                dc.drawLine(cx - h * 0.75, cy + h * 0.2, cx + h * 0.75, cy + h * 0.2);
                dc.fillCircle(cx, cy + h * 0.6, p + 1);
                break;
            }

            case MOUNTAIN: {
                dc.fillPolygon([
                    [cx - h, cy + h * 0.7],
                    [cx - h * 0.25, cy - h * 0.6],
                    [cx + h * 0.15, cy],
                    [cx + h * 0.45, cy - h * 0.35],
                    [cx + h, cy + h * 0.7]
                ] as Array< Array<Numeric> >);
                break;
            }

            case THERMO: {
                dc.drawLine(cx, cy - h, cx, cy + h * 0.3);
                dc.fillCircle(cx, cy + h * 0.55, (h * 0.4).toNumber());
                break;
            }

            case SUN: {
                dc.fillCircle(cx, cy, (h * 0.45).toNumber());
                for (var i = 0; i < 8; i += 1) {
                    var a = i * Math.PI / 4.0;
                    var s = Math.sin(a);
                    var c = Math.cos(a);
                    dc.drawLine(cx + c * h * 0.7, cy + s * h * 0.7,
                                cx + c * h, cy + s * h);
                }
                break;
            }

            case MOON: {
                // Crescent: full disc, then punch a bg-coloured disc out of it.
                dc.fillCircle(cx, cy, h - p);
                dc.setColor(bg, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx + h * 0.45, cy - h * 0.3, h - p);
                dc.setColor(color, Graphics.COLOR_TRANSPARENT);
                break;
            }

            case MOVE: {
                // Four rising bars, like the Garmin move bar.
                var bw2 = (size / 6).toNumber();
                if (bw2 < 1) { bw2 = 1; }
                for (var i = 0; i < 4; i += 1) {
                    var bh2 = (size * (0.3 + 0.22 * i)).toNumber();
                    dc.fillRectangle(cx - h + i * (bw2 + 2), cy + h - bh2, bw2, bh2);
                }
                break;
            }

            case PHONE: {
                dc.drawRoundedRectangle(cx - h * 0.55, cy - h, (h * 1.1).toNumber(), size, 2);
                dc.drawLine(cx - h * 0.2, cy + h * 0.7, cx + h * 0.2, cy + h * 0.7);
                break;
            }

            case DOT: {
                dc.fillCircle(cx, cy, (h * 0.55).toNumber());
                break;
            }

            case DROP: {
                dc.fillPolygon([
                    [cx, cy - h],
                    [cx + h * 0.7, cy + h * 0.25],
                    [cx - h * 0.7, cy + h * 0.25]
                ] as Array< Array<Numeric> >);
                dc.fillCircle(cx, cy + h * 0.25, (h * 0.7).toNumber());
                break;
            }

            case TARGET: {
                dc.drawCircle(cx, cy, h - p);
                dc.fillCircle(cx, cy, (h * 0.3).toNumber());
                break;
            }

            case ALARM: {
                dc.drawCircle(cx, cy + h * 0.15, (h * 0.75).toNumber());
                dc.drawLine(cx, cy + h * 0.15, cx, cy - h * 0.3);
                dc.drawLine(cx - h, cy - h * 0.65, cx - h * 0.4, cy - h);
                dc.drawLine(cx + h, cy - h * 0.65, cx + h * 0.4, cy - h);
                break;
            }

            case CALENDAR: {
                dc.drawRectangle(cx - h, cy - h * 0.7, size, (size * 0.85).toNumber());
                dc.drawLine(cx - h, cy - h * 0.2, cx + h, cy - h * 0.2);
                dc.drawLine(cx - h * 0.5, cy - h * 0.7, cx - h * 0.5, cy - h);
                dc.drawLine(cx + h * 0.5, cy - h * 0.7, cx + h * 0.5, cy - h);
                break;
            }
        }

        dc.setPenWidth(1);
    }
}
