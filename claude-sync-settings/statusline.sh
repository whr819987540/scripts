#!/usr/bin/env bash
# Claude Code status line: model(effort) | cwd (branch) | ctx in+out/max | decode speed / cache hit (current/session)
# Reads the status-line JSON payload from stdin and prints one formatted line.
#
# Portability note (Windows/Git-Bash): jq is usually absent and `python3` resolves
# to the WindowsApps stub, which exits non-zero without output. So we resolve a
# real interpreter ourselves and do all JSON + transcript work in one python pass;
# jq is only a fallback for the basic fields.

input="$(cat)"

# ---- resolve a usable python (skip the WindowsApps App-Execution-Alias stub) ----
py_cmd=""
for cand in python3 python py; do
  p="$(command -v "$cand" 2>/dev/null)" || continue
  [ -n "$p" ] || continue
  case "$p" in *WindowsApps*) continue ;; esac
  if [ "$cand" = "py" ]; then py_cmd="py -3"; else py_cmd="$cand"; fi
  break
done

# ---- one pass: parse the payload and mine the transcript tail ----
# Emits 8 lines: model_seg, disp_path, ctx_seg, hit_current, decode, hit_session, raw_cwd, now
# `tr -d "\r"`: python on Windows writes CRLF, and a stray CR both garbles the
# rendered line and makes the `-d "$raw_cwd"` test below fail.
_f=()
if [ -n "$py_cmd" ]; then
  mapfile -t _f < <(printf '%s' "$input" | $py_cmd -c '
import sys, json, os, re, statistics
from datetime import datetime, timezone

def g(obj, path, default=None):
    cur = obj
    for k in path.split("."):
        if not isinstance(cur, dict):
            return default
        cur = cur.get(k)
        if cur is None:
            return default
    return cur

def fmt_k(n):
    try:
        n = float(n)
    except Exception:
        return "?"
    if n >= 1000:
        k = n / 1000.0
        return "%dk" % int(k) if abs(k - int(k)) < 1e-9 else "%.1fk" % k
    return "%d" % int(n)

def parse_ts(ts):
    if not ts:
        return None
    ts = ts.rstrip("Z")
    if "." in ts:
        base, frac = ts.split(".", 1)
        frac = "".join(ch for ch in frac if ch.isdigit())
        ts = base + "." + (frac + "000000")[:6]
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(ts, fmt)
        except Exception:
            continue
    return None

# stdin/stdout are locale-encoded on Windows (e.g. gbk on a zh-CN box), so a payload
# with non-ASCII in the cwd blows up on read and prints mojibake on write. Force UTF-8.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass
try:
    data = json.loads(sys.stdin.buffer.read().decode("utf-8", "replace") or "{}")
except Exception:
    data = {}

model = g(data, "model.display_name") or g(data, "model.id") or "?"
# "Opus 5.5 (1M context)" -> "Opus 5.5 1M"
model = re.sub(r"\s*\((\S+) context\)", r" \1", model)
effort = g(data, "effort.level") or ""
model_seg = "%s(%s)" % (model, effort) if effort else model

# ---- current path, abbreviate $HOME as ~ (payload is native-separated) ----
# Path rules are platform-specific: only Windows treats "\" as a separator and
# compares paths case-insensitively. On POSIX "\" is a legal filename character
# and case is significant, so applying the Windows rules there mangles real paths.
WINDOWS = os.name == "nt"

def norm(p):
    if WINDOWS:
        p = p.replace("\\", "/")
    return p.rstrip("/") or "/"

def under_home(child, parent):
    if WINDOWS:
        child, parent = child.lower(), parent.lower()
    return child == parent or child.startswith(parent + "/")

cwd = g(data, "workspace.current_dir") or data.get("cwd") or "?"
cwd_n, home_n = norm(cwd), norm(os.path.expanduser("~"))
if home_n not in ("", "/") and under_home(cwd_n, home_n):
    disp_path = "~" + cwd_n[len(home_n):]
else:
    disp_path = cwd_n or "?"

# "in+out/max": input of the latest request (the whole prompt, not a session total
# despite the name), plus the output of the reply to it -- a running count while
# it streams, final once it completes. That output joins the context next request.
ctx_used = g(data, "context_window.total_input_tokens")
ctx_max = g(data, "context_window.context_window_size")
ctx_out = g(data, "context_window.current_usage.output_tokens")
if ctx_used is not None and ctx_max is not None:
    ctx_seg = "%s%s/%s" % (fmt_k(ctx_used), "+" + fmt_k(ctx_out) if ctx_out is not None else "", fmt_k(ctx_max))
else:
    ctx_seg = "n/a"

# ---- cache hit rate for the current request, straight from the payload ----
cu = g(data, "context_window.current_usage") or {}
r = cu.get("cache_read_input_tokens") or 0
c = cu.get("cache_creation_input_tokens") or 0
i = cu.get("input_tokens") or 0
denom = r + c + i
hit_cur = ("%.0f%%" % (r / denom * 100.0)) if denom > 0 else "n/a"

# ---- session cache hit rate: Claude Code computes it itself ----
# prompt_cache.hit_ratio = cache_read / (cache_read + cache_creation + input) summed
# over every request of the session (verified against the transcript to 6 decimals).
hr = g(data, "prompt_cache.hit_ratio")
hit_sess = ("%.0f%%" % (hr * 100.0)) if isinstance(hr, (int, float)) else "n/a"

# ---- session cost & subscription usage windows, straight from the payload ----
# total_cost_usd is Claude Code own estimate at API prices (the /cost figure); on a
# subscription it is notional, not billed. rate_limits exists only for subscribers,
# and only once a response has come back.
cost_usd = g(data, "cost.total_cost_usd")
cost_str = ("$%.2f" % cost_usd) if isinstance(cost_usd, (int, float)) else ""

# Each window -> (used %, reset): reset is local "HH:MM" today, else "周X HH:MM"
# (unambiguous inside 7 days). Once resets_at has passed, the figures are from
# before the reset -- they only refresh with the next response -- so the window
# shows as reset instead of a stale percentage.
WEEKDAYS = "一二三四五六日"

def window(key):
    used = g(data, "rate_limits.%s.used_percentage" % key)
    if not isinstance(used, (int, float)):
        return "", ""
    at = g(data, "rate_limits.%s.resets_at" % key)
    if not isinstance(at, (int, float)):
        return "%.0f" % used, ""
    now = datetime.now().astimezone()
    rt = datetime.fromtimestamp(at, timezone.utc).astimezone()
    if rt <= now:
        return "", "已重置"
    if rt.date() == now.date():
        return "%.0f" % used, rt.strftime("%H:%M")
    return "%.0f" % used, "周" + WEEKDAYS[rt.weekday()] + rt.strftime("%H:%M")

rl5, rl5_reset = window("five_hour")
rl7, rl7_reset = window("seven_day")

# ---- output speed from the transcript tail ----
decode_str = "n/a"
transcript = data.get("transcript_path") or ""
lines = []
if transcript and os.path.isfile(transcript):
    TAIL_BYTES = 2000000
    try:
        with open(transcript, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - TAIL_BYTES))
            chunk = f.read()
        lines = chunk.decode("utf-8", "replace").splitlines()
        if size > TAIL_BYTES and lines:
            lines = lines[1:]   # first line is a partial record
        lines = lines[-400:]
    except Exception:
        lines = []

