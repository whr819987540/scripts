# Claude Code 配置同步步骤

`sync.py` 读取本目录的 `shared-settings.json` 和 `statusline.sh`，与本机 `~/.claude/settings.json`、`~/.claude/statusline.sh` 比对，逐项确认后写入（写入前自动备份）。需要 Python 3.8+，比对规则见 [`README.md`](README.md)。

1. 确认本机配置目录。设置了 `CLAUDE_CONFIG_DIR` 时以它为准。

   ```bash
   echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
   ```

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

   访问 GitHub 需要代理时，先设置 `HTTPS_PROXY`；只想用某一个来源时加 `--source github` 或 `--source gitee`；之前选了「忽略」的项想重新询问时加 `--all`。

5. 检查写入结果。改动前的文件备份为 `settings.json.bak-sync-<时间>`，需要回退时复制回去即可。

   ```bash
   ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/settings.json.bak-sync-* | head -n 1
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
