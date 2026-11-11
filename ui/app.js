"use strict";

const NF1 = new Intl.NumberFormat("it-IT", { maximumFractionDigits: 1, minimumFractionDigits: 1 });
const NF0 = new Intl.NumberFormat("it-IT");
const DAY = 86400000;
const STALE_DAYS = 8;

let TOKEN = "";
try {
  const u = new URL(location.href);
  TOKEN = u.searchParams.get("t") || sessionStorage.getItem("bekky-t") || "";
  if (u.searchParams.has("t")) {
    try { sessionStorage.setItem("bekky-t", TOKEN); } catch (e) { /* nessun storage: il token resta in memoria */ }
    u.searchParams.delete("t");
    history.replaceState(null, "", u.pathname + u.search);
  }
} catch (e) { /* URL non leggibile */ }

const $ = (id) => document.getElementById(id);
const state = { status: null, checks: null, checksPending: true, core: null, coreAll: false,
  logs: {}, lastError: null };

/* ---------- utilità DOM ---------- */

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
  for (const kid of kids.flat()) {
    if (kid == null || kid === false) continue;
    el.append(kid.nodeType ? kid : document.createTextNode(kid));
  }
  return el;
}

// Testo con `comandi` tra backtick resi come <code>
function rich(text) {
  const out = [];
  text.split("`").forEach((part, i) => { if (part) out.push(i % 2 ? h("code", { text: part }) : part); });
  return out;
}

const SVG = "http://www.w3.org/2000/svg";
function mark(kind) {
  const s = document.createElementNS(SVG, "svg");
  s.setAttribute("viewBox", "0 0 10 10");
  s.setAttribute("aria-hidden", "true");
  const el = (n, a) => { const e = document.createElementNS(SVG, n); for (const k in a) e.setAttribute(k, a[k]); s.append(e); };
  if (kind === "ok") el("rect", { x: 0, y: 0, width: 10, height: 10, rx: 1, class: "s-ok" });
  else if (kind === "dedup") el("rect", { x: 1, y: 1, width: 8, height: 8, rx: 1, class: "s-dedup" });
  else if (kind === "fail") el("path", { d: "M1 1L9 9M9 1L1 9", class: "s-fail" });
  else el("path", { d: "M2 5H8", class: "s-none" });
  return s;
}

/* ---------- formati ---------- */

function parseTs(ts) {
  if (!ts) return null;
  const m = /^(\d{4})-?(\d\d)-?(\d\d)T(\d\d):?(\d\d):?(\d\d)Z$/.exec(ts);
  return m ? new Date(Date.UTC(+m[1], m[2] - 1, +m[3], +m[4], +m[5], +m[6])) : null;
}
function ago(d, now) {
  const s = Math.max(0, Math.round((now - d) / 1000));
  if (s < 60) return "adesso";
  const m = Math.round(s / 60);
  if (m < 60) return m + " min fa";
  const hh = Math.round(m / 60);
  if (hh < 24) return hh + (hh === 1 ? " ora fa" : " ore fa");
  const dd = Math.floor(s / 86400);
  return dd + (dd === 1 ? " giorno fa" : " giorni fa");
}
const absTime = (d) => d.toLocaleString("it-IT", { dateStyle: "full", timeStyle: "short" });
function mb(b) { return b >= 1e6 ? NF1.format(b / 1e6) + " MB" : b >= 1e3 ? NF1.format(b / 1e3) + " kB" : NF0.format(b) + " B"; }
const WORD = { upload: "Caricato", dedup: "Nessuna modifica", fail: "Fallito" };
function mmss(sec) { sec = Math.max(0, sec); return Math.floor(sec / 60) + ":" + String(sec % 60).padStart(2, "0"); }

/* ---------- rete ---------- */

async function api(path, opts) {
  const o = Object.assign({ headers: {} }, opts);
  o.headers["X-Bekky-Token"] = TOKEN;
  let r;
  try { r = await fetch(path, o); } catch (e) { throw new Error("Il server bekky non risponde."); }
  let body = null;
  try { body = await r.json(); } catch (e) { /* corpo non JSON */ }
  if (!r.ok) {
    const err = new Error((body && body.error) || ("Errore " + r.status));
    err.status = r.status;
    throw err;
  }
  return body;
}