# Claude Code writes one JSONL line per content block (thinking / text / tool_use)
# and every line repeats the full usage of its response, so group lines by
# message.id -- counting raw lines counts every output token 2-3 times.
# A response runs from the user record that triggered it (prompt or tool_result;
# not "attachment", whose timestamp can land after the request went out) to its
# last block.
resps, order, last_user = {}, [], None
last_req = None   # (end time, "" | why it did not complete) of the latest request
for line in lines:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if obj.get("isSidechain"):
        continue
    t = parse_ts(obj.get("timestamp"))
    if t is None:
        continue
    typ = obj.get("type")
    if typ == "user":
        last_user = t
        # Esc while a request streams. Not "... for tool use": that one stops a
        # running tool, and the request before it had already completed.
        c = (obj.get("message") or {}).get("content")
        if c == "[Request interrupted by user]" or (isinstance(c, list) and any(
                isinstance(b, dict) and b.get("text") == "[Request interrupted by user]" for b in c)):
            last_req = (t, "中断")
    elif typ == "assistant":
        msg = obj.get("message") or {}
        # A failed request leaves one <synthetic> record flagged isApiErrorMessage
        # (error: rate_limit, server_error = connection lost mid-response, ...).
        # Other <synthetic> records are partial output saved on Esc (marked by the
        # interrupt record above) or "No response requested." (no request at all).
        if obj.get("isApiErrorMessage"):
            last_req = (t, "用量耗尽" if obj.get("error") == "rate_limit" else "出错")
        elif msg.get("model") != "<synthetic>":
            last_req = (t, "")
        mid, usage = msg.get("id"), msg.get("usage")
        if not mid or not usage:
            continue
        e = resps.get(mid)
        if e is None:
            resps[mid] = e = {"start": last_user, "end": t}
            order.append(mid)
        e["end"] = max(e["end"], t)
        e["usage"] = usage

