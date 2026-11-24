"""Claude Code hook: tell you which session on which machine finished or needs you.

One script serves every event; the event comes from the payload's hook_event_name.
  UserPromptSubmit  record turn start               (silent: stdout here would enter the model context)
  Stop              turn done; notify when it ran >= stop_min_seconds (counted from your last own
                    prompt, read from the transcript), otherwise keep the reply for the idle_prompt
                    that Claude Code fires ~60s later if you stay away. Quiet while background
                    subagents launched by this session have not handed back yet: each hand-back
                    starts a turn of its own, and only the turn after the last one is the real end
  StopFailure       turn ended on an API error; always notify
  Notification      permission_prompt / idle_prompt / MCP elicitation / agent view; idle_prompt only
                    follows a short Stop that stayed quiet, so a fresh or just-resumed session that
                    has not run a turn yet, or one waiting on its subagents, does not ask for input
  PreToolUse        AskUserQuestion / ExitPlanMode: Claude is about to wait on you
  PostToolUse       (async) you answered: take this session's toast off the screen
  SessionEnd        delete this session's state and toast, plus state older than 7 days

Channels, switched in cc_notify.json next to this script (JSONC: // and /* */ comments and trailing
commas allowed; missing keys fall back to DEFAULTS,
edits apply to the next event without restarting Claude Code):
  bell    BEL. Windows Terminal marks the tab with a bell and flashes the taskbar (beeps only
          when the profile's bellStyle has "audible"); Tabby obeys its terminal.bell setting.
          Travels through SSH / WSL to the terminal you are looking at.
  osc777  OSC 777 desktop notification: Windows Terminal 1.26+ with compatibility.allowOSC777,
          Ghostty, Warp. Also travels through SSH.
  toast   Windows toast on the machine running Claude Code, naming machine / project / session.
          With toast_persist it is a reminder toast: it shows through Do Not Disturb and stays
          until dismissed; your next prompt or tool result in that session removes it.
  ntfy    push through an ntfy server to phone, browser or other machines; off while topic is empty.
          ntfy.mode: always | away (only once this PC has had no keyboard / mouse input for
          away_minutes; on non-Windows hosts away acts as always) | off. Needs-you alerts go out
          at ntfy.priority, finished turns at ntfy.priority_done.

Phone switch without editing the config (the ccphone wrapper runs `cc_notify.py phone ...`):
  phone on|off|away [30m|2h|1d]   override ntfy.mode, for a while or until the next switch
  phone reset                     back to ntfy.mode from the config
  phone status                    mode in force, idle time, whether an alert would push now
  phone test                      push a test message right away, whatever the mode

Hooks have no terminal, so bell / osc777 go out as {"terminalSequence": ...} on stdout and Claude
Code writes them itself. toast / ntfy run in detached children so the hook returns at once. Any
failure is logged to STATE_DIR/cc_notify.log and swallowed: a notifier must never break a turn.
"""
import base64
import calendar
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "cc_notify.json")
TOAST_SCRIPT = os.path.join(HERE, "cc_notify_toast.ps1")
STATE_DIR = os.path.join(os.path.expanduser("~"), ".claude", "state", "cc-notify")
LOG_PATH = os.path.join(STATE_DIR, "cc_notify.log")
PHONE_PATH = os.path.join(STATE_DIR, "phone.json")  # {mode, until} written by `phone on|off|away`
# while this file exists, every event received is logged too, not only the alerts sent
DEBUG_FLAG = os.path.join(STATE_DIR, "debug")
LOG_MAX = 256 * 1024
STALE_SECONDS = 7 * 24 * 3600
TITLE_TAIL = 2 * 1024 * 1024  # transcript bytes searched for the session title before a full scan
WAIT_DEDUP = 15  # a Notification this soon after an AskUserQuestion / ExitPlanMode alert is the same wait

DEFAULTS = {
    "bell": True,
    "osc777": False,
    "toast": True,
    "toast_sound": True,
    "toast_persist": True,
    "stop_min_seconds": 20,
    # a subagent that has not handed back counts as still running while its transcript was written
    # within this many minutes; past that it is taken as dead, so a lost one cannot mute Stop forever
    "bg_alive_minutes": 30,
    "machine": "",  # name shown for this machine; empty = hostname
    "ntfy": {
        "mode": "away",
        "away_minutes": 5,
        "server": "https://ntfy.sh",
        "topic": "",
        "token": "",
        "proxy": "",  # "" = env / Windows system proxy, "none" = direct, or e.g. "http://127.0.0.1:7890"
        "priority": 4,  # high: Android pops it over the screen
        "priority_done": 3,  # default: sound + vibration, no pop-over
        "detail": True,  # False: leave the reply / question text out of the push
    },
}
PHONE_MODES = {"on": "always", "always": "always", "off": "off", "away": "away", "auto": "away"}

