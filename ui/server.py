#!/usr/bin/env python3
"""Console web locale di bekky: server su 127.0.0.1, solo libreria standard.

Uso: confsync ui [--port N] [--no-open]
Con BEKKY_UI_MOCK=ok|reauth|stale|fresh|setup risponde con dati finti e job finti,
senza toccare gcloud, bucket, cron, settings di Claude o backup.
"""
import argparse
import datetime as dt
import errno
import hmac
import json
import os
import re
import secrets
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

UI_DIR = os.path.dirname(os.path.abspath(__file__))
BEKKY_DIR = os.path.dirname(UI_DIR)
HOME = os.path.expanduser("~")
CONF = os.path.join(HOME, ".config", "confsync")
HISTORY = os.path.join(CONF, "history.tsv")
JOBS_DIR = os.path.join(CONF, "ui-jobs")
QUICK_LOGS = os.path.join(CONF, "quick-logs")

MOCK = os.environ.get("BEKKY_UI_MOCK", "")
SCENARIOS = ("ok", "reauth", "stale", "fresh", "setup")
if MOCK and MOCK not in SCENARIOS:
    sys.exit("BEKKY_UI_MOCK deve essere uno di: " + ", ".join(SCENARIOS))

# --- Configurazione --------------------------------------------------------
# Il server modifica solo le tre righe CONFSYNC_BUCKET/PROJECT/ACCOUNT del file
# di config; il resto (HOST_TAG, OP_REF, commenti) resta com'e'.

CONFIG_PATH = os.environ.get("CONFSYNC_CONFIG") or os.path.join(CONF, "config")
CONFIG_VARS = {"bucket": "CONFSYNC_BUCKET", "project": "CONFSYNC_PROJECT",
               "account": "CONFSYNC_ACCOUNT"}
# Nessun default: il repo e' pubblico, il comando per il PC nuovo porta sempre i valori correnti
DEFAULTS = {"bucket": "", "project": "", "account": ""}
OP_REF_DEFAULT = "op://Personal/bekky passphrase/password"
BUCKET_RE = re.compile(r"gs://[a-z0-9][a-z0-9._-]{1,220}[a-z0-9]")
PROJECT_RE = re.compile(r"[a-z][a-z0-9-]{3,28}[a-z0-9]")
BUCKET_NAME_RE = re.compile(r"[a-z0-9][a-z0-9_-]{1,61}[a-z0-9]")
ACCOUNT_RE = re.compile(r"[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,190}\.[A-Za-z]{2,24}")
CONF_LINE_RE = re.compile(
    r"""^(\s*(?:export\s+)?)(CONFSYNC_[A-Z_]+)=("[^"]*"|'[^']*'|[^\s#]*)(\s*#.*)?\s*$""")

HOST_TAG = os.environ.get("CONFSYNC_HOST_TAG") or os.uname().nodename


def _unquote(v):
    return v[1:-1] if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'" else v


def read_config_file(path=None):
    """Valori CONFSYNC_* letti dal file senza eseguirlo; {} se manca."""
    out = {}
    try:
        with open(path or CONFIG_PATH, encoding="utf-8") as f:
            for line in f:
                m = CONF_LINE_RE.match(line.rstrip("\n"))
                if m:
                    out[m.group(2)] = _unquote(m.group(3))
    except OSError:
        pass
    return out


def _initial_config():
    if MOCK:
        if MOCK == "setup":
            return {"bucket": "", "project": "", "account": "", "opRef": ""}
        return {"bucket": "gs://bekky-esempio", "project": "progetto-esempio",
                "account": "tu@esempio.it", "opRef": "op://Personal/bekky passphrase/password"}
    f = read_config_file()
    g = lambda k: f.get(k, os.environ.get(k, ""))
    return {"bucket": g("CONFSYNC_BUCKET"), "project": g("CONFSYNC_PROJECT"),
            "account": g("CONFSYNC_ACCOUNT"), "opRef": g("CONFSYNC_OP_REF")}


CONFIG = _initial_config()
BUCKET = CONFIG["bucket"]
ACCOUNT = CONFIG["account"]
if MOCK:
    HOST_TAG = "pc-di-prova"


def validate_config(vals, fields=("bucket", "project", "account")):
    """Errori per campo (dict vuoto = valido). Le regex escludono virgolette, $, backtick e a capo."""
    err = {}
    v = {k: vals.get(k, "") for k in fields}
    if any(not isinstance(x, str) for x in v.values()):
        return {"_": "Valori non validi."}
    if "bucket" in fields and not BUCKET_RE.fullmatch(v["bucket"]):
        err["bucket"] = "Scrivi il nome come gs://nome-dello-spazio (minuscole, numeri, punti e trattini)."
    if "project" in fields and v["project"] and not PROJECT_RE.fullmatch(v["project"]):
        err["project"] = "Il progetto usa minuscole, numeri e trattini (da 5 a 30 caratteri)."
    if "account" in fields and v["account"] and not ACCOUNT_RE.fullmatch(v["account"]):
        err["account"] = "Scrivi un indirizzo email valido, per esempio nome@azienda.it."
    return err


