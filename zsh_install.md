# Zsh 安装与配置步骤

`zsh_install.sh` 安装 Zsh 和 Git，安装或更新 Oh My Zsh 及三个插件，生成 `~/.zshrc`，最后尝试把 Zsh 设为默认 shell。

## 安装依赖

1. 检查 Zsh 和 Git。

   ```bash
   command -v zsh
   command -v git
   ```

2. 安装缺失的软件。Ubuntu/Debian 使用：

   ```bash
   sudo apt-get update
   sudo apt-get install -y zsh git
   ```

   脚本还支持 `dnf`、`yum`、`pacman` 和 Homebrew，并且只安装缺失的软件。

## 安装 Oh My Zsh 和插件

1. 安装 Oh My Zsh。目录已经是 Git 仓库时，执行 `git -C ~/.oh-my-zsh pull --ff-only` 更新。

   ```bash
   git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh
   ```

2. 安装 Conda 补全插件。

   ```bash
   git clone --depth=1 https://github.com/conda-incubator/conda-zsh-completion.git \
       ~/.oh-my-zsh/custom/plugins/conda-zsh-completion
   ```

3. 安装命令建议和语法高亮插件。

   ```bash
   git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git \
       ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
   git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git \
       ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
   ```

   插件目录已经是 Git 仓库时，与 Oh My Zsh 一样使用 `git -C <插件目录> pull --ff-only` 更新。

## 配置并启用 Zsh

1. 如果已有 `~/.zshrc`，先创建带时间戳的备份。

   ```bash
   cp -p ~/.zshrc ~/.zshrc.backup.$(date +%Y%m%d%H%M%S)
   ```

2. 编辑 `~/.zshrc`，设置主题和插件。

   ```zsh
   export ZSH="$HOME/.oh-my-zsh"
   ZSH_THEME="robbyrussell"
   zstyle ':omz:update' mode disabled
   plugins=(git extract conda-zsh-completion zsh-autosuggestions zsh-syntax-highlighting)
   source "$ZSH/oh-my-zsh.sh"
   ```

3. 按需在 `~/.zshrc` 中加载个人环境变量、Conda、Homebrew、Clash、NVM 和 Rust 环境。脚本会检测对应文件或命令，仅加载已安装的组件。

4. 在 `~/.zshrc` 中配置历史记录，使历史在 shell 退出时追加，并避免多个终端实时共享。

   ```zsh
   HISTFILE="$HOME/.zsh_history"
   HISTSIZE=10000
   SAVEHIST=10000
   setopt APPEND_HISTORY EXTENDED_HISTORY
   unsetopt SHARE_HISTORY INC_APPEND_HISTORY INC_APPEND_HISTORY_TIME
   ```

5. 将 Zsh 设为默认 shell，并启动新 shell。

   ```bash
   chsh -s "$(command -v zsh)"
   exec zsh
   ```

也可以通过统一入口一次完成。脚本生成的完整 `~/.zshrc` 还包含第 3 步所述的可选组件检测：

```bash
source <(curl -fsSL https://gitee.com/hit_whr/scripts/raw/main/run.sh) zsh
```