# Notification types worth an alert; the rest (auth_success, elicitation_complete, quota_*) stay quiet
NOTIFY_TYPES = {
    "permission_prompt": "🔐 等你授权",
    "idle_prompt": "💬 等你输入",
    "elicitation_dialog": "🧩 MCP 请求输入",
    "elicitation_url_dialog": "🧩 MCP 请求输入",
    "agent_needs_input": "🙋 后台会话等你",
    "agent_completed": "✅ 后台会话完成",
}
WAIT_TOOLS = {"AskUserQuestion": "❓ 有问题问你", "ExitPlanMode": "📋 计划待批准"}

CREATE_BREAKAWAY_FROM_JOB = 0x01000000


def log(msg):
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > LOG_MAX:
            os.replace(LOG_PATH, LOG_PATH + ".1")
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {msg}\n")
    except OSError:
        pass


_JSONC_BLOCK = r"/\*(?:[^*]|\*(?!/))*\*/"  # cannot run past its own */, even when backtracking
_JSONC_LINE = r"//[^\n]*(?:\n|$)"  # must reach the line end, so a ] or } inside a comment is never taken
_JSONC_TOKEN = re.compile(rf'"(?:\\.|[^"\\])*"|{_JSONC_LINE}|{_JSONC_BLOCK}|,(?=(?:\s|{_JSONC_LINE}|{_JSONC_BLOCK})*[}}\]])')


def strip_jsonc(text):
    """JSONC -> JSON: drop // and /* */ comments and trailing commas, leaving string contents alone."""
    # removed comments keep their line breaks, so a JSON error's line number still matches the file
    return _JSONC_TOKEN.sub(lambda m: m.group(0) if m.group(0).startswith('"') else "\n" * m.group(0).count("\n"),
                            text)


def load_config():
    cfg = json.loads(json.dumps(DEFAULTS))
    try:
        with open(CONFIG_PATH, encoding="utf-8-sig") as f:
            user = json.loads(strip_jsonc(f.read()))
    except FileNotFoundError:
        return cfg
    except (OSError, ValueError) as e:
        log(f"config: {e}")
        return cfg
    for key, value in user.items():
        if isinstance(value, dict) and isinstance(cfg.get(key), dict):
            cfg[key].update(value)
        else:
            cfg[key] = value
    return cfg


def safe_name(s):
    return "".join(ch if ch.isalnum() or ch in "-_" else "_" for ch in str(s))[:120] or "x"


def state_path(sid):
    return os.path.join(STATE_DIR, safe_name(sid) + ".json")


def load_state(sid):
    """The session's state; {} when there is none yet, None when the file exists but stays unreadable
    (on Windows another hook's os.replace holds it for a moment). With None the caller must not save,
    or it would overwrite turn_start and the rest with an empty state."""
    for attempt in range(10):
        try:
            with open(state_path(sid), encoding="utf-8") as f:
                st = json.load(f)
            return st if isinstance(st, dict) else {}
        except FileNotFoundError:
            return {}
        except (OSError, ValueError):  # PermissionError mid-replace, or a torn read
            time.sleep(0.03)
    return None


def save_state(sid, st):
    """Atomic write. The tmp name is per process: subagents' tool calls fire PostToolUse hooks with this
    session's id in parallel, and a shared tmp name made them trip over each other."""
    os.makedirs(STATE_DIR, exist_ok=True)
    path = state_path(sid)
    tmp = f"{path}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, ensure_ascii=False)
    for attempt in range(20):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:  # a reader has the target open right now
            time.sleep(0.03)
    os.remove(tmp)
    raise PermissionError(f"state still locked: {path}")


def cleanup(sid, now):
    try:
        os.remove(state_path(sid))
    except OSError:
        pass
    try:
        for name in os.listdir(STATE_DIR):
            path = os.path.join(STATE_DIR, name)
            stale = now - os.path.getmtime(path) > (STALE_SECONDS if name.endswith(".json") else 3600)
            if name.endswith((".json", ".tmp")) and stale:
                os.remove(path)
    except OSError:
        pass


