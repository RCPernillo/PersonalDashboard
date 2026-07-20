/* ═══ TELEGRAM · receptor de acciones ya parseadas por el shell nativo ═══
   El loop Kotlin manda JSON por window.TG.handle(); aquí se escribe en
   IndexedDB, se refresca la vista y se confirma al chat en español vía
   Android.telegramReply(chatId, texto). */
"use strict";

window.TG = (() => {

  function reply(chatId, text) {
    try {
      if (window.Android && Android.telegramReply)
        Android.telegramReply(String(chatId), text);
    } catch (_) { /* sin puente */ }
  }

  async function handle(jsonStr) {
    let a;
    try { a = JSON.parse(jsonStr); } catch (_) { return; }
    try {
      switch (a.action) {

        case "addNote": {
          await DB.add("notes", { text: a.text, createdAt: Date.now() });
          Cabinet.renderNotes();
          reply(a.chatId, `Nota guardada ✓\n«${a.text}»`);
          break;
        }

        case "addShopping": {
          for (const item of a.items) {
            await DB.add("shopping", { item, checked: false, createdAt: Date.now() });
          }
          Cabinet.renderShopping();
          reply(a.chatId, `Agregado a compras ✓\n· ${a.items.join("\n· ")}`);
          break;
        }

        case "addEvent": {
          const n = GT.now();
          const date = a.date || GT.iso(n.y, n.m, n.d); // recurrentes anclan hoy
          await DB.add("events", {
            title: a.title, type: "other", date,
            recurrence: a.recurrence || "none",
            source: "telegram", createdAt: Date.now()
          });
          Cal.render();
          const recTxt = a.recurrence === "weekly" ? " (cada semana)"
                       : a.recurrence === "monthly" ? " (cada mes)" : "";
          reply(a.chatId, `Recordatorio guardado ✓\n${date} — ${a.title}${recTxt}`);
          break;
        }

        case "setService": {
          await Events.setService(a.date, a.text, "telegram");
          Cal.render();
          reply(a.chatId, `Servicio del ${a.date} guardado ✓\n${a.text}`);
          break;
        }

        case "list": {
          reply(a.chatId, await buildList(a.what));
          break;
        }

        case "doneShopping": {
          const items = await DB.all("shopping");
          const q = a.item.toLowerCase();
          const hit = items.find(i => !i.checked && i.item.toLowerCase().includes(q));
          if (hit) {
            hit.checked = true;
            await DB.put("shopping", hit);
            Cabinet.renderShopping();
            reply(a.chatId, `Marcado como comprado ✓ ${hit.item}`);
          } else {
            reply(a.chatId, `No encontré «${a.item}» pendiente en compras.`);
          }
          break;
        }
      }
    } catch (e) {
      reply(a.chatId, "Ocurrió un error guardando en el tablero.");
    }
  }

  async function buildList(what) {
    const parts = [];
    if (what === "compra" || what === "all") {
      const items = (await DB.all("shopping"))
        .sort((x, y) => x.checked - y.checked || y.createdAt - x.createdAt);
      parts.push("COMPRAS:\n" + (items.length
        ? items.map(i => `${i.checked ? "◼" : "◻"} ${i.item}`).join("\n")
        : "(vacía)"));
    }
    if (what === "notas" || what === "all") {
      const notes = (await DB.all("notes"))
        .sort((x, y) => y.createdAt - x.createdAt);
      parts.push("NOTAS:\n" + (notes.length
        ? notes.map(n => `· ${n.text}`).join("\n")
        : "(sin notas)"));
    }
    if (what === "all") {
      const up = await Events.upcoming(30);
      parts.push("PRÓXIMOS 30 DÍAS:\n" + (up.length
        ? up.map(o => `${o.iso} — ${o.ev.title}` +
            (o.ev.serviceText ? ` (${o.ev.serviceText})` : "")).join("\n")
        : "(sin eventos)"));
    }
    return parts.join("\n\n");
  }

  return { handle };
})();
