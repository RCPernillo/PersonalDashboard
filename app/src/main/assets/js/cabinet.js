/* ═══ ARCHIVERO · fólderes SPOTIFY / MENÚS / NOTAS / COMPRAS ═══
   Cambio de contenido instantáneo al tocar la pestaña (sin animación de
   gaveta, estilo TE) + fila de control fija: LUZ y CONECTAR BOCINA. */
"use strict";

const Cabinet = (() => {
  const $ = (id) => document.getElementById(id);

  /* ── pestañas ── */
  function initTabs() {
    document.querySelectorAll(".tab").forEach(tab => {
      tab.addEventListener("click", () => {
        document.querySelectorAll(".tab").forEach(t =>
          t.classList.toggle("active", t === tab));
        const f = tab.dataset.folder;
        document.querySelectorAll(".folder").forEach(el =>
          el.hidden = el.id !== "folder-" + f);
      });
    });
  }

  /* ── SPOTIFY (deep link vía nativo) ── */
  function initSpotify() {
    const doSearch = () => {
      const q = $("sp-query").value.trim();
      if (!q) return;
      $("sp-status").textContent = "BUSCANDO…";
      $("sp-results").innerHTML = "";
      if (window.Android && Android.spotifySearch) Android.spotifySearch(q);
      else $("sp-status").textContent = "SIN PUENTE NATIVO (NAVEGADOR)";
    };
    $("sp-search").addEventListener("click", doSearch);
    $("sp-query").addEventListener("keydown", e => {
      if (e.key === "Enter") doSearch();
    });

    // resultados desde Kotlin
    window.onSpotifyResults = (jsonStr) => {
      let data;
      try { data = JSON.parse(jsonStr); } catch (_) { data = { error: "Respuesta inválida" }; }
      const ul = $("sp-results");
      ul.innerHTML = "";
      if (data.error) { $("sp-status").textContent = data.error.toUpperCase(); return; }
      $("sp-status").textContent = `${data.tracks.length} RESULTADOS`;
      for (const t of data.tracks) {
        const li = document.createElement("li");
        const tick = document.createElement("span");
        tick.className = "tick"; tick.textContent = "▸";
        const name = document.createElement("span");
        name.textContent = t.name;
        const artist = document.createElement("span");
        artist.className = "artist"; artist.textContent = "— " + t.artist;
        li.append(tick, name, artist);
        li.addEventListener("click", () => {
          if (window.Android) Android.openSpotifyUri(t.uri);
        });
        ul.appendChild(li);
      }
    };
    window.onSpotifyError = (msg) => { $("sp-status").textContent = msg.toUpperCase(); };
  }

  /* ── MENÚS · rotación fija de 4 semanas, se repite cada mes ── */
  let menuWeek = 1;

  function weekOfMonth() {
    // días 1–7 → S1 … 22 en adelante → S4 (los días 29–31 quedan en S4)
    return Math.min(4, Math.ceil(GT.now().d / 7));
  }

  async function renderMenus() {
    const meals = await DB.all("meals");
    const cur = weekOfMonth();
    document.querySelectorAll(".week-btn").forEach(b => {
      const w = +b.dataset.week;
      b.classList.toggle("sel", w === menuWeek);
      b.classList.toggle("cur", w === cur); // punto naranja = semana actual
    });
    const row = meals.find(m => m.weekNumber === menuWeek);
    $("menu-name").textContent = row ? row.menuName : "—";
  }

  function initMenus() {
    menuWeek = weekOfMonth();
    document.querySelectorAll(".week-btn").forEach(b => {
      b.addEventListener("click", () => {
        menuWeek = +b.dataset.week;
        $("menu-edit-row").hidden = true;
        renderMenus();
      });
    });
    $("menu-edit").addEventListener("click", async () => {
      const meals = await DB.all("meals");
      const row = meals.find(m => m.weekNumber === menuWeek);
      $("menu-input").value = row ? row.menuName : "";
      $("menu-edit-row").hidden = false;
      $("menu-input").focus();
    });
    $("menu-save").addEventListener("click", async () => {
      const name = $("menu-input").value.trim();
      if (name) await DB.put("meals", { weekNumber: menuWeek, menuName: name });
      $("menu-edit-row").hidden = true;
      renderMenus();
    });
  }

  /* ── NOTAS · más recientes primero ── */
  async function renderNotes() {
    const notes = (await DB.all("notes"))
      .sort((a, b) => b.createdAt - a.createdAt);
    const ul = $("note-list");
    ul.innerHTML = "";
    if (!notes.length) {
      ul.innerHTML = '<li class="empty">SIN NOTAS</li>';
      return;
    }
    for (const nt of notes) {
      const li = document.createElement("li");
      const txt = document.createElement("span");
      txt.textContent = nt.text;
      const when = document.createElement("span");
      when.className = "when";
      const d = new Date(nt.createdAt);
      when.textContent =
        `${String(d.getDate()).padStart(2, "0")} ${GT.MON[d.getMonth()]}`;
      const x = document.createElement("span");
      x.className = "x"; x.textContent = "×";
      x.addEventListener("click", async (e) => {
        e.stopPropagation();
        await DB.del("notes", nt.id);
        renderNotes();
      });
      // tocar el texto = editar en línea
      txt.addEventListener("click", () => {
        const inp = document.createElement("input");
        inp.type = "text"; inp.value = nt.text; inp.maxLength = 200;
        inp.className = "mono";
        li.replaceChild(inp, txt);
        inp.focus();
        const commit = async () => {
          const v = inp.value.trim();
          if (v && v !== nt.text) {
            nt.text = v;
            await DB.put("notes", nt);
          }
          renderNotes();
        };
        inp.addEventListener("keydown", e => { if (e.key === "Enter") commit(); });
        inp.addEventListener("blur", commit);
      });
      li.append(txt, when, x);
      ul.appendChild(li);
    }
  }

  function initNotes() {
    const add = async () => {
      const v = $("note-input").value.trim();
      if (!v) return;
      await DB.add("notes", { text: v, createdAt: Date.now() });
      $("note-input").value = "";
      renderNotes();
    };
    $("note-add").addEventListener("click", add);
    $("note-input").addEventListener("keydown", e => { if (e.key === "Enter") add(); });
  }

  /* ── COMPRAS · tocar = marcar (verde apagado) ── */
  async function renderShopping() {
    const items = (await DB.all("shopping"))
      .sort((a, b) => a.checked - b.checked || b.createdAt - a.createdAt);
    const ul = $("shop-list");
    ul.innerHTML = "";
    if (!items.length) {
      ul.innerHTML = '<li class="empty">LISTA VACÍA</li>';
      return;
    }
    for (const it of items) {
      const li = document.createElement("li");
      li.className = it.checked ? "checked" : "";
      const tick = document.createElement("span");
      tick.className = "tick";
      tick.textContent = it.checked ? "■" : "□";
      const item = document.createElement("span");
      item.className = "item";
      item.textContent = it.item;
      const x = document.createElement("span");
      x.className = "x"; x.textContent = "×";
      x.addEventListener("click", async (e) => {
        e.stopPropagation();
        await DB.del("shopping", it.id);
        renderShopping();
      });
      li.append(tick, item, x);
      li.addEventListener("click", async () => {
        it.checked = !it.checked;
        await DB.put("shopping", it);
        renderShopping();
      });
      ul.appendChild(li);
    }
  }

  function initShopping() {
    const add = async () => {
      const v = $("shop-input").value.trim();
      if (!v) return;
      await DB.add("shopping", { item: v, checked: false, createdAt: Date.now() });
      $("shop-input").value = "";
      renderShopping();
    };
    $("shop-add").addEventListener("click", add);
    $("shop-input").addEventListener("keydown", e => { if (e.key === "Enter") add(); });
    $("shop-clear").addEventListener("click", async () => {
      const items = await DB.all("shopping");
      for (const it of items.filter(i => i.checked)) await DB.del("shopping", it.id);
      renderShopping();
    });
  }

  /* ── fila de control: LUZ (stub) + BOCINA ── */
  function initControls() {
    $("btn-light").addEventListener("click", () => {
      if (!(window.Android && Android.toggleLight)) {
        $("hw-status").textContent = "SIN PUENTE NATIVO"; return;
      }
      try {
        const st = JSON.parse(Android.toggleLight());
        const label = st.on ? "ENCENDIDA" : "APAGADA";
        $("btn-light").textContent =
          `LUZ · ${label}` + (st.stub ? " (SIMULADA)" : "");
        $("btn-light").classList.toggle("on", !!st.on);
      } catch (_) {
        $("hw-status").textContent = "ERROR DE LUZ";
      }
    });

    $("btn-speaker").addEventListener("click", () => {
      if (window.Android && Android.connectSpeaker) {
        $("hw-status").textContent = "CONECTANDO BOCINA…";
        Android.connectSpeaker();
      } else {
        $("hw-status").textContent = "SIN PUENTE NATIVO";
      }
    });

    window.onSpeakerStatus = (msg) => {
      $("hw-status").textContent = msg.toUpperCase();
    };
  }

  function init() {
    initTabs();
    initSpotify();
    initMenus();
    initNotes();
    initShopping();
    initControls();
    renderMenus();
    renderNotes();
    renderShopping();
  }

  return { init, renderNotes, renderShopping, renderMenus };
})();