def write_config(vals):
    """Riscrive solo le tre righe note: atomico, file 600, copia in config.bak."""
    target = os.path.realpath(CONFIG_PATH)
    try:
        with open(target, encoding="utf-8") as f:
            lines = f.read().splitlines()
        existed = True
    except FileNotFoundError:
        lines, existed = [], False
    names = {CONFIG_VARS[k]: vals[k] for k in CONFIG_VARS}
    out, seen = [], set()
    for line in lines:
        m = CONF_LINE_RE.match(line)
        if m and m.group(2) in names:
            if m.group(2) in seen:
                continue
            seen.add(m.group(2))
            out.append('%s%s="%s"%s' % (m.group(1) or "export ", m.group(2), names[m.group(2)], m.group(4) or ""))
        else:
            out.append(line)
    for name, val in names.items():
        if name not in seen:
            out.append('export %s="%s"' % (name, val))
    os.makedirs(os.path.dirname(target), mode=0o700, exist_ok=True)
    if existed:
        bak = os.open(target + ".bak", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(bak, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    tmp = target + ".ui-tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")
    os.replace(tmp, target)


def apply_config(vals):
    """Aggiorna il server in memoria (e l'ambiente dei processi figli)."""
    global BUCKET, ACCOUNT
    CONFIG.update({k: vals[k] for k in CONFIG_VARS})
    BUCKET, ACCOUNT = CONFIG["bucket"], CONFIG["account"]
    for k, name in CONFIG_VARS.items():
        os.environ[name] = CONFIG[k]
    CHECKS_CACHE.val = BACKUPS_CACHE.val = None


def tilde(path):
    return "~" + path[len(HOME):] if path.startswith(HOME + os.sep) else path


def list_buckets():
    """Nomi (senza gs://) degli spazi del progetto configurato."""
    if MOCK:
        with MOCK_STATE.lock:
            return list(MOCK_STATE.buckets)
    if not CONFIG["project"]:
        raise RuntimeError("Manca il progetto Google Cloud: indicalo in Avanzate.")
    r = subprocess.run([os.environ.get("CONFSYNC_GSUTIL", "gsutil"), "ls", "-p", CONFIG["project"]],
                       capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL,
                       env=_gcloud_env())
    if r.returncode != 0:
        raise RuntimeError(_gsutil_reason(r.stderr))
    names = sorted(l.strip()[5:].rstrip("/") for l in r.stdout.splitlines() if l.startswith("gs://"))
    # Bucket di servizio creati da Google (App Engine, Cloud Deploy): non sono
    # una scelta sensata per i salvataggi e confondono l'elenco. Quello in uso resta sempre.
    current = CONFIG["bucket"][5:] if CONFIG.get("bucket", "").startswith("gs://") else ""
    hidden = ("appspot.com", "_clouddeploy", "deploy-artifacts", "_cloudbuild", "gcf-")
    return [n for n in names if n == current or not any(h in n for h in hidden)]


def create_bucket(name):
    """Crea lo spazio con scripts/create-bucket.sh. Torna (ok, errore)."""
    if MOCK:
        time.sleep(1.5)
        with MOCK_STATE.lock:
            if name == "nome-gia-usato" or name in MOCK_STATE.buckets:
                return False, "Questo nome è già usato da un altro spazio. Scegline un altro."
            MOCK_STATE.buckets.append(name)
        return True, ""
    if not CONFIG["project"]:
        return False, "Manca il progetto Google Cloud: indicalo in Avanzate."
    # CONFSYNC_CONFIG=/dev/null: lo script rilegge il file di config e
    # sovrascriverebbe bucket e progetto passati qui; il file lo tocca solo il salvataggio.
    env = _gcloud_env()
    env.update(CONFSYNC_CONFIG="/dev/null", CONFSYNC_BUCKET="gs://" + name,
               CONFSYNC_PROJECT=CONFIG["project"], CONFSYNC_ACCOUNT=CONFIG.get("account") or "")
    try:
        r = subprocess.run(["bash", os.path.join(BEKKY_DIR, "scripts", "create-bucket.sh")],
                           capture_output=True, text=True, timeout=180, stdin=subprocess.DEVNULL, env=env)
    except subprocess.TimeoutExpired:
        return False, "La creazione impiega troppo: riprova tra poco."
    if r.returncode != 0:
        t = r.stderr or ""
        if "already exists" in t or "409" in t:
            return False, "Questo nome è già usato da un altro spazio. Scegline un altro."
        return False, _gsutil_reason(t)
    return True, ""


def get_config():
    return dict(CONFIG, opRefDefault=OP_REF_DEFAULT, defaults=DEFAULTS,
                configPath="~/.config/confsync/config" if MOCK else tilde(CONFIG_PATH),
                passphrasePath="~/.config/confsync/passphrase")


def _gsutil_reason(stderr):
    t = stderr or ""
    if "BucketNotFound" in t or "404" in t:
        return "Questo spazio di archiviazione non esiste."
    if "AccessDenied" in t or "403" in t:
        return "L'account non ha il permesso di usare questo spazio."
    if "Reauthentication" in t or "credentials" in t.lower() or "login" in t.lower():
        return "L'accesso a Google Cloud è scaduto: rifallo dal terminale."
    return _short_error(t)


def verify_config(bucket, account):
    if MOCK:
        if "nonesiste" in bucket:
            return {"ok": False, "error": "Questo spazio di archiviazione non esiste."}
        if "negato" in bucket:
            return {"ok": False, "error": "L'account non ha il permesso di usare questo spazio."}
        time.sleep(0.6)
        return {"ok": True, "error": ""}
    env = dict(os.environ)
    if account:
        env["CLOUDSDK_CORE_ACCOUNT"] = account
    try:
        r = subprocess.run([os.environ.get("CONFSYNC_GSUTIL", "gsutil"), "ls", "-b", bucket],
                           capture_output=True, text=True, timeout=20, stdin=subprocess.DEVNULL, env=env)
    except FileNotFoundError:
        return {"ok": False, "error": "gsutil non è installato su questo PC."}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "Nessuna risposta entro 20 secondi: controlla la rete."}
    return {"ok": True, "error": ""} if r.returncode == 0 else {"ok": False, "error": _gsutil_reason(r.stderr)}


