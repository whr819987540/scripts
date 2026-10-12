# claude-sync-settings

在多台机器之间同步 Claude Code 的用户级配置：

| 远端（本仓库） | 本机 |
|---|---|
| `shared-settings.json` | `~/.claude/settings.json` |
| `statusline.sh` | `~/.claude/statusline.sh` |

设置了 `CLAUDE_CONFIG_DIR` 时，本机目录以它为准。

## 同步

在要同步的机器上运行下面一条命令，需要 Python 3.8+。脚本先从 GitHub 下载，5 秒内没有响应就改用 Gitee。

**macOS / Linux**

```bash
f=$(mktemp) && { curl -fsSL -m 5 https://raw.githubusercontent.com/whr819987540/claude-sync-settings/main/sync.py -o "$f" || curl -fsSL -m 15 https://gitee.com/hit_whr/claude-sync-settings/raw/main/sync.py -o "$f"; } && python3 "$f"; rm -f "$f"
```

**Windows PowerShell**

```powershell
$f="$env:TEMP\claude-sync.py"; try { iwr https://raw.githubusercontent.com/whr819987540/claude-sync-settings/main/sync.py -OutFile $f -TimeoutSec 5 -UseBasicParsing } catch { iwr https://gitee.com/hit_whr/claude-sync-settings/raw/main/sync.py -OutFile $f -TimeoutSec 15 -UseBasicParsing }; python $f; Remove-Item $f
```

**Windows Git Bash**：用 macOS / Linux 那条，把 `python3` 换成 `python`。如果 `python` 打开的是微软商店，就换成 `py`。

想先看差异、不写入，就在命令里的 `python3 "$f"` 或 `python $f` 后面加 `--dry-run`。

## 运行过程

```
来源：GitHub  https://raw.githubusercontent.com/whr819987540/claude-sync-settings/main/
本机：C:\Users\me\.claude\settings.json

发现 3 处差异：
   1. [新增] permissions.deny 追加 "Read(//**/*.pem)"
   2. [修改] effortLevel："high" → "xhigh"
   3. [文件] statusline.sh（内容不同：+12 -3 行）

[a] 全部应用  [e] 逐项确认  [q] 退出 > e
```

逐项确认时，每一项都可以选：

- `[y]` 应用
- `[n]` 本次跳过
- `[i]` 忽略，远端值不变就不再问
- `[a]` 这项及剩余全部应用
- `[q]` 退出，不写入任何改动
- `[d]` 看 diff，只有文件项才有

## 比对规则

- **按完整路径比对**，比如 `env.ANTHROPIC_MODEL`、`modelSettings.claude-opus-5-5.effortLevel`。本机缺的算「新增」，值不同算「修改」。
- **每一处新增和修改都要你确认**才会写入。
- **数组**（比如 `permissions.deny`）：只补本机缺少的元素。
- **从不删除**：本机独有的 key 和数组元素都不会被删掉。
- **写入前自动备份**，备份名为 `settings.json.bak-sync-<时间>`，状态栏脚本同理。
- **忽略记录**存在 `~/.claude/.claude-sync-state.json`。远端的值变了会重新询问；想马上重新询问，加 `--all`。

## 参数

| 参数 | 作用 |
|---|---|
| `--dry-run` | 只列出差异，不写入 |
| `--all` | 之前选了忽略的项也重新询问 |
| `--source auto\|github\|gitee` | 默认 `auto`：先 GitHub，超时或失败再用 Gitee |
| `--timeout 秒` | GitHub 的超时时间，默认 5 秒 |
| `--base URL或目录` | 改从指定的 URL 前缀或本地目录读取，用于调试或自建镜像，比如在本仓库里运行 `python sync.py --base .` |

访问 GitHub 需要代理时，脚本会读取 `HTTPS_PROXY` 环境变量；在 Windows 上还会读系统代理设置。

## 维护远端

在本仓库里编辑 `shared-settings.json` 或 `statusline.sh`，然后：

```bash
git commit -am "更新共用配置" && git push
```

`origin` 配置了两个推送地址，一次 `git push` 会同时推到 GitHub 和 Gitee。

这个仓库是公开的，不要往里放 token、密码这类机密。另外，只放每台机器都通用的项：项目专属或机器专属的配置（比如 `autoMode.environment`）不要放进来。
