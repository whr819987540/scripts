#!/usr/bin/env bash
# Claude Code status line: model(effort) | cwd (branch) | ctx in+out/max | decode speed / cache hit (current/session)
# Reads the status-line JSON payload from stdin and prints one formatted line, or two
# when the terminal is too narrow (the second one cut with "…"); see "layout" below.
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

# ---- colors (dim-friendly ANSI 256; real ESC bytes, printed with %s) ----
C_RESET=$'\033[0m'
C_MODEL=$'\033[38;5;110m'
C_PATH=$'\033[38;5;108m'
C_BRANCH=$'\033[38;5;180m'
C_CTX=$'\033[38;5;146m'
C_PERF=$'\033[38;5;244m'
C_TIME=$'\033[38;5;103m'
C_WARN=$'\033[38;5;173m'

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

# no wall-clock fallback: a refresh must never move this time
req_time="${_f[7]}"
[ -n "$req_time" ] || req_time="--:--:--"
req_flag="${_f[8]}"

# ---- segments, in display order ----
# Plain text + color per piece, joined by single spaces. glue=1 keeps a piece on
# the same line as the one before it (branch after path, flag after time); the
# layout below may wrap between any other two pieces.
P_TEXT=() P_COLOR=() P_GLUE=()
add_piece() { P_TEXT+=("$1"); P_COLOR+=("$2"); P_GLUE+=("${3:-0}"); }

add_piece "$model_seg" "$C_MODEL"
add_piece "$disp_path" "$C_PATH"
[ -n "$branch" ] && add_piece "(${branch}${dirty})" "$C_BRANCH" 1
add_piece "ctx:${ctx_seg}" "$C_CTX"
add_piece "decode:${decode_str}" "$C_PERF"
add_piece "hit:${hit_cur_str}/${hit_session_str}" "$C_PERF"
# cost, then 5h / 7d subscription usage as "5h:16%→21:00"; a window at 80%+ turns
# the warning color.
[ -n "${_f[9]}" ] && add_piece "cost:${_f[9]}" "$C_PERF"
win_names=(5h 7d)
for i in 0 1; do
  name="${win_names[i]}" pct="${_f[10 + 2 * i]}" reset="${_f[11 + 2 * i]}"
  if [ "$reset" = "已重置" ]; then
    add_piece "${name}:已重置" "$C_PERF"
    continue
  fi
  [ -n "$pct" ] || continue
  if [ "$pct" -ge 80 ]; then c="$C_WARN"; else c="$C_PERF"; fi
  add_piece "${name}:${pct}%${reset:+→$reset}" "$c"
done
add_piece "$req_time" "$C_TIME"
[ -n "$req_flag" ] && add_piece "$req_flag" "$C_WARN" 1

# ---- layout: at most two lines, the second one cut with "…" ----
# Claude Code cuts each status line at the footer width without wrapping. That
# width is $COLUMNS (Claude Code sets it for the command) minus the footer's side
# padding (2 columns per side in the default layout, 0 in some fullscreen ones)
# and minus the statusLine "padding" setting (per side). STATUSLINE_RESERVE is
# that total: 4 + 2 * padding; set it to 0 if the line sits flush against the
# left edge of the terminal.
STATUSLINE_RESERVE="${STATUSLINE_RESERVE:-4}"

# Widths need a UTF-8 locale (so ${#s} counts characters, not bytes); bash
# switches locale the moment LC_ALL is assigned.
utf8=0
for loc in C.UTF-8 en_US.UTF-8; do
  LC_ALL="$loc"
  t="中"
  if [ "${#t}" -eq 1 ]; then utf8=1; break; fi
done 2>/dev/null

# Terminal columns of one character -> CW: 2 for East Asian wide / fullwidth,
# 0 for combining marks and zero-width joiners/selectors, 1 otherwise (ambiguous
# ones such as → and … count as 1, the same way Claude Code measures them).
ch_w() {
  local cp
  printf -v cp '%d' "'$1"
  if (( (cp >= 0x300 && cp <= 0x36F) || (cp >= 0x200B && cp <= 0x200F) || (cp >= 0xFE00 && cp <= 0xFE0F) )); then
    CW=0
  elif (( (cp >= 0x1100 && cp <= 0x115F) || (cp >= 0x2E80 && cp <= 0x303E) || (cp >= 0x3041 && cp <= 0x33FF)
       || (cp >= 0x3400 && cp <= 0x4DBF) || (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0xA000 && cp <= 0xA4CF)
       || (cp >= 0xAC00 && cp <= 0xD7A3) || (cp >= 0xF900 && cp <= 0xFAFF) || (cp >= 0xFE30 && cp <= 0xFE4F)
       || (cp >= 0xFF00 && cp <= 0xFF60) || (cp >= 0xFFE0 && cp <= 0xFFE6) || (cp >= 0x1F300 && cp <= 0x1F64F)
       || (cp >= 0x1F900 && cp <= 0x1F9FF) || (cp >= 0x20000 && cp <= 0x3FFFD) )); then
    CW=2
  else
    CW=1
  fi
}