ACTIONS = ("quick-push", "full-backup", "hook-install", "hook-uninstall",
           "tools-retry", "repos-retry")
STATIC = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
    "/theme.js": ("theme.js", "text/javascript; charset=utf-8"),
}
MOCK_JOB_SECONDS = 8


def now_utc():
    return dt.datetime.now(dt.timezone.utc)


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(s):
    return dt.datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


# --- Storico ---------------------------------------------------------------

def read_history():
    """Righe di history.tsv come dict, dalla piu' vecchia. Righe rotte ignorate."""
    out = []
    try:
        with open(HISTORY, encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 3 or parts[1] not in ("quick", "full"):
                    continue
                try:
                    parse_iso(parts[0])
                    b = int(parts[3]) if len(parts) > 3 else 0
                except ValueError:
                    continue
                out.append({"ts": parts[0], "kind": parts[1], "result": parts[2], "bytes": b})
    except OSError:
        pass
    return out


def append_history(kind, result):
    """Stessa riga di lib/history.sh, per i fallimenti dei job lanciati dalla UI."""
    try:
        os.makedirs(CONF, exist_ok=True)
        with open(HISTORY, "a", encoding="utf-8") as f:
            f.write("%s\t%s\t%s\t0\n" % (iso(now_utc()), kind, result))
        with open(HISTORY, encoding="utf-8") as f:
            lines = f.readlines()[-500:]
        tmp = HISTORY + ".ui-tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.writelines(lines)
        os.replace(tmp, HISTORY)
    except OSError:
        pass


def last_of(history, kind):
    for e in reversed(history):
        if e["kind"] == kind:
            return {"ts": e["ts"], "result": e["result"], "bytes": e["bytes"]}
    return None


# --- Cron ------------------------------------------------------------------

def _cron_field(spec, lo, hi):
    vals = set()
    for part in spec.split(","):
        step = 1
        if "/" in part:
            part, st = part.split("/", 1)
            step = int(st)
        if part in ("*", ""):
            a, b = lo, hi
        elif "-" in part:
            a, b = (int(x) for x in part.split("-", 1))
        else:
            a = int(part)
            b = hi if step != 1 else a
        vals.update(range(a, b + 1, step))
    return vals


def cron_next(line, after):
    """Prossima esecuzione (UTC iso) di una riga cron a 5 campi, o None."""
    try:
        f = line.split()[:5]
        mins, hours = _cron_field(f[0], 0, 59), _cron_field(f[1], 0, 23)
        doms, months = _cron_field(f[2], 1, 31), _cron_field(f[3], 1, 12)
        dows = {d % 7 for d in _cron_field(f[4], 0, 7)}
        dom_star, dow_star = f[2].startswith("*"), f[4].startswith("*")
    except (ValueError, IndexError):
        return None
    local = after.astimezone().replace(second=0, microsecond=0) + dt.timedelta(minutes=1)
    day = local.replace(hour=0, minute=0)
    for i in range(0, 400):
        d = day + dt.timedelta(days=i)
        dow = (d.weekday() + 1) % 7
        if d.month not in months:
            continue
        in_dom, in_dow = d.day in doms, dow in dows
        ok = (in_dom and in_dow) if (dom_star or dow_star) else (in_dom or in_dow)
        if not ok:
            continue
        for h in sorted(hours):
            for m in sorted(mins):
                cand = d.replace(hour=h, minute=m)
                if cand >= local:
                    return iso(cand.astimezone(dt.timezone.utc))
    return None


def read_cron():
    try:
        r = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return {"present": False, "line": "", "next": None}
    for line in r.stdout.splitlines():
        s = line.strip()
        if s and not s.startswith("#") and "bekky-cron.sh" in s:
            return {"present": True, "line": s, "next": cron_next(s, now_utc())}
    return {"present": False, "line": "", "next": None}


# --- Hook ------------------------------------------------------------------

def hook_installed():
    path = os.environ.get("CLAUDE_SETTINGS") or os.path.join(HOME, ".claude", "settings.json")
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        for group in data.get("hooks", {}).get("SessionEnd", []):
            for h in group.get("hooks", []):
                if str(h.get("command", "")).endswith("quick-push.sh"):
                    return True
    except (OSError, ValueError, AttributeError):
        pass
    return False


# --- Restore (stato lasciato da scripts/quick.sh) --------------------------

def read_restore():
    if not os.path.isdir(QUICK_LOGS):
        return None
    tools, failed = [], []
    try:
        with open(os.path.join(QUICK_LOGS, "tools-status.txt"), encoding="utf-8") as f:
            for line in f:
                parts = line.rstrip("\n").split(None, 2)
                if len(parts) >= 2:
                    tools.append({"name": parts[0], "status": parts[1],
                                  "detail": parts[2] if len(parts) > 2 else ""})
    except OSError:
        pass
    try:
        with open(os.path.join(QUICK_LOGS, "repos-failed.txt"), encoding="utf-8") as f:
            for line in f:
                p = line.rstrip("\n").split("\t")
                if p[0]:
                    failed.append({"path": p[0], "remote": p[1] if len(p) > 1 else ""})
    except OSError:
        pass
    return {"tools": tools, "reposFailed": failed}


# --- Job -------------------------------------------------------------------

class Jobs:
    """Un solo job per tipo. Reale: processo figlio con log su file. Mock: thread."""

    def __init__(self):
        self.lock = threading.Lock()
        self.state = {}      # name -> {proc, started, rc}
        self.mock_logs = {}  # name -> [righe]
        self.order = []      # nomi, dal piu' recente

    def running(self, name):
        s = self.state.get(name)
        return bool(s) and s.get("rc") is None

    def info(self):
        return {n: {"running": s.get("rc") is None, "startedAt": s["started"], "rc": s.get("rc")}
                for n, s in self.state.items()}

    def start(self, name):
        with self.lock:
            if self.running(name):
                return False
            self.state[name] = {"started": iso(now_utc()), "rc": None}
            if name in self.order:
                self.order.remove(name)
            self.order.insert(0, name)
        target = self._mock_run if MOCK else self._real_run
        threading.Thread(target=target, args=(name,), daemon=True).start()
        return True

    def log_path(self, name):
        return os.path.join(JOBS_DIR, name + ".log")

    # -- mock
    def _mock_run(self, name):
        steps = ["avvio %s (finto)" % name, "raccolgo dotfiles", "raccolgo secrets",
                 "manifest + checksum", "upload -> %s/%s/" % (BUCKET, HOST_TAG),
                 "backup completato"]
        lines = self.mock_logs[name] = []
        for i, text in enumerate(steps):
            lines.append(">> %s" % text)
            time.sleep(MOCK_JOB_SECONDS / len(steps))
        MOCK_STATE.job_done(name)
        self.state[name]["rc"] = 0

    # -- reale
    def _command(self, name):
        sh = os.path.join(BEKKY_DIR, "scripts")
        env = dict(os.environ)
        if name == "quick-push":
            with open(os.path.join(CONF, "passphrase"), encoding="utf-8") as f:
                env["CONFSYNC_PASSPHRASE"] = f.read().strip()
            return [os.path.join(BEKKY_DIR, "confsync"), "backup", "--quick"], env
        if name == "full-backup":
            return ["bash", os.path.join(sh, "bekky-cron.sh")], env
        if name == "hook-install":
            return ["bash", os.path.join(sh, "install-hooks.sh")], env
        if name == "hook-uninstall":
            return ["bash", os.path.join(sh, "install-hooks.sh"), "--uninstall"], env
        if name == "tools-retry":
            failed = [t["name"] for t in (read_restore() or {"tools": []})["tools"]
                      if t["status"] == "FAIL"]
            return ["bash", os.path.join(sh, "quick-tools.sh")] + failed, env
        if name == "repos-retry":
            try:
                os.remove(os.path.join(QUICK_LOGS, "repos-failed.txt"))
            except OSError:
                pass
            return ["bash", os.path.join(sh, "quick-repos.sh")], env
        raise ValueError(name)

    def _real_run(self, name):
        rc = 1
        try:
            os.makedirs(JOBS_DIR, exist_ok=True)
            cmd, env = self._command(name)
            with open(self.log_path(name), "w", encoding="utf-8") as log:
                log.write("$ %s\n" % " ".join(os.path.basename(c) if i == 0 else c
                                              for i, c in enumerate(cmd)))
                log.flush()
                proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=log,
                                        stderr=subprocess.STDOUT, env=env, cwd=BEKKY_DIR,
                                        start_new_session=True)
                rc = proc.wait()
                if name == "full-backup":
                    # bekky-cron.sh manda l'output in last-run.log
                    try:
                        with open(os.path.join(CONF, "last-run.log"), encoding="utf-8",
                                  errors="replace") as lr:
                            log.write(lr.read())
                    except OSError:
                        pass
                log.write("\n[uscito con codice %d]\n" % rc)
        except (OSError, ValueError) as e:
            try:
                with open(self.log_path(name), "a", encoding="utf-8") as log:
                    log.write("errore: %s\n" % e)
            except OSError:
                pass
        # bekky-cron.sh e confsync scrivono lo storico da soli; qui solo il caso
        # in cui il job non e' nemmeno partito.
        if name == "quick-push" and rc != 0:
            append_history("quick", "fail")
        self.state[name]["rc"] = rc


