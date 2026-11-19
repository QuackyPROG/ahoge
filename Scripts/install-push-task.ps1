# Runs Scripts/push-to-phone.sh every -Minutes (default 6 hours), and at the next chance when the PC was off. Run once from Windows.
# Usage: .\Scripts\install-push-task.ps1 -Branch main -Minutes 10      Remove it with: Unregister-ScheduledTask AhogePush
# A run with no new commit exits quickly, and overlapping runs skip themselves (flock), so short intervals are fine.
param(
    [string]$Branch = 'main',
    [string]$Distro = 'Ubuntu-24.04',
    [ValidateRange(1, 1440)]
    [int]$Minutes = 360
)
$ErrorActionPreference = 'Stop'

$script = (wsl.exe -d $Distro -- wslpath -a ($PSScriptRoot.Replace('\', '/') + '/push-to-phone.sh')).Trim()
# conhost --headless keeps a console window from opening every run.
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless wsl.exe -d $Distro -- bash -lc `"bash '$script' '$Branch'`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $Minutes)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'AhogePush' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
"AhogePush runs every $Minutes minutes on $Branch. Log: ~/.ahoge-push/push.log in $Distro"
