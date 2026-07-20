/* ═══ 01 · RELOJ — matriz de puntos 5×7 dibujada en canvas ═══
   Sin fuentes externas: los dígitos se dibujan punto a punto, estilo
   dot-matrix OP-1. 12 horas + AM/PM + segundos vivos + fecha + batería. */
"use strict";

const Clock = (() => {

  /* Matriz 5×7 por carácter: cadenas de 5 bits por fila. */
  const GLYPHS = {
    "0": ["01110","10001","10011","10101","11001","10001","01110"],
    "1": ["00100","01100","00100","00100","00100","00100","01110"],
    "2": ["01110","10001","00001","00010","00100","01000","11111"],
    "3": ["11111","00010","00100","00010","00001","10001","01110"],
    "4": ["00010","00110","01010","10010","11111","00010","00010"],
    "5": ["11111","10000","11110","00001","00001","10001","01110"],
    "6": ["00110","01000","10000","11110","10001","10001","01110"],
    "7": ["11111","00001","00010","00100","01000","01000","01000"],
    "8": ["01110","10001","10001","01110","10001","10001","01110"],
    "9": ["01110","10001","10001","01111","00001","00010","01100"],
    ":": ["00000","00100","00100","00000","00100","00100","00000"],
    " ": ["00000","00000","00000","00000","00000","00000","00000"]
  };
  const ROWS = 7, COLS = 5;

  let cvs, ctx, secCvs, secCtx;
  let lastText = "", lastSec = "", lastDay = 0;

  function ink() {
    return getComputedStyle(document.documentElement)
      .getPropertyValue("--ink").trim() || "#1a1a1a";
  }

  /* Dibuja `text` centrado en el canvas como matriz de puntos. */
  function drawMatrix(c, x2d, text) {
    const dpr = window.devicePixelRatio || 1;
    const w = c.clientWidth * dpr, h = c.clientHeight * dpr;
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    x2d.clearRect(0, 0, w, h);

    const chars = text.split("");
    const gapCols = 1.6; // columnas de aire entre caracteres
    const totalCols = chars.length * COLS + (chars.length - 1) * gapCols;
    const cell = Math.min(w / totalCols, h / ROWS);
    const r = cell * 0.38; // radio del punto
    const ox = (w - totalCols * cell) / 2;
    const oy = (h - ROWS * cell) / 2;

    x2d.fillStyle = ink();
    let cx = ox;
    for (const ch of chars) {
      const g = GLYPHS[ch] || GLYPHS[" "];
      for (let row = 0; row < ROWS; row++) {
        for (let col = 0; col < COLS; col++) {
          if (g[row][col] === "1") {
            x2d.beginPath();
            x2d.arc(cx + (col + .5) * cell, oy + (row + .5) * cell, r, 0, 7);
            x2d.fill();
          }
        }
      }
      cx += (COLS + gapCols) * cell;
    }
  }

  function updateBattery() {
    let pct = "—", chg = "";
    try {
      if (window.Android && Android.getBattery) {
        const b = JSON.parse(Android.getBattery());
        pct = b.pct;
        chg = b.charging ? " · CARGA" : "";
      }
    } catch (_) { /* navegador de escritorio */ }
    document.getElementById("battery").textContent = `BAT ${pct}%${chg}`;
  }

  function tick() {
    if (!cvs) return; // aún sin init (p. ej. redraw durante el arranque)
    const n = GT.now();

    // hora 12h en matriz de puntos
    let h12 = n.hh % 12; if (h12 === 0) h12 = 12;
    const text = `${h12}:${String(n.mm).padStart(2, "0")}`;
    if (text !== lastText) {
      lastText = text;
      drawMatrix(cvs, ctx, text);
      document.getElementById("ampm").textContent = n.hh < 12 ? "AM" : "PM";
    }
    const sec = String(n.ss).padStart(2, "0");
    if (sec !== lastSec) { lastSec = sec; drawMatrix(secCvs, secCtx, sec); }

    // fecha de hoy (acento naranja vía CSS)
    if (n.d !== lastDay) {
      const isFirstTick = lastDay === 0;
      lastDay = n.d;
      document.getElementById("date-line").textContent =
        `${GT.DOW[n.dow]} ${String(n.d).padStart(2, "0")} · ${GT.MON[n.m - 1]} ${n.y}`;
      // nuevo día → recalcular calendario, mes y versículo
      // (en el primer tick no: App.init ya los renderiza)
      if (!isFirstTick) App.onNewDay();
    }

    Theme.sync(); // vigila los cortes 05/18/22 aunque la alarma nativa duerma
  }

  function init() {
    cvs = document.getElementById("clock-canvas"); ctx = cvs.getContext("2d");
    secCvs = document.getElementById("sec-canvas"); secCtx = secCvs.getContext("2d");
    tick();
    setInterval(tick, 1000);
    updateBattery();
    setInterval(updateBattery, 60_000);
    window.addEventListener("resize", redraw);
  }

  function redraw() { // tras cambio de tema o de tamaño
    lastText = ""; lastSec = "";
    tick();
  }

  return { init, redraw };
})();
