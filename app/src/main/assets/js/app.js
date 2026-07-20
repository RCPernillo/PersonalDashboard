/* ═══ APP · arranque y pegamento ═══ */
"use strict";

const App = (() => {

  async function init() {
    Theme.init();
    Clock.init();
    Editor.init();
    Cabinet.init();
    await Promise.all([Cal.render(), Verse.render()]);

    // Avisar al shell que la página está lista: vacía la cola de acciones
    // de Telegram acumuladas durante la carga.
    try {
      if (window.Android && Android.ready) Android.ready();
    } catch (_) { /* navegador de escritorio */ }
  }

  /* Media noche (o vuelta de BLACK-OFF): recalcular lo que depende del día. */
  function onNewDay() {
    Cal.render();
    Verse.render();
    Cabinet.renderMenus(); // la semana del mes puede cambiar
  }

  document.addEventListener("DOMContentLoaded", init);

  return { onNewDay };
})();
