# tmux 安装与配置步骤

`tmux_install.sh` 从源码编译 tmux 3.7b 并安装到 `~/.local/bin`，让非交互式 bash 和 zsh 也使用这个版本，最后生成 `~/.tmux.conf`。安装本身不需要 root，只有缺少编译依赖时才会用 `sudo` 安装。

## 编译安装 tmux 3.7b

`~/.local/bin/tmux` 已经是 3.7b 时，脚本跳过本节。

1. 检查编译依赖：C 编译器、make、pkg-config，以及 libevent 和 ncurses 的开发文件。

   ```bash
   command -v gcc make pkg-config
   pkg-config --exists libevent_core && echo libevent ok
   pkg-config --exists ncursesw && echo ncurses ok
   ```

2. 安装缺失的依赖。Ubuntu/Debian 使用：

   ```bash
   sudo apt-get update
   sudo apt-get install -y gcc make pkg-config libevent-dev libncurses-dev
   ```

   脚本还支持 `dnf` 和 `yum`（`gcc make pkgconfig libevent-devel ncurses-devel`）。

3. 下载源码包，校验 SHA-256 后解压。可以用 `tmux_download_url` 环境变量换成其他下载地址，校验值不变。

   ```bash
   cd "$(mktemp -d)"
   curl -fsSLO https://github.com/tmux/tmux/releases/download/3.7b/tmux-3.7b.tar.gz
   echo "87f2e99e3b685973f2ca002ffd6ed7e51a5744f7009daae5a15670b6d532db96  tmux-3.7b.tar.gz" | sha256sum -c
   tar -xzf tmux-3.7b.tar.gz
   cd tmux-3.7b
   ```

4. 编译并安装到 `~/.local`，然后确认版本。

   ```bash
   ./configure --prefix="$HOME/.local"
   make -j"$(nproc)"
   make install
   ~/.local/bin/tmux -V
   ```

   源码包自带生成好的 `cmd-parse.c`，`configure` 只检查 yacc 是否存在。系统里没有 bison 或 yacc 时，改用：

   ```bash
   ./configure --prefix="$HOME/.local" YACC=false
   ```

## 让非交互式 shell 使用 `~/.local/bin`

`ssh host tmux ls` 这类命令不读取 `~/.zshrc`；Ubuntu 默认的 `~/.bashrc` 在开头遇到非交互 shell 就 `return`。不做这一步时，非交互 shell 会用到系统自带的旧版 tmux（如 `/usr/bin/tmux`）。

1. 在 `~/.bashrc` 的**最前面**插入下面这段，它必须位于 `case $- in` 的非交互判断之前：

   ```bash
   # >>> ~/.local/bin for non-interactive shells (tmux_install.sh) >>>
   case ":${PATH}:" in
       *":${HOME}/.local/bin:"*) ;;
       *) export PATH="${HOME}/.local/bin:${PATH}" ;;
   esac
   # <<< ~/.local/bin for non-interactive shells <<<
   ```

2. 在 `~/.zshenv` 末尾追加同一段。zsh 在所有 shell 中都会读取 `~/.zshenv`，包括非交互 shell。

   脚本修改这两个文件前会备份为 `<文件>.backup.<时间戳>`；文件中已有这段时跳过。

3. 验证。从另一台机器执行：

   ```bash
   ssh <host> 'command -v tmux; tmux -V'
   ```

   脚本在本机模拟 SSH 命令的环境（最简 PATH，并设置 `SSH_CLIENT` 让 bash 读取 `~/.bashrc`），分别检查 bash 和 zsh，不是 3.7b 时报错退出：

   ```bash
   env -i HOME="$HOME" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
       SSH_CLIENT="127.0.0.1 0 0" bash -c 'command -v tmux; tmux -V'
   ```

## 写入 `~/.tmux.conf`

1. 如果已有 `~/.tmux.conf` 且内容不同，先创建带时间戳的备份。

   ```bash
   cp -p ~/.tmux.conf ~/.tmux.conf.backup.$(date +%Y%m%d%H%M%S)
   ```

2. 写入配置：

   ```tmux
   # Line limit of tmux buffer
   set-option -g history-limit 1000000

   # Support scroll bar
   set-option -g mouse on
   set-option -g pane-scrollbars on
   set-option -g pane-scrollbars-position right
   set -g pane-scrollbars-style "fg=colour245,bg=colour236,width=1,pad=0"

   # Keep copy-mode open after mouse selection so the view does not jump to bottom.
   # copy-selection-no-clear also copies on tmux 3.0a; copy-pipe-no-clear without a command does not.
   bind-key -T copy-mode MouseDown1Pane select-pane \; send-keys -X clear-selection
   bind-key -T copy-mode MouseDragEnd1Pane send-keys -X copy-selection-no-clear
   bind-key -T copy-mode-vi MouseDown1Pane select-pane \; send-keys -X clear-selection
   bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-selection-no-clear
   ```

   - `history-limit`：每个 pane 保留 100 万行回滚历史（默认 2000），只对新建的 pane 生效。
   - `mouse on`：滚轮滚动、点击切换 pane、拖动边框调整大小、拖选文字。
   - `pane-scrollbars*`：在每个 pane 右侧显示 1 列宽的灰色滚动条，需要 tmux 3.6 及以上。
   - 鼠标拖选松开后复制但不退出 copy-mode，视图不会跳回底部；单击清除上一次的选区。

3. 已有 tmux server 在运行时，版本相同就重新加载配置，版本不同则需要重启 server：

   ```bash
   tmux display-message -p '#{version}'
   tmux source-file ~/.tmux.conf
   ```

也可以通过统一入口一次完成：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) tmux
```
