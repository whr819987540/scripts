# cc_notify.py 的 toast 子进程。用 Windows PowerShell 5.1 自带的 WinRT 弹通知，不依赖 BurntToast，
# 换一台 Windows 机器也能直接用。参数是 base64(UTF-8 JSON) {title, lines[], tag, sound, persist}，
# 避开命令行引号、换行和代码页问题。失败只写日志。
#
# 通知以独立身份 "Claude Code"（AUMID ClaudeCode.Notify，只写 HKCU 注册表，不需要快捷方式）发出，
# 在 设置 → 系统 → 通知 里有自己的开关，可以单独加进勿扰的优先通知名单。
# persist 用 reminder 场景：开着勿扰也会弹出，并停在屏幕上直到点"知道了"；普通 toast 在勿扰下只进通知中心。

param([Parameter(Mandatory = $true)][string]$Payload)

$log = Join-Path $env:USERPROFILE '.claude\state\cc-notify\cc_notify.log'
$app = 'ClaudeCode.Notify'
try {
    $p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload)) | ConvertFrom-Json
    $key = "HKCU:\Software\Classes\AppUserModelId\$app"
    if ((Get-ItemProperty $key -ErrorAction SilentlyContinue).DisplayName -ne 'Claude Code') {
        New-Item $key -Force | Out-Null
        Set-ItemProperty $key DisplayName 'Claude Code'
    }
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

    # {clear, tag}：你已经回到这个会话，把它的通知从屏幕和通知中心撤掉
    if ($p.clear) {
        [Windows.UI.Notifications.ToastNotificationManager]::History.Remove([string]$p.tag, 'claude-code', $app)
        exit 0
    }

    # ToastGeneric 最多显示 3 行文本：标题 + 2 行正文
    $texts = (@($p.title) + @($p.lines) | Where-Object { $_ } | Select-Object -First 3 |
        ForEach-Object { '<text>' + [Security.SecurityElement]::Escape([string]$_) + '</text>' }) -join ''
    $audio = if ($p.sound) { '<audio src="ms-winsoundevent:Notification.Reminder"/>' } else { '<audio silent="true"/>' }
    # reminder 场景至少要有一个按钮，否则按普通 toast 处理
    $scenario, $actions = '', ''
    if ($p.persist) {
        $scenario = ' scenario="reminder"'
        $actions = '<actions><action content="知道了" arguments="dismiss" activationType="system"/></actions>'
    }
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml("<toast$scenario><visual><binding template=`"ToastGeneric`">$texts</binding></visual>$actions$audio</toast>")

    $toast = New-Object Windows.UI.Notifications.ToastNotification $xml
    # 同一会话的新通知替换旧通知，屏幕和通知中心里每个会话只留最新一条
    $toast.Tag = [string]$p.tag
    $toast.Group = 'claude-code'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show($toast)
}
catch {
    "$(Get-Date -Format s) toast: $($_.Exception.Message)" | Add-Content -LiteralPath $log -Encoding utf8
}
