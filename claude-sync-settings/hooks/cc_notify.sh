#!/usr/bin/env bash
# Claude Code hook 入口：settings.json 里所有机器都写同一条命令
#   bash "$HOME/.claude/hooks/cc_notify.sh"
# 由这里决定这台机器跑哪个脚本、用哪个 Python，参数和 stdin 原样传过去。
#
# 跑哪个脚本：
#   - 不是 Windows，且同目录有 cc_notify_remote.py（如 Ubuntu 上经 ssh 把通知交给 Windows 中继的机器）：
#     跑 cc_notify_remote.py。它复用 cc_notify.py，只把 toast / ntfy 改为写 ~/.cc/notify/events.jsonl。
#     cc_notify_remote.py 是机器专属的，不在仓库里、也不同步，有没有它就决定了这台机器的角色。
#   - 其他情况（Windows、没有 cc_notify_remote.py 的机器）跑 cc_notify.py。
#   - 带参数的调用（phone status / --ntfy ...）总是交给 cc_notify.py，cc_notify_remote.py 只处理 hook 事件。
#
# 用哪个 Python：有的机器只有 python3，有的只有 python；Windows 上的 python3 / python 还可能是
# WindowsApps 里的应用执行别名占位程序，一运行就失败。按 python3、python、py 的顺序挑第一个
# 不在 WindowsApps 里的解释器（和 statusline.sh 的做法相同）。

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

script="$here/cc_notify.py"
case "$(uname -s 2>/dev/null)" in
  MINGW* | MSYS* | CYGWIN*) ;;
  *) if [ $# -eq 0 ] && [ -f "$here/cc_notify_remote.py" ]; then script="$here/cc_notify_remote.py"; fi ;;
esac

for cand in python3 python py; do
  p="$(command -v "$cand" 2>/dev/null)" || continue
  [ -n "$p" ] || continue
  case "$p" in *WindowsApps*) continue ;; esac
  if [ "$cand" = "py" ]; then
    exec "$p" -3 "$script" "$@"
  fi
  exec "$p" "$script" "$@"
done

echo "cc_notify: 找不到可用的 Python 3（试过 python3、python、py）" >&2
exit 1
