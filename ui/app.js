"use strict";

/* =========================================================================
   bekky: console locale. Un solo file, moduli logici in ordine:
   1 utilita' DOM · 2 icone · 3 formati · 4 rete e stato · 5 componenti
   6 azioni · 7 logica della panoramica · 8 viste · 9 router e polling
   ========================================================================= */

/* ---------- 1. Utilita' DOM ---------- */

let TOKEN = "";
try {
  const u = new URL(location.href);
  TOKEN = u.searchParams.get("t") || sessionStorage.getItem("bekky-t") || "";
  if (u.searchParams.has("t")) {
    try { sessionStorage.setItem("bekky-t", TOKEN); } catch (e) { /* senza storage il token resta in memoria */ }
    u.searchParams.delete("t");
    history.replaceState(null, "", u.pathname + u.search + u.hash);
  }
} catch (e) { /* URL non leggibile */ }

const $ = (id) => document.getElementById(id);

function h(tag, attrs, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v == null) continue;
    if (k === "class") el.className = v;
    else if (k === "text") el.textContent = v;
    else if (k === "style") el.style.cssText = v; // CSSOM: la CSP vieta l'attributo style inline
    else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
    else el.setAttribute(k, v === true ? "" : v);
  }
  for (const kid of kids.flat(Infinity)) {
    if (kid == null || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(kid));
  }
  return el;
}

/* ---------- 2. Icone: set unico, tratto 1.5, griglia 24 mostrata a 20px ---------- */

const SVGNS = "http://www.w3.org/2000/svg";
// "c:cx,cy,r" disegna un cerchio, ogni altra voce e' un path
const ICONS = {
  home: ["M3 11.5 12 4l9 7.5", "M5.5 10v9.5h13V10", "M10 19.5v-5h4v5"],
  folder: ["M3.5 6.5A1.5 1.5 0 0 1 5 5h4l2 2.5h8a1.5 1.5 0 0 1 1.5 1.5v8.5a1.5 1.5 0 0 1-1.5 1.5H5a1.5 1.5 0 0 1-1.5-1.5z"],
  laptop: ["M6.5 5h11A1.5 1.5 0 0 1 19 6.5V15H5V6.5A1.5 1.5 0 0 1 6.5 5z", "M3 19h18"],
  sliders: ["M4 7h8", "M18 7h2", "M4 17h2", "M12 17h8", "c:15,7,2.5", "c:9,17,2.5"],
  list: ["M7 3.5h7.5L19 8v12.5H7z", "M14.5 3.5V8H19", "M9.5 12.5h7", "M9.5 16h7"],
  shield: ["M12 3.5 5 6v5.5c0 4.2 2.8 7.4 7 9 4.2-1.6 7-4.8 7-9V6z", "m8.8 12 2.4 2.4 4-4.6"],
  alert: ["M12 4 3 19.5h18z", "M12 10v4.5", "M12 17.2v.1"],
  clock: ["c:12,12,8.5", "M12 7.5V12l3 2"],
  check: ["M5 12.5l4.5 4.5L19 7.5"],
  x: ["M6 6l12 12", "M18 6 6 18"],
  copy: ["M10 9h8.5A1.5 1.5 0 0 1 20 10.5V19a1.5 1.5 0 0 1-1.5 1.5H10A1.5 1.5 0 0 1 8.5 19v-8.5A1.5 1.5 0 0 1 10 9z", "M15.5 9V6.5A1.5 1.5 0 0 0 14 5H5.5A1.5 1.5 0 0 0 4 6.5V15a1.5 1.5 0 0 0 1.5 1.5h3"],
  info: ["c:12,12,8.5", "M12 11v5", "M12 8v.1"],
  chevron: ["M6 9.5l6 6 6-6"],
  key: ["c:8.5,15.5,3.5", "M11 13l8-8", "M16 8l2.5 2.5"],
  cloud: ["M7 18a4 4 0 0 1-.5-7.97A5.5 5.5 0 0 1 17.2 9.3 4.4 4.4 0 0 1 17 18z"],
  refresh: ["M19.5 12a7.5 7.5 0 1 1-2.2-5.3", "M19.5 4.5v4h-4"],
  arrow: ["M5 12h14", "M13 6l6 6-6 6"],
  plus: ["M12 5v14", "M5 12h14"],
};

function icon(name, size) {
  const s = document.createElementNS(SVGNS, "svg");
  const set = (e, a) => { for (const k in a) e.setAttribute(k, a[k]); return e; };
  set(s, { viewBox: "0 0 24 24", width: size || 20, height: size || 20, fill: "none", stroke: "currentColor",
    "stroke-width": 1.5, "stroke-linecap": "round", "stroke-linejoin": "round", "aria-hidden": "true", class: "ic" });
  for (const d of ICONS[name]) {
    if (d.startsWith("c:")) {
      const [cx, cy, r] = d.slice(2).split(",");
      s.append(set(document.createElementNS(SVGNS, "circle"), { cx, cy, r }));
    } else s.append(set(document.createElementNS(SVGNS, "path"), { d }));
  }
  return s;
}

// Marcatori della striscia: forma diversa per ogni esito, mai solo colore
function mark(kind) {
  const s = document.createElementNS(SVGNS, "svg");
  s.setAttribute("viewBox", "0 0 10 10");
  s.setAttribute("aria-hidden", "true");
  const el = (n, a) => { const e = document.createElementNS(SVGNS, n); for (const k in a) e.setAttribute(k, a[k]); s.append(e); };
  if (kind === "ok") el("rect", { x: 0.5, y: 0.5, width: 9, height: 9, rx: 1.5, class: "s-ok" });
  else if (kind === "dedup") el("rect", { x: 1.2, y: 1.2, width: 7.6, height: 7.6, rx: 1.5, class: "s-dedup" });
  else if (kind === "fail") el("path", { d: "M1.5 1.5L8.5 8.5M8.5 1.5L1.5 8.5", class: "s-fail" });
  else el("path", { d: "M2.5 5H7.5", class: "s-none" });
  return s;
}

/* ---------- 3. Formati ---------- */

const NF1 = new Intl.NumberFormat("it-IT", { maximumFractionDigits: 1, minimumFractionDigits: 1 });
const NF0 = new Intl.NumberFormat("it-IT");
const DAY = 86400000;
const STALE_DAYS = 8;
const WEEKDAYS = ["domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"];