function showError(msg, retry) {
  state.lastError = retry;
  $("errtext").textContent = msg;
  $("errbar").hidden = false;
}
function clearError() { $("errbar").hidden = true; state.lastError = null; }
$("errretry").addEventListener("click", () => { const f = state.lastError; clearError(); if (f) f(); });

/* ---------- stato ---------- */

function problem(s, c) {
  const now = new Date(s.now);
  const q = s.quick.last, f = s.full.last;
  const act = (label, name, primary) => ({ label, action: name, primary });
  if (!s.checks.passphrase) {
    return { level: "err", tag: "Errore",
      text: "Manca la passphrase. Scrivila in `~/.config/confsync/passphrase` e dai `chmod 600`.",
      copy: "~/.config/confsync/passphrase", copyLabel: "Copia il path" };
  }
  if (c && !c.gcloud.ok) {
    const acct = c.gcloud.account ? " --account=" + c.gcloud.account : "";
    const cmd = "gcloud auth login" + acct;
    return { level: "err", tag: "Errore", text: "Login gcloud scaduto. Esegui `" + cmd + "` nel terminale.",
      copy: cmd, copyLabel: "Copia il comando" };
  }
  if (c && c.gcloud.ok && !c.bucket.ok) {
    return { level: "err", tag: "Errore", text: "Il bucket non risponde. Controlla la rete e i permessi dell'account." };
  }
  if (q && q.result === "fail") {
    return { level: "err", tag: "Errore", text: "Ultimo push del core fallito " + ago(parseTs(q.ts), now) + ". Guarda il log, poi riprova.",
      actions: [act("Push ora", "quick-push", true)] };
  }
  if (f && f.result === "fail") {
    return { level: "err", tag: "Errore", text: "Ultimo backup completo fallito " + ago(parseTs(f.ts), now) + ". Guarda il log, poi riprova.",
      actions: [act("Backup ora", "full-backup", true)] };
  }
  if (f && f.result !== "fail") {
    const days = Math.floor((now - parseTs(f.ts)) / DAY);
    if (days > STALE_DAYS) {
      return { level: "warn", tag: "Attenzione", text: "Il backup completo ha " + days + " giorni. Lancialo ora.",
        actions: [act("Backup ora", "full-backup", true)] };
    }
  }
  if (!s.checks.hook) {
    return { level: "warn", tag: "Attenzione", text: "L'hook di fine sessione non è installato. Il core non parte da solo.",
      actions: [act("Installa hook", "hook-install", true)] };
  }
  const r = s.restore;
  if (r) {
    const tf = r.tools.filter((t) => t.status === "FAIL").length, rf = r.reposFailed.length;
    if (tf || rf) {
      const parts = [];
      if (tf) parts.push(tf + " tool");
      if (rf) parts.push(rf + " repo");
      return { level: "warn", tag: "Attenzione", text: "Dopo il ripristino non sono andati a buon fine: " + parts.join(" e ") + ".",
        link: { label: "Vai al ripristino", href: "#pc-nuovo" } };
    }
  }
  if (!q && !f) {
    return { level: "warn", tag: "Attenzione", text: "Nessun backup registrato su questo PC. Fai il primo push.",
      actions: [act("Push ora", "quick-push", true)] };
  }
  if (state.checksPending && !c) return { level: "wait", tag: "Attendi", text: "Controllo il login gcloud e il bucket." };
  const parts = [q ? "Core pushato " + ago(parseTs(q.ts), now) : "Core mai pushato da qui",
                 f ? "backup completo " + ago(parseTs(f.ts), now) : "backup completo mai registrato"];
  return { level: "ok", tag: "Ok", text: "Tutto protetto. " + parts[0] + ", " + parts[1] + "." };
}

function renderStatusLine() {
  const s = state.status;
  if (!s) return;
  const p = problem(s, state.checks);
  const box = $("status");
  box.dataset.level = p.level;
  $("status-tag").textContent = p.tag;
  $("status-text").replaceChildren(...rich(p.text));
  const acts = [];
  if (p.copy) acts.push(copyButton(p.copyLabel, () => p.copy, true));
  for (const a of p.actions || []) acts.push(actionButton(a.label, a.action, a.primary));
  if (p.link) acts.push(h("button", { type: "button", onclick: () => { location.hash = p.link.href; $("pc-nuovo").scrollIntoView(); } }, p.link.label));
  $("status-actions").replaceChildren(...acts);
}

