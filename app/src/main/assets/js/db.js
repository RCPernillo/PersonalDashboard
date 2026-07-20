/* ═══ DB · IndexedDB en el dispositivo — sin backend, sin nube ═══
   Almacenes:
     events   {id, title, type(church|friends|other), date "AAAA-MM-DD",
               recurrence(none|weekly|monthly), serviceText?, source, createdAt}
     meals    {weekNumber 1–4, menuName}           — rotación fija mensual
     notes    {id, text, createdAt}
     shopping {id, item, checked, createdAt}
*/
"use strict";

const DB = (() => {
  const NAME = "tablero", VERSION = 1;
  let dbp = null;

  function open() {
    if (dbp) return dbp;
    dbp = new Promise((resolve, reject) => {
      const req = indexedDB.open(NAME, VERSION);
      let seeded = false;
      req.onupgradeneeded = (e) => {
        const db = e.target.result;
        db.createObjectStore("events", { keyPath: "id", autoIncrement: true });
        db.createObjectStore("meals", { keyPath: "weekNumber" });
        db.createObjectStore("notes", { keyPath: "id", autoIncrement: true });
        db.createObjectStore("shopping", { keyPath: "id", autoIncrement: true });
        seeded = true; // primera vez: sembrar datos de muestra
      };
      req.onsuccess = async () => {
        const db = req.result;
        if (seeded) await seed(db);
        resolve(db);
      };
      req.onerror = () => reject(req.error);
    });
    return dbp;
  }

  function tx(db, store, mode, fn) {
    return new Promise((resolve, reject) => {
      const t = db.transaction(store, mode);
      const s = t.objectStore(store);
      const out = fn(s);
      t.oncomplete = () => resolve(out && out.result !== undefined ? out.result : undefined);
      t.onerror = () => reject(t.error);
    });
  }

  async function all(store) {
    const db = await open();
    return new Promise((resolve, reject) => {
      const req = db.transaction(store).objectStore(store).getAll();
      req.onsuccess = () => resolve(req.result);
      req.onerror = () => reject(req.error);
    });
  }
  async function add(store, obj) {
    const db = await open();
    return tx(db, store, "readwrite", s => s.add(obj));
  }
  async function put(store, obj) {
    const db = await open();
    return tx(db, store, "readwrite", s => s.put(obj));
  }
  async function del(store, key) {
    const db = await open();
    return tx(db, store, "readwrite", s => s.delete(key));
  }

  /* Datos de muestra (primera ejecución): fechas relativas a hoy para que
     el tablero se vea vivo desde el primer arranque. */
  async function seed(db) {
    const now = GT.now();
    const today = GT.iso(now.y, now.m, now.d);
    const ts = Date.now();

    // próximo domingo (o hoy si es domingo)
    const base = new Date(Date.UTC(now.y, now.m - 1, now.d));
    const toSun = (7 - base.getUTCDay()) % 7;
    const sun = new Date(base); sun.setUTCDate(base.getUTCDate() + toSun);
    const sunIso = GT.iso(sun.getUTCFullYear(), sun.getUTCMonth() + 1, sun.getUTCDate());
    const in3 = new Date(base); in3.setUTCDate(base.getUTCDate() + 3);
    const in3Iso = GT.iso(in3.getUTCFullYear(), in3.getUTCMonth() + 1, in3.getUTCDate());

    const events = [
      { title: "CULTO", type: "church", date: sunIso, recurrence: "none",
        serviceText: "Bevy canto, Roberto cámara y multimedia",
        source: "manual", createdAt: ts },
      { title: "Cena con amigos", type: "friends", date: in3Iso,
        recurrence: "none", source: "manual", createdAt: ts },
      { title: "Pago de internet", type: "other",
        date: GT.iso(now.y, now.m, 5), recurrence: "monthly",
        source: "manual", createdAt: ts }
    ];
    const meals = [
      { weekNumber: 1, menuName: "Pepián" },
      { weekNumber: 2, menuName: "Jocón" },
      { weekNumber: 3, menuName: "Hilachas" },
      { weekNumber: 4, menuName: "Kak'ik" }
    ];
    const notes = [
      { text: "Comprar gas la próxima semana", createdAt: ts },
      { text: "Llamar al fontanero", createdAt: ts - 1 }
    ];
    const shopping = [
      { item: "Leche", checked: false, createdAt: ts },
      { item: "Huevos", checked: false, createdAt: ts - 1 },
      { item: "Tortillas", checked: true, createdAt: ts - 2 }
    ];

    await Promise.all([
      ...events.map(e => tx(db, "events", "readwrite", s => s.add(e))),
      ...meals.map(m => tx(db, "meals", "readwrite", s => s.put(m))),
      ...notes.map(n => tx(db, "notes", "readwrite", s => s.add(n))),
      ...shopping.map(i => tx(db, "shopping", "readwrite", s => s.add(i)))
    ]);
  }

  return { all, add, put, del };
})();