# Pure generation speed. Each span is time-to-first-token + output_tokens / speed,
# and TTFT cannot be read off the transcript: block timestamps are receive times,
# and a text block that follows thinking often lands within ms of it. So fit
# span = TTFT + out * slope over the last 20 responses with a Theil-Sen line
# (median of pairwise slopes), which shrugs off the odd stalled request;
# 1 / slope is the speed. Pairs closer than 200 output tokens are too noisy to use.
pts = []
for m in order:
    e = resps[m]
    out = e["usage"].get("output_tokens") or 0
    if e["start"] is None or out <= 0:
        continue
    span = (e["end"] - e["start"]).total_seconds()
    if 0 < span <= 600:
        pts.append((out, span))
pts = pts[-20:]
slopes = [(y2 - y1) / (x2 - x1) for i, (x1, y1) in enumerate(pts)
          for (x2, y2) in pts[i + 1:] if abs(x2 - x1) >= 200]
if len(slopes) >= 5:
    slope = statistics.median(slopes)
    if slope > 0:
        decode_str = "%.0f" % (1.0 / slope)

# older Claude Code without prompt_cache: same formula, deduped, over the tail only
if hit_sess == "n/a" and order:
    us = [resps[m]["usage"] for m in order]
    d = sum((u.get("input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0)
            + (u.get("cache_creation_input_tokens") or 0) for u in us)
    if d > 0:
        hit_sess = "%.0f%%" % (sum(u.get("cache_read_input_tokens") or 0 for u in us) / d * 100.0)

# When the latest request ended: its last block (records are written once the
# response completes) or its error / interrupt record. Taken from the transcript,
# so a refreshInterval tick leaves it alone. Local time, with the date once it is
# not today. Converted here, not with `date`: the shell Claude Code spawns can
# carry a TZ that MSYS cannot resolve, and it then silently reports UTC.
req_time, req_flag = "--:--:--", ""
if last_req:
    lt = last_req[0].replace(tzinfo=timezone.utc).astimezone()
    today = lt.date() == datetime.now().astimezone().date()
    req_time = lt.strftime("%H:%M:%S" if today else "%m-%d %H:%M:%S")
    req_flag = last_req[1]
for s in (model_seg, disp_path, ctx_seg, hit_cur, decode_str, hit_sess, cwd_n, req_time, req_flag,
          cost_str, rl5, rl5_reset, rl7, rl7_reset):
    print(s)
' 2>/dev/null | tr -d "\r")
fi

# ---- fallback: no usable python, but jq is around -> basic fields only ----
if [ "${#_f[@]}" -lt 14 ] && command -v jq >/dev/null 2>&1; then
  # mirror the python stage: rewrite "\" to "/" on Windows only
  case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) win=1 ;;
    *) if [ "${OS:-}" = "Windows_NT" ]; then win=1; else win=0; fi ;;
  esac
  mapfile -t _f < <(
    printf '%s' "$input" | jq -r --argjson win "$win" '
      def slash: if $win == 1 then gsub("\\\\"; "/") else . end;
      ((.model.display_name // .model.id // "?") | sub("\\s*\\((?<c>\\S+) context\\)"; " \(.c)"))
        + (if (.effort.level // "") == "" then "" else "(" + .effort.level + ")" end),
      ((.workspace.current_dir // .cwd // "?") | slash),
      "n/a", "n/a", "n/a", "n/a",
      ((.workspace.current_dir // .cwd // "") | slash),
      "", "", "", "", "", "", ""
    ' | tr -d "\r"
  )
fi

model_seg="${_f[0]:-?}"
disp_path="${_f[1]:-?}"
ctx_seg="${_f[2]:-n/a}"
hit_cur_str="${_f[3]:-n/a}"
decode_str="${_f[4]:-n/a}"
hit_session_str="${_f[5]:-n/a}"

# ---- colors (dim-friendly ANSI 256) ----
C_RESET="\033[0m"
C_MODEL="\033[38;5;110m"
C_PATH="\033[38;5;108m"
C_BRANCH="\033[38;5;180m"
C_CTX="\033[38;5;146m"
C_PERF="\033[38;5;244m"
C_TIME="\033[38;5;103m"
C_WARN="\033[38;5;173m"

# ---- git branch + dirty flag (skip optional locks; only if inside a repo) ----
# Uses the raw cwd from the payload, not the ~-abbreviated display form.
# One `status --porcelain=v2 --branch` call gives both: "# branch.head <name>"
# header, then one non-"#" line per changed/untracked path. Any such line => "*".
branch=""
dirty=""
raw_cwd="${_f[6]:-$PWD}"
if [ -d "$raw_cwd" ]; then
  while IFS= read -r line; do
    case "$line" in
      "# branch.head "*) branch="${line#"# branch.head "}" ;;
      "#"*) ;;
      *) dirty="*"; break ;;
    esac
  done < <(git -C "$raw_cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
fi
# detached HEAD: keep the old behavior of showing no branch
[ "$branch" = "(detached)" ] && branch=""

perf_seg="decode:${decode_str} hit:${hit_cur_str}/${hit_session_str}"
# no wall-clock fallback: a refresh must never move this time
req_time="${_f[7]}"
[ -n "$req_time" ] || req_time="--:--:--"
req_flag="${_f[8]}"

# cost, then 5h / 7d subscription usage as "5h:16%→21:00"; a window at 80%+ turns
# the warning color. Holds raw escape codes, so it is printed with %b.
usage_seg=""
[ -n "${_f[9]}" ] && usage_seg=" ${C_PERF}cost:${_f[9]}${C_RESET}"
win_names=(5h 7d)
for i in 0 1; do
  name="${win_names[i]}" pct="${_f[10 + 2 * i]}" reset="${_f[11 + 2 * i]}"
  if [ "$reset" = "已重置" ]; then
    usage_seg+=" ${C_PERF}${name}:已重置${C_RESET}"
    continue
  fi
  [ -n "$pct" ] || continue
  if [ "$pct" -ge 80 ]; then c="$C_WARN"; else c="$C_PERF"; fi
  usage_seg+=" ${c}${name}:${pct}%${reset:+→$reset}${C_RESET}"
done

# ---- assemble the status line ----
printf "${C_MODEL}%s${C_RESET} ${C_PATH}%s${C_RESET}" "$model_seg" "$disp_path"
if [ -n "$branch" ]; then
  printf " ${C_BRANCH}(%s%s)${C_RESET}" "$branch" "$dirty"
fi
printf " ${C_CTX}ctx:%s${C_RESET} ${C_PERF}%s${C_RESET}%b ${C_TIME}%s${C_RESET}" "$ctx_seg" "$perf_seg" "$usage_seg" "$req_time"
if [ -n "$req_flag" ]; then
  printf " ${C_WARN}%s${C_RESET}" "$req_flag"
fi
printf "\n"
