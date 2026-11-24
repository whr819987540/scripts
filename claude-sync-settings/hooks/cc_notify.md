# Claude Code 通知 hook 安装步骤

`cc_notify.py` 是 Claude Code 的 hook：一轮跑完、等你授权或回答、出错时，告诉你是哪台机器上的哪个会话。通知渠道有终端响铃、OSC 777 桌面通知、Windows toast，以及经 ntfy 推送到手机。所有事件都由这一个脚本处理，事件类型从 hook 传入的 JSON 里读取。只用标准库，需要 Python 3。

| 文件 | 作用 |
|---|---|
| `cc_notify.sh` | hook 入口。有的机器只有 `python3`，有的只有 `python`，Windows 上还可能是 WindowsApps 里的占位程序，所以由它按 `python3`、`python`、`py` 的顺序挑第一个不在 WindowsApps 里的解释器，再运行 `cc_notify.py` |
| `cc_notify.py` | 通知逻辑 |
| `cc_notify.json` | 各渠道的开关（JSONC，可以写注释）；缺少的键用 `cc_notify.py` 里的 `DEFAULTS` |
| `cc_notify_toast.ps1` | Windows toast 子进程，见 [`cc_notify_toast.md`](cc_notify_toast.md) |

通常由 [`sync.py`](../sync.md) 把这四个文件一并同步到 `~/.claude/hooks/`，`hooks` 配置也在 [`shared-settings.json`](../shared-settings.json) 里。下面是手动安装的步骤。

1. 下载到 `~/.claude/hooks`。设置了 `CLAUDE_CONFIG_DIR` 也放这里，因为 hook 命令写的是 `$HOME/.claude`。

   ```bash
   mkdir -p "$HOME/.claude/hooks"
   for f in cc_notify.sh cc_notify.py cc_notify.json cc_notify_toast.ps1; do
       curl -fsSL "https://gitee.com/hit_whr/scripts/raw/main/claude-sync-settings/hooks/$f" \
           -o "$HOME/.claude/hooks/$f"
   done
   ```

2. 在本机的 `cc_notify.json` 里填 `ntfy.topic`，手机 ntfy App 订阅同一个 topic。topic 相当于订阅密码，仓库是公开的，所以仓库里这份留空，`topic` 为空时手机推送关闭。填好后，同步时对 `hooks/cc_notify.json` 选 `[i]` 忽略，否则会被换回空 topic 的仓库版本；仓库里这个文件以后再有改动，还会再问一次。

   ```bash
   "${EDITOR:-vi}" "$HOME/.claude/hooks/cc_notify.json"
   ```

3. 在 `settings.json` 的 `hooks` 里为每个事件加同一条命令。完整列表照抄 `shared-settings.json`：`UserPromptSubmit`、`Stop`、`StopFailure`、`Notification`、`PreToolUse`（matcher 为 `AskUserQuestion|ExitPlanMode`）、`PostToolUse`（加 `"async": true`）、`SessionEnd`。其中一项长这样：

   ```json
   "Stop": [
     {"hooks": [{"type": "command", "command": "bash \"$HOME/.claude/hooks/cc_notify.sh\"", "timeout": 10}]}
   ]
   ```

4. 检查找到的 Python 和手机推送的状态，再发一条测试推送。

   ```bash
   bash "$HOME/.claude/hooks/cc_notify.sh" phone status
   bash "$HOME/.claude/hooks/cc_notify.sh" phone test
   ```

   输出「找不到可用的 Python 3」时，装一个 Python 3，或者让 `python3`、`python`、`py` 中的一个指向它。想临时切换手机推送、不改配置时，用 `phone on|off|away [30m|2h|1d]`；用 `phone reset` 恢复成 `cc_notify.json` 里的 `ntfy.mode`。

5. 没收到通知时查日志。hook 出错不会打断 Claude Code，只会记到日志里。

   ```bash
   tail -n 20 "$HOME/.claude/state/cc-notify/cc_notify.log"
   ```