def oneline(text, limit):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[: limit - 1] + "…"


def fmt_duration(sec):
    sec = int(sec)
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m{sec % 60:02d}s"
    return f"{sec // 3600}h{sec % 3600 // 60:02d}m"


def scan_titles(lines):
    """Last /rename-or---name title and last AI title among transcript lines."""
    custom = ai = ""
    for line in lines:
        if b'"custom-title"' in line or b'"ai-title"' in line:
            try:
                entry = json.loads(line)
            except ValueError:  # the partial first line of a tail read
                continue
            custom = entry.get("customTitle") or custom
            ai = entry.get("aiTitle") or ai
    return custom, ai


def session_title(transcript):
    """What Claude Code calls the session; the same text it puts in the terminal tab title."""
    if not transcript or not os.path.isfile(transcript):
        return ""
    size = os.path.getsize(transcript)
    with open(transcript, "rb") as f:
        f.seek(max(0, size - TITLE_TAIL))
        custom, ai = scan_titles(f.read().split(b"\n"))
    if not custom and size > TITLE_TAIL:  # a rename can sit far back in a long session
        with open(transcript, "rb") as f:
            custom, ai_full = scan_titles(f)
        ai = ai or ai_full
    return custom or ai


TASK_ID_RE = re.compile(r"<task-id>([^<\s]+)</task-id>")