function copyButton(label, getText, primary) {
  const b = h("button", { type: "button", class: primary ? "primary" : "" }, label);
  b.addEventListener("click", async () => {
    const text = getText();
    try { await navigator.clipboard.writeText(text); }
    catch (e) {
      const ta = h("textarea", { "aria-hidden": "true", style: "position:fixed;opacity:0" });
      ta.value = text; document.body.append(ta); ta.select();
      try { document.execCommand("copy"); } catch (e2) { /* niente da fare */ }
      ta.remove();
    }
    b.textContent = "Copiato";
    setTimeout(() => { b.textContent = label; }, 1600);
  });
  return b;
}

/* ---------- azioni ---------- */

const JOB_LABEL = { "quick-push": "Push", "full-backup": "Backup", "hook-install": "Installazione", "hook-uninstall": "Rimozione",
  "tools-retry": "Riprova", "repos-retry": "Riprova" };

function jobRunning(name) {
  const j = state.status && state.status.jobs && state.status.jobs[name];
  return !!(j && j.running);
}
function elapsed(name) {
  const j = state.status.jobs[name];
  const t0 = j && parseTs(j.startedAt);
  return t0 ? mmss(Math.round((Date.now() - t0.getTime()) / 1000)) : "0:00";
}

function actionButton(label, name, primary, disabledReason) {
  if (jobRunning(name)) return h("span", { class: "busy mono", "data-job": name }, "In corso · " + elapsed(name));
  const b = h("button", { type: "button", class: primary ? "primary" : "" }, label);
  if (disabledReason) { b.disabled = true; b.title = disabledReason; }
  else b.addEventListener("click", () => runAction(name, b));
  return b;
}

async function runAction(name, btn) {
  btn.disabled = true;
  try {
    await api("/api/action", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name }) });
    clearError();
  } catch (e) {
    if (e.status !== 409) showError("Azione non partita: " + e.message, () => runAction(name, btn));
  }
  await loadStatus();
}

function resultLine(last, now) {
  if (!last) return [h("span", { class: "muted", text: "Mai registrato su questo PC." })];
  const d = parseTs(last.ts);
  const out = [h("span", { class: last.result === "fail" ? "w-fail" : "w-ok", text: WORD[last.result] || last.result }),
    h("span", { class: "mono", title: absTime(d), text: ago(d, now) })];
  if (last.bytes > 0) out.push(h("span", { class: "mono", text: "· " + mb(last.bytes) }));
  return out;
}

function actionRow(title, desc, kind, name, btnLabel, s) {
  const now = new Date(s.now);
  const running = jobRunning(name) || s[kind].running;
  let reason = "";
  if (name === "quick-push" && !s.checks.passphrase) reason = "Manca la passphrase";
  let right;
  if (running && !jobRunning(name)) right = h("span", { class: "busy mono" }, "In corso");
  else right = actionButton(btnLabel, name, true, reason);
  const row = h("div", { class: "arow" },
    h("div", {}, h("div", { class: "arow-name", text: title }), h("div", { class: "arow-desc", text: desc })),
    h("div", { class: "arow-btn" }, right),
    h("div", { class: "arow-res" }, resultLine(s[kind].last, now)));
  if (jobRunning(name)) {
    const lines = state.logs[name] || [];
    row.append(h("pre", { class: "joblog mono", role: "log", "aria-live": "polite", "aria-label": "Log di " + title, text: lines.slice(-8).join("\n") || "Parte…" }));
  }
  return row;
}

function renderActions() {
  const s = state.status;
  $("actions").replaceChildren(
    actionRow("Core (quick)", "Config, memoria di Claude, segreti, inventario dev.", "quick", "quick-push", "Push ora", s),
    actionRow("Backup completo", "Dotfiles, repo, pacchetti. Il cron lo lancia ogni settimana.", "full", "full-backup", "Backup ora", s));
}

/* ---------- striscia 30 giorni ---------- */

function dayKey(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }

