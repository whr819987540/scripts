#!/usr/bin/env bash
# Claude Code hook 入口：找一个能用的 Python 3 运行同目录的 cc_notify.py，参数和 stdin 原样传过去。
#
# 有的机器只有 python3，有的只有 python；Windows 上的 python3 / python 还可能是 WindowsApps 里的
# 应用执行别名占位程序，一运行就失败。所以 settings.json 里的 hook 命令统一写
#   bash "$HOME/.claude/hooks/cc_notify.sh"
# 由这里按 python3、python、py 的顺序挑第一个不在 WindowsApps 里的解释器（和 statusline.sh 的做法相同）。

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for cand in python3 python py; do
  p="$(command -v "$cand" 2>/dev/null)" || continue
  [ -n "$p" ] || continue
  case "$p" in *WindowsApps*) continue ;; esac
  if [ "$cand" = "py" ]; then
    exec "$p" -3 "$here/cc_notify.py" "$@"
  fi
  exec "$p" "$here/cc_notify.py" "$@"
done

echo "cc_notify: 找不到可用的 Python 3（试过 python3、python、py）" >&2
exit 1