JOBS = Jobs()


# --- Mock ------------------------------------------------------------------

class MockState:
    def __init__(self, scenario):
        self.scenario = scenario
        self.t0 = now_utc()
        self.history = self._history(scenario)
        self.lock = threading.Lock()
        self.hook = scenario in ("ok", "fresh")
        self.passphrase = scenario != "setup"
        self.buckets = ["archivio-famiglia", "backup-vecchio-2024", "bekky-esempio"]

    def _history(self, sc):
        now, h = self.t0, []

        def add(ago, kind, result, size):
            h.append({"ts": iso(now - ago), "kind": kind, "result": result, "bytes": size})

        D, H, M = dt.timedelta(days=1), dt.timedelta(hours=1), dt.timedelta(minutes=1)
        if sc in ("fresh", "setup"):
            return h
        quick_days = {"ok": [0, 1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14, 16, 17, 19, 20, 21, 22, 23, 25, 26, 28],
                      "reauth": [1, 2, 3, 4, 5, 7, 8, 9, 12, 13, 14, 15, 18, 19, 20, 22, 23, 24, 27, 28],
                      "stale": [1, 2, 5, 6, 12, 13, 14, 17, 18, 19, 20, 24, 25, 26]}[sc]
        full_days = {"ok": [3, 10, 17, 24], "reauth": [4, 11, 18, 25],
                     "stale": [12, 19, 26]}[sc]
        for d in sorted(quick_days, reverse=True):
            add(D * d + H * (3 + d % 5), "quick", "dedup" if d % 3 == 0 else "upload", 41_300_000 + d * 17_000)
        for d in sorted(full_days, reverse=True):
            add(D * d + H * 1, "full", "upload", 182_000_000 + d * 91_000)
        if sc == "ok":
            add(D * 5 + H * 2, "full", "fail", 0)
            add(M * 12, "quick", "upload", 41_810_000)
        if sc == "reauth":
            add(D * 6 + H * 5, "quick", "fail", 0)
            add(H * 30, "quick", "fail", 0)
            add(H * 2, "quick", "fail", 0)
        if sc == "stale":
            add(D * 8 + H * 4, "quick", "fail", 0)
        h.sort(key=lambda e: e["ts"])
        return h

    def job_done(self, name):
        with self.lock:
            now = iso(now_utc())
            if name == "quick-push":
                self.history.append({"ts": now, "kind": "quick", "result": "upload", "bytes": 41_850_000})
            elif name == "full-backup":
                self.history.append({"ts": now, "kind": "full", "result": "upload", "bytes": 183_400_000})
            elif name == "hook-install":
                self.hook = True
            elif name == "hook-uninstall":
                self.hook = False

    def restore(self):
        if self.scenario != "fresh":
            return None
        return {"tools": [
            {"name": "gcloud", "status": "ok", "detail": ""},
            {"name": "gh", "status": "ok", "detail": ""},
            {"name": "kubectl", "status": "ok", "detail": ""},
            {"name": "node", "status": "ok", "detail": ""},
            {"name": "opencode", "status": "FAIL", "detail": "FAIL: download opencode"},
            {"name": "rtk", "status": "skip", "detail": ""},
            {"name": "terraform", "status": "ok", "detail": ""},
            {"name": "uv", "status": "skip", "detail": ""},
        ], "reposFailed": [
            {"path": "code/cliente/progetto/api", "remote": "git@gitlab.com:esempio/progetto-api.git"},
            {"path": "code/tea/infra", "remote": "git@gitlab.com:esempio/tea-infra.git"},
            {"path": "code/misc/appunti", "remote": "https://github.com/esempio/appunti.git"},
        ]}

    def cron(self):
        if self.scenario in ("fresh", "setup"):
            return {"present": False, "line": "", "next": None}
        line = "0 13 * * 3 /home/utente/code/misc/bekky/scripts/bekky-cron.sh"
        return {"present": True, "line": line, "next": cron_next(line, now_utc())}

    def checks(self):
        if self.scenario == "reauth":
            return {"gcloud": {"ok": False, "account": ACCOUNT,
                               "error": "Reauthentication failed. cannot prompt during non-interactive execution."},
                    "bucket": {"ok": False}}
        return {"gcloud": {"ok": True, "account": ACCOUNT, "error": ""},
                "bucket": {"ok": bool(BUCKET)}}

    def backups(self):
        base = self.t0
        offs = {"ok": [3, 10, 17, 24], "reauth": [4, 11, 18, 25],
                "stale": [12, 19, 26], "fresh": [14], "setup": []}[self.scenario]
        out = [{"ts": (base - dt.timedelta(days=d, hours=1)).strftime("%Y%m%dT%H%M%SZ"),
                "bytes": 182_000_000 + d * 91_000} for d in offs]
        with self.lock:
            fulls = [e for e in self.history if e["kind"] == "full" and e["result"] == "upload"
                     and parse_iso(e["ts"]) > base]
        for e in fulls:
            out.insert(0, {"ts": parse_iso(e["ts"]).strftime("%Y%m%dT%H%M%SZ"), "bytes": e["bytes"]})
        return out