# Display width of $1 -> DW. Globals, not $(...): every fork costs on Git Bash.
dw() {
  local s="$1" i n=0
  if [[ "$s" != *[![:ascii:]]* ]]; then DW=${#s}; return; fi
  for ((i = 0; i < ${#s}; i++)); do ch_w "${s:i:1}"; ((n += CW)); done
  DW=$n
}

# Longest prefix of $1 that fits in $2 columns -> CUT_HEAD, the rest -> CUT_REST.
cut_w() {
  local s="$1" max="$2" i n=0
  if [[ "$s" != *[![:ascii:]]* ]]; then CUT_HEAD="${s:0:max}" CUT_REST="${s:max}"; return; fi
  for ((i = 0; i < ${#s}; i++)); do
    ch_w "${s:i:1}"
    if (( n + CW > max )); then break; fi
    ((n += CW))
  done
  CUT_HEAD="${s:0:i}" CUT_REST="${s:i}"
}

n=${#P_TEXT[@]}
W=$(( ${COLUMNS:-0} - STATUSLINE_RESERVE ))
out1="" out2=""

if [ "$utf8" -ne 1 ] || [ "$W" -lt 20 ]; then
  # width unknown (or absurdly small): one line, as before; Claude Code cuts it
  for ((k = 0; k < n; k++)); do
    (( k > 0 )) && out1+=" "
    out1+="${P_COLOR[k]}${P_TEXT[k]}${C_RESET}"
  done
else
  P_W=()
  for ((k = 0; k < n; k++)); do dw "${P_TEXT[k]}"; P_W[k]=$DW; done

  # Line 1: whole units (a piece plus the pieces glued to it) while they fit.
  # Everything after goes to line 2 as a flat list L2_* (space-joined).
  L2_TEXT=() L2_COLOR=()
  used=0 k=0
  while (( k < n )); do
    j=$((k + 1)) uw=${P_W[k]}
    while (( j < n && P_GLUE[j] == 1 )); do ((uw += 1 + P_W[j], j++)); done
    sep=$(( used > 0 ? 1 : 0 ))
    if (( used + sep + uw <= W )); then
      for ((m = k; m < j; m++)); do
        (( m > k || used > 0 )) && out1+=" "
        out1+="${P_COLOR[m]}${P_TEXT[m]}${C_RESET}"
      done
      ((used += sep + uw))
      k=$j
      continue
    fi
    # fits on a line of its own: line 2 starts with it
    (( uw <= W )) && break
    # Wider than a whole line, so the glue has to give: place its pieces one by
    # one, wrap at the first piece that does not fit, and cut a piece mid-text
    # only when that piece alone is wider than a line.
    for ((m = k; m < j; m++)); do
      sep=$(( used > 0 ? 1 : 0 ))
      if (( used + sep + P_W[m] <= W )); then
        (( sep )) && out1+=" "
        out1+="${P_COLOR[m]}${P_TEXT[m]}${C_RESET}"
        ((used += sep + P_W[m]))
        continue
      fi
      if (( P_W[m] <= W )); then
        for ((; m < j; m++)); do L2_TEXT+=("${P_TEXT[m]}") L2_COLOR+=("${P_COLOR[m]}"); done
        break
      fi
      room=$(( W - used - sep ))
      if (( room > 0 )); then
        cut_w "${P_TEXT[m]}" "$room"
        (( sep )) && out1+=" "
        out1+="${P_COLOR[m]}${CUT_HEAD}${C_RESET}"
        L2_TEXT+=("$CUT_REST") L2_COLOR+=("${P_COLOR[m]}")
      else
        L2_TEXT+=("${P_TEXT[m]}") L2_COLOR+=("${P_COLOR[m]}")
      fi
      for ((m++; m < j; m++)); do L2_TEXT+=("${P_TEXT[m]}") L2_COLOR+=("${P_COLOR[m]}"); done
      break
    done
    k=$j
    break
  done
  for ((; k < n; k++)); do L2_TEXT+=("${P_TEXT[k]}") L2_COLOR+=("${P_COLOR[k]}"); done

  # Line 2: everything left if it fits, else cut so that "…" ends the line.
  n2=${#L2_TEXT[@]}
  if (( n2 > 0 )); then
    L2_W=() total=0
    for ((m = 0; m < n2; m++)); do
      dw "${L2_TEXT[m]}"; L2_W[m]=$DW
      ((total += (m > 0 ? 1 : 0) + DW))
    done
    budget=$W
    (( total > W )) && budget=$((W - 1))
    used=0
    for ((m = 0; m < n2; m++)); do
      sep=$(( m > 0 ? 1 : 0 ))
      if (( used + sep + L2_W[m] <= budget )); then
        (( sep )) && out2+=" "
        out2+="${L2_COLOR[m]}${L2_TEXT[m]}${C_RESET}"
        ((used += sep + L2_W[m]))
        continue
      fi
      room=$(( budget - used - sep ))
      if (( room > 0 )); then
        cut_w "${L2_TEXT[m]}" "$room"
        (( sep )) && out2+=" "
        out2+="${L2_COLOR[m]}${CUT_HEAD}…${C_RESET}"
      else
        out2+="${L2_COLOR[m]}…${C_RESET}"
      fi
      break
    done
  fi
fi

printf '%s' "$out1"
[ -n "$out2" ] && printf '\n%s' "$out2"
printf '\n'
