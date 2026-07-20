/* ═══ 04 · VERSÍCULO — Reina-Valera 1960, por día del año ═══
   365 versículos en data/versiculos.json, empaquetados en assets.
   Sin red, sin API: el índice es el día del año (1–365; el 366 en
   bisiesto reutiliza el 365). */
"use strict";

const Verse = (() => {
  let verses = null;

  async function load() {
    if (verses) return verses;
    const res = await fetch("data/versiculos.json");
    verses = await res.json();
    return verses;
  }

  async function render() {
    try {
      const list = await load();
      const doy = Math.min(GT.now().doy, 365); // 366 → 365
      const v = list[doy - 1] || list[0];
      document.getElementById("verse-text").textContent = `“${v.texto}”`;
      document.getElementById("verse-ref").textContent = `${v.ref} · RVR1960`;
    } catch (e) {
      document.getElementById("verse-text").textContent =
        "No se pudo cargar el versículo.";
      document.getElementById("verse-ref").textContent = "—";
    }
  }

  return { render };
})();
