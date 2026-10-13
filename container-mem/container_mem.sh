#!/usr/bin/env bash
# container_mem.sh — 分析当前容器的内存占用（支持 cgroup v1 / v2）
#
# 用法: bash container_mem.sh [-n N]
#   -n N  进程和分组列表显示前 N 项（默认 15）
#
# 依次输出：总量与上限、内存组成、回收/OOM 事件、内存压力（PSI）、
# 按进程和按程序分组的占用，最后给出诊断结论。

set -u

TOP_N=15
while getopts "n:h" opt; do
  case $opt in
    n) TOP_N=$OPTARG ;;
    h) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) exit 1 ;;
  esac
done
case $TOP_N in
  '' | *[!0-9]*) echo "-n 需要一个正整数" >&2; exit 1 ;;
esac

if [ -t 1 ]; then
  BOLD=$'\e[1m' DIM=$'\e[2m' RED=$'\e[31m' YEL=$'\e[33m' GRN=$'\e[32m' RST=$'\e[0m'
else
  BOLD='' DIM='' RED='' YEL='' GRN='' RST=''
fi

# 字节数转成可读大小：10 GiB 以下用 MiB，以上用 GiB
size()     { awk -v b="$1" -v w="${2:-}" 'BEGIN {
               if (b >= 10737418240) printf "%" w ".1f GiB", b / 1073741824
               else                  printf "%" w ".1f MiB", b / 1048576 }'; }