def iso_time(text):
    """Epoch seconds of a transcript timestamp like 2026-11-12T14:40:15.071Z; None if unparsable."""
    try:
        return calendar.timegm(time.strptime(str(text)[:19], "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return None


def transcript_facts(transcript, now, alive_seconds):
    """(time of your last own prompt, ids of background subagents not handed back yet).

    In the transcript a background Agent launch is a tool result with toolUseResult.status
    "async_launched" and its agentId; its end is a user entry with origin.kind "peer" from that id
    (the hand-back, written before the turn it starts) or "task-notification" naming it in <task-id>
    (written only after that turn's Stop, so it cannot be relied on alone). Your own prompts carry
    origin.kind "human". A subagent still counts as running only while its own transcript
    (<session>/subagents/agent-<id>.jsonl) was written within alive_seconds.
    """
    if not transcript or not os.path.isfile(transcript):
        return None, []
    launched, ended, human = {}, {}, None
    with open(transcript, "rb") as f:
        for line in f:  # cheap byte filter first: only these lines are worth a JSON parse
            if b'"status":"async_launched"' not in line and b'"origin":{' not in line:
                continue
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if not isinstance(e, dict):
                continue
            ts = iso_time(e.get("timestamp")) or now
            res = e.get("toolUseResult")
            if isinstance(res, dict) and res.get("status") == "async_launched" and res.get("agentId"):
                launched[str(res["agentId"])] = ts
                continue
            origin = e.get("origin")
            if e.get("type") != "user" or not isinstance(origin, dict):
                continue
            kind = origin.get("kind")
            if kind == "human":
                human = ts
            elif kind == "peer":
                aid = origin.get("senderTaskId") or origin.get("from")
                if aid:
                    ended[str(aid)] = ts
            elif kind == "task-notification":
                content = (e.get("message") or {}).get("content")
                text = content if isinstance(content, str) else json.dumps(content, ensure_ascii=False)
                for m in TASK_ID_RE.finditer(text):
                    ended[m.group(1)] = ts

    subagents = os.path.join(os.path.splitext(transcript)[0], "subagents")
    pending = []
    for aid, start in launched.items():
        if ended.get(aid, -1) >= start:
            continue
        try:
            last = os.path.getmtime(os.path.join(subagents, f"agent-{aid}.jsonl"))
        except OSError:
            last = start
        if now - last < alive_seconds:
            pending.append(aid)
    return human, pending


def machine_name(cfg):
    return cfg.get("machine") or os.environ.get("COMPUTERNAME") or socket.gethostname()


def terminal_label():
    if os.environ.get("SSH_CONNECTION"):
        return "SSH"
    if os.environ.get("WT_SESSION"):
        return "Windows Terminal"
    term = os.environ.get("TERM_PROGRAM", "")
    return {"vscode": "VS Code", "Tabby": "Tabby"}.get(term, term)


def build(event, p, st, cfg, now):
    """(headline, detail) to announce, or None to stay quiet. Updates the session state st."""
    if event == "UserPromptSubmit":
        st.update(turn_start=now, stop_notified=False, last_reply="", awaiting=False)
        return None

    if event == "Stop":
        reply = oneline(p.get("last_assistant_message"), 120)
        human, pending = transcript_facts(p.get("transcript_path"), now,
                                          float(cfg.get("bg_alive_minutes") or 0) * 60)
        # a hand-back turn may not fire UserPromptSubmit, or may fire it with the hand-back as the
        # prompt; your own last prompt is what the duration is measured from either way
        start = human or st.get("turn_start")
        took = now - start if start else None
        st["last_reply"] = reply
        st["awaiting"] = False
        if pending:  # subagents still out: Claude carries on by itself when they hand back
            if os.path.exists(DEBUG_FLAG):
                log(f"Stop {str(p.get('session_id'))[:8]} quiet, {len(pending)} subagent(s) pending")
            return None
        if took is not None and took < cfg["stop_min_seconds"]:
            st["awaiting"] = True  # left for idle_prompt, in case you walk away
            return None
        st["stop_notified"] = True
        if took is None:  # hook installed mid-turn
            return "✅ 已完成", reply
        return "✅ 已完成", f"用时 {fmt_duration(took)} · {reply}" if reply else f"用时 {fmt_duration(took)}"

    if event == "StopFailure":
        st["stop_notified"] = True
        return "❌ 出错中断", oneline(p.get("last_assistant_message") or p.get("error_details") or p.get("error"), 120)

    if event == "Notification":
        ntype = p.get("notification_type")
        if ntype and ntype not in NOTIFY_TYPES:
            return None
        if ntype == "idle_prompt":
            # only a short turn that ended quietly earns this; a session that has not run a turn
            # (fresh, resumed) or is waiting on its subagents stays quiet
            if not st.get("awaiting") or st.get("stop_notified"):
                return None
            st["awaiting"] = False
            return NOTIFY_TYPES[ntype], st.get("last_reply") or oneline(p.get("message"), 120)
        if now - st.get("wait_notified", 0) < WAIT_DEDUP:
            return None
        return NOTIFY_TYPES.get(ntype, "🔔 需要你介入"), oneline(p.get("message"), 120)

    if event == "PreToolUse":
        tool = p.get("tool_name")
        if tool not in WAIT_TOOLS:
            return None
        st["wait_notified"] = now
        detail = ""
        if tool == "AskUserQuestion":
            questions = (p.get("tool_input") or {}).get("questions") or []
            if questions and isinstance(questions[0], dict):
                detail = questions[0].get("question", "")
        return WAIT_TOOLS[tool], oneline(detail, 120)

    return None


def spawn(args):
    """Start a child that outlives the hook and holds none of its pipes."""
    kw = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, close_fds=True)
    if os.name != "nt":
        subprocess.Popen(args, start_new_session=True, **kw)
        return
    flags = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    try:  # leave Claude Code's job object, if any, so the child is not killed with the hook
        subprocess.Popen(args, creationflags=flags | CREATE_BREAKAWAY_FROM_JOB, **kw)
    except OSError:  # the job forbids breakaway
        subprocess.Popen(args, creationflags=flags, **kw)


def spawn_toast(payload):
    if os.name == "nt":
        spawn(["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
               "-WindowStyle", "Hidden", "-File", TOAST_SCRIPT, "-Payload", b64(payload)])


def b64(obj):
    return base64.b64encode(json.dumps(obj, ensure_ascii=False).encode("utf-8")).decode("ascii")


def osc_text(s):
    # ';' separates OSC 777 fields; control bytes would end or corrupt the sequence
    return re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", s).replace(";", "；")


def idle_seconds():
    """Seconds since the last keyboard / mouse input in this Windows session; None elsewhere."""
    if os.name != "nt":
        return None
    import ctypes

    class LASTINPUTINFO(ctypes.Structure):
        _fields_ = [("cbSize", ctypes.c_uint32), ("dwTime", ctypes.c_uint32)]

    info = LASTINPUTINFO(ctypes.sizeof(LASTINPUTINFO), 0)
    if not ctypes.windll.user32.GetLastInputInfo(ctypes.byref(info)):
        return None
    ctypes.windll.kernel32.GetTickCount.restype = ctypes.c_uint32
    return ((ctypes.windll.kernel32.GetTickCount() - info.dwTime) & 0xFFFFFFFF) / 1000  # ticks wrap at 49.7 days


def phone_mode(cfg, now):
    """(mode, until, overridden): a `phone` override while it lasts, else ntfy.mode from the config."""
    try:
        with open(PHONE_PATH, encoding="utf-8") as f:
            override = json.load(f)
        if override.get("mode") in PHONE_MODES.values() and now < (override.get("until") or float("inf")):
            return override["mode"], override.get("until"), True
    except (OSError, ValueError):
        pass
    return PHONE_MODES.get(str(cfg["ntfy"].get("mode")), "always"), None, False


def phone_wanted(cfg, now):
    if not cfg["ntfy"].get("topic"):
        return False
    mode = phone_mode(cfg, now)[0]
    if mode == "away":
        idle = idle_seconds()
        return idle is None or idle >= float(cfg["ntfy"].get("away_minutes") or 0) * 60
    return mode == "always"


def ntfy_opener(n):
    """Proxy for the push. ntfy.proxy: "none" = direct, a URL = that proxy, "" = HTTPS_PROXY / HTTP_PROXY
    from the environment, else the Windows system proxy. urllib alone skips the system proxy as soon
    as any *_proxy variable (even NO_PROXY) is set, and going direct through a TUN proxy means local
    DNS, which can stall for seconds."""
    proxy = n.get("proxy") or ""
    host = urllib.parse.urlsplit(n["server"]).hostname or ""
    bypass = urllib.request.proxy_bypass_environment(host) or (
        os.name == "nt" and urllib.request.proxy_bypass_registry(host))
    if proxy == "none" or (not proxy and bypass):
        proxies = {}
    elif proxy:
        proxies = {"http": proxy, "https": proxy}
    else:
        env = urllib.request.getproxies_environment()
        found = env if ("https" in env or "http" in env) else (
            urllib.request.getproxies_registry() if os.name == "nt" else {})
        proxies = {k: v for k, v in found.items() if k in ("http", "https")}
    return urllib.request.build_opener(urllib.request.ProxyHandler(proxies))


def send_ntfy(note, cfg):
    """POST one message; returns the server's JSON reply (has the message id)."""
    n = cfg["ntfy"]
    lines = [note["where"]] + ([note["detail"]] if n.get("detail", True) and note["detail"] else [])
    body = {
        "topic": n["topic"],
        "title": f"{note['headline']} · {note['title']}",
        "message": "\n".join(lines),
        "priority": int(note.get("priority") or 3),
    }
    req = urllib.request.Request(
        n["server"].rstrip("/") + "/", data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    if n.get("token"):
        req.add_header("Authorization", "Bearer " + n["token"])
    with ntfy_opener(n).open(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8") or "{}")


def main():
    p = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace"))
    event = p.get("hook_event_name", "")
    sid = str(p.get("session_id") or "unknown")
    now = time.time()
    if os.path.exists(DEBUG_FLAG):
        log(f"event {event} {sid[:8]} {p.get('notification_type') or p.get('tool_name') or ''}"
            f"{' agent=' + str(p['agent_id'])[:8] if p.get('agent_id') else ''}")
    loaded = load_state(sid)
    if loaded is None:
        log(f"{event} {sid[:8]}: state file stayed locked, this event leaves it alone")
    st = dict(loaded or {})
    if st.get("toasted") and event in ("UserPromptSubmit", "PostToolUse", "SessionEnd"):
        st["toasted"] = False
        spawn_toast({"clear": True, "tag": sid[:64]})
    if event == "SessionEnd":
        cleanup(sid, now)
        return

    def persist():  # write only real changes: most PostToolUse hooks change nothing
        if loaded is not None and st != loaded:
            save_state(sid, st)

    cfg = load_config()
    built = build(event, p, st, cfg, now)
    if not built:
        persist()
        return

    headline, detail = built
    project = os.path.basename(os.path.normpath(p.get("cwd") or "")) or "?"
    title = oneline(session_title(p.get("transcript_path")), 60) or project
    where = " · ".join(x for x in (machine_name(cfg), project, terminal_label()) if x)
    done = event == "Stop" or p.get("notification_type") == "agent_completed"
    note = {"headline": headline, "title": title, "where": where, "detail": detail,
            "priority": cfg["ntfy"].get("priority_done" if done else "priority")}
    push = phone_wanted(cfg, now)
    log(f"{event}/{p.get('notification_type') or p.get('tool_name') or '-'} {sid[:8]} {headline} | {title} | "
        f"{detail[:60]}{' | 📱' if push else ''}")

    seq = ""
    if cfg.get("osc777"):
        seq += f"\x1b]777;notify;{osc_text(headline + ' · ' + title)};{osc_text(where + ' — ' + detail)}\x07"
    if cfg.get("bell"):
        seq += "\x07"
    if cfg.get("toast") and os.name == "nt":
        spawn_toast({"title": f"{headline} · {title}", "lines": [where, detail], "tag": sid[:64],
                     "sound": bool(cfg.get("toast_sound")), "persist": bool(cfg.get("toast_persist"))})
        st["toasted"] = True
    persist()
    if push:
        spawn([sys.executable, os.path.abspath(__file__), "--ntfy", b64(note)])
    if seq:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stdout.write(json.dumps({"terminalSequence": seq}))


MODE_TEXT = {"always": "总是推送", "away": "离开电脑时才推", "off": "不推送"}


def parse_duration(text):
    m = re.fullmatch(r"(\d+(?:\.\d+)?)([smhd]?)", text.strip().lower())
    if not m:
        raise ValueError(f"看不懂的时长 {text!r}，请用 30m / 2h / 1d 这样的写法")
    return float(m.group(1)) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2) or "m"]


def phone_cli(args):
    """`phone ...` subcommand: switch, inspect or test the phone channel. Returns the exit code."""
    sys.stdout.reconfigure(encoding="utf-8")
    cfg = load_config()
    n = cfg["ntfy"]
    now = time.time()
    cmd = args[0].lower() if args else "status"

    if cmd in PHONE_MODES:
        try:
            until = now + parse_duration(args[1]) if len(args) > 1 else None
        except ValueError as e:
            print(e)
            return 2
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(PHONE_PATH, "w", encoding="utf-8") as f:
            json.dump({"mode": PHONE_MODES[cmd], "until": until}, f)
    elif cmd == "reset":
        try:
            os.remove(PHONE_PATH)
        except FileNotFoundError:
            pass
    elif cmd == "test":
        if not n.get("topic"):
            print(f"{CONFIG_PATH} 里 ntfy.topic 为空，先填一个")
            return 1
        note = {"headline": "🧪 测试推送", "title": "cc_notify", "priority": n.get("priority"),
                "where": f"{machine_name(cfg)} · {time.strftime('%H:%M:%S')}",
                "detail": "手机上看到这条，就说明订阅配置好了"}
        try:
            reply = send_ntfy(note, cfg)
        except Exception as e:
            print(f"发送失败：{type(e).__name__}: {e}\n检查本机能否访问 {n['server']}（走代理时看系统代理或 HTTPS_PROXY）")
            return 1
        print(f"已发送到 {n['server'].rstrip('/')}/{n['topic']}（消息 id {reply.get('id')}）")
        return 0
    elif cmd != "status":
        print("用法：ccphone [on|off|away] [30m|2h|1d]   临时切换，不写时长就保持到下次切换\n"
              "      ccphone reset                        回到 cc_notify.json 里的 ntfy.mode\n"
              "      ccphone status | test")
        return 2

    if not n.get("topic"):
        print(f"手机推送：关闭（{CONFIG_PATH} 里 ntfy.topic 为空）")
        return 0
    mode, until, overridden = phone_mode(cfg, now)
    if until:
        source = f"临时设置，{time.strftime('%m-%d %H:%M', time.localtime(until))} 后恢复为 {n.get('mode')}"
    elif overridden:
        source = "临时设置，直到 ccphone reset"
    else:
        source = "cc_notify.json 的默认值"
    print(f"手机推送：{MODE_TEXT[mode]}（{mode}）  ← {source}")
    if mode == "away":
        idle = idle_seconds()
        if idle is None:
            print("  这台机器读不到键鼠空闲时间，away 等同于 always")
        else:
            print(f"  键鼠空闲 ≥ {n.get('away_minutes')} 分钟算离开；当前已空闲 {fmt_duration(idle)}"
                  f" → 现在有事件{'会' if phone_wanted(cfg, now) else '不会'}推送")
    print(f"推送目标：{n['server'].rstrip('/')}/{n['topic']}")
    return 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["phone"]:
        sys.exit(phone_cli(sys.argv[2:]))
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--ntfy":
            send_ntfy(json.loads(base64.b64decode(sys.argv[2]).decode("utf-8")), load_config())
        else:
            main()
    except Exception as e:  # never let a notifier break the turn
        log(f"{' '.join(sys.argv[1:2]) or 'hook'}: {type(e).__name__}: {e}")
    sys.exit(0)