function renderStrip() {
  const s = state.status;
  const now = new Date(s.now);
  const days = [];
  for (let i = 29; i >= 0; i--) { const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i); days.push({ d, key: dayKey(d), full: [], quick: [] }); }
  const byKey = Object.fromEntries(days.map((x) => [x.key, x]));
  for (const e of s.history) {
    const t = parseTs(e.ts);
    const slot = t && byKey[dayKey(t)];
    if (slot) slot[e.kind].push(e.result);
  }
  const summarize = (arr) => {
    if (!arr.length) return { kind: "none", text: "nessun backup" };
    const last = arr[arr.length - 1];
    const w = last === "fail" ? "fallito" : last === "dedup" ? "nessuna modifica" : "caricato";
    return { kind: last === "upload" ? "ok" : last, text: (arr.length > 1 ? arr.length + " esecuzioni, ultima: " : "") + w };
  };
  const cells = [h("span", { class: "lab", text: "completo" })];
  const qcells = [h("span", { class: "lab", text: "quick" })];
  const tbody = $("strip-table").tBodies[0];
  tbody.replaceChildren();
  for (const x of days) {
    const f = summarize(x.full), q = summarize(x.quick);
    const name = x.d.toLocaleDateString("it-IT", { weekday: "long", day: "numeric", month: "long" });
    const label = name + ". Completo: " + f.text + ". Quick: " + q.text + ".";
    const today = x.key === dayKey(now);
    cells.push(h("span", { class: "day" + (today ? " today" : ""), title: label, "aria-hidden": "true" }, mark(f.kind)));
    qcells.push(h("span", { class: "day" + (today ? " today" : ""), title: label, "aria-hidden": "true" }, mark(q.kind)));
    tbody.append(h("tr", {}, h("th", { scope: "row", text: name }), h("td", { text: f.text }), h("td", { text: q.text })));
  }
  $("strip").replaceChildren(...cells, ...qcells);
  if (!$("legend").firstChild) {
    $("legend").replaceChildren(
      h("span", {}, mark("ok"), "caricato"), h("span", {}, mark("dedup"), "nessuna modifica"),
      h("span", {}, mark("fail"), "fallito"), h("span", {}, mark("none"), "niente"));
  }
}

/* ---------- automatismi ---------- */

function kvRow(key, valueNodes, actionNode) {
  return h("div", {}, h("dt", { text: key }), h("dd", {}, valueNodes), actionNode || h("span"));
}

