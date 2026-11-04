# Runs Scripts/push-to-phone.sh every 6 hours, and at the next chance when the PC was off. Run once from Windows.
# Usage: .\Scripts\install-push-task.ps1 -Branch main      Remove it with: Unregister-ScheduledTask AhogePush
param(
    [string]$Branch = 'main',
    [string]$Distro = 'Ubuntu-24.04'
)
$ErrorActionPreference = 'Stop'

$script = (wsl.exe -d $Distro -- wslpath -a ($PSScriptRoot.Replace('\', '/') + '/push-to-phone.sh')).Trim()
# conhost --headless keeps a console window from opening every run.
$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless wsl.exe -d $Distro -- bash -lc `"bash '$script' '$Branch'`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 6)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1)
Register-ScheduledTask -TaskName 'AhogePush' -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
"AhogePush runs every 6 hours on $Branch. Log: ~/.ahoge-push/push.log in $Distro"