function parseTs(ts) {
  if (!ts) return null;
  const m = /^(\d{4})-?(\d\d)-?(\d\d)T(\d\d):?(\d\d):?(\d\d)Z$/.exec(ts);
  return m ? new Date(Date.UTC(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6])) : null;
}
function ago(d, now) {
  const s = Math.max(0, Math.round((now - d) / 1000));
  if (s < 60) return "meno di un minuto fa";
  const m = Math.round(s / 60);
  if (m < 60) return m === 1 ? "1 minuto fa" : m + " minuti fa";
  const hh = Math.round(m / 60);
  if (hh < 24) return hh === 1 ? "1 ora fa" : hh + " ore fa";
  const dd = Math.floor(s / 86400);
  return dd === 1 ? "ieri" : dd + " giorni fa";
}
const absTime = (d) => d.toLocaleString("it-IT", { dateStyle: "full", timeStyle: "short" });
const shortDate = (d) => d.toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" });
function mb(b) { return b >= 1e6 ? NF1.format(b / 1e6) + " MB" : b >= 1e3 ? NF1.format(b / 1e3) + " kB" : NF0.format(b) + " B"; }
function mmss(sec) { sec = Math.max(0, sec); return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0"); }
function dayKey(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }

// Riga cron a 5 campi in parole; null se la pianificazione non e' semplice
function cronWords(line) {
  const f = (line || "").split(/\s+/).slice(0, 5);
  if (f.length < 5 || !/^\d+$/.test(f[0]) || !/^\d+$/.test(f[1]) || f[2] !== "*" || f[3] !== "*") return null;
  const at = " alle " + f[1].padStart(2, "0") + ":" + f[0].padStart(2, "0");
  if (f[4] === "*") return "ogni giorno" + at;
  if (!/^[0-7](,[0-7])*$/.test(f[4])) return null;
  const days = f[4].split(",").map((n) => WEEKDAYS[+n % 7]);
  return "ogni " + (days.length > 1 ? days.slice(0, -1).join(", ") + " e " + days.at(-1) : days[0]) + at;
}

// "op://Vault/Item/campo" -> "1Password → Vault → Item"
function friendlyOpRef(ref) {
  const m = /^op:\/\/([^/]+)\/([^/]+)\//.exec(ref || "");
  return m ? "1Password → " + m[1] + " → " + m[2] : ref || "";
}

/* ---------- 4. Rete e stato ---------- */

async function api(path, opts) {
  const o = Object.assign({ headers: {} }, opts);
  o.headers["X-Bekky-Token"] = TOKEN;
  let r;
  try { r = await fetch(path, o); } catch (e) { throw new Error("Il programma bekky non risponde. Riavvialo dal terminale."); }
  let body = null;
  try { body = await r.json(); } catch (e) { /* corpo non JSON */ }
  if (!r.ok) {
    const err = new Error((body && body.error) || ("Errore " + r.status));
    err.status = r.status;
    err.fields = body && body.fields;
    throw err;
  }
  return body;
}
const post = (path, body) => api(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

const state = {
  status: null, checks: null, checksPending: true, config: null,
  core: null, coreOpen: {}, backups: null, logs: {},
  open: {}, selDay: null, prevJobs: null, route: "panoramica", lastError: null,
};

function showError(msg, retry) {
  state.lastError = retry;
  $("errtext").textContent = msg;
  $("errbar").hidden = false;
  $("errretry").hidden = !retry;
}
function clearError() { $("errbar").hidden = true; state.lastError = null; }
$("errretry").addEventListener("click", () => { const f = state.lastError; clearError(); if (f) f(); });

/* ---------- 5. Componenti ---------- */

// Ridisegna solo se il contenuto cambia e riporta il focus sul controllo che lo aveva (data-k)
function paint(el, build) {
  const next = h("div", {}, build());
  const sig = next.innerHTML;
  if (el._sig === sig) return;
  const a = document.activeElement;
  const key = a && el.contains(a) && a.dataset ? a.dataset.k : null;
  el.replaceChildren(...next.childNodes);
  el._sig = sig;
  if (key) {
    const t = [...el.querySelectorAll("[data-k]")].find((n) => n.dataset.k === key);
    if (t && !t.disabled) t.focus();
  }
}

function btn(label, o) {
  o = o || {};
  const b = h("button", { type: "button", class: "btn" + (o.kind ? " " + o.kind : "") + (o.sm ? " sm" : ""), "data-k": o.k,
    "aria-label": o.aria }, o.icon ? icon(o.icon) : null, label);
  if (o.disabled) b.disabled = true;
  else if (o.onClick) b.addEventListener("click", (e) => o.onClick(e, b));
  return b;
}
function badge(kind, ic, text) { return h("span", { class: "badge " + kind }, icon(ic), text); }
function techDetails(key, summary, content) {
  const d = h("details", { class: "tech" }, h("summary", {}, summary, icon("chevron")), content);
  if (state.open[key]) d.open = true;
  d.addEventListener("toggle", () => { state.open[key] = d.open; });
  return d;
}
function panelHead(title, desc) { return h("div", { class: "panel-head" }, h("h2", { text: title }), desc ? h("p", { text: desc }) : null); }

async function copyText(text) {
  try { await navigator.clipboard.writeText(text); return true; } catch (e) {
    const ta = h("textarea", { "aria-hidden": "true", style: "position:fixed;opacity:0" });
    ta.value = text; document.body.append(ta); ta.select();
    let ok = false;
    try { ok = document.execCommand("copy"); } catch (e2) { /* niente da fare */ }
    ta.remove();
    return ok;
  }
}
function copyButton(label, getText, o) {
  return btn(label, Object.assign({ icon: "copy", onClick: async (e, b) => {
    const ok = await copyText(getText());
    toast(ok ? "Copiato negli appunti." : "Non riesco a copiare: seleziona il testo a mano.", ok ? "ok" : "err");
  } }, o));
}
function cmdBlock(text) {
  return h("div", { class: "cmd" }, h("pre", { text }), copyButton("Copia", () => text, { k: "copy-" + text.slice(0, 24) }));
}

function toast(text, kind) {
  const t = h("div", { class: "toast " + (kind || "ok") }, icon(kind === "err" ? "alert" : "check"), h("span", { text }));
  $("toasts").append(t);
  setTimeout(() => t.remove(), kind === "err" ? 8000 : 5000);
}

/* dialog: un solo <dialog> nativo (focus trap ed Esc gratis), contenuto sostituibile per le procedure a passi */
const dlg = $("dlg");
let dlgDone = null, dlgOpener = null;
function dlgRender(o) {
  dlg.classList.toggle("wide", !!o.wide);
  $("dlg-title").textContent = o.title;
  $("dlg-body").replaceChildren(...[].concat(o.body || []).flat(Infinity).filter(Boolean));
  $("dlg-actions").replaceChildren(...(o.actions || []).map((a) =>
    btn(a.label, { kind: a.kind, disabled: a.disabled, onClick: a.onClick, k: "dlg-" + a.label })));
  if (!dlg.open) {
    const a = document.activeElement;
    dlgOpener = a && a.dataset ? a.dataset.k : null;
    dlg.showModal();
  }
  const f = $("dlg-body").querySelector("[data-autofocus]");
  if (f) f.focus();
}
function dlgClose() { if (dlg.open) dlg.close(); }
dlg.addEventListener("close", () => {
  const d = dlgDone; dlgDone = null;
  if (dlgOpener) {
    const k = dlgOpener; dlgOpener = null;
    setTimeout(() => { const t = [...document.querySelectorAll("[data-k]")].find((n) => n.dataset.k === k); if (t && !t.disabled) t.focus(); }, 0);
  }
  if (d) d();
});
function confirmDialog(o) {
  return new Promise((resolve) => {
    let val = false;
    dlgDone = () => resolve(val);
    dlgRender({ title: o.title, body: [].concat(o.body).map((t) => (typeof t === "string" ? h("p", { text: t }) : t)),
      actions: [{ label: o.cancel || "Annulla", onClick: dlgClose },
        { label: o.ok, kind: o.danger ? "danger" : "primary", onClick: () => { val = true; dlgClose(); } }] });
  });
}

/* ---------- 6. Azioni (job lanciati dal server) ---------- */

const JOBS = {
  "quick-push": { label: "Salvataggio rapido", ok: "Salvataggio rapido completato.", fail: "Il salvataggio rapido non è riuscito." },
  "full-backup": { label: "Salvataggio completo", ok: "Salvataggio completo completato.", fail: "Il salvataggio completo non è riuscito." },
  "hook-install": { label: "Salvataggio automatico", ok: "Salvataggio automatico acceso.", fail: "Non sono riuscito ad accenderlo." },
  "hook-uninstall": { label: "Salvataggio automatico", ok: "Salvataggio automatico spento.", fail: "Non sono riuscito a spegnerlo." },
  "tools-retry": { label: "Strumenti", ok: "Strumenti installati.", fail: "Alcuni strumenti non si sono installati." },
  "repos-retry": { label: "Repo", ok: "Repo scaricate.", fail: "Alcune repo non si sono scaricate." },
};
const CONFIRM = {
  "full-backup": { title: "Avviare il salvataggio completo?", body: "Dura circa 20 minuti. Puoi continuare a lavorare: bekky va avanti da solo.", ok: "Avvia il salvataggio" },
  "hook-uninstall": { title: "Spegnere il salvataggio automatico?", body: "Quando chiudi Claude, i tuoi dati non verranno più salvati da soli. Potrai riaccenderlo quando vuoi.", ok: "Spegni" },
};

function jobRunning(name) {
  const j = state.status && state.status.jobs && state.status.jobs[name];
  return !!(j && j.running);
}
const anyBusy = () => !!state.status && (Object.values(state.status.jobs || {}).some((j) => j.running) || state.status.quick.running || state.status.full.running);

async function startJob(name) {
  const c = CONFIRM[name];
  if (c && !(await confirmDialog(c))) return;
  try {
    await post("/api/action", { name });
    clearError();
  } catch (e) {
    if (e.status !== 409) showError("Non sono riuscito ad avviare l'operazione: " + e.message, () => startJob(name));
  }
  await loadStatus();
}
function jobButton(label, name, o) {
  o = o || {};
  return btn(label, { kind: o.kind, k: "job-" + name, aria: o.aria, icon: o.icon, sm: o.sm,
    disabled: !!o.disabled, onClick: () => startJob(name) });
}

// Fasi dedotte dalle righe ">> ..." del log; -1 = nessuna riga riconosciuta
const PHASES = [
  { label: "Raccolgo i file", re: /raccolgo|scansiono|bundle|inventario|lista pacchetti|quick: (?!upload|backup|nessuna)/ },
  { label: "Cifro e confronto", re: /manifest|checksum|nessuna modifica|cifr/ },
  { label: "Carico", re: /upload|carico/ },
];
function phaseOf(lines) {
  let p = -1;
  for (const l of lines || []) PHASES.forEach((ph, i) => { if (i > p && ph.re.test(l)) p = i; });
  return p;
}

function progressNode(job, external) {
  const lines = state.logs[job] || [];
  const p = external ? -1 : phaseOf(lines);
  const label = external ? "In corso: partito alla chiusura di Claude" : p < 0 ? "Sto lavorando…" : "Passo " + (p + 1) + " di " + PHASES.length + ": " + PHASES[p].label;
  const bar = h("div", { class: "bar" + (p < 0 ? " indet" : "") }, h("span", { style: p < 0 ? "" : "width:" + Math.round(((p + 0.6) / PHASES.length) * 100) + "%" }));
  return h("div", { class: "progress" },
    h("div", { class: "progress-top" }, h("span", { text: label }), external ? null : h("span", { class: "num", "data-elapsed": job })),
    h("div", { role: "progressbar", "aria-label": label, "aria-valuetext": label }, bar),
    p >= 0 ? h("div", { class: "phases", "aria-hidden": "true" }, PHASES.map((ph, i) => h("span", { class: i === p ? "on" : "", text: ph.label }))) : null,
    external ? null : techDetails("log-" + job, "Dettagli tecnici", h("pre", { class: "techbox", role: "log", text: lines.slice(-12).join("\n") || "Parte…" })));
}
function tickElapsed() {
  if (!state.status) return;
  document.querySelectorAll("[data-elapsed]").forEach((el) => {
    const j = state.status.jobs[el.dataset.elapsed];
    const t0 = j && parseTs(j.startedAt);
    el.textContent = t0 ? mmss(Math.round((Date.now() - t0.getTime()) / 1000)) : "";
  });
}
setInterval(tickElapsed, 1000);

/* ---------- 7. Logica della panoramica ---------- */

function newPcCommand(cfg) {
  const base = "curl -fsSL https://raw.githubusercontent.com/gerardocipriano/bekky/main/scripts/quick.sh | ";
  const d = cfg.defaults, vars = [];
  if (["bucket", "project", "account"].some((k) => cfg[k] !== d[k])) {
    if (cfg.bucket) vars.push("BEKKY_BUCKET=" + cfg.bucket);
    if (cfg.project) vars.push("BEKKY_PROJECT=" + cfg.project);
    if (cfg.account) vars.push("BEKKY_ACCOUNT=" + cfg.account);
  }
  return base + vars.join(" ") + (vars.length ? " " : "") + "bash";
}

function loginSteps(account) {
  const cmd = "gcloud auth login" + (account ? " --account=" + account : "");
  return [
    h("li", {}, h("h3", { text: "Apri il terminale" }), h("div", { class: "body" }, h("p", { text: "Cerca «Terminale» tra le app del tuo PC." }))),
    h("li", {}, h("h3", { text: "Incolla questo comando e premi Invio" }), h("div", { class: "body" }, cmdBlock(cmd))),
    h("li", {}, h("h3", { text: "Segui le istruzioni nel browser" }), h("div", { class: "body" },
      h("p", { text: "Quando hai finito, torna qui e premi il pulsante." }),
      h("div", { class: "btn-row" }, recheckButton("Ho fatto, ricontrolla", true)))),
  ];
}
function recheckButton(label, primary) {
  return btn(label, { kind: primary ? "primary" : "", k: "recheck", icon: "refresh", onClick: async (e, b) => {
    b.disabled = true; b.lastChild.textContent = "Controllo…";
    await loadChecks(true);
    if (state.checks && !state.checks.gcloud.ok) toast("L'accesso non è ancora valido. Controlla di aver completato i passi.", "err");
    else if (state.checks && state.checks.gcloud.ok) toast("Accesso a Google Cloud ricontrollato: tutto a posto.");
  } });
}

// Descrive il problema piu' urgente. Priorita': primo avvio, in corso, accesso, spazio, ultimo esito, ritardo, automatismo, ripristino
function heroModel() {
  const s = state.status, c = state.checks;
  const now = new Date(s.now), q = s.quick.last, f = s.full.last;
  if (!s.configured.bucket || !s.configured.passphrase) return { kind: "setup" };
  const rq = jobRunning("quick-push") || s.quick.running, rf = jobRunning("full-backup") || s.full.running;
  if (rq || rf) return { level: "busy", icon: "clock", title: rf && !rq ? "Salvataggio completo in corso" : "Salvataggio rapido in corso",
    text: "Sto salvando i tuoi dati. Puoi continuare a lavorare." };
  if (c && !c.gcloud.ok) return { level: "err", icon: "alert", title: "Serve rifare l'accesso a Google Cloud",
    text: "Senza questo accesso i salvataggi non possono partire. Ci vuole circa un minuto.", steps: loginSteps(c.gcloud.account) };
  if (c && c.gcloud.ok && !c.bucket.ok) return { level: "err", icon: "alert", title: "Lo spazio di archiviazione non risponde",
    text: "Controlla che il PC sia connesso a Internet. Se il problema resta, controlla lo spazio scelto.",
    actions: [{ node: recheckButton("Ricontrolla", true) }, { link: "#/impostazioni", label: "Apri le impostazioni" }] };
  if (q && q.result === "fail") return { level: "err", icon: "alert", title: "L'ultimo salvataggio rapido non è riuscito",
    text: "È successo " + ago(parseTs(q.ts), now) + ". Riprova: di solito basta un secondo tentativo.",
    actions: [{ job: "quick-push", label: "Riprova ora", primary: true }, { link: "#/registro", label: "Vedi cosa è successo" }] };
  if (f && f.result === "fail") return { level: "err", icon: "alert", title: "L'ultimo salvataggio completo non è riuscito",
    text: "È successo " + ago(parseTs(f.ts), now) + ". Riprova quando puoi: dura circa 20 minuti.",
    actions: [{ job: "full-backup", label: "Riprova ora", primary: true }, { link: "#/registro", label: "Vedi cosa è successo" }] };
  if (f && f.result !== "fail") {
    const days = Math.floor((now - parseTs(f.ts)) / DAY);
    if (days > STALE_DAYS) return { level: "warn", icon: "alert", title: "Il salvataggio completo è in ritardo",
      text: "L'ultimo risale a " + days + " giorni fa. Conviene rifarlo.",
      actions: [{ job: "full-backup", label: "Salva tutto ora", primary: true }] };
  }
  if (!s.checks.hook) return { level: "warn", icon: "alert", title: "Il salvataggio automatico è spento",
    text: "Quando chiudi Claude i tuoi dati non vengono più salvati da soli.",
    actions: [{ job: "hook-install", label: "Accendi il salvataggio automatico", primary: true }] };
  const r = s.restore;
  if (r) {
    const tf = r.tools.filter((t) => t.status === "FAIL").length, rf = r.reposFailed.length;
    if (tf || rf) return { level: "warn", icon: "alert", title: "Qualcosa non è stato ripristinato su questo PC",
      text: [tf ? tf + (tf === 1 ? " strumento" : " strumenti") : "", rf ? rf + (rf === 1 ? " repo" : " repo") : ""].filter(Boolean).join(" e ") + " da rifare.",
      actions: [{ link: "#/nuovo-pc", label: "Vai al ripristino", primary: true }] };
  }
  if (!q && !f) return { level: "warn", icon: "alert", title: "Non hai ancora salvato nulla",
    text: "Fai il primo salvataggio: ci vogliono pochi secondi.", actions: [{ job: "quick-push", label: "Salva ora", primary: true }] };
  if (state.checksPending && !c) return { level: "busy", icon: "clock", title: "Controllo l'accesso", text: "Verifico Google Cloud e lo spazio di archiviazione." };
  const done = [q, f].filter((x) => x && x.result !== "fail").map((x) => parseTs(x.ts)).sort((a, b) => b - a)[0];
  return { level: "ok", icon: "shield", title: "I tuoi dati sono al sicuro",
    text: done ? "Ultimo salvataggio " + ago(done, now) + "." : "Nessun salvataggio recente." };
}

/* ---------- 8. Viste ---------- */

function actionNode(a) {
  if (a.node) return a.node;
  if (a.job) return jobButton(a.label, a.job, { kind: a.primary ? "primary" : "", icon: undefined });
  return h("a", { class: "btn" + (a.primary ? " primary" : ""), href: a.link, "data-k": "lnk-" + a.link }, a.label);
}

function setupWizard() {
  const s = state.status, ready = s.configured.bucket && s.configured.passphrase;
  const step = (done, title, body) => h("li", { class: done ? "done" : "" }, h("h3", { text: title }), h("div", { class: "body" }, body));
  return h("section", { class: "panel hero", "data-level": "busy" },
    h("div", { class: "hero-head" }, h("div", { class: "hero-ic" }, icon("shield")),
      h("div", {}, h("h2", { text: "Prepariamo bekky" }),
        h("p", { class: "sub", text: "Mancano un paio di cose prima del primo salvataggio. Sono tre passi." }))),
    h("div", { class: "hero-body" },
      h("ol", { class: "steps" },
        step(s.configured.bucket, "Scegli dove salvare",
          s.configured.bucket ? h("p", { text: "Spazio scelto: " + s.bucket.replace("gs://", "") })
            : [h("p", { text: "È il posto su Google Cloud dove finiscono i tuoi salvataggi." }),
               h("div", { class: "btn-row" }, h("a", { class: "btn primary", href: "#/impostazioni/spazio", "data-k": "go-spazio" }, "Scegli lo spazio"))]),
        step(s.configured.passphrase, "Crea la passphrase",
          s.configured.passphrase ? h("p", { text: "La passphrase c'è." })
            : [h("p", { text: "È la chiave che cifra i tuoi salvataggi. Senza, non si recuperano." }),
               h("div", { class: "btn-row" }, h("a", { class: "btn" + (s.configured.bucket ? " primary" : ""), href: "#/impostazioni/passphrase", "data-k": "go-pass" }, "Come si fa"))]),
        step(false, "Fai il primo salvataggio",
          [h("p", { text: "Ci vogliono pochi secondi." }),
           h("div", { class: "btn-row" }, jobButton("Salva ora", "quick-push", { kind: "primary", disabled: !ready }),
             ready ? null : h("span", { class: "why" }, icon("info", 16), "Prima completa i passi 1 e 2."))]))));
}

function heroPanel(m) {
  const body = [];
  if (m.steps) body.push(h("ol", { class: "steps" }, m.steps));
  if (m.actions) body.push(h("div", { class: "btn-row" }, m.actions.map(actionNode)));
  return h("section", { class: "panel hero", "data-level": m.level },
    h("div", { class: "hero-head" }, h("div", { class: "hero-ic" }, icon(m.icon)),
      h("div", {}, h("h2", { text: m.title }), h("p", { class: "sub", text: m.text }))),
    body.length ? h("div", { class: "hero-body" }, body) : null);
}

function resultBlock(last, now) {
  if (!last) return h("p", { class: "muted", text: "Non è ancora stato fatto su questo PC." });
  const d = parseTs(last.ts);
  const b = last.result === "fail" ? badge("err", "x", "Non riuscito") : last.result === "dedup" ? badge("ok", "check", "Già aggiornato") : badge("ok", "check", "Salvato");
  return h("div", { class: "row" }, b, h("span", { title: absTime(d), text: ago(d, now) }),
    last.bytes > 0 ? h("span", { class: "faint num", text: "· " + mb(last.bytes) }) : null);
}

function savePanel(o, s) {
  const now = new Date(s.now), mine = jobRunning(o.job), ext = !mine && s[o.key].running;
  const missingPass = o.job === "quick-push" && !s.checks.passphrase;
  let action;
  if (mine || ext) action = null;
  else action = h("div", { class: "btn-row" },
    jobButton("Salva ora", o.job, { kind: o.primary ? "primary" : "", aria: "Salva ora: " + o.title.toLowerCase(), disabled: missingPass }),
    missingPass ? h("span", { class: "why" }, icon("info", 16), "Manca la passphrase") : null);
  return h("section", { class: "panel save" },
    h("div", { class: "save-head" }, icon(o.icon), h("div", {}, h("h2", { text: o.title }), h("p", { class: "what", text: o.what }))),
    h("div", { class: "last" }, resultBlock(s[o.key].last, now)),
    mine || ext ? progressNode(o.job, ext) : null,
    action ? h("div", { class: "actions" }, action) : null);
}

function activitySection(s) {
  const now = new Date(s.now);
  const days = [];
  for (let i = 29; i >= 0; i--) { const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i); days.push({ d, key: dayKey(d), full: [], quick: [] }); }
  const byKey = Object.fromEntries(days.map((x) => [x.key, x]));
  let fails = 0;
  for (const e of s.history) {
    const t = parseTs(e.ts), slot = t && byKey[dayKey(t)];
    if (slot) slot[e.kind].push(e.result);
    if (e.result === "fail") fails++;
  }
  const word = (arr) => {
    if (!arr.length) return { kind: "none", text: "nessun salvataggio" };
    const last = arr[arr.length - 1];
    const w = last === "fail" ? "non riuscito" : last === "dedup" ? "già aggiornato" : "salvato";
    return { kind: last === "upload" ? "ok" : last, text: (arr.length > 1 ? arr.length + " volte, l'ultima: " : "") + w };
  };
  const saved = days.filter((x) => [...x.full, ...x.quick].some((r) => r !== "fail")).length;
  const summary = saved === 0 ? "Nessun salvataggio negli ultimi 30 giorni." :
    "Salvato in " + saved + " giorni su 30. " + (fails ? fails + (fails === 1 ? " salvataggio non è riuscito." : " salvataggi non sono riusciti.") : "Nessun salvataggio fallito.");
  const label = (x) => x.d.toLocaleDateString("it-IT", { weekday: "long", day: "numeric", month: "long" }) +
    ". Rapido: " + word(x.quick).text + ". Completo: " + word(x.full).text + ".";
  const cells = { quick: [h("span", { class: "lab", text: "Rapido" })], full: [h("span", { class: "lab", text: "Completo" })] };
  const detail = h("p", { class: "strip-detail", "aria-hidden": "true",
    text: state.selDay != null && days[state.selDay] ? label(days[state.selDay]) : "Passa il mouse o tocca un giorno per vedere i dettagli." });
  days.forEach((x, i) => {
    for (const kind of ["quick", "full"]) {
      const c = h("span", { class: "day" + (x.key === dayKey(now) ? " today" : "") + (state.selDay === i ? " sel" : ""), title: label(x), "aria-hidden": "true" }, mark(word(x[kind]).kind));
      c.addEventListener("mouseenter", () => { detail.textContent = label(x); });
      c.addEventListener("click", () => { state.selDay = i; detail.textContent = label(x); });
      cells[kind].push(c);
    }
  });
  const tick = (i, text, end) => h("span", { class: "tick" + (end ? " end" : ""), "aria-hidden": "true",
    style: "grid-row:3;grid-column:" + (end ? "26 / 32" : (i + 2) + " / span 6"), text });
  const ticks = [0, 7, 14, 21].map((i) => tick(i, days[i].d.toLocaleDateString("it-IT", { day: "numeric", month: "short" }))).concat(tick(29, "oggi", true));
  const tb = h("tbody", {}, days.slice().reverse().map((x) => h("tr", {}, h("th", { scope: "row", text: x.d.toLocaleDateString("it-IT", { weekday: "short", day: "numeric", month: "short" }) }),
    h("td", { text: word(x.quick).text }), h("td", { text: word(x.full).text }))));
  return h("section", { class: "panel", "aria-labelledby": "h-act" },
    h("div", { class: "panel-head" }, h("h2", { id: "h-act", text: "Ultimi 30 giorni" })),
    h("p", { class: "summary-line", text: summary }),
    h("div", { class: "strip" }, cells.quick, cells.full, ticks),
    detail,
    h("p", { class: "legend" }, h("span", {}, mark("ok"), "Salvato"), h("span", {}, mark("dedup"), "Già aggiornato"),
      h("span", {}, mark("fail"), "Non riuscito"), h("span", {}, mark("none"), "Niente")),
    techDetails("giorno-per-giorno", "Vedi giorno per giorno", h("div", { class: "tbl-wrap" }, h("table", { class: "tbl" },
      h("caption", { class: "sr-only", text: "Salvataggi giorno per giorno negli ultimi 30 giorni" }),
      h("thead", {}, h("tr", {}, h("th", { scope: "col", text: "Giorno" }), h("th", { scope: "col", text: "Rapido" }), h("th", { scope: "col", text: "Completo" }))), tb))));
}

function automationSection(s) {
  const hook = s.checks.hook, cron = s.checks.cron, hookBusy = jobRunning("hook-install") || jobRunning("hook-uninstall");
  const sw = h("button", { type: "button", class: "switch", role: "switch", "aria-checked": String(hook), "data-k": "sw-hook",
    "aria-labelledby": "lbl-hook", onclick: () => startJob(hook ? "hook-uninstall" : "hook-install") },
    h("span", { class: "track", "aria-hidden": "true" }), h("span", { text: hookBusy ? "Un momento…" : hook ? "Acceso" : "Spento" }));
  if (hookBusy) sw.disabled = true;
  const words = cron.present ? cronWords(cron.line) : null;
  const next = cron.present && cron.next ? parseTs(cron.next) : null;
  return h("section", { class: "panel", "aria-labelledby": "h-auto" },
    h("div", { class: "panel-head" }, h("h2", { id: "h-auto", text: "Salvataggi automatici" }),
      h("p", { text: "Così non devi ricordarti di salvare." })),
    h("div", { class: "auto-row" },
      h("div", {}, h("h3", { id: "lbl-hook", text: "Salvataggio automatico alla chiusura di Claude" }),
        h("p", { text: "Ogni volta che chiudi Claude, i tuoi dati vengono salvati da soli." })), sw),
    h("div", { class: "auto-row" },
      h("div", {}, h("h3", { text: "Salvataggio completo settimanale" }),
        h("p", { text: cron.present ? (words ? words.charAt(0).toUpperCase() + words.slice(1) + "." : "È pianificato su questo PC.") + (next ? " Il prossimo: " + next.toLocaleString("it-IT", { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit" }) + "." : "") : "Non è pianificato su questo PC." }),
        techDetails("tech-cron", "Dettagli tecnici", h("pre", { class: "techbox", text: cron.present ? cron.line : "Nel crontab manca la riga con bekky-cron.sh." }))),
      cron.present ? badge("ok", "check", "Attivo") : badge("warn", "alert", "Non attivo")));
}

const OverviewView = {
  title: "Panoramica", sub: "Qui vedi se i tuoi dati sono al sicuro.",
  mount(root) {
    this.r = { hero: h("div", { "aria-live": "polite" }), duo: h("div", { class: "duo" }), act: h("div"), auto: h("div") };
    root.append(h("div", { class: "stack" }, Object.values(this.r)));
  },
  update() {
    const s = state.status, r = this.r;
    const m = heroModel();
    paint(r.hero, () => (m.kind === "setup" ? setupWizard() : heroPanel(m)));
    const show = m.kind !== "setup";
    r.duo.hidden = r.act.hidden = r.auto.hidden = !show;
    if (!show) return;
    paint(r.duo, () => [
      savePanel({ key: "quick", job: "quick-push", title: "Salvataggio rapido", icon: "shield", primary: true,
        what: "Impostazioni di Claude, chiavi e accessi. Ci vogliono pochi secondi." }, s),
      savePanel({ key: "full", job: "full-backup", title: "Salvataggio completo", icon: "cloud",
        what: "Tutto, comprese le repo. Ci vogliono circa 20 minuti." }, s)]);
    paint(r.act, () => activitySection(s));
    paint(r.auto, () => automationSection(s));
    tickElapsed();
  },
};

/* --- Cosa viene salvato --- */

const GROUPS = [
  { title: "Claude: impostazioni, memoria, skill e plugin", test: (p) => p.startsWith(".claude") || p === "CLAUDE.md" },
  { title: "Accessi cloud e chiavi", test: (p) => /^(\.config\/(gcloud|gh)|\.ssh|\.gnupg|\.netrc|\.kube|\.aws|\.azure|\.docker)/.test(p) },
  { title: "Terminale e git", test: (p) => /^(\.(zshrc|bashrc|profile|zprofile|bash_profile|zshenv|gitconfig|inputrc|tmux\.conf)|\.config\/(git|starship|fish|zsh))/.test(p) },
  { title: "Script personali", test: (p) => /^(\.local\/bin|bin)(\/|$)/.test(p) },
  { title: "Editor e strumenti", test: (p) => /^(\.config\/(Code|opencode|nvim|cursor|zed)|\.vscode)/.test(p) },
  { title: "Altro", test: () => true },
];
const FRIENDLY = {
  ".claude/projects": "Cronologia dei progetti", ".claude/skills": "Skill di Claude", ".claude/plugins": "Plugin di Claude",
  ".claude/settings.json": "Impostazioni di Claude", ".config/Code": "Impostazioni di VS Code", ".config/gcloud": "Accesso a Google Cloud",
  ".config/opencode": "Impostazioni di opencode", ".zshrc": "Configurazione di zsh", ".bashrc": "Configurazione di bash",
  ".gitconfig": "Configurazione di git", ".config/git": "Altre impostazioni di git", ".local/bin": "Programmi e script personali",
};

function coreContent() {
  const c = state.core;
  const q = ($("core-filter") ? $("core-filter").value : "").trim().toLowerCase();
  const groups = GROUPS.map((g) => ({ g, items: [] }));
  for (const e of c.entries) {
    if (q && !(e.path.toLowerCase().includes(q) || (FRIENDLY[e.path] || "").toLowerCase().includes(q))) continue;
    groups.find((x) => x.g.test(e.path)).items.push(e);
  }
  const max = c.entries.length ? c.entries[0].bytes : 1;
  const used = groups.filter((x) => x.items.length);
  if (!used.length) return h("p", { class: "muted", text: "Nessun file o cartella corrisponde a «" + q + "»." });
  return used.map(({ g, items }) => {
    const total = items.reduce((a, e) => a + e.bytes, 0), files = items.reduce((a, e) => a + e.files, 0);
    const open = q || state.coreOpen[g.title];
    const shown = open ? items : items.slice(0, 6);
    return h("section", { class: "group" },
      h("div", { class: "group-head" }, h("h3", { text: g.title }), h("span", { text: mb(total) + " · " + NF0.format(files) + (files === 1 ? " file" : " file") })),
      h("ul", { class: "bars" }, shown.map((e) => h("li", {},
        h("div", {}, FRIENDLY[e.path] ? [h("div", { text: FRIENDLY[e.path] }), h("div", { class: "path faint", text: e.path })] : h("div", { class: "path", text: e.path })),
        h("div", { class: "bar", "aria-hidden": "true" }, h("span", { style: "width:" + Math.max(1, (e.bytes / max) * 100) + "%" })),
        h("div", { class: "n", text: mb(e.bytes) })))),
      items.length > shown.length ? btn("Mostra le altre " + (items.length - shown.length), { sm: true, k: "more-" + g.title,
        onClick: () => { state.coreOpen[g.title] = true; renderCore(); } }) : null);
  });
}
function renderCore() {
  const body = $("core-body");
  if (!body) return;
  const keep = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.k : null;
  body.replaceChildren(...[].concat(coreContent()));
  if (keep) { const t = [...body.querySelectorAll("[data-k]")].find((n) => n.dataset.k === keep); if (t) t.focus(); }
}
async function loadCore() {
  const box = $("core-box");
  box.replaceChildren(h("div", { class: "stack", "aria-busy": "true" }, h("p", { class: "muted", text: "Sto contando i file… Ci vogliono alcuni secondi." }),
    [70, 55, 62, 40].map((w) => h("div", { class: "skel", style: "width:" + w + "%" }))));
  try {
    state.core = await api("/api/core");
    clearError();
    drawCore();
  } catch (e) {
    box.replaceChildren(emptyState("alert", "Non sono riuscito a leggere l'elenco", e.message, btn("Riprova", { kind: "primary", icon: "refresh", onClick: loadCore })));
  }
}
function drawCore() {
  const c = state.core;
  $("core-box").replaceChildren(
    h("div", { class: "total" }, h("span", { class: "big", text: mb(c.totalBytes) }), h("span", { class: "muted", text: "in " + NF0.format(c.totalFiles) + " file" }),
      btn("Ricalcola", { sm: true, icon: "refresh", k: "core-recalc", onClick: loadCore })),
    h("hr", { class: "rule" }),
    h("div", { class: "field filter-row" }, h("label", { for: "core-filter", text: "Cerca un file o una cartella" }),
      h("input", { class: "input", id: "core-filter", type: "search", autocomplete: "off", spellcheck: "false", placeholder: "Per esempio: gcloud", oninput: renderCore })),
    h("div", { id: "core-body" }));
  renderCore();
}
function emptyState(ic, title, text, action) {
  return h("div", { class: "empty" }, icon(ic), h("h3", { text: title }), h("p", { class: "muted", text }), action || null);
}

const SavedView = {
  title: "Cosa viene salvato", sub: "Il salvataggio rapido protegge queste cartelle e questi file.",
  mount(root) {
    root.append(h("div", { class: "stack" },
      h("section", { class: "panel" }, panelHead("Elenco del salvataggio rapido"), h("div", { id: "core-box" })),
      h("div", { class: "note" }, icon("info"), h("p", {}, "Nel salvataggio rapido non entrano le repo e i documenti: stanno nel salvataggio completo. I file più grandi di 5 MB restano fuori dal rapido."))));
    if (state.core) drawCore();
    else $("core-box").replaceChildren(emptyState("folder", "Vuoi vedere cosa viene salvato?", "bekky conta i file e te li mostra per tipo. Ci vogliono alcuni secondi.",
      btn("Mostra l'elenco", { kind: "primary", k: "core-go", onClick: loadCore })));
  },
  update() { /* si ridisegna solo su richiesta */ },
};

/* --- Nuovo PC --- */

function restorePanel(r) {
  const tf = r.tools.filter((t) => t.status === "FAIL").length;
  const st = (t) => t.status === "FAIL" ? badge("err", "x", "Non riuscito") : t.status === "skip" ? badge("", "check", "Già presente") : badge("ok", "check", "Installato");
  return h("section", { class: "panel" },
    panelHead("Ripristino su questo PC", "Quello che è successo dopo l'ultimo ripristino fatto qui."),
    h("h3", { class: "small", text: "Strumenti" }),
    h("ul", { class: "rlist" }, r.tools.map((t) => h("li", {}, st(t), h("span", { class: "nm", text: t.name }), t.detail ? h("span", { class: "d", text: t.detail }) : null))),
    h("div", { class: "btn-row" }, jobButton("Riprova gli strumenti", "tools-retry", { disabled: !tf || jobRunning("tools-retry") }),
      tf ? null : h("span", { class: "why" }, icon("info", 16), "Nessuno strumento da rifare")),
    h("hr", { class: "rule" }),
    h("h3", { class: "small", text: "Repo" }),
    r.reposFailed.length ? [h("p", { class: "muted small", text: "Queste repo non si sono scaricate." }),
      h("ul", { class: "rlist" }, r.reposFailed.map((x) => h("li", {}, badge("err", "x", "Non scaricata"), h("span", { class: "nm", text: x.path }), x.remote ? h("span", { class: "d", text: x.remote }) : null))),
      h("div", { class: "btn-row" }, jobButton("Riprova le repo", "repos-retry", { disabled: jobRunning("repos-retry") }))]
      : h("p", { class: "muted", text: "Tutte le repo sono state scaricate." }));
}

const NewPcView = {
  title: "Nuovo PC", sub: "Come ritrovare tutto su un computer nuovo, in tre passi.",
  mount(root) { this.box = h("div", { class: "stack" }); root.append(this.box); },
  update() {
    const cfg = state.config, s = state.status;
    paint(this.box, () => [
      h("section", { class: "panel" },
        h("ol", { class: "steps" },
          h("li", {}, h("h3", { text: "Apri il terminale sul PC nuovo" }), h("div", { class: "body" }, h("p", { text: "Cerca «Terminale» tra le app del PC." }))),
          h("li", {}, h("h3", { text: "Incolla questo comando e premi Invio" }), h("div", { class: "body" },
            cfg && cfg.bucket ? cmdBlock(newPcCommand(cfg))
              : [h("p", { text: "Prima serve scegliere lo spazio di archiviazione." }), h("div", { class: "btn-row" }, h("a", { class: "btn primary", href: "#/impostazioni/spazio", "data-k": "go-spazio" }, "Scegli lo spazio"))])),
          h("li", {}, h("h3", { text: "Rispondi alle due domande" }), h("div", { class: "body" },
            h("p", { text: "Ti chiede la passphrase: la trovi in 1Password. Poi si apre il browser per l'accesso a Google: scegli il tuo account." }))))),
      h("section", { class: "panel" }, panelHead("Cosa succede dopo"),
        h("ul", { class: "rlist" },
          h("li", {}, badge("info", "clock", "Circa 10 secondi"), h("span", { text: "Claude è pronto, con le tue impostazioni." })),
          h("li", {}, badge("info", "clock", "Circa 1 minuto"), h("span", { text: "Gli strumenti si installano." })))),
      h("div", { class: "note" }, icon("info"), h("p", { text: "Il ripristino non parte da questa pagina: sostituirebbe i file di questo PC. Si fa solo dal PC nuovo." })),
      s.restore ? restorePanel(s.restore) : null]);
  },
};

/* --- Impostazioni --- */

const BUCKET_NAME_RE = /^[a-z0-9][a-z0-9_-]{1,61}[a-z0-9]$/;
const BUCKET_FULL_RE = /^gs:\/\/[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]$/;
const PROJECT_RE = /^[a-z][a-z0-9-]{3,28}[a-z0-9]$/;
const ACCOUNT_RE = /^[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}$/;

function nameProblem(n, existing) {
  if (!n) return "Scrivi un nome per il nuovo spazio.";
  if (/[A-Z]/.test(n)) return "Usa solo lettere minuscole.";
  if (/\s/.test(n)) return "Niente spazi: usa i trattini, per esempio il-mio-spazio.";
  if (n.length < 3) return "Servono almeno 3 caratteri.";
  if (n.length > 63) return "Troppo lungo: massimo 63 caratteri.";
  if (!/^[a-z0-9]/.test(n) || !/[a-z0-9]$/.test(n)) return "Deve iniziare e finire con una lettera o un numero.";
  if (!BUCKET_NAME_RE.test(n)) return "Usa solo lettere minuscole, numeri e trattini.";
  if ((existing || []).includes(n)) return "Esiste già uno spazio con questo nome.";
  return "";
}
function configProblems(v) {
  const e = {};
  if (!BUCKET_FULL_RE.test(v.bucket)) e.bucket = "Scrivi l'indirizzo completo, che inizia con gs:// (per esempio gs://il-mio-spazio).";
  if (v.project && !PROJECT_RE.test(v.project)) e.project = "Il progetto usa minuscole, numeri e trattini (da 5 a 30 caratteri).";
  if (v.account && !ACCOUNT_RE.test(v.account)) e.account = "Scrivi un indirizzo email valido, per esempio nome@azienda.it.";
  return e;
}
function verifySolution(msg) {
  if (/permesso/.test(msg)) return "Chiedi a chi gestisce Google Cloud di darti il permesso, oppure scegli un altro spazio.";
  if (/scaduto/.test(msg)) return "Rifai l'accesso a Google Cloud (lo trovi nella Panoramica) e poi riprova.";
  if (/non esiste/.test(msg)) return "Scegli un altro spazio oppure creane uno nuovo.";
  return "Controlla la connessione a Internet e riprova.";
}

// Salva la configurazione e riallinea la UI; la conferma e' a carico del chiamante
async function commitConfig(vals) {
  const cfg = await post("/api/config", vals);
  state.config = cfg;
  state.checks = null; state.checksPending = true; state.backups = null;
  loadChecks(true);
  await loadStatus();
  return cfg;
}

const lastBucketNote = (oldB) => oldB
  ? ["I salvataggi vecchi restano dove sono: " + oldB.replace("gs://", "") + ".", "Il prossimo salvataggio ricarica tutto nel nuovo spazio, quindi può durare di più.", "Il comando per il PC nuovo cambia: lo trovi in «Nuovo PC»."]
  : ["Il primo salvataggio carica tutto nel nuovo spazio.", "Il comando per il PC nuovo si aggiorna da solo: lo trovi in «Nuovo PC»."];

/* procedura a passi per cambiare spazio: Scegli, Verifica, Conferma */
async function changeStorageFlow() {
  const cfg = state.config;
  const w = { step: 1, buckets: null, loadErr: "", choice: "", newName: "", nameErr: "", verify: null, busy: "", error: "", doneCfg: null };
  const stepsBar = () => h("div", { class: "dlg-steps", "aria-label": "Passo " + w.step + " di 3" }, ["Scegli", "Verifica", "Conferma"].map((t, i) =>
    h("span", { class: w.step === i + 1 ? "on" : "", text: (i + 1) + " " + t })));
  const cancel = { label: "Annulla", onClick: dlgClose };
  const suggest = () => {
    const base = "bekky-" + (state.status.host || "pc").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
    let n = base.slice(0, 55), i = 2;
    while ((w.buckets || []).includes(n)) n = base.slice(0, 52) + "-" + i++;
    return n;
  };
  const chosenBucket = () => "gs://" + (w.choice === "__new" ? w.newName : w.choice);
  const verify = async () => {
    w.step = 2; w.verify = null; w.error = ""; w.busy = "Controllo l'accesso…"; draw();
    try { w.verify = await post("/api/config/verify", { bucket: chosenBucket(), account: cfg.account }); }
    catch (e) { w.verify = { ok: false, error: e.message }; }
    w.busy = ""; draw();
  };
  const proceed = async () => {
    if (w.choice === "__new") {
      const p = nameProblem(w.newName, w.buckets);
      if (p) { w.nameErr = p; draw(); return; }
      w.step = 2; w.busy = "Creo il nuovo spazio… Ci vuole qualche secondo."; w.error = ""; draw();
      try { await post("/api/buckets", { name: w.newName }); }
      catch (e) { w.busy = ""; w.step = 1; w.nameErr = (e.fields && e.fields.name) || e.message; if (e.status === 409 || e.status === 400) { /* nome da cambiare */ } draw(); return; }
      w.buckets = (w.buckets || []).concat(w.newName).sort();
      w.choice = w.newName; w.newName = "";
    }
    verify();
  };
  const save = async () => {
    w.busy = "Salvo…"; w.error = ""; draw();
    try { w.doneCfg = await commitConfig({ bucket: chosenBucket(), project: cfg.project, account: cfg.account }); w.step = 4; }
    catch (e) { w.error = e.message; }
    w.busy = ""; draw();
  };
  function draw() {
    if (w.step === 1) {
      let body;
      if (w.loadErr) body = [h("p", { class: "error", style: "color:var(--err)", text: w.loadErr }),
        h("p", { text: "Puoi riprovare, oppure scrivere l'indirizzo a mano nelle impostazioni avanzate." })];
      else if (!w.buckets) body = [h("p", { text: "Cerco i tuoi spazi…" }), h("div", { class: "skel", style: "width:70%" }), h("div", { class: "skel", style: "width:55%" })];
      else {
        const cur = cfg.bucket.replace("gs://", "");
        const opt = (value, name, sub, isCur) => h("label", { class: "choice" },
          h("input", { type: "radio", name: "sp", value, checked: w.choice === value, "data-autofocus": w.choice === value || (!w.choice && value === w.buckets[0]),
            onchange: () => { w.choice = value; w.nameErr = ""; if (value === "__new" && !w.newName) w.newName = suggest(); draw(); } }),
          h("span", { class: "nm" }, name, sub ? h("small", { text: sub }) : null), isCur ? badge("info", "check", "In uso") : null);
        body = [h("fieldset", { class: "choices" }, h("legend", { class: "sr-only", text: "Dove vuoi salvare?" }),
          w.buckets.map((b) => opt(b, b, null, b === cur)), opt("__new", "Crea un nuovo spazio", "Un posto nuovo e vuoto, solo per te", false)),
          w.choice === "__new" ? h("div", { class: "field" },
            h("label", { for: "nn", text: "Nome del nuovo spazio" }),
            h("div", { class: "affix" }, h("span", { class: "pre", "aria-hidden": "true", text: "gs://" }),
              h("input", { class: "input mono", id: "nn", value: w.newName, autocomplete: "off", spellcheck: "false", "data-autofocus": "",
                "aria-invalid": w.nameErr ? "true" : "false", "aria-describedby": "nn-h nn-e",
                oninput: (e) => { w.newName = e.target.value.trim(); w.nameErr = ""; const er = $("nn-e"); er.hidden = true; $("dlg-actions").querySelector("button:last-child").disabled = !!nameProblem(w.newName, w.buckets); } })),
            h("p", { class: "help", id: "nn-h", text: "Usa minuscole, numeri e trattini. Il nome deve essere unico su tutto Google Cloud." }),
            h("p", { class: "error", id: "nn-e", hidden: !w.nameErr }, icon("alert"), w.nameErr)) : null];
      }
      const bad = w.choice === "__new" ? !!nameProblem(w.newName, w.buckets) : !w.choice || w.choice === cfg.bucket.replace("gs://", "");
      dlgRender({ title: cfg.bucket ? "Cambia lo spazio di archiviazione" : "Scegli lo spazio di archiviazione", wide: true,
        body: [stepsBar(), h("p", { text: "Dove vuoi che bekky metta i tuoi salvataggi?" }), body],
        actions: w.loadErr ? [cancel, { label: "Riprova", onClick: load }, { label: "Apri le impostazioni avanzate", kind: "primary", onClick: () => { dlgClose(); openAdvanced(); } }]
          : [cancel, { label: "Avanti", kind: "primary", disabled: !w.buckets || bad, onClick: proceed }] });
    } else if (w.step === 2) {
      const v = w.verify;
      let body;
      if (w.busy) body = [h("p", { "aria-busy": "true" }, icon("clock", 18), " " + w.busy)];
      else if (v && v.ok) body = [h("p", {}, badge("ok", "check", "Tutto a posto")), h("p", { text: "Posso usare lo spazio «" + chosenBucket().replace("gs://", "") + "» con il tuo account." })];
      else body = [h("p", {}, badge("err", "x", "Non funziona")), h("p", { text: v ? v.error : "" }), h("p", { text: verifySolution(v ? v.error : "") })];
      dlgRender({ title: "Controllo dell'accesso", wide: true, body: [stepsBar(), body],
        actions: w.busy ? [] : v && v.ok ? [{ label: "Indietro", onClick: () => { w.step = 1; draw(); } }, { label: "Avanti", kind: "primary", onClick: () => { w.step = 3; draw(); } }]
          : [{ label: "Scegli un altro spazio", onClick: () => { w.step = 1; draw(); } }, { label: "Riprova", kind: "primary", onClick: verify }] });
    } else if (w.step === 3) {
      dlgRender({ title: "Conferma", wide: true,
        body: [stepsBar(), h("p", {}, "Stai per usare lo spazio ", h("strong", { text: chosenBucket().replace("gs://", "") }), "."),
          h("ul", {}, lastBucketNote(cfg.bucket).map((t) => h("li", { text: t }))),
          w.error ? h("p", { style: "color:var(--err)", text: w.error }) : null],
        actions: w.busy ? [] : [{ label: "Indietro", onClick: () => { w.step = 2; draw(); } }, { label: "Usa questo spazio", kind: "primary", onClick: save }] });
    } else {
      const nc = w.doneCfg;
      dlgRender({ title: "Spazio cambiato", wide: true,
        body: [h("p", {}, badge("ok", "check", "Fatto"), " Da ora i salvataggi vanno in ", h("strong", { text: nc.bucket.replace("gs://", "") }), "."),
          h("p", { text: "Ti conviene fare subito un salvataggio rapido, così il nuovo spazio non resta vuoto." }),
          h("p", { class: "small", text: "Per il PC nuovo, usa questo comando:" }), cmdBlock(newPcCommand(nc))],
        actions: [{ label: "Chiudi", onClick: dlgClose }, { label: "Salva ora", kind: "primary", onClick: () => { dlgClose(); startJob("quick-push"); } }] });
    }
  }
  async function load() {
    w.loadErr = ""; w.buckets = null; draw();
    try { w.buckets = (await api("/api/buckets")).buckets; if (cfg.bucket && !w.choice) w.choice = ""; }
    catch (e) { w.loadErr = "Non riesco a leggere l'elenco degli spazi. " + e.message; }
    draw();
  }
  draw(); load();
}

function openAdvanced() {
  state.open["avanzate"] = true;
  const d = $("adv"); if (d) { d.open = true; const i = $("f-bucket"); if (i) { i.scrollIntoView(); i.focus(); } }
}

function storageStatus() {
  const cfg = state.config, c = state.checks;
  if (!cfg) return h("div", { class: "skel", style: "width:60%" });
  const name = cfg.bucket ? cfg.bucket.replace("gs://", "") : "";
  const conn = !cfg.bucket ? badge("warn", "alert", "Non scelto") : !c ? badge("", "clock", "Controllo…")
    : c.bucket.ok ? badge("ok", "check", "Raggiungibile") : badge("err", "x", "Non raggiungibile");
  const acc = !c ? badge("", "clock", "Controllo…") : c.gcloud.ok ? badge("ok", "check", "Accesso valido") : badge("err", "x", "Accesso scaduto");
  return [h("dl", { class: "kv" },
    h("div", {}, h("dt", { text: "Spazio in uso" }), h("dd", {}, name ? [h("strong", { text: name }), " ", conn, h("div", { class: "faint small mono", text: cfg.bucket })] : [conn, h("p", { class: "muted small", text: "Scegli dove mettere i salvataggi." })])),
    h("div", {}, h("dt", { text: "Account Google" }), h("dd", {}, cfg.account ? [cfg.account, " ", acc] : h("span", { class: "muted", text: "Quello attivo sul PC" }))),
    h("div", {}, h("dt", { text: "Progetto" }), h("dd", { text: cfg.project || "Non indicato" }))),
    h("div", { class: "btn-row", style: "margin-top:20px" }, btn(cfg.bucket ? "Cambia spazio" : "Scegli lo spazio", { kind: "primary", k: "change-storage", onClick: changeStorageFlow }))];
}

function advancedForm() {
  const cfg = state.config;
  const F = {};
  const field = (key, label, help, ph, mono) => {
    const input = h("input", { class: "input" + (mono ? " mono" : ""), id: "f-" + key, value: cfg[key] || "", autocomplete: "off", spellcheck: "false", inputmode: key === "account" ? "email" : "text",
      placeholder: ph, "aria-describedby": "f-" + key + "-h f-" + key + "-e", "aria-invalid": "false" });
    const err = h("p", { class: "error", id: "f-" + key + "-e", hidden: true });
    F[key] = { input, err };
    return h("div", { class: "field" }, h("label", { for: "f-" + key, text: label }), input, h("p", { class: "help", id: "f-" + key + "-h", text: help }), err);
  };
  const vals = () => ({ bucket: F.bucket.input.value.trim(), project: F.project.input.value.trim(), account: F.account.input.value.trim() });
  const dirty = () => { const v = vals(); return ["bucket", "project", "account"].some((k) => v[k] !== (state.config[k] || "")); };
  const showErrs = (errs) => {
    let first = null;
    for (const k of ["bucket", "project", "account"]) {
      const e = errs[k];
      F[k].input.setAttribute("aria-invalid", e ? "true" : "false");
      F[k].err.hidden = !e;
      F[k].err.replaceChildren(...(e ? [icon("alert"), e] : []));
      if (e && !first) first = F[k].input;
    }
    if (first) first.focus();
    return !first;
  };
  const result = h("div", { "aria-live": "polite", class: "small" });
  const save = btn("Salva", { kind: "primary" });
  const refreshSave = () => {
    const d = dirty();
    save.disabled = !d;
    why.textContent = d ? "" : "Nessuna modifica da salvare.";
    why.hidden = d;
  };
  const why = h("span", { class: "why" });
  const verifyBtn = btn("Verifica accesso", { onClick: async (e, b) => {
    const v = vals(), errs = configProblems(v); delete errs.project;
    if (!showErrs(errs)) return;
    b.disabled = true; result.replaceChildren(h("span", { class: "why" }, icon("clock", 16), "Controllo…"));
    try {
      const r = await post("/api/config/verify", { bucket: v.bucket, account: v.account });
      result.replaceChildren(r.ok ? badge("ok", "check", "Posso usare questo spazio con questo account.") : [badge("err", "x", r.error), h("p", { class: "muted", text: verifySolution(r.error) })]);
    } catch (er) { result.replaceChildren(badge("err", "x", er.message)); }
    b.disabled = false;
  } });
  save.addEventListener("click", async () => {
    const v = vals();
    if (!showErrs(configProblems(v))) return;
    if (v.bucket !== state.config.bucket) {
      const ok = await confirmDialog({ title: "Cambiare lo spazio di archiviazione?",
        body: [h("ul", {}, lastBucketNote(state.config.bucket).map((t) => h("li", { text: t })))], ok: "Usa questo spazio" });
      if (!ok) return;
    }
    save.disabled = true;
    try { await commitConfig(v); toast("Impostazioni salvate."); showErrs({}); result.replaceChildren(); }
    catch (e) { if (e.fields) showErrs(e.fields); else showError("Non sono riuscito a salvare: " + e.message, null); }
    refreshSave();
  });
  const det = h("details", { class: "tech", id: "adv" }, h("summary", {}, "Impostazioni avanzate", icon("chevron")),
    h("div", { style: "margin-top:12px" },
      h("p", { class: "muted small", style: "margin-bottom:20px", text: "Per chi conosce già l'indirizzo dello spazio. Di solito basta «Cambia spazio»." }),
      field("bucket", "Indirizzo dello spazio", "Inizia con gs://. Esempio: gs://il-mio-spazio.", "gs://il-mio-spazio", true),
      field("project", "Progetto Google Cloud", "Serve per elencare e creare spazi. Puoi lasciarlo com'è.", "nome-del-progetto", true),
      field("account", "Account Google", "L'email con cui accedi a Google Cloud.", "nome@azienda.it", false),
      h("div", { class: "btn-row", style: "margin-top:20px" }, verifyBtn, save, why), h("div", { style: "margin-top:12px" }, result),
      h("pre", { class: "techbox", text: "File di configurazione: " + cfg.configPath + "\nCopia precedente: " + cfg.configPath + ".bak" })));
  for (const k of ["bucket", "project", "account"]) F[k].input.addEventListener("input", () => { result.replaceChildren(); refreshSave(); });
  if (state.open.avanzate) det.open = true;
  det.addEventListener("toggle", () => { state.open.avanzate = det.open; });
  refreshSave();
  return det;
}

function passphrasePanel() {
  const s = state.status, cfg = state.config, ok = s.checks.passphrase;
  const op = cfg && cfg.opRef ? friendlyOpRef(cfg.opRef) : "";
  const createCmd = "bash -c 'umask 077; mkdir -p ~/.config/confsync; read -rsp \"Scegli la passphrase: \" p; printf \"%s\" \"$p\" > ~/.config/confsync/passphrase; echo'";
  return h("section", { class: "panel", id: "sub-passphrase", tabindex: "-1", "aria-labelledby": "h-pass" },
    h("div", { class: "panel-head" }, h("div", { class: "btn-row" }, h("h2", { id: "h-pass", text: "Passphrase" }), ok ? badge("ok", "check", "Presente") : badge("err", "x", "Manca")),
      h("p", { text: "È la chiave che cifra i tuoi salvataggi: senza, non si recuperano." })),
    h("div", { class: "note", style: "margin-bottom:20px" }, icon("key"), h("p", { text: "Conservala in 1Password. Senza, i salvataggi non si possono recuperare. bekky non la mostra mai, nemmeno qui." })),
    h("dl", { class: "kv" },
      h("div", {}, h("dt", { text: "Su questo PC" }), h("dd", {}, h("code", { text: cfg ? cfg.passphrasePath : "~/.config/confsync/passphrase" }))),
      h("div", {}, h("dt", { text: "Copia di sicurezza" }), h("dd", {}, op ? op : h("span", { class: "muted", text: "Non indicata. Conservala in 1Password o in un altro gestore di password." })))),
    ok ? null : [h("hr", { class: "rule" }), h("h3", { class: "small", text: "Come crearla" }),
      h("ol", { class: "steps", style: "margin-top:16px" },
        h("li", {}, h("h3", { text: "Apri il terminale" }), h("div", { class: "body" }, h("p", { text: "Cerca «Terminale» tra le app del tuo PC." }))),
        h("li", {}, h("h3", { text: "Incolla questo comando e scrivi la passphrase" }), h("div", { class: "body" }, cmdBlock(createCmd), h("p", { class: "small", text: "Mentre scrivi non compare nulla: è normale. Premi Invio alla fine." }))),
        h("li", {}, h("h3", { text: "Salvala anche in 1Password" }), h("div", { class: "body" }, h("p", { text: "Così potrai ritrovarla su un PC nuovo." }),
          h("div", { class: "btn-row" }, btn("Ho fatto, ricontrolla", { kind: "primary", icon: "refresh", k: "pass-recheck", onClick: async () => { await loadStatus(); toast(state.status.checks.passphrase ? "Passphrase trovata." : "Non la trovo ancora. Controlla di aver premuto Invio.", state.status.checks.passphrase ? "ok" : "err"); } })))))]);
}

const THEMES = [["light", "Chiaro"], ["dark", "Scuro"], ["auto", "Automatico"]];
function currentTheme() { try { const t = localStorage.getItem("bekky-theme"); return t === "light" || t === "dark" ? t : "auto"; } catch (e) { return "auto"; } }
function setTheme(t) {
  try { if (t === "auto") localStorage.removeItem("bekky-theme"); else localStorage.setItem("bekky-theme", t); } catch (e) { /* tema non salvato */ }
  if (t === "auto") document.documentElement.removeAttribute("data-theme"); else document.documentElement.setAttribute("data-theme", t);
}

const SettingsView = {
  title: "Impostazioni", sub: "Dove finiscono i salvataggi, la passphrase e l'aspetto.",
  mount(root) {
    this.r = { storage: h("div"), adv: h("div"), pass: h("div") };
    const cur = currentTheme();
    this.advBuilt = false;
    root.append(h("div", { class: "stack" },
      h("section", { class: "panel", id: "sub-spazio", tabindex: "-1", "aria-labelledby": "h-store" },
        h("div", { class: "panel-head" }, h("h2", { id: "h-store", text: "Spazio di archiviazione" }), h("p", { text: "È il posto su Google Cloud dove vengono messi i tuoi salvataggi." })),
        this.r.storage, this.r.adv),
      this.r.pass,
      h("section", { class: "panel", "aria-labelledby": "h-look" },
        panelHead("Aspetto", "Come appare bekky su questo schermo."),
        h("div", { class: "seg", role: "radiogroup", "aria-label": "Aspetto" }, THEMES.map(([v, l]) => h("label", {},
          h("input", { type: "radio", name: "tema", value: v, checked: cur === v, onchange: () => setTheme(v) }), h("span", { text: l })))))));
  },
  update() {
    paint(this.r.storage, storageStatus);
    if (state.config && !this.advBuilt) { this.r.adv.replaceChildren(advancedForm()); this.advBuilt = true; }
    if (state.config && this.advBuilt && this.cfgSig !== JSON.stringify(state.config)) {
      if (this.cfgSig) this.r.adv.replaceChildren(advancedForm());
      this.cfgSig = JSON.stringify(state.config);
    }
    paint(this.r.pass, passphrasePanel);
  },
};

/* --- Registro --- */

const LOG_OPTIONS = [
  ["job", "Ultima operazione lanciata da qui"], ["quick", "Salvataggio rapido (alla chiusura di Claude)"],
  ["full", "Salvataggio completo (settimanale)"], ["tools", "Installazione degli strumenti (PC nuovo)"], ["repos", "Download delle repo (PC nuovo)"],
];
async function loadLog() {
  const name = $("log-name").value;
  try {
    const r = await api("/api/log?name=" + encodeURIComponent(name));
    const text = r.exists ? (r.lines.join("\n") || "(il registro è vuoto)") : "Nessun registro: questa operazione non è mai partita su questo PC.";
    const v = $("logview");
    const atEnd = v.scrollTop + v.clientHeight >= v.scrollHeight - 8;
    if (v.textContent !== text) { v.textContent = text; if (atEnd) v.scrollTop = v.scrollHeight; }
  } catch (e) { showError("Non riesco a leggere il registro: " + e.message, loadLog); }
}
async function loadBackups() {
  const box = $("backups-box");
  box.replaceChildren(h("p", { class: "muted", text: "Leggo l'elenco…" }), h("div", { class: "skel", style: "width:60%" }));
  try {
    const r = await api("/api/backups");
    clearError();
    state.backups = r.backups;
    drawBackups();
  } catch (e) {
    box.replaceChildren(emptyState("alert", "Non sono riuscito a leggere l'elenco", e.message, btn("Riprova", { kind: "primary", icon: "refresh", onClick: loadBackups })));
  }
}
function drawBackups() {
  const list = state.backups, box = $("backups-box");
  if (!list.length) { box.replaceChildren(emptyState("cloud", "Nessun salvataggio completo", "Non ce n'è ancora nessuno per questo PC.", btn("Aggiorna", { icon: "refresh", onClick: loadBackups }))); return; }
  box.replaceChildren(
    h("div", { class: "btn-row" }, h("p", { class: "muted small", text: list.length + (list.length === 1 ? " salvataggio completo" : " salvataggi completi") + " per questo PC." }), btn("Aggiorna", { sm: true, icon: "refresh", onClick: loadBackups })),
    h("table", { class: "tbl", style: "margin-top:8px" },
      h("thead", {}, h("tr", {}, h("th", { scope: "col", text: "Data" }), h("th", { scope: "col", class: "r", text: "Peso" }))),
      h("tbody", {}, list.map((x) => { const d = parseTs(x.ts); return h("tr", {}, h("td", { title: absTime(d), text: shortDate(d) + " · " + ago(d, new Date()) }), h("td", { class: "r", text: mb(x.bytes) })); }))));
}

const LogView = {
  title: "Registro", sub: "Il racconto dettagliato di cosa è successo. Serve se qualcosa non funziona.",
  mount(root) {
    const sel = h("select", { class: "input", id: "log-name", onchange: loadLog }, LOG_OPTIONS.map(([v, l]) => h("option", { value: v, text: l })));
    root.append(h("div", { class: "stack" },
      h("section", { class: "panel" },
        panelHead("Registro delle operazioni"),
        h("div", { class: "toolbar" }, h("div", { class: "field" }, h("label", { for: "log-name", text: "Quale registro vuoi vedere?" }), sel),
          btn("Aggiorna", { icon: "refresh", onClick: loadLog }), copyButton("Copia", () => $("logview").textContent)),
        h("pre", { class: "logview", id: "logview", role: "log", tabindex: "0", "aria-label": "Contenuto del registro" })),
      h("section", { class: "panel" },
        panelHead("Salvataggi completi nello spazio di archiviazione", "L'elenco di quelli già caricati su Google Cloud."),
        h("div", { id: "backups-box" }))));
    if (state.backups) drawBackups();
    else $("backups-box").replaceChildren(emptyState("cloud", "Vuoi vedere l'elenco?", "Lo leggo da Google Cloud: ci vuole qualche secondo.", btn("Carica l'elenco", { kind: "primary", onClick: loadBackups })));
    loadLog();
  },
  update() { if (anyBusy() && $("log-name")) loadLog(); },
};

/* ---------- 9. Router, polling, avvio ---------- */

const ROUTES = {
  panoramica: { view: OverviewView, nav: "Panoramica", short: "Panoramica", ic: "home" },
  salvato: { view: SavedView, nav: "Cosa viene salvato", short: "Salvato", ic: "folder" },
  "nuovo-pc": { view: NewPcView, nav: "Nuovo PC", short: "Nuovo PC", ic: "laptop" },
  impostazioni: { view: SettingsView, nav: "Impostazioni", short: "Impost.", ic: "sliders" },
  registro: { view: LogView, nav: "Registro", short: "Registro", ic: "list" },
};

function buildNav() {
  $("nav").replaceChildren(...Object.entries(ROUTES).map(([id, r]) => {
    const a = h("a", { href: "#/" + id, "data-route": id }, icon(r.ic), h("span", { class: "full", text: r.nav }), h("span", { class: "short", text: r.short }));
    a.setAttribute("aria-label", r.nav);
    return a;
  }));
}

function parseHash() {
  const raw = location.hash.replace(/^#\/?/, "");
  const [route, sub] = raw.split("/");
  if (route === "pc-nuovo") return { route: "nuovo-pc", sub: "" };
  return { route: ROUTES[route] ? route : "panoramica", sub: sub || "" };
}

function route(first) {
  const { route: id, sub } = parseHash();
  const r = ROUTES[id];
  state.route = id;
  document.querySelectorAll("#nav a").forEach((a) => {
    if (a.dataset.route === id) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
  });
  $("view-title").textContent = r.view.title;
  $("view-sub").textContent = r.view.sub;
  document.title = r.view.title + " · bekky";
  const root = $("view");
  root.replaceChildren();
  r.view.mount(root);
  if (state.status) r.view.update();
  window.scrollTo(0, 0);
  const target = sub && $("sub-" + sub);
  if (target) { target.scrollIntoView(); target.focus(); }
  else if (!first) $("view-title").focus();
}
window.addEventListener("hashchange", () => route(false));

function renderAll() {
  const s = state.status;
  const name = s.host + (s.mock ? " · prova: " + s.mock : "");
  $("pc-name").textContent = name;
  $("pc-mobile").textContent = name;
  ROUTES[state.route].view.update();
}

function notifyJobEnds(s) {
  const prev = state.prevJobs;
  if (prev) {
    for (const [n, j] of Object.entries(s.jobs || {})) {
      if (j.running || !(prev[n] && prev[n].running)) continue;
      const t = JOBS[n];
      if (t) toast(j.rc === 0 ? t.ok : t.fail, j.rc === 0 ? "ok" : "err");
    }
  }
  state.prevJobs = JSON.parse(JSON.stringify(s.jobs || {}));
}

let wasBusy = false, timer = null;
async function loadJobLogs() {
  for (const [name, j] of Object.entries(state.status.jobs || {})) {
    if (!j.running) continue;
    try { state.logs[name] = (await api("/api/log?name=job-" + name)).lines; } catch (e) { /* il prossimo giro riprova */ }
  }
}
async function loadStatus() {
  if (!TOKEN) { showError("Manca il codice di accesso. Apri la pagina dall'indirizzo che compare nel terminale quando lanci bekky.", null); return; }
  try {
    const s = await api("/api/status");
    state.status = s;
    const busyNow = anyBusy();
    if (busyNow) await loadJobLogs();
    notifyJobEnds(s);
    clearError();
    renderAll();
    if (wasBusy && !busyNow) { loadChecks(); state.backups = null; }
    wasBusy = busyNow;
    schedule(busyNow ? 1000 : 15000);
  } catch (e) {
    showError(e.message, loadStatus);
    schedule(15000);
  }
}
async function loadChecks(fresh) {
  try { state.checks = await api("/api/checks" + (fresh ? "?fresh=1" : "")); }
  catch (e) { state.checks = null; showError("Non riesco a controllare l'accesso a Google Cloud: " + e.message, () => loadChecks(true)); }
  state.checksPending = false;
  if (state.status) renderAll();
}
async function loadConfig() {
  try { state.config = await api("/api/config"); } catch (e) { showError("Non riesco a leggere le impostazioni: " + e.message, loadConfig); }
  if (state.status) renderAll();
}
function schedule(ms) {
  clearTimeout(timer);
  if (document.hidden) return;
  timer = setTimeout(loadStatus, ms);
}
document.addEventListener("visibilitychange", () => { if (document.hidden) clearTimeout(timer); else loadStatus(); });

buildNav();
route(true);
loadConfig();
loadStatus();
loadChecks();