MOCK_STATE = MockState(MOCK) if MOCK else None

MOCK_CORE = [
    (".claude/projects", 18_400_000, 412), (".config/Code", 6_100_000, 87),
    (".claude/skills", 3_900_000, 640), (".local/bin", 2_700_000, 31),
    (".config/gcloud", 1_800_000, 55), (".claude/plugins", 1_200_000, 233),
    (".config/opencode", 640_000, 19), (".zshrc", 8_400, 1), (".gitconfig", 1_100, 1),
    (".config/git", 900, 3), (".claude/settings.json", 4_800, 1), (".bashrc", 3_700, 1),
]


# --- Dati ------------------------------------------------------------------

def get_status():
    jobs = JOBS.info()
    if MOCK:
        with MOCK_STATE.lock:
            hist = list(MOCK_STATE.history)
        checks = {"passphrase": MOCK_STATE.passphrase, "hook": MOCK_STATE.hook, "cron": MOCK_STATE.cron()}
        restore = MOCK_STATE.restore()
    else:
        hist = read_history()
        checks = {"passphrase": _passphrase_ok(), "hook": hook_installed(), "cron": read_cron()}
        restore = read_restore()
    cutoff = iso(now_utc() - dt.timedelta(days=30))
    quick, full = last_of(hist, "quick"), last_of(hist, "full")
    out = {
        "host": HOST_TAG, "bucket": BUCKET, "mock": MOCK or None, "now": iso(now_utc()),
        "checks": checks,
        "configured": {"bucket": bool(BUCKET), "passphrase": bool(checks["passphrase"])},
        "quick": {"last": quick, "running": JOBS.running("quick-push") or (not MOCK and _quick_locked())},
        "full": {"last": full, "running": JOBS.running("full-backup")},
        "jobs": jobs,
        "history": [{"ts": e["ts"], "kind": e["kind"], "result": e["result"]}
                    for e in hist if e["ts"] >= cutoff],
    }
    if restore is not None:
        out["restore"] = restore
    return out


