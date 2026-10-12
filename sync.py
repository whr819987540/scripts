#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""claude-sync：把远端共用的 Claude Code 用户级配置同步到本机。

远端（公开仓库）放 shared-settings.json 和 statusline.sh，本机对应
~/.claude/settings.json 和 ~/.claude/statusline.sh（设置了 CLAUDE_CONFIG_DIR 时用它）。

比对规则：
  - 按完整路径比对（如 env.ANTHROPIC_MODEL）：本机缺的算「新增」，值不同算「修改」
  - 数组只补本机缺少的元素；本机独有的 key 和数组元素不删除，除非远端在 $remove 里列出
  - 每一处新增、修改、删除都先列出来，经你确认后才写入，写入前自动备份；删除总是逐项确认
  - 选了「忽略」的项记在 <配置目录>/.claude-sync-state.json，远端值不变就不再询问

只用标准库，Python 3.8+，Windows / macOS / Linux 通用。
"""

import argparse
import copy
import datetime
import difflib
import hashlib
import json
import os
import re
import shutil
import socket
import stat
import sys
import tempfile
import textwrap
import time
import urllib.error
import urllib.request
from pathlib import Path

# 按顺序尝试：默认 GitHub，超时或失败再用 Gitee
SOURCES = [
    ("GitHub", "https://raw.githubusercontent.com/whr819987540/claude-sync-settings/main/"),
    ("Gitee", "https://gitee.com/hit_whr/claude-sync-settings/raw/main/"),
]
FALLBACK_TIMEOUT = 15  # GitHub 之外的来源给更宽的超时
SHARED_SETTINGS = "shared-settings.json"
# 远端文件名 -> 本机文件名（都相对于配置目录）
SHARED_FILES = [("statusline.sh", "statusline.sh")]
STATE_FILE = ".claude-sync-state.json"
REMOVE_KEY = "$remove"  # 远端专用：列出要从本机删除的 key / 数组元素，不写进本机
SIMPLE_KEY = re.compile(r"^[A-Za-z0-9_-]+$")
MISSING = object()


# ---------------------------------------------------------------- 基础工具

def config_dir():
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(env).expanduser() if env else Path.home() / ".claude"


def canon(value):
    """JSON 值的规范文本，用来判断相等、计算指纹。"""
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def short(value, limit=90):
    s = json.dumps(value, ensure_ascii=False)
    return s if len(s) <= limit else s[:limit - 1] + "…"


def fmt_path(path):
    out = ""
    for key in path:
        if SIMPLE_KEY.match(key):
            out += ("." if out else "") + key
        else:
            out += "[%s]" % json.dumps(key, ensure_ascii=False)
    return out


def udiff(old, new, name):
    return list(difflib.unified_diff(
        old.splitlines(), new.splitlines(), "本机/" + name, "远端/" + name, lineterm=""))


def why(exc):
    if isinstance(exc, urllib.error.HTTPError):
        return "HTTP %d" % exc.code
    if isinstance(exc, urllib.error.URLError):
        exc = exc.reason
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return "超时"
    return str(exc) or type(exc).__name__


def atomic_write(path, text, mode=None):
    """先写临时文件再替换，避免写到一半留下坏文件。符号链接写到它指向的文件，链接本身保留。"""
    path = Path(os.path.realpath(str(path)))
    path.parent.mkdir(parents=True, exist_ok=True)
    if mode is None and path.exists():
        mode = stat.S_IMODE(path.stat().st_mode)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        if mode is not None and os.name != "nt":
            os.chmod(tmp, mode)
        os.replace(tmp, str(path))
    except BaseException:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise


def backup(path, stamp):
    if not path.exists():
        return None
    dest = path.with_name(path.name + ".bak-sync-" + stamp)
    shutil.copy2(str(path), str(dest))
    return dest


def ask(prompt, valid):
    while True:
        try:
            ans = input(prompt).strip().lower()
        except EOFError:
            print()
            return "q"
        if ans in valid:
            return ans
        print("  请输入 " + " / ".join(valid))


# ---------------------------------------------------------------- 读取

def read_source(base, name, timeout):
    """从 URL 前缀或本地目录读一个文件，返回统一成 LF 换行的文本。"""
    if not re.match(r"^[A-Za-z][A-Za-z0-9+.-]*://", base):
        text = (Path(base) / name).read_bytes().decode("utf-8-sig")
    else:
        url = base.rstrip("/") + "/" + name
        if url.startswith("http"):
            url += "?t=%d" % time.time()  # 绕过 CDN 缓存，拿到最新版本
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (claude-sync)"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8-sig")
        if text.lstrip()[:20].lower().startswith(("<!doctype", "<html")):
            raise ValueError("返回的是网页而不是文件内容")
    return text.replace("\r\n", "\n")


def load_remote(args):
    if args.base:
        sources = [("指定来源", args.base)]
    elif args.source == "auto":
        sources = SOURCES
    else:
        sources = [s for s in SOURCES if s[0].lower() == args.source]
    for i, (name, base) in enumerate(sources):
        timeout = args.timeout if name == "GitHub" else max(args.timeout, FALLBACK_TIMEOUT)
        try:
            remote = json.loads(read_source(base, SHARED_SETTINGS, timeout))
            if not isinstance(remote, dict):
                raise ValueError("%s 顶层不是 JSON 对象" % SHARED_SETTINGS)
        except Exception as exc:
            nxt = "，改用 %s" % sources[i + 1][0] if i + 1 < len(sources) else ""
            print("%s 拉取失败（%s）%s" % (name, why(exc), nxt))
            continue
        print("来源：%s  %s" % (name, base))
        return base, timeout, remote
    sys.exit("所有来源都拉取失败，未做任何改动。")


def load_local(path):
    if not path.exists():
        return {}
    raw = path.read_bytes().decode("utf-8-sig")
    if not raw.strip():
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        sys.exit("本机 %s 不是合法 JSON（第 %d 行第 %d 列：%s），先修好再同步。"
                 % (path, exc.lineno, exc.colno, exc.msg))
    if not isinstance(data, dict):
        sys.exit("本机 %s 顶层不是 JSON 对象，先修好再同步。" % path)
    return data


def load_state(path):
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(state, dict) and isinstance(state.get("ignored"), dict):
            return state
    except (OSError, ValueError):
        pass
    return {"ignored": {}}


# ---------------------------------------------------------------- 比对

class Change:
    """一处待同步的差异。kind: add / modify / append / file / remove / remove_item。

    remove 删除整个 key，local 是本机值；remove_item 删除数组里的一个元素，remote 是这个元素。
    """

    def __init__(self, kind, path, remote, local=None):
        self.kind = kind
        self.path = path  # settings 内的 key 路径（list）；file 时是本机文件名
        self.remote = remote
        self.local = local
        if kind == "file":
            self.key = "file:" + path
            self.hash = digest(remote)
        else:
            self.hash = digest(canon(remote))
            self.key = (("remove:" if self.removes else "settings:") + canon(path)
                        + ("#" + self.hash if kind in ("append", "remove_item") else ""))

    @property
    def removes(self):
        return self.kind in ("remove", "remove_item")

    def summary(self):
        if self.kind == "file":
            if self.local is None:
                return "[文件] %s（本机没有）" % self.path
            lines = udiff(self.local, self.remote, self.path)
            plus = sum(1 for l in lines if l.startswith("+") and not l.startswith("+++"))
            minus = sum(1 for l in lines if l.startswith("-") and not l.startswith("---"))
            return "[文件] %s（内容不同：+%d -%d 行）" % (self.path, plus, minus)
        p = fmt_path(self.path)
        if self.kind == "add":
            return "[新增] %s = %s" % (p, short(self.remote))
        if self.kind == "append":
            return "[新增] %s 追加 %s" % (p, short(self.remote))
        if self.kind == "remove":
            return "[删除] %s（本机值：%s）" % (p, short(self.local))
        if self.kind == "remove_item":
            return "[删除] %s 移除 %s" % (p, short(self.remote))
        return "[修改] %s：%s → %s" % (p, short(self.local), short(self.remote))

    def detail(self):
        """逐项确认时，值太长就把完整内容展开给你看。"""
        if self.kind == "file":
            if self.local is None:
                print("    远端文件 %d 行，将写入本机" % len(self.remote.splitlines()))
            return
        full = json.dumps(self.local if self.kind == "remove" else self.remote, ensure_ascii=False, indent=2)
        if self.kind == "modify":
            local = json.dumps(self.local, ensure_ascii=False, indent=2)
            if len(full) > 90 or len(local) > 90:
                print("    本机：\n" + textwrap.indent(local, "      "))
                print("    远端：\n" + textwrap.indent(full, "      "))
        elif len(full) > 90:
            print(textwrap.indent(full, "      "))

    def apply(self, settings):
        node = settings
        for key in self.path[:-1]:
            node = node[key]
        last = self.path[-1]
        value = copy.deepcopy(self.remote)
        if self.kind == "append":
            node[last].append(value)
        elif self.kind == "remove":
            del node[last]
        elif self.kind == "remove_item":
            node[last] = [x for x in node[last] if canon(x) != canon(value)]
        else:
            node[last] = value


def diff_settings(local, remote, path, out):
    for key, rv in remote.items():
        p = path + [key]
        if key not in local:
            out.append(Change("add", p, rv))
            continue
        lv = local[key]
        if isinstance(lv, dict) and isinstance(rv, dict):
            diff_settings(lv, rv, p, out)
        elif isinstance(lv, list) and isinstance(rv, list):
            have = {canon(x) for x in lv}
            for item in rv:
                c = canon(item)
                if c not in have:
                    have.add(c)
                    out.append(Change("append", p, item))
        elif canon(lv) != canon(rv):
            out.append(Change("modify", p, rv, lv))


def lookup(obj, path):
    for key in path:
        if not isinstance(obj, dict) or key not in obj:
            return MISSING
        obj = obj[key]
    return obj


def parse_removals(spec):
    """把远端的 $remove 规范成 [(路径, 数组元素)]；数组元素为 MISSING 表示删整个 key。

    每条可以是点分路径 "env.ANTHROPIC_MODEL"，或 {"path": "permissions.deny", "item": "Read(...)"}
    删数组里的一个元素；key 本身含点时 path 写成数组，如 {"path": ["a.b", "c"]}。
    """
    out = []
    for entry in spec if isinstance(spec, list) else [spec]:
        path, item = entry, MISSING
        if isinstance(entry, dict):
            path, item = entry.get("path"), entry.get("item", MISSING)
        if isinstance(path, str):
            path = path.split(".")
        if not (isinstance(path, list) and path and all(isinstance(k, str) and k for k in path)):
            print("跳过无法识别的 %s 条目：%s" % (REMOVE_KEY, short(entry)))
            continue
        out.append((path, item))
    return out


def diff_removals(local, remote, removals, out):
    for path, item in removals:
        lv, rv = lookup(local, path), lookup(remote, path)
        if item is MISSING:
            if rv is not MISSING:
                print("%s 同时出现在共享配置里，跳过对它的删除" % fmt_path(path))
            elif lv is not MISSING:
                out.append(Change("remove", path, None, lv))
        elif isinstance(rv, list) and canon(item) in {canon(x) for x in rv}:
            print("%s 里的 %s 同时出现在共享配置里，跳过对它的删除" % (fmt_path(path), short(item)))
        elif isinstance(lv, list) and canon(item) in {canon(x) for x in lv}:
            out.append(Change("remove_item", path, item))


def diff_files(base, timeout, cfg):
    out = []
    for remote_name, local_name in SHARED_FILES:
        try:
            text = read_source(base, remote_name, timeout)
        except Exception as exc:
            print("拉取 %s 失败（%s），本次跳过这个文件" % (remote_name, why(exc)))
            continue
        target = cfg / local_name
        local = None
        if target.exists():
            local = target.read_bytes().decode("utf-8", "replace").replace("\r\n", "\n")
            if local == text:
                continue
        out.append(Change("file", local_name, text, local))
    return out


# ---------------------------------------------------------------- 交互

def review(pending, ignored, apply_rest=False):
    """逐项确认。apply_rest 为真时非删除项直接应用，删除项总是单独询问。

    返回要应用的列表；选 q 时返回 None，表示什么都不写。
    """
    accepted, newly_ignored = [], {}
    total = len(pending)
    rest_note = "（删除项仍逐项确认）" if any(c.removes for c in pending) else ""
    for i, c in enumerate(pending):
        if apply_rest and not c.removes:
            accepted.append(c)
            continue
        print("\n(%d/%d) %s" % (i + 1, total, c.summary()))
        c.detail()
        opts = ["y", "n", "i"]
        prompt = "  应用？[y] 是  [n] 本次跳过  [i] 忽略（远端不变就不再问）"
        if not c.removes:
            opts.append("a")
            prompt += "  [a] 这项及剩余全部应用" + rest_note
        opts.append("q")
        prompt += "  [q] 退出不写入"
        if c.kind == "file" and c.local is not None:
            opts.append("d")
            prompt += "  [d] 看 diff"
        ans = ask(prompt + " > ", opts)
        while ans == "d":
            print("\n".join(udiff(c.local, c.remote, c.path)))
            ans = ask(prompt + " > ", opts)
        if ans == "q":
            return None
        if ans in ("y", "a"):
            accepted.append(c)
            apply_rest = apply_rest or ans == "a"
        elif ans == "i":
            newly_ignored[c.key] = c.hash
    ignored.update(newly_ignored)
    return accepted


def main():
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except Exception:
            pass
    # `curl ... | python3 -` 时 stdin 是脚本本身，改从终端读回答
    if sys.argv[0] == "-" and os.name != "nt":
        try:
            sys.stdin = open("/dev/tty", encoding="utf-8")
        except OSError:
            pass

    ap = argparse.ArgumentParser(description="把远端共用的 Claude Code 用户级配置同步到本机，每项改动都需确认。")
    ap.add_argument("--dry-run", action="store_true", help="只列出差异，不写入")
    ap.add_argument("--all", action="store_true", help="之前选了忽略的项也重新询问")
    ap.add_argument("--source", choices=["auto", "github", "gitee"], default="auto",
                    help="默认 auto：先 GitHub，超时或失败再用 Gitee")
    ap.add_argument("--base", metavar="URL或目录", help="改从这个 URL 前缀或本地目录读取（调试或自建镜像用）")
    ap.add_argument("--timeout", type=float, default=5, help="GitHub 超时秒数，默认 5")
    args = ap.parse_args()

    cfg = config_dir()
    settings_path = cfg / "settings.json"
    state_path = cfg / STATE_FILE

    local = load_local(settings_path)
    base, timeout, remote = load_remote(args)
    print("本机：%s" % settings_path)

    removals = parse_removals(remote.pop(REMOVE_KEY, []))
    changes = []
    diff_settings(local, remote, [], changes)
    changes += diff_files(base, timeout, cfg)
    diff_removals(local, remote, removals, changes)

    state = load_state(state_path)
    ignored = state["ignored"]
    pending = changes if args.all else [c for c in changes if ignored.get(c.key) != c.hash]
    hidden = len(changes) - len(pending)
    hidden_note = "（另有 %d 项之前选了忽略且远端未变，加 --all 重新询问）" % hidden if hidden else ""

    if not pending:
        print("已是最新，没有需要同步的项。" + hidden_note)
        return
    print("\n发现 %d 处差异：" % len(pending))
    for i, c in enumerate(pending, 1):
        print("  %2d. %s" % (i, c.summary()))
    if hidden_note:
        print("  " + hidden_note)
    if args.dry_run:
        print("\n--dry-run：只列出差异，未写入。")
        return

    all_note = "（删除项仍逐项确认）" if any(c.removes for c in pending) else ""
    choice = ask("\n[a] 全部应用%s  [e] 逐项确认  [q] 退出 > " % all_note, ["a", "e", "q"])
    if choice == "q":
        print("未做任何改动。")
        return
    accepted = review(pending, ignored, apply_rest=choice == "a")
    if accepted is None:
        print("已退出，未做任何改动。")
        return

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    setting_changes = [c for c in accepted if c.kind != "file"]
    if setting_changes:
        bak = backup(settings_path, stamp)
        # 先删再改：远端把上级整体换掉时，删除不会落到新值上
        for c in sorted(setting_changes, key=lambda c: not c.removes):
            c.apply(local)
        atomic_write(settings_path, json.dumps(local, indent=2, ensure_ascii=False) + "\n")
        print("\n已写入 settings.json：%d 项%s" % (
            len(setting_changes), "（原文件备份为 %s）" % bak.name if bak else ""))
    for c in accepted:
        if c.kind == "file":
            target = cfg / c.path
            bak = backup(target, stamp)
            atomic_write(target, c.remote, mode=0o755 if target.suffix == ".sh" else None)
            print("已更新 %s%s" % (c.path, "（原文件备份为 %s）" % bak.name if bak else ""))
    for c in accepted:
        ignored.pop(c.key, None)
    atomic_write(state_path, json.dumps(state, indent=2, ensure_ascii=False) + "\n")

    skipped = len(pending) - len(accepted)
    print("完成：应用 %d 项，跳过 %d 项。settings.json 的改动 Claude Code 通常会自动加载，没生效就重开会话。"
          % (len(accepted), skipped))


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n已中断。")
        sys.exit(130)