size_col() { size "$1" 8; }                                                  # 右对齐，用于表格
pct()      { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f%%", (b > 0 ? a * 100 / b : 0) }'; }
clamp0()   { if [ "$1" -gt 0 ]; then echo "$1"; else echo 0; fi; }
stat_get() { awk -v k="$1" '$1 == k { print $2; exit }' "$STAT"; }
section()  { printf '\n%s[%s]%s\n' "$BOLD" "$1" "$RST"; }
say()      { printf '  %s%s%s %s\n' "$1" "$2" "$RST" "$3"; }

# ---------- 定位本容器的 cgroup ----------
# 有 cgroup namespace 时 /sys/fs/cgroup 就是本容器的；没有时按 /proc/self/cgroup 里的路径往下找
find_cgroup() {
  local rel d
  if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
    VER=2
    rel=$(awk -F: '$1 == "0" { print $3 }' /proc/self/cgroup 2>/dev/null)
    for d in /sys/fs/cgroup "/sys/fs/cgroup$rel"; do
      if [ -f "$d/memory.current" ]; then CG=$d; return 0; fi
    done
  elif [ -d /sys/fs/cgroup/memory ]; then
    VER=1
    rel=$(awk -F: '$2 ~ /(^|,)memory(,|$)/ { print $3 }' /proc/self/cgroup 2>/dev/null)
    for d in /sys/fs/cgroup/memory "/sys/fs/cgroup/memory$rel"; do
      if [ -f "$d/memory.usage_in_bytes" ]; then CG=$d; return 0; fi
    done
  fi
  return 1
}

if ! find_cgroup; then
  echo "没找到 cgroup 内存统计文件：可能不在容器里，或者没有启用 memory 控制器。" >&2
  exit 1
fi

# ---------- 读取 cgroup 数据（单位：字节） ----------
STAT=$CG/memory.stat
if [ "$VER" = 2 ]; then
  CUR=$(cat "$CG/memory.current")
  MAX=$(cat "$CG/memory.max")                          # "max" 表示无限制
  PEAK=$(cat "$CG/memory.peak" 2>/dev/null)            # 内核 5.19+ 才有
  ANON=$(stat_get anon) FILE=$(stat_get file) SHMEM=$(stat_get shmem)
  ACT=$(stat_get active_file) INACT=$(stat_get inactive_file)
  EV_MAX=$(awk '$1 == "max" { print $2 }' "$CG/memory.events")
  EV_OOM=$(awk '$1 == "oom" { print $2 }' "$CG/memory.events")
  EV_KILL=$(awk '$1 == "oom_kill" { print $2 }' "$CG/memory.events")
  PSI=$(grep -E '^(some|full) ' "$CG/memory.pressure" 2>/dev/null)   # 内核没开 PSI 时读不到
  if [ "$MAX" = max ]; then UNLIMITED=1; else UNLIMITED=0; fi
else
  CUR=$(cat "$CG/memory.usage_in_bytes")
  MAX=$(cat "$CG/memory.limit_in_bytes")
  PEAK=$(cat "$CG/memory.max_usage_in_bytes" 2>/dev/null)
  ANON=$(stat_get total_rss) FILE=$(stat_get total_cache) SHMEM=$(stat_get total_shmem)
  ACT=$(stat_get total_active_file) INACT=$(stat_get total_inactive_file)
  EV_MAX=$(cat "$CG/memory.failcnt" 2>/dev/null)
  EV_OOM=''                                            # v1 没有这个计数
  EV_KILL=$(awk '$1 == "oom_kill" { print $2 }' "$CG/memory.oom_control" 2>/dev/null)  # 内核 4.13+
  PSI=''                                               # v1 没有按 cgroup 统计的 PSI
  # v1 不设上限时是一个接近 2^63 的数
  if [ "$MAX" -ge 4611686018427387904 ]; then UNLIMITED=1; else UNLIMITED=0; fi
fi
: "${ANON:=0}" "${FILE:=0}" "${SHMEM:=0}" "${ACT:=0}" "${INACT:=0}" "${EV_MAX:=0}"

HOST_TOTAL=$(awk '/^MemTotal:/ { printf "%.0f", $2 * 1024 }' /proc/meminfo)
if [ "$UNLIMITED" = 1 ]; then
  LIMIT=$HOST_TOTAL LIMIT_NAME=宿主机总内存
else
  LIMIT=$MAX LIMIT_NAME=上限
fi
[ "${LIMIT:-0}" -gt 0 ] || LIMIT=1

OTHER=$(clamp0 $(( CUR - ANON - FILE )))    # 内核开销（slab、页表等）
WS=$(clamp0 $(( CUR - INACT )))             # working set，docker stats / kubectl top 显示的值
UNRECL=$(( ANON + SHMEM + OTHER ))          # 没有 swap 时回收不了的部分
FREE=$(clamp0 $(( LIMIT - CUR )))
HEADROOM=$(clamp0 $(( LIMIT - UNRECL )))
CUR_PCT=$(( CUR * 100 / LIMIT ))
UNRECL_PCT=$(( UNRECL * 100 / LIMIT ))

# ---------- 收集进程（直接读 /proc，不依赖 ps 的版本） ----------
SELF_CMD=$(tr '\0' ' ' 2>/dev/null < /proc/$$/cmdline)
collect_procs() {
  local d pid cmd mem
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    cmd=$(tr '\0' ' ' 2>/dev/null < "$d/cmdline") || continue
    [ -n "$cmd" ] || continue                       # 内核线程没有 cmdline
    [ "$cmd" = "$SELF_CMD" ] && continue            # 跳过本脚本自己
    mem=$(awk '/^VmRSS:/ { r = $2 } /^RssAnon:/ { a = $2 } END { print r + 0, a + 0 }' "$d/status" 2>/dev/null) || continue
    [ "${mem% *}" -gt 0 ] || continue
    printf '%s\t%s\t%s\t%s\n' "${mem% *}" "${mem#* }" "$pid" "${cmd% }"
  done
}
# 每行：RSS(kB) \t RssAnon(kB) \t PID \t 命令行，按 RSS 降序
# 先收集完再排序：直接接管道的话，sort 进程本身也会被统计进去
RAW_PROCS=$(collect_procs)
PROCS=$(printf '%s\n' "$RAW_PROCS" | sort -t $'\t' -k1,1nr)

# 把同一个程序的多个进程归到一组
GROUP_AWK='
function base(p) { sub(/.*\//, "", p); return p }
function group(cmd,   a, n, i, b, m) {
  if (cmd ~ /\.vscode-server\//)   return "VS Code Server"
  if (cmd ~ /\.cursor-server\//)   return "Cursor Server"
  if (cmd ~ /\.windsurf-server\//) return "Windsurf Server"
  n = split(cmd, a, " ")
  b = base(a[1]); sub(/^-/, "", b); sub(/:$/, "", b)    # 登录 shell 的 "-zsh"、"sshd:" 之类
  if (b ~ /^(python[0-9.]*|node)$/) {                   # 解释器按脚本名或模块名归组
    for (i = 2; i <= n; i++) {
      if (a[i] == "-m" && i < n) { split(a[i + 1], m, "."); return b " -m " m[1] }
      if (a[i] == "-c") return b " -c"
      if (a[i] !~ /^-/) return base(a[i])
    }
  }
  return b
}'
PGROUPS=$(printf '%s\n' "$PROCS" | awk -F'\t' "$GROUP_AWK"'
  NF >= 4 { g = group($4); rss[g] += $1; anon[g] += $2; cnt[g]++ }
  END { for (g in rss) printf "%d\t%d\t%d\t%s\n", rss[g], anon[g], cnt[g], g }' | sort -t $'\t' -k1,1nr)

COLS=$(tput cols 2>/dev/null) || COLS=120
[ "${COLS:-0}" -ge 60 ] 2>/dev/null || COLS=120
CMD_W=$(( COLS - 32 ))

# ================= 输出 =================
printf '%s容器内存分析%s  %s(cgroup v%s: %s)%s\n' "$BOLD" "$RST" "$DIM" "$VER" "$CG" "$RST"

section 总量
if [ "$UNLIMITED" = 1 ]; then
  echo "  内存上限    无限制  ${DIM}(下面的比例按宿主机总内存 $(size "$HOST_TOTAL") 计算)${RST}"
else
  echo "  内存上限    $(size_col "$LIMIT")"
fi
echo "  当前用量    $(size_col "$CUR")  占${LIMIT_NAME} $(pct "$CUR" "$LIMIT")"
echo "  剩余空间    $(size_col "$FREE")"
[ -n "$PEAK" ] && echo "  历史峰值    $(size_col "$PEAK")  占${LIMIT_NAME} $(pct "$PEAK" "$LIMIT")"
echo "  工作集      $(size_col "$WS")  占${LIMIT_NAME} $(pct "$WS" "$LIMIT")  ${DIM}= 当前用量 - inactive_file，即 docker stats / kubectl top 显示的值${RST}"

section 组成
row() { printf '  %-15s %s  %s\n' "$1" "$(size_col "$2")" "$3"; }
row anon            "$ANON"   "进程的堆、栈等匿名内存，不可回收"
row file            "$FILE"   "文件缓存，大部分可回收"
row "  active_file"   "$ACT"    "最近访问过的缓存"
row "  inactive_file" "$INACT"  "优先被回收的缓存"
row "  shmem"         "$SHMEM"  "/dev/shm 等共享内存，计入 file，没有 swap 时不可回收"
row other           "$OTHER"  "内核开销（slab、页表等）= 当前用量 - anon - file"
echo "  ${DIM}------------------------------${RST}"
echo "  不可回收合计    $(size_col "$UNRECL")  占${LIMIT_NAME} $(pct "$UNRECL" "$LIMIT")  ${DIM}= anon + shmem + other${RST}"

section "回收与 OOM 事件"
if [ "$VER" = 2 ]; then
  echo "  顶到上限    $EV_MAX 次  ${DIM}(memory.events max：每次都要靠回收内存腾出空间)${RST}"
  echo "  OOM         $EV_OOM 次"
  echo "  OOM kill    $EV_KILL 次  ${DIM}(进程因为内存不足被杀)${RST}"
else
  echo "  顶到上限    $EV_MAX 次  ${DIM}(memory.failcnt)${RST}"
  echo "  OOM kill    ${EV_KILL:--} 次"
fi

section "内存压力 (PSI)"
PSI_SOME10=''
if [ -n "$PSI" ]; then
  printf '%s\n' "$PSI" | sed 's/ total=.*//; s/^/  /'
  echo "  ${DIM}some：至少一个进程在等内存的时间比例；full：所有进程都在等的时间比例。avg10/60/300 是 10 秒、1 分钟、5 分钟的平均值${RST}"
  PSI_SOME10=$(printf '%s\n' "$PSI" | awk '$1 == "some" { sub(/avg10=/, "", $2); print $2 }')
else
  echo "  不可用（cgroup v1，或者内核没有开启 PSI）"
fi

section "进程 Top $TOP_N（按 RSS）"
printf '  %7s %10s %10s  %s\n' PID RSS RssAnon COMMAND
printf '%s\n' "$PROCS" | head -n "$TOP_N" | awk -F'\t' -v w="$CMD_W" 'NF >= 4 {
  cmd = $4; if (length(cmd) > w) cmd = substr(cmd, 1, w - 3) "..."
  printf "  %7s %8.1f M %8.1f M  %s\n", $3, $1 / 1024, $2 / 1024, cmd }'

section 按程序分组
printf '  %-28s %5s %10s %10s\n' GROUP PROCS RSS RssAnon
printf '%s\n' "$PGROUPS" | awk -F'\t' -v n="$TOP_N" 'NF >= 4 {
  if (++k <= n) printf "  %-28s %5d %8.1f M %8.1f M\n", substr($4, 1, 28), $3, $1 / 1024, $2 / 1024
  r += $1; a += $2; c += $3 }
  END {
    if (k > n) printf "  ... 另外 %d 组\n", k - n
    printf "  %-28s %5d %8.1f M %8.1f M\n", "TOTAL", c, r / 1024, a / 1024 }'
echo "  ${DIM}RSS 包含映射进内存的可执行文件等文件页，所以合计通常比 cgroup 的 anon 大；RssAnon 的合计更接近 anon${RST}"

section 结论
if [ "${EV_KILL:-0}" -gt 0 ]; then
  say "$RED" "[危险]" "已经发生过 $EV_KILL 次 OOM kill，有进程因为内存不足被杀掉了"
fi
if [ "$UNRECL_PCT" -ge 90 ]; then
  say "$RED" "[危险]" "不可回收内存占${LIMIT_NAME}的 $(pct "$UNRECL" "$LIMIT")，随时可能触发 OOM"
elif [ "$UNRECL_PCT" -ge 75 ]; then
  say "$YEL" "[注意]" "不可回收内存占${LIMIT_NAME}的 $(pct "$UNRECL" "$LIMIT")，比较紧张"
else
  say "$GRN" "[正常]" "不可回收内存占${LIMIT_NAME}的 $(pct "$UNRECL" "$LIMIT")，暂时没有 OOM 风险"
fi
if [ "$UNLIMITED" = 0 ]; then
  if [ "$UNRECL_PCT" -ge 50 ]; then
    say "" "[信息]" "进程内存（anon）再增长约 $(size "$HEADROOM") 就会触发 OOM；实际余量更小，因为还要留一部分活跃的文件缓存"
  fi
  if [ "$EV_MAX" -gt 0 ]; then
    if [ "$CUR_PCT" -ge 95 ]; then
      say "$YEL" "[注意]" "用量贴着上限（$(pct "$CUR" "$LIMIT")），已经顶到上限 ${EV_MAX} 次，一直靠回收文件缓存维持；频繁读文件的操作（import、编译、git 等）会变慢"
    else
      say "" "[信息]" "历史上顶到过上限 ${EV_MAX} 次，当前用量占上限 $(pct "$CUR" "$LIMIT")"
    fi
  fi
fi
if [ -n "$PSI_SOME10" ] && awk -v v="$PSI_SOME10" 'BEGIN { exit !(v >= 5) }'; then
  say "$YEL" "[注意]" "最近 10 秒里有 ${PSI_SOME10}% 的时间有进程在等内存，回收已经明显拖慢了运行速度"
fi
if [ -n "$PGROUPS" ]; then
  IFS=$'\t' read -r g_rss _ g_cnt g_name <<< "$(printf '%s\n' "$PGROUPS" | head -n 1)"
  say "" "[信息]" "占用最多的是 ${g_name}：${g_cnt} 个进程，RSS 共 $(size $(( g_rss * 1024 )))"
fi
if [ -d /root/autodl-tmp ] && [ "$UNLIMITED" = 0 ] && [ "$LIMIT" -le $(( 3 * 1073741824 )) ]; then
  say "$YEL" "[注意]" "这是 AutoDL 实例，内存上限只有 $(size "$LIMIT")，可能是无卡模式开机；编译或运行大模型（如 vLLM）请切换到有卡模式"
fi