def _passphrase_ok():
    p = os.path.join(CONF, "passphrase")
    try:
        return os.path.getsize(p) > 0 and os.access(p, os.R_OK)
    except OSError:
        return False


def _quick_locked():
    """True se un backup quick (hook di sessione incluso) tiene il lock."""
    try:
        import fcntl
        fd = os.open(os.path.join(CONF, "quick.lock"), os.O_RDONLY)
    except (OSError, ImportError):
        return False
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    except OSError as e:
        return e.errno in (errno.EWOULDBLOCK, errno.EAGAIN)
    finally:
        os.close(fd)


class Cache:
    def __init__(self, ttl):
        self.ttl, self.val, self.at, self.lock = ttl, None, 0.0, threading.Lock()

    def get(self, fn):
        with self.lock:
            if self.val is None or time.monotonic() - self.at > self.ttl:
                self.val = fn()
                self.at = time.monotonic()
            return self.val


CHECKS_CACHE, BACKUPS_CACHE, BUCKETS_CACHE = Cache(60), Cache(300), Cache(20)


def _gcloud_env():
    env = dict(os.environ)
    if ACCOUNT:
        env["CLOUDSDK_CORE_ACCOUNT"] = ACCOUNT
    return env


def _short_error(text):
    lines = [l.strip() for l in (text or "").splitlines() if l.strip()]
    return (lines[-1] if lines else "errore sconosciuto")[:200]


def compute_checks():
    if MOCK:
        return MOCK_STATE.checks()
    cmd = ["gcloud", "auth", "print-access-token"]
    if ACCOUNT:
        cmd.append("--account=" + ACCOUNT)
    gc = {"ok": False, "account": ACCOUNT, "error": ""}
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15,
                           stdin=subprocess.DEVNULL, env=_gcloud_env())
        gc["ok"] = r.returncode == 0
        if not gc["ok"]:
            gc["error"] = _short_error(r.stderr)
    except FileNotFoundError:
        gc["error"] = "gcloud non trovato nel PATH"
    except subprocess.TimeoutExpired:
        gc["error"] = "gcloud non risponde (timeout 15 s)"
    bucket = {"ok": False}
    if gc["ok"] and BUCKET:
        try:
            r = subprocess.run([os.environ.get("CONFSYNC_GSUTIL", "gsutil"), "ls", "-b", BUCKET],
                               capture_output=True, text=True, timeout=15,
                               stdin=subprocess.DEVNULL, env=_gcloud_env())
            bucket["ok"] = r.returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            pass
    return {"gcloud": gc, "bucket": bucket}


