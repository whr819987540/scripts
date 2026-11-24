# Claude Code 配置同步步骤

`sync.py` 读取本目录的 `shared-settings.json`、`statusline.sh` 和 `hooks/` 下的通知 hook，与本机 `settings.json`、`~/.claude/statusline.sh`、`~/.claude/hooks/` 比对，逐项确认后写入（写入前自动备份）。共享配置 `$keep` 里列出的项（`rec` 写进 `env` 的代理和 CA 证书）任何模式下都不动，其他本机独有的项默认也保留。需要 Python 3.8+，比对规则见 [`README.md`](README.md)。

1. 确认要同步哪个配置目录。脚本开始比对前会列出候选：`~/.claude`（直接运行 `claude` 时用）、`rec` 的各个账号、`CLAUDE_CONFIG_DIR`，让你选一个，每次只改一个。`rec` 只给它启动的 `claude` 进程设置 `CLAUDE_CONFIG_DIR`，终端里通常看不到，可以先列出本机有哪些目录：

   ```bash
   ls -d "$HOME/.claude" "$HOME"/.rec/claude/accounts/*/config 2>/dev/null
   cat "$HOME/.rec/claude/current" 2>/dev/null   # rec 当前账号
   ```

   `statusline.sh` 和 `hooks/` 不管选哪个目录，总是写到 `~/.claude`，因为共享配置里的命令写的是 `$HOME/.claude/...`。

2. 下载同步脚本。先试 GitHub，5 秒内没有响应就改用 Gitee。

   ```bash
   curl -fsSL -m 5 https://raw.githubusercontent.com/whr819987540/scripts/main/claude-sync-settings/sync.py \
       -o /tmp/claude-sync.py ||
   curl -fsSL -m 15 https://gitee.com/hit_whr/scripts/raw/main/claude-sync-settings/sync.py \
       -o /tmp/claude-sync.py
   ```

3. 只看差异、不写入。脚本会先问是否开启严格比对（本机多出的项也列为删除），然后列出全部差异。

   ```bash
   python3 /tmp/claude-sync.py --dry-run
   ```

4. 正式同步。选 `[a]` 全部应用（删除项仍逐项确认），或选 `[e]` 逐项确认。

   ```bash
   python3 /tmp/claude-sync.py
   ```

   不想每次选目录时加 `--config-dir 目录`。访问 GitHub 需要代理时，先设置 `HTTPS_PROXY`；只想用某一个来源时加 `--source github` 或 `--source gitee`；之前选了「忽略」的项想重新询问时加 `--all`。

5. 检查写入结果。改动前的文件备份为 `settings.json.bak-sync-<时间>`，需要回退时复制回去即可。

   ```bash
   # 在所有候选目录里找最新的一份备份
   ls -t "$HOME"/.claude/settings.json.bak-sync-* "$HOME"/.rec/claude/accounts/*/config/settings.json.bak-sync-* 2>/dev/null | head -n 1
   ```

6. 删除下载的脚本。

   ```bash
   rm -f /tmp/claude-sync.py
   ```

调试本目录里未推送的改动时，在仓库根目录用 `--base` 改从本地读取：

```bash
python3 claude-sync-settings/sync.py --dry-run --base claude-sync-settings
```

也可以通过统一入口一次完成，参数原样传给 `sync.py`：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) claude-sync
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) claude-sync --dry-run
```
