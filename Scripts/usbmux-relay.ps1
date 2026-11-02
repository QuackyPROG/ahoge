# Pipes stdin/stdout to Apple Mobile Device Service (usbmuxd on 127.0.0.1:27015). Run by Scripts/wsl-usbmux.sh, one process per connection.
$ErrorActionPreference = 'Stop'
$client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', 27015)
$client.NoDelay = $true
$net = $client.GetStream()
$stdin = [Console]::OpenStandardInput()
$stdout = [Console]::OpenStandardOutput()
$up = $stdin.CopyToAsync($net)
$down = $net.CopyToAsync($stdout)
[void][System.Threading.Tasks.Task]::WaitAny(@($up, $down))
$client.Close()