def compute_backups():
    if MOCK:
        return MOCK_STATE.backups()
    if not BUCKET:
        return []
    r = subprocess.run([os.environ.get("CONFSYNC_GSUTIL", "gsutil"), "du", "%s/%s/" % (BUCKET, HOST_TAG)],
                       capture_output=True, text=True, timeout=60, stdin=subprocess.DEVNULL,
                       env=_gcloud_env())
    if r.returncode != 0:
        raise RuntimeError(_short_error(r.stderr))
    sizes = {}
    prefix = "%s/%s/" % (BUCKET, HOST_TAG)
    for line in r.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit() or not parts[1].startswith(prefix):
            continue
        # gsutil du stampa anche una riga di totale per ogni dir (finisce con
        # "/"): sommarla agli oggetti raddoppia il peso
        if parts[1].endswith("/"):
            continue
        ts = parts[1][len(prefix):].split("/", 1)[0]
        if len(ts) == 16 and ts[8] == "T" and ts.endswith("Z"):
            sizes[ts] = sizes.get(ts, 0) + int(parts[0])
    return [{"ts": k, "bytes": v} for k, v in sorted(sizes.items(), reverse=True)]


def compute_core():
    if MOCK:
        entries = [{"path": p, "bytes": b, "files": n} for p, b, n in MOCK_CORE]
    else:
        r = subprocess.run([os.path.join(BEKKY_DIR, "confsync"), "quick-list"],
                           capture_output=True, text=True, timeout=120, stdin=subprocess.DEVNULL,
                           env=dict(os.environ))
        if r.returncode != 0:
            raise RuntimeError(_short_error(r.stderr))
        agg = {}
        for rel in r.stdout.splitlines():
            if not rel:
                continue
            parts = rel.split("/")
            key = rel if len(parts) <= 2 else "/".join(parts[:2])
            try:
                st = os.lstat(os.path.join(HOME, rel))
            except OSError:
                continue
            if not (st.st_mode & 0o170000 == 0o100000):  # solo file regolari
                continue
            e = agg.setdefault(key, [0, 0])
            e[0] += st.st_size
            e[1] += 1
        entries = [{"path": k, "bytes": v[0], "files": v[1]} for k, v in agg.items()]
    entries.sort(key=lambda e: -e["bytes"])
    return {"entries": entries, "totalBytes": sum(e["bytes"] for e in entries),
            "totalFiles": sum(e["files"] for e in entries)}


def tail_lines(path, n=200):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 64 * 1024))
            data = f.read().decode("utf-8", errors="replace")
    except OSError:
        return None
    return data.splitlines()[-n:]


def get_log(name):
    paths = {"quick": os.path.join(CONF, "quick-push.log"),
             "full": os.path.join(CONF, "last-run.log"),
             "tools": os.path.join(QUICK_LOGS, "tools.log"),
             "repos": os.path.join(QUICK_LOGS, "repos.log")}
    if MOCK:
        if name == "job" or name.startswith("job-"):
            key = name[4:] if name.startswith("job-") else (JOBS.order[0] if JOBS.order else "")
            lines = JOBS.mock_logs.get(key)
        else:
            lines = ["(log finto: %s)" % name] if name in paths else None
        return {"name": name, "exists": lines is not None, "lines": (lines or [])[-200:]}
    if name == "job" or name.startswith("job-"):
        key = name[4:] if name.startswith("job-") else None
        if key is None:
            key = JOBS.order[0] if JOBS.order else None
        if key is None:
            try:
                files = [f for f in os.listdir(JOBS_DIR) if f.endswith(".log")]
                key = max(files, key=lambda f: os.path.getmtime(os.path.join(JOBS_DIR, f)))[:-4]
            except (OSError, ValueError):
                key = None
        if key not in ACTIONS:
            return {"name": name, "exists": False, "lines": []}
        path = JOBS.log_path(key)
    else:
        path = paths[name]
    lines = tail_lines(path)
    return {"name": name, "exists": lines is not None, "lines": lines or []}


LOG_NAMES = {"quick", "full", "tools", "repos", "job"} | {"job-" + a for a in ACTIONS}


