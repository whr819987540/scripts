# Windows toast 子进程手动测试步骤

`cc_notify_toast.ps1` 由 `cc_notify.py` 在 Windows 上以 `powershell.exe -File cc_notify_toast.ps1 -Payload <base64>` 启动，用 Windows PowerShell 5.1 自带的 WinRT 弹 toast，不依赖 BurntToast。参数是 base64 编码的 UTF-8 JSON：

- 弹通知：`{"title", "lines": [...], "tag", "sound", "persist"}`。`persist` 为真时用 reminder 场景，开着勿扰也会弹出，并停在屏幕上直到点「知道了」。
- 撤掉通知：`{"clear": true, "tag"}`。

通知以独立身份「Claude Code」发出，首次运行时写入 `HKCU:\Software\Classes\AppUserModelId\ClaudeCode.Notify`。文件必须带 UTF-8 BOM，否则 5.1 会把中文读成乱码；`sync.py` 写入 `.ps1` 时会自动加上 BOM。

下面的命令在 Windows PowerShell 里执行。

1. 确认文件带 BOM，前三个字节应为 `239 187 191`。

   ```powershell
   $ps1 = "$env:USERPROFILE\.claude\hooks\cc_notify_toast.ps1"
   [IO.File]::ReadAllBytes($ps1)[0..2]
   ```

2. 弹一条测试 toast，应看到标题为「测试 · cc_notify」的通知。

   ```powershell
   $json = '{"title":"测试 · cc_notify","lines":["本机 · 手动测试","看到这条说明 toast 正常"],"tag":"manual-test","sound":true,"persist":true}'
   $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($json))
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -Payload $b64
   ```

3. 撤掉这条测试 toast。

   ```powershell
   $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"clear":true,"tag":"manual-test"}'))
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1 -Payload $b64
   ```

4. 没弹出时查日志，并到「设置 → 系统 → 通知」里确认「Claude Code」的通知开着。

   ```powershell
   Get-Content "$env:USERPROFILE\.claude\state\cc-notify\cc_notify.log" -Tail 20
   ```