/* ═══ GT · reloj de America/Guatemala (UTC-6 fijo, sin DST) ═══
   Independiente de la zona configurada en la tablet. */
const GT = (() => {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Guatemala",
    year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", second: "2-digit",
    hour12: false
  });

  function now() {
    const p = {};
    for (const part of fmt.formatToParts(new Date())) p[part.type] = part.value;
    const y = +p.year, m = +p.month, d = +p.day;
    const hh = +p.hour % 24, mm = +p.minute, ss = +p.second;
    const dow = new Date(Date.UTC(y, m - 1, d)).getUTCDay(); // 0=domingo
    const start = Date.UTC(y, 0, 1);
    const doy = Math.floor((Date.UTC(y, m - 1, d) - start) / 86400000) + 1;
    return { y, m, d, hh, mm, ss, dow, doy };
  }

  const iso = (y, m, d) =>
    `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

  const DOW = ["DOM", "LUN", "MAR", "MIÉ", "JUE", "VIE", "SÁB"];
  const MON = ["ENE", "FEB", "MAR", "ABR", "MAY", "JUN",
               "JUL", "AGO", "SEP", "OCT", "NOV", "DIC"];
  const MON_FULL = ["ENERO", "FEBRERO", "MARZO", "ABRIL", "MAYO", "JUNIO",
                    "JULIO", "AGOSTO", "SEPTIEMBRE", "OCTUBRE", "NOVIEMBRE", "DICIEMBRE"];

  return { now, iso, DOW, MON, MON_FULL };
})();

/* ═══ Events · expansión de recurrencias a fechas concretas ═══ */
const Events = (() => {

  const parse = (isoStr) => {
    const [y, m, d] = isoStr.split("-").map(Number);
    return { y, m, d, utc: Date.UTC(y, m - 1, d) };
  };
  const DAY = 86400000;

  /* Expande un evento a sus ocurrencias dentro de [fromUtc, toUtc] (ms UTC). */
  function occurrences(ev, fromUtc, toUtc) {
    if (!ev.date) return [];
    const a = parse(ev.date);
    const out = [];
    if (ev.recurrence === "weekly") {
      let t = a.utc;
      if (t < fromUtc) t += Math.ceil((fromUtc - t) / (7 * DAY)) * 7 * DAY;
      for (; t <= toUtc; t += 7 * DAY) if (t >= fromUtc) out.push(t);
    } else if (ev.recurrence === "monthly") {
      const from = new Date(fromUtc), to = new Date(toUtc);
      let y = from.getUTCFullYear(), m = from.getUTCMonth();
      const endY = to.getUTCFullYear(), endM = to.getUTCMonth();
      while (y < endY || (y === endY && m <= endM)) {
        const days = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
        if (a.d <= days) { // si el mes es corto (31 en feb), se omite
          const t = Date.UTC(y, m, a.d);
          if (t >= fromUtc && t <= toUtc && t >= a.utc) out.push(t);
        }
        m++; if (m > 11) { m = 0; y++; }
      }
    } else {
      if (a.utc >= fromUtc && a.utc <= toUtc) out.push(a.utc);
    }
    return out;
  }

  const toIso = (utc) => {
    const d = new Date(utc);
    return GT.iso(d.getUTCFullYear(), d.getUTCMonth() + 1, d.getUTCDate());
  };

  /* Eventos concretos del mes (y, m 1–12): [{iso, day, ev}] ordenados. */
  async function forMonth(y, m) {
    const list = await DB.all("events");
    const from = Date.UTC(y, m - 1, 1);
    const to = Date.UTC(y, m, 0);
    const out = [];
    for (const ev of list) {
      for (const t of occurrences(ev, from, to)) {
        out.push({ iso: toIso(t), day: new Date(t).getUTCDate(), ev });
      }
    }
    out.sort((p, q) => p.iso < q.iso ? -1 : p.iso > q.iso ? 1 : 0);
    return out;
  }

  /* Próximos `days` días desde hoy (para /lista). */
  async function upcoming(days) {
    const list = await DB.all("events");
    const n = GT.now();
    const from = Date.UTC(n.y, n.m - 1, n.d);
    const to = from + days * DAY;
    const out = [];
    for (const ev of list) {
      for (const t of occurrences(ev, from, to)) out.push({ iso: toIso(t), ev });
    }
    out.sort((p, q) => p.iso < q.iso ? -1 : p.iso > q.iso ? 1 : 0);
    return out;
  }

  /* /servicio: adjunta asignación al evento-iglesia de esa fecha (upsert). */
  async function setService(dateIso, text, source) {
    const list = await DB.all("events");
    const hit = list.find(e => e.date === dateIso && e.type === "church"
                               && e.recurrence === "none");
    if (hit) {
      hit.serviceText = text;
      await DB.put("events", hit);
    } else {
      await DB.add("events", {
        title: "CULTO", type: "church", date: dateIso, recurrence: "none",
        serviceText: text, source: source || "manual", createdAt: Date.now()
      });
    }
  }

  return { forMonth, upcoming, setService };
})();
