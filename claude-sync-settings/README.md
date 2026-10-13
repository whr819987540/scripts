# claude-sync-settings

在多台机器之间同步 Claude Code 的用户级配置：

| 远端（本目录） | 本机 |
|---|---|
| `shared-settings.json` | `~/.claude/settings.json` |
| `statusline.sh` | `~/.claude/statusline.sh` |

设置了 `CLAUDE_CONFIG_DIR` 时，本机目录以它为准。

## 同步

在要同步的机器上运行下面一条命令，需要 Python 3.8+。脚本先从 GitHub 下载，5 秒内没有响应就改用 Gitee。

**通过本仓库的统一入口**（Linux / macOS，从 Gitee 下载 `sync.py`，参数原样传给它）

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) claude-sync
```

**macOS / Linux**

```bash
f=$(mktemp) && { curl -fsSL -m 5 https://raw.githubusercontent.com/whr819987540/scripts/main/claude-sync-settings/sync.py -o "$f" || curl -fsSL -m 15 https://gitee.com/hit_whr/scripts/raw/main/claude-sync-settings/sync.py -o "$f"; } && python3 "$f"; rm -f "$f"
```

**Windows PowerShell**

```powershell
$f="$env:TEMP\claude-sync.py"; try { iwr https://raw.githubusercontent.com/whr819987540/scripts/main/claude-sync-settings/sync.py -OutFile $f -TimeoutSec 5 -UseBasicParsing } catch { iwr https://gitee.com/hit_whr/scripts/raw/main/claude-sync-settings/sync.py -OutFile $f -TimeoutSec 15 -UseBasicParsing }; python $f; Remove-Item $f
```

**Windows Git Bash**：用 macOS / Linux 那条，把 `python3` 换成 `python`。如果 `python` 打开的是微软商店，就换成 `py`。

想先看差异、不写入，就在命令里的 `python3 "$f"` 或 `python $f` 后面加 `--dry-run`；用统一入口时写成 `... run.sh) claude-sync --dry-run`。

逐步执行的命令见 [`sync.md`](sync.md)。

## 运行过程

```
来源：GitHub  https://raw.githubusercontent.com/whr819987540/scripts/main/claude-sync-settings/
本机：C:\Users\me\.claude\settings.json

开启严格比对？本机有、共享配置没有的 key 和数组元素会逐项询问是否删除，$remove 不生效 [y/n] > n

发现 4 处差异：
   1. [新增] permissions.deny 追加 "Read(//**/*.pem)"
   2. [修改] modelSettings.claude-opus-5-5.effortLevel："high" → "xhigh"
   3. [文件] statusline.sh（内容不同：+12 -3 行）
   4. [删除] env.ANTHROPIC_MODEL（本机值："claude-opus-5-5[1m]"）

[a] 全部应用（删除项仍逐项确认）  [e] 逐项确认  [q] 退出 > e
```

逐项确认时，每一项都可以选：

- `[y]` 应用
- `[n]` 本次跳过
- `[i]` 忽略，远端值不变就不再问
- `[a]` 这项及剩余全部应用，删除项除外；删除项没有这个选项
- `[s]` 这项及剩下的删除项都跳过，只有严格比对时的删除项才有；其他项照常处理，下次运行还会再问
- `[q]` 退出，不写入任何改动
- `[d]` 看 diff，只有文件项才有

## 比对规则

- **按完整路径比对**，比如 `statusLine.command`、`modelSettings.claude-opus-5-5.effortLevel`。本机缺的算「新增」，值不同算「修改」。
- **每一处新增、修改、删除都要你确认**才会写入。
- **数组**（比如 `permissions.deny`）：只补本机缺少的元素。
- **默认不删除**：本机独有的 key 和数组元素都保留。只有远端在 `$remove` 里列出的才会提示「删除」，而且删除项总是逐项确认，选 `[a]` 也不会替你删。
- **严格比对**：每次运行先问是否开启。开启后，本机有、共享配置没有的 key 和数组元素全部列为「删除」，逐项确认；两边都是对象时逐层往下比，两边都是数组时逐个元素比。这时 `$remove` 不生效。新增、修改、文件的比对不受影响。机器专属的项（比如 `autoMode`、`permissions.allow`）可以选 `[i]` 忽略，以后不再问；删除项太多时选 `[s]` 跳过剩下的。
- **写入前自动备份**，备份名为 `settings.json.bak-sync-<时间>`，状态栏脚本同理。
- **忽略记录**存在 `~/.claude/.claude-sync-state.json`。远端的值变了会重新询问；想马上重新询问，加 `--all`。

## 参数

| 参数 | 作用 |
|---|---|
| `--dry-run` | 只列出差异，不写入 |
| `--all` | 之前选了忽略的项也重新询问 |
| `--source auto\|github\|gitee` | 默认 `auto`：先 GitHub，超时或失败再用 Gitee |
| `--timeout 秒` | GitHub 的超时时间，默认 5 秒 |
| `--base URL或目录` | 改从指定的 URL 前缀或本地目录读取，用于调试或自建镜像，比如在本目录里运行 `python sync.py --base .` |

访问 GitHub 需要代理时，脚本会读取 `HTTPS_PROXY` 环境变量；在 Windows 上还会读系统代理设置。

## 维护远端

编辑本目录下的 `shared-settings.json` 或 `statusline.sh`，然后在 scripts 仓库里：

```bash
git commit -am "更新共用配置" && git push
```

`origin` 配置了两个推送地址，一次 `git push` 会同时推到 GitHub 和 Gitee。

本目录原来是独立仓库 `whr819987540/claude-sync-settings`，已连同提交历史并入 scripts 仓库；`sync.py` 现在从 scripts 仓库的 `claude-sync-settings/` 目录读取共享配置，只维护这里即可。

scripts 仓库是公开的，不要往里放 token、密码这类机密。另外，只放每台机器都通用的项：项目专属或机器专属的配置（比如 `autoMode.environment`）不要放进来。

### 让各机器删掉某一项

从 `shared-settings.json` 删掉一个 key，已经同步过的机器不会跟着删。要让它们删掉，就在顶层的 `$remove` 里列出来：

```json
"$remove": [
  "env.ANTHROPIC_MODEL",
  {"path": "permissions.deny", "item": "Read(某条规则)"}
]
```

- 字符串是点分路径，删掉整个 key。key 本身含 `.` 时，路径写成数组：`{"path": ["a.b", "c"]}`。
- 带 `item` 的条目只删数组里的这一个元素。
- 同一个 key 或数组元素不能既在 `$remove` 里、又留在共享配置里；遇到这种情况脚本会跳过这条删除并提示。
- `$remove` 只给同步脚本看，不会写进本机 `settings.json`。条目可以一直留着，本机没有这一项时不会提示。
