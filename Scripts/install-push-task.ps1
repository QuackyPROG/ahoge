# Runs Scripts/push-to-phone.sh every -Minutes (default 6 hours), and at the next chance when the PC was off. Run once from Windows.
# Usage: .\Scripts\install-push-task.ps1 -Branch main -Minutes 10 -QuietHours '02-06'      Remove it with: Unregister-ScheduledTask AhogePush
# A run with no new commit exits quickly, and overlapping runs skip themselves (flock), so short intervals are fine.
# New commits install only inside -QuietHours (local HH-HH, start inclusive, end exclusive), because installing kills the app;
# a daily run 5 minutes after the window opens makes sure one run lands inside it. For an install right now, run
# push-to-phone.sh with --force. The task does not wake the PC: if it is usually off at night, move the window with -QuietHours.
param(
    [string]$Branch = 'main',
    [string]$Distro = 'Ubuntu-24.04',
    [ValidateRange(1, 1440)]
    [int]$Minutes = 360,
    [ValidatePattern('^([01][0-9]|2[0-3])-([01][0-9]|2[0-3])$')]
    [string]$QuietHours = '02-06'
)
$ErrorActionPreference = 'Stop'

$script = (wsl.exe -d $Distro -- wslpath -a ($PSScriptRoot.Replace('\', '/') + '/push-to-phone.sh')).Trim()
# conhost --headless keeps a console window from opening every run.
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless wsl.exe -d $Distro -- bash -lc `"bash '$script' '$Branch' --quiet-hours '$QuietHours'`""
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
$opens = (Get-Date).Date.AddHours([int]$QuietHours.Split('-')[0]).AddMinutes(5)
$daily = New-ScheduledTaskTrigger -Daily -At $opens
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'AhogePush' -Action $action -Trigger $repeat, $daily -Settings $settings -Force | Out-Null
"AhogePush runs every $Minutes minutes and daily at $($opens.ToString('HH:mm')) on $Branch; new commits install only in the quiet window $QuietHours. Log: ~/.ahoge-push/push.log in $Distro"
