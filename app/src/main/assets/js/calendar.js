/* ═══ 02 · CALENDARIO + 03 · MES + editor mínimo de eventos ═══
   Hoy en naranja; puntos naranja = días con evento; todos los domingos
   marcados como día de culto (verde hueco); domingos con asignación de
   servicio en verde sólido. */
"use strict";

const Cal = (() => {

  async function render() {
    const n = GT.now();
    const occ = await Events.forMonth(n.y, n.m);

    // días con evento / con asignación de servicio
    const evDays = new Set(occ.map(o => o.day));
    const svcDays = new Set(
      occ.filter(o => o.ev.type === "church" && o.ev.serviceText).map(o => o.day)
    );

    renderGrid(n, evDays, svcDays);
    renderMonthList(n, occ);
  }

  function renderGrid(n, evDays, svcDays) {
    document.getElementById("cal-month").textContent =
      `${GT.MON_FULL[n.m - 1]} ${n.y}`;

    const head = document.getElementById("cal-head");
    head.innerHTML = "";
    for (const d of ["D", "L", "M", "M", "J", "V", "S"]) {
      const s = document.createElement("span");
      s.textContent = d;
      head.appendChild(s);
    }

    const first = new Date(Date.UTC(n.y, n.m - 1, 1)).getUTCDay();
    const days = new Date(Date.UTC(n.y, n.m, 0)).getUTCDate();

    const grid = document.getElementById("cal-grid");
    grid.innerHTML = "";
    for (let i = 0; i < first; i++) {
      const c = document.createElement("div");
      c.className = "cal-cell out";
      grid.appendChild(c);
    }
    for (let d = 1; d <= days; d++) {
      const c = document.createElement("div");
      c.className = "cal-cell" + (d === n.d ? " today" : "");
      c.textContent = d;

      const dow = (first + d - 1) % 7;
      const dots = document.createElement("div");
      dots.className = "cal-dots";
      if (evDays.has(d)) dots.appendChild(dot("dot-orange"));
      if (dow === 0) { // domingo: día de culto siempre
        dots.appendChild(dot(svcDays.has(d) ? "dot-green" : "dot-green-o"));
      }
      if (dots.childNodes.length) c.appendChild(dots);
      grid.appendChild(c);
    }
  }

  function dot(cls) {
    const i = document.createElement("i");
    i.className = "dot " + cls;
    return i;
  }

  function renderMonthList(n, occ) {
    const ul = document.getElementById("month-list");
    ul.innerHTML = "";
    if (!occ.length) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = "SIN EVENTOS ESTE MES";
      ul.appendChild(li);
      return;
    }
    for (const o of occ) {
      const li = document.createElement("li");
      if (o.day < n.d) li.style.opacity = ".45"; // pasado, atenuado

      const d = document.createElement("span");
      d.className = "d";
      const dow = new Date(Date.UTC(n.y, n.m - 1, o.day)).getUTCDay();
      d.textContent = `${String(o.day).padStart(2, "0")} ${GT.DOW[dow]}`;

      const t = document.createElement("span");
      t.className = "t";
      t.textContent = o.ev.title;
      if (o.ev.serviceText) {
        const svc = document.createElement("span");
        svc.className = "svc";
        svc.textContent = o.ev.serviceText;
        t.appendChild(svc);
      }
      li.appendChild(d);
      li.appendChild(t);
      li.addEventListener("click", () => Editor.open(o.ev));
      ul.appendChild(li);
    }
  }

  return { render };
})();

/* ── Editor mínimo (alta/edición/borrado) de eventos ── */
const Editor = (() => {
  let editing = null; // evento en edición o null (nuevo)

  const $ = (id) => document.getElementById(id);

  function open(ev) {
    editing = ev || null;
    const n = GT.now();
    $("ev-date").value = ev ? (ev.date || "") : GT.iso(n.y, n.m, n.d);
    $("ev-title").value = ev ? ev.title : "";
    $("ev-type").value = ev ? ev.type : "other";
    $("ev-rec").value = ev ? ev.recurrence : "none";
    $("ev-service").value = ev ? (ev.serviceText || "") : "";
    $("ev-delete").hidden = !ev;
    $("modal-backdrop").hidden = false;
  }

  function close() { $("modal-backdrop").hidden = true; editing = null; }

  async function save() {
    const date = $("ev-date").value;
    const title = $("ev-title").value.trim();
    if (!date || !title) return;
    const obj = {
      title,
      type: $("ev-type").value,
      date,
      recurrence: $("ev-rec").value,
      serviceText: $("ev-service").value.trim() || undefined,
      source: editing ? editing.source : "manual",
      createdAt: editing ? editing.createdAt : Date.now()
    };
    if (editing) { obj.id = editing.id; await DB.put("events", obj); }
    else await DB.add("events", obj);
    close();
    Cal.render();
  }

  async function remove() {
    if (editing) await DB.del("events", editing.id);
    close();
    Cal.render();
  }

  function init() {
    $("btn-add-event").addEventListener("click", () => open(null));
    $("ev-save").addEventListener("click", save);
    $("ev-delete").addEventListener("click", remove);
    $("ev-cancel").addEventListener("click", close);
    $("modal-backdrop").addEventListener("click", (e) => {
      if (e.target.id === "modal-backdrop") close();
    });
  }

  return { init, open };
})();
