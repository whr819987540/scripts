# Claude Code 状态栏安装步骤

`statusline.sh` 从标准输入读取 Claude Code 传入的状态 JSON，输出一行状态栏：模型（effort）、当前路径和 Git 分支、上下文用量、输出速度与缓存命中率、费用和订阅用量、最近一次请求的完成时间。解析 JSON 需要 Python 3，没有 Python 时退回用 `jq` 显示基本字段。

通常由 [`sync.py`](sync.md) 一并同步，下面是手动安装的步骤。

1. 下载脚本到 Claude Code 配置目录。

   ```bash
   claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
   mkdir -p "$claude_dir"
   curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/claude-sync-settings/statusline.sh \
       -o "$claude_dir/statusline.sh"
   ```

2. 在 `settings.json` 中启用状态栏，与 `shared-settings.json` 中的配置相同：

   ```json
   "statusLine": {
     "type": "command",
     "command": "bash \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline.sh\"",
     "padding": 0
   }
   ```

3. 用一份示例 JSON 测试输出，应看到带颜色的一行状态栏。

   ```bash
   printf '{"model":{"display_name":"Opus 5.5 (1M context)"},"effort":{"level":"xhigh"},"workspace":{"current_dir":"%s"},"context_window":{"total_input_tokens":12000,"context_window_size":1000000}}' "$PWD" |
       bash "$claude_dir/statusline.sh"
   ```

   示例 JSON 里没有对话记录，所以输出速度、缓存命中率和请求时间显示为 `n/a` 或 `--:--:--`；在 Claude Code 里运行时会显示实际数值。
