Unicode True
ManifestDPIAware True
RequestExecutionLevel user

!include "MUI2.nsh"
!include "x64.nsh"

Name "Cartrest"
OutFile "${SETUP}"
InstallDir "$LOCALAPPDATA\Programs\Cartrest"
InstallDirRegKey HKCU "Software\Cartrest" "InstallDir"
BrandingText "Cartrest"
Icon "Cartrest.ico"
UninstallIcon "Cartrest.ico"
VIProductVersion "1.4.0.2"
VIAddVersionKey "ProductName" "Cartrest"
VIAddVersionKey "FileDescription" "Cartrest Windows x64 Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "CompanyName" "Rafael Furlanetto Casamaximo"
VIAddVersionKey "LegalCopyright" "Copyright (c) 2026 Rafael Furlanetto Casamaximo"
SetCompressor /SOLID lzma

!define MUI_ABORTWARNING
!define MUI_WELCOMEFINISHPAGE_BITMAP "Welcome.bmp"
!define MUI_UNWELCOMEFINISHPAGE_BITMAP "Welcome.bmp"
!define MUI_WELCOMEPAGE_TITLE "Install Cartrest"
!define MUI_WELCOMEPAGE_TEXT "Set up Cartrest to design cartridge labels and export 3D-printable coasters.$\r$\n$\r$\nThis setup installs Cartrest for your Windows account."
!define MUI_FINISHPAGE_RUN "$INSTDIR\Cartrest.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open Cartrest"
!define MUI_FINISHPAGE_RUN_NOTCHECKED

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function CheckAppClosed
    retry:
        FindWindow $0 "" "Cartrest"
        StrCmp $0 0 done
        IfSilent cancel
        MessageBox MB_RETRYCANCEL|MB_ICONINFORMATION "Close Cartrest before continuing." /SD IDCANCEL IDRETRY retry
    cancel:
        SetErrorLevel 1
        Abort
    done:
FunctionEnd

Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_OK|MB_ICONSTOP "This build requires a 64-bit edition of Windows." /SD IDOK
        SetErrorLevel 1
        Abort
    ${EndIf}
    SetShellVarContext current
    Call CheckAppClosed
FunctionEnd

Function un.onInit
    SetShellVarContext current
    retry:
        FindWindow $0 "" "Cartrest"
        StrCmp $0 0 done
        IfSilent cancel
        MessageBox MB_RETRYCANCEL|MB_ICONINFORMATION "Close Cartrest before continuing." /SD IDCANCEL IDRETRY retry
    cancel:
        SetErrorLevel 1
        Abort
    done:
FunctionEnd

Section "Cartrest"
    SetOutPath "$INSTDIR"
    SetOverwrite on
    File /r "${PAYLOAD_GLOB}"
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateShortCut "$SMPROGRAMS\Cartrest.lnk" "$INSTDIR\Cartrest.exe" "" "$INSTDIR\Cartrest.exe"

    WriteRegStr HKCU "Software\Cartrest" "InstallDir" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "DisplayName" "Cartrest"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "DisplayVersion" "${VERSION}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "Publisher" "Rafael Furlanetto Casamaximo"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "DisplayIcon" "$INSTDIR\Cartrest.exe"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "URLInfoAbout" "https://github.com/RafaelCasamaximo/cartrest"
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "NoRepair" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest" "EstimatedSize" ${SIZE_KIB}
SectionEnd

Section "Uninstall"
    !include "${UNINSTALL_FILES}"
    Delete "$SMPROGRAMS\Cartrest.lnk"
    DeleteRegValue HKCU "Software\Cartrest" "InstallDir"
    DeleteRegKey /ifempty HKCU "Software\Cartrest"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Cartrest"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
SectionEnd