function renderAuto() {
  const s = state.status, c = state.checks;
  const rows = [];
  const hook = s.checks.hook;
  rows.push(kvRow("Hook di fine sessione",
    [h("span", { class: hook ? "w-ok" : "w-warn", text: hook ? "Installato" : "Non installato" }),
     h("span", { class: "sub", text: "Dopo ogni sessione di Claude parte il push del core." })],
    hook ? actionButton("Rimuovi", "hook-uninstall", false) : actionButton("Installa", "hook-install", true)));
  const cron = s.checks.cron;
  rows.push(kvRow("Cron settimanale",
    cron.present
      ? [h("span", { class: "w-ok", text: "Attivo" }),
         h("span", { class: "sub mono", text: cron.line }),
         cron.next ? h("span", { class: "sub" }, "Prossima: ", h("span", { class: "mono", text: parseTs(cron.next).toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" }) })) : null]
      : [h("span", { class: "w-warn", text: "Assente" }), h("span", { class: "sub", text: "Nessuna riga bekky-cron.sh nel crontab. Sola lettura." })]));
  if (!c) {
    rows.push(kvRow("Login gcloud", [h("span", { class: "muted", text: "Controllo in corso…" })]));
    rows.push(kvRow("Bucket", [h("span", { class: "muted", text: "Controllo in corso…" })]));
  } else {
    rows.push(kvRow("Login gcloud", c.gcloud.ok
      ? [h("span", { class: "w-ok", text: "Valido" }), c.gcloud.account ? h("span", { class: "sub mono", text: c.gcloud.account }) : null]
      : [h("span", { class: "w-bad", text: "Scaduto o assente" }), h("span", { class: "sub", text: c.gcloud.error || "" })]));
    rows.push(kvRow("Bucket", c.bucket.ok
      ? [h("span", { class: "w-ok", text: "Raggiungibile" })]
      : [h("span", { class: "w-bad", text: "Non raggiungibile" })]));
  }
  rows.push(kvRow("Passphrase", [h("span", { class: s.checks.passphrase ? "w-ok" : "w-bad", text: s.checks.passphrase ? "Presente" : "Manca" }),
    h("span", { class: "sub mono", text: "~/.config/confsync/passphrase" })]));
  $("auto").replaceChildren(...rows);
}

/* ---------- ripristino ---------- */

function renderRestore() {
  const box = $("restore"), r = state.status.restore;
  if (!r) { box.hidden = true; return; }
  box.hidden = false;
  const kids = [h("h3", { text: "Ripristino su questo PC" })];
  const tf = r.tools.filter((t) => t.status === "FAIL").length;
  kids.push(h("p", { class: "muted", text: "Tool installati dopo il restore." }));
  kids.push(h("ul", { class: "rlist" }, r.tools.map((t) => h("li", {},
    h("span", { class: "w mono w-" + (t.status === "FAIL" ? "fail" : t.status === "skip" ? "skip" : "ok"),
      text: t.status === "FAIL" ? "Fallito" : t.status === "skip" ? "Già c'era" : "Installato" }),
    h("span", { class: "mono", text: t.name }),
    t.detail ? h("span", { class: "d mono", text: t.detail }) : null))));
  kids.push(actionButton("Riprova i tool", "tools-retry", false, tf ? "" : "Nessun tool fallito"));
  kids.push(h("p", { class: "muted", style: "margin-top:16px", text: r.reposFailed.length ? "Repo che non si sono clonate." : "Tutte le repo sono state clonate." }));
  if (r.reposFailed.length) {
    kids.push(h("ul", { class: "rlist" }, r.reposFailed.map((x) => h("li", {},
      h("span", { class: "w mono w-fail", text: "Fallita" }), h("span", { class: "mono", text: x.path }),
      x.remote ? h("span", { class: "d mono", text: x.remote }) : null))));
    kids.push(actionButton("Riprova le repo", "repos-retry", false));
  }
  box.replaceChildren(...kids);
}

/* ---------- core ---------- */

function renderCore() {
  const c = state.core;
  if (!c) return;
  $("core-body").hidden = false;
  $("core-sum").textContent = "";
  const q = $("core-filter").value.trim().toLowerCase();
  const all = c.entries.filter((e) => !q || e.path.toLowerCase().includes(q));
  const shown = state.coreAll || q ? all : all.slice(0, 15);
  const max = c.entries.length ? c.entries[0].bytes : 1;
  const list = $("core-list");
  list.replaceChildren(
    h("li", { class: "core-total mono" }, "Totale: " + mb(c.totalBytes) + " in " + NF0.format(c.totalFiles) + " file"),
    ...(shown.length ? shown.map((e) => h("li", {},
      h("span", { class: "p mono", text: e.path }),
      h("span", { class: "track", "aria-hidden": "true" }, h("span", { class: "fill", style: "width:" + Math.max(0.5, (e.bytes / max) * 100) + "%" })),
      h("span", { class: "n mono", text: mb(e.bytes) }),
      h("span", { class: "n files mono", text: NF0.format(e.files) + " file" })))
      : [h("li", { class: "empty", text: "Nessun path corrisponde." })]));
  const more = $("core-more");
  const hidden = all.length - shown.length;
  more.hidden = hidden <= 0;
  more.textContent = "Mostra tutte le voci (" + all.length + ")";
}

async function loadCore() {
  const b = $("core-go");
  b.disabled = true; b.title = "Sto calcolando"; b.textContent = "Calcolo…";
  try {
    state.core = await api("/api/core");
    clearError();
    renderCore();
  } catch (e) { showError("Non riesco a leggere il core: " + e.message, loadCore); }
  b.disabled = false; b.title = ""; b.textContent = "Ricalcola";
}
$("core-go").addEventListener("click", loadCore);
$("core-filter").addEventListener("input", renderCore);
$("core-more").addEventListener("click", () => { state.coreAll = true; renderCore(); });

/* ---------- backup nel bucket e log ---------- */

async function loadBackups() {
  const b = $("backups-go");
  b.disabled = true; b.title = "Sto leggendo il bucket";
  $("backups-note").textContent = "Leggo il bucket…";
  try {
    const r = await api("/api/backups");
    clearError();
    const tb = $("backups-table").tBodies[0];
    tb.replaceChildren(...r.backups.map((x) => {
      const d = parseTs(x.ts);
      return h("tr", {}, h("td", { class: "mono", title: absTime(d), text: d.toLocaleString("it-IT", { dateStyle: "medium", timeStyle: "short" }) + " · " + ago(d, new Date()) }),
        h("td", { class: "num mono", text: mb(x.bytes) }));
    }));
    $("backups-table").hidden = !r.backups.length;
    $("backups-note").textContent = r.backups.length ? r.backups.length + " backup per questo host." : "Nessun backup per questo host.";
  } catch (e) {
    $("backups-note").textContent = "";
    showError("Non riesco a leggere i backup: " + e.message, loadBackups);
  }
  b.disabled = false; b.title = "";
}
$("backups-go").addEventListener("click", loadBackups);
$("d-backups").addEventListener("toggle", () => { if ($("d-backups").open && $("backups-table").hidden && !$("backups-note").textContent) loadBackups(); });

async function loadLog() {
  const name = $("log-name").value;
  try {
    const r = await api("/api/log?name=" + encodeURIComponent(name));
    const text = r.exists ? (r.lines.join("\n") || "(log vuoto)") : "Nessun log: questo job non è mai partito su questo PC.";
    const v = $("logview");
    const atEnd = v.scrollTop + v.clientHeight >= v.scrollHeight - 8;
    if (v.textContent !== text) { v.textContent = text; if (atEnd) v.scrollTop = v.scrollHeight; }
  } catch (e) { showError("Non riesco a leggere il log: " + e.message, loadLog); }
}
$("log-go").addEventListener("click", loadLog);
$("log-name").addEventListener("change", loadLog);
$("d-log").addEventListener("toggle", () => { if ($("d-log").open) loadLog(); });

/* ---------- carico e polling ---------- */

async function loadJobLogs() {
  const s = state.status;
  for (const name of Object.keys(s.jobs || {})) {
    if (!s.jobs[name].running) continue;
    try { state.logs[name] = (await api("/api/log?name=job-" + name)).lines; } catch (e) { /* il prossimo giro riprova */ }
  }
}

function renderAll() {
  renderStatusLine(); renderStrip(); renderActions(); renderAuto(); renderRestore();
  $("where").textContent = state.status.host + " · " + state.status.bucket + (state.status.mock ? " · prova: " + state.status.mock : "");
}

let wasBusy = false;
async function loadStatus() {
  if (!TOKEN) { showError("Manca il token. Apri la pagina dall'URL stampato da `confsync ui`.", null); return; }
  try {
    const s = await api("/api/status");
    const busyNow = Object.values(s.jobs || {}).some((j) => j.running) || s.quick.running || s.full.running;
    state.status = s;
    if (busyNow) await loadJobLogs();
    clearError();
    renderAll();
    if (wasBusy && !busyNow) { loadChecks(); if ($("d-backups").open) loadBackups(); }
    wasBusy = busyNow;
    if ($("d-log").open && busyNow) loadLog();
    schedule(busyNow ? 1000 : 15000);
  } catch (e) {
    showError(e.message, loadStatus);
    schedule(15000);
  }
}

async function loadChecks() {
  try {
    state.checks = await api("/api/checks");
  } catch (e) {
    state.checks = null;
    showError("Non riesco a controllare gcloud e il bucket: " + e.message, loadChecks);
  }
  state.checksPending = false;
  if (state.status) { renderStatusLine(); renderAuto(); }
}

let timer = null;
function schedule(ms) {
  clearTimeout(timer);
  if (document.hidden) return;
  timer = setTimeout(loadStatus, ms);
}
document.addEventListener("visibilitychange", () => {
  if (document.hidden) clearTimeout(timer);
  else loadStatus();
});

document.querySelectorAll("[data-copy]").forEach((btn) => {
  const label = btn.textContent;
  btn.addEventListener("click", async () => {
    const text = document.querySelector(btn.dataset.copy).textContent;
    try { await navigator.clipboard.writeText(text); } catch (e) {
      const ta = h("textarea", { "aria-hidden": "true", style: "position:fixed;opacity:0" });
      ta.value = text; document.body.append(ta); ta.select();
      try { document.execCommand("copy"); } catch (e2) { /* niente da fare */ }
      ta.remove();
    }
    btn.textContent = "Copiato";
    setTimeout(() => { btn.textContent = label; }, 1600);
  });
});

loadStatus();
loadChecks();
