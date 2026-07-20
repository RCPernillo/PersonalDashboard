/* ═══ TEMA · tres estados por reloj local (America/Guatemala) ═══
     05:00–18:00 LIGHT · 18:00–22:00 DARK · 22:00–05:00 BLACK-OFF
   El cambio es solo un intercambio de tokens CSS (data-theme en <html>):
   mismo layout, misma retícula, sin recarga → sin parpadeo.
   El lado nativo dispara los cortes con AlarmManager (cinturón) y este
   módulo vigila el reloj cada segundo (tirantes). */
"use strict";

const Theme = (() => {
  let current = null;

  function themeFor(hh) {
    if (hh >= 5 && hh < 18) return "light";
    if (hh >= 18 && hh < 22) return "dark";
    return "off";
  }

  function set(theme) {
    if (theme !== "light" && theme !== "dark" && theme !== "off") return;
    if (theme === current) return;
    current = theme;
    document.documentElement.dataset.theme = theme;
    // el reloj de puntos lee los colores del tema al redibujar
    // (typeof: Clock es const de script, no cuelga de window)
    if (typeof Clock !== "undefined") Clock.redraw();
  }

  function sync() { set(themeFor(GT.now().hh)); }

  function init() {
    // Estado inicial: manda el reloj nativo si existe; si no, el local.
    let t = null;
    try {
      if (window.Android && Android.getThemeState) t = Android.getThemeState();
    } catch (_) { /* sin puente (navegador de escritorio) */ }
    set(t || themeFor(GT.now().hh));
  }

  return { init, set, sync, themeFor, get current() { return current; } };
})();

/* API que usa el lado nativo en cada corte de alarma */
window.setTheme = (t) => Theme.set(t);
window.syncTheme = () => Theme.sync();