# --- HTTP ------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "bekky-ui"
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # niente access log: contiene il token nell'URL
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body).encode("utf-8")
        elif isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; script-src 'self'; style-src 'self'; "
                         "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
        self.end_headers()
        self.wfile.write(body)

    def _err(self, code, msg):
        self._send(code, {"error": msg})

    def _host_ok(self):
        port = self.server.server_address[1]
        return self.headers.get("Host", "") in ("127.0.0.1:%d" % port, "localhost:%d" % port)

    def _token_ok(self):
        return hmac.compare_digest(self.headers.get("X-Bekky-Token", ""), self.server.token)

    def _guard(self, api):
        if not self._host_ok():
            self._err(403, "host non ammesso")
            return False
        if api and not self._token_ok():
            self._err(403, "token mancante o errato")
            return False
        return True

    def do_GET(self):
        u = urlparse(self.path)
        if u.path in STATIC:
            if not self._guard(False):
                return
            fname, ctype = STATIC[u.path]
            try:
                with open(os.path.join(UI_DIR, fname), "rb") as f:
                    self._send(200, f.read(), ctype)
            except OSError:
                self._err(404, "file non trovato")
            return
        if not u.path.startswith("/api/"):
            return self._err(404, "non trovato")
        if not self._guard(True):
            return
        q = parse_qs(u.query)
        try:
            if u.path == "/api/status":
                return self._send(200, get_status())
            if u.path == "/api/config":
                return self._send(200, get_config())
            if u.path == "/api/buckets":
                return self._send(200, {"buckets": BUCKETS_CACHE.get(list_buckets)})
            if u.path == "/api/checks":
                if q.get("fresh"):
                    CHECKS_CACHE.val = None
                return self._send(200, CHECKS_CACHE.get(compute_checks))
            if u.path == "/api/backups":
                return self._send(200, {"backups": BACKUPS_CACHE.get(compute_backups)})
            if u.path == "/api/core":
                return self._send(200, compute_core())
            if u.path == "/api/log":
                name = (q.get("name") or [""])[0]
                if name not in LOG_NAMES:
                    return self._err(400, "log sconosciuto")
                return self._send(200, get_log(name))
        except subprocess.TimeoutExpired:
            return self._err(504, "il comando ha impiegato troppo")
        except (RuntimeError, OSError) as e:
            return self._err(502, str(e))
        self._err(404, "non trovato")

    def do_POST(self):
        u = urlparse(self.path)
        if not u.path.startswith("/api/"):
            return self._err(404, "non trovato")
        if not self._guard(True):
            return
        if u.path not in ("/api/action", "/api/config", "/api/config/verify", "/api/buckets"):
            return self._err(404, "non trovato")
        try:
            n = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            n = -1
        if not 0 < n <= 4096:
            return self._err(400, "corpo non valido")
        try:
            body = json.loads(self.rfile.read(n).decode("utf-8"))
            if not isinstance(body, dict):
                raise TypeError
        except (ValueError, TypeError):
            return self._err(400, "serve un oggetto JSON")
        if u.path == "/api/config":
            return self._post_config(body)
        if u.path == "/api/config/verify":
            return self._post_verify(body)
        if u.path == "/api/buckets":
            return self._post_bucket(body)
        name = body.get("name")
        if name not in ACTIONS:
            return self._err(400, "azione sconosciuta")
        if not MOCK:
            if name in ("quick-push",) and not _passphrase_ok():
                return self._err(400, "passphrase mancante")
            if name == "tools-retry" and not any(
                    t["status"] == "FAIL" for t in (read_restore() or {"tools": []})["tools"]):
                return self._err(400, "nessun tool fallito")
        if not JOBS.start(name):
            return self._err(409, "azione gia' in corso")
        self._send(202, {"started": name})

    def _post_config(self, body):
        vals = {k: body.get(k, "") for k in CONFIG_VARS}
        errs = validate_config(vals)
        if errs:
            return self._send(400, {"error": "Valori non validi", "fields": errs})
        if not MOCK:
            try:
                write_config(vals)
            except OSError as e:
                return self._err(500, "non riesco a salvare: %s" % e.strerror)
        apply_config(vals)
        self._send(200, get_config())

    def _post_bucket(self, body):
        name = body.get("name")
        if not isinstance(name, str) or not BUCKET_NAME_RE.fullmatch(name) or name.startswith("goog"):
            return self._send(400, {"error": "Nome non valido", "fields": {
                "name": "Usa minuscole, numeri e trattini (da 3 a 63 caratteri), senza spazi."}})
        ok, msg = create_bucket(name)
        BUCKETS_CACHE.val = None
        if not ok:
            return self._err(409, msg)
        self._send(201, {"name": name, "bucket": "gs://" + name})

    def _post_verify(self, body):
        vals = {k: body.get(k, "") for k in ("bucket", "account")}
        errs = validate_config(vals, ("bucket", "account"))
        if errs:
            return self._send(400, {"error": "Valori non validi", "fields": errs})
        try:
            self._send(200, verify_config(vals["bucket"], vals["account"]))
        except OSError as e:
            self._send(200, {"ok": False, "error": str(e)})

    def do_PUT(self):
        self._err(405, "metodo non ammesso")

    do_DELETE = do_PATCH = do_PUT


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def main():
    ap = argparse.ArgumentParser(prog="confsync ui")
    ap.add_argument("--port", type=int, default=0, help="porta (default 7842, altrimenti una libera)")
    ap.add_argument("--no-open", action="store_true", help="non aprire il browser")
    args = ap.parse_args()
    srv = None
    ports = [args.port] if args.port else [7842, 0]
    for p in ports:
        try:
            srv = Server(("127.0.0.1", p), Handler)
            break
        except OSError as e:
            if p == ports[-1]:
                sys.exit("porta non disponibile: %s" % e)
    srv.token = secrets.token_urlsafe(24)
    url = "http://127.0.0.1:%d/?t=%s" % (srv.server_address[1], srv.token)
    print("bekky ui%s: %s" % (" (mock %s)" % MOCK if MOCK else "", url), flush=True)
    if not args.no_open:
        threading.Timer(0.3, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
