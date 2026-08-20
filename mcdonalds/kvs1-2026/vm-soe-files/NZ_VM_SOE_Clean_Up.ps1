##############################################################################
#
# NZ_VM_SOE_Clean_Up.ps1
# Run ON the staged VM SOE from an elevated PowerShell (as Administrator):
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\Source\Scripts\NZ_VM_SOE_Clean_Up.ps1
# Completes the software setup after staging, in this order:
#   1. Maxtel   2. PLS   3. Java   4. generatekvs   5. printer driver   6. desktop cleanup
# Every action and result is logged to C:\Source\Scripts\NZ_VM_SOE_Clean_Up_<timestamp>.log.
# Exits 1 if anything failed - review the log before continuing the runsheet.
#
# v1.00 20/08/2026  Initial build (Nick Barnes - Certeq)
#
##############################################################################

$MaxtelScript  = 'E:\Ghost Images\Waystation\AppStore\Maxtel.ps1'
$PlsInstaller  = 'C:\Source\Scripts\SOE_PLS_Install.exe'
$JavaInstaller = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
$KvsCurrent    = 'C:\Helpdesk\tools\generatekvs.exe'
$KvsStaged     = 'C:\Source\Scripts\generatekvs.exe'
$DriverDir     = 'C:\Temp\Printer Drivers'
$LogDir        = 'C:\Source\Scripts'

If (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir ("NZ_VM_SOE_Clean_Up_{0}.log" -f (Get-Date).ToString('yyyyMMdd-HHmmss'))
$script:Failed = 0

Function Write-Log($Message, $Level)
{
    If (-not $Level) { $Level = 'INFO' }
    $Stamp = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
    Add-Content -Path $LogFile -Value "$Stamp [$Level] $Message"
    If ($Level -eq 'FAIL') { Write-Host "[$Level] $Message" -ForegroundColor Red }
    ElseIf ($Level -eq 'PASS') { Write-Host "[$Level] $Message" -ForegroundColor Green }
    Else { Write-Host "[$Level] $Message" -ForegroundColor Yellow }
}

Function Fail($Message)
{
    $script:Failed++
    Write-Log $Message 'FAIL'
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
If (-not (New-Object Security.Principal.WindowsPrincipal $identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Run this script as Administrator (elevated PowerShell).' -ForegroundColor Red
    Exit 1
}

Write-Log "NZ_VM_SOE_Clean_Up v1.00 starting on $env:COMPUTERNAME"

# --- 1. Maxtel ---------------------------------------------------------------
If (Test-Path $MaxtelScript) {
    Write-Log 'Running Maxtel.ps1 (waiting for it to finish)...'
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $MaxtelScript) -Wait -PassThru
    If ($p.ExitCode -eq 0) { Write-Log 'Maxtel.ps1 completed (exit 0)' 'PASS' }
    Else { Fail "Maxtel.ps1 exited with code $($p.ExitCode)" }
} Else {
    Fail "Maxtel.ps1 not found at $MaxtelScript"
}

# --- 2. PLS ------------------------------------------------------------------
# SOE_PLS_Install.exe ends with a known PLSCleanStart crash (see Flow 36).
# Suppress the Windows Error Reporting dialog so the crash cannot block the run,
# then put the setting back the way it was.
If (Test-Path $PlsInstaller) {
    Write-Log 'Running SOE_PLS_Install.exe...'
    $werKey = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
    $werOld = $null
    Try { $werOld = (Get-ItemProperty -Path $werKey -Name DontShowUI -ErrorAction Stop).DontShowUI } Catch { }
    Try {
        New-ItemProperty -Path $werKey -Name DontShowUI -Value 1 -PropertyType DWord -Force | Out-Null
        $p = Start-Process -FilePath $PlsInstaller -Wait -PassThru
        Start-Sleep -Seconds 5
        $crashed = Get-Process -Name 'PLSCleanStart' -ErrorAction SilentlyContinue
        If ($crashed) { $crashed | Stop-Process -Force -ErrorAction SilentlyContinue }
        If ($p.ExitCode -eq 0) { Write-Log 'SOE_PLS_Install.exe completed (exit 0; known PLSCleanStart crash handled)' 'PASS' }
        Else { Fail "SOE_PLS_Install.exe exited with code $($p.ExitCode)" }
    } Finally {
        If ($werOld -eq $null) { Remove-ItemProperty -Path $werKey -Name DontShowUI -ErrorAction SilentlyContinue }
        Else { Set-ItemProperty -Path $werKey -Name DontShowUI -Value $werOld }
    }
} Else {
    Fail "SOE_PLS_Install.exe not found at $PlsInstaller"
}

# --- 3. Java -----------------------------------------------------------------
If (Test-Path $JavaInstaller) {
    Write-Log 'Installing Java (silent)...'
    $p = Start-Process -FilePath $JavaInstaller -ArgumentList '/s' -Wait -PassThru
    If ($p.ExitCode -eq 0) { Write-Log 'Java installed (exit 0)' 'PASS' }
    Else { Fail "Java installer exited with code $($p.ExitCode)" }
} Else {
    Fail "Java installer not found at $JavaInstaller"
}

# --- 4. generatekvs ----------------------------------------------------------
# Staging can leave the old 2015 build at C:\Helpdesk\tools. Always overwrite
# with the staged copy, then confirm what is on disk is 2025 or later.
If (Test-Path $KvsStaged) {
    Try {
        If (-not (Test-Path 'C:\Helpdesk\tools')) { New-Item -ItemType Directory -Path 'C:\Helpdesk\tools' -Force | Out-Null }
        Copy-Item -Path $KvsStaged -Destination $KvsCurrent -Force -ErrorAction Stop
        Write-Log "generatekvs.exe overwritten from $KvsStaged" 'PASS'
    } Catch {
        Fail "Could not overwrite generatekvs.exe - $($_.Exception.Message)"
    }
} Else {
    Write-Log "No staged generatekvs.exe at $KvsStaged - checking the current copy instead" 'INFO'
}
If (Test-Path $KvsCurrent) {
    $kvs = Get-Item $KvsCurrent
    $kvsYear = $kvs.LastWriteTime.Year
    If ($kvs.VersionInfo.FileVersion) { Write-Log ("generatekvs.exe version {0}, dated {1}" -f $kvs.VersionInfo.FileVersion, $kvs.LastWriteTime.ToString('dd/MM/yyyy')) }
    If ($kvsYear -ge 2025) { Write-Log "generatekvs.exe is the $kvsYear build" 'PASS' }
    Else { Fail "generatekvs.exe is dated $kvsYear - 2025 or later required" }
} Else {
    Fail "generatekvs.exe not found at $KvsCurrent"
}

# --- 5. Printer driver -------------------------------------------------------
If ((Test-Path $DriverDir) -and (Get-ChildItem -Path $DriverDir -Filter *.inf -Recurse -ErrorAction SilentlyContinue)) {
    Write-Log 'Installing printer driver via pnputil...'
    $p = Start-Process -FilePath 'pnputil.exe' -ArgumentList ('/add-driver "{0}\*.inf" /subdirs /install' -f $DriverDir) -Wait -PassThru
    If ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { Write-Log "pnputil completed (exit $($p.ExitCode))" 'PASS' }
    Else { Fail "pnputil exited with code $($p.ExitCode)" }
} Else {
    Write-Log "No printer driver package at $DriverDir - skipped" 'SKIP'
}

# --- 6. Desktop cleanup ------------------------------------------------------
# All DT Ranking shortcuts go, including DT Ranking Reboot (DTR is retired).
$desktops = @('C:\Users\Public\Desktop')
Get-ChildItem -Path 'C:\Users' -Directory -Filter 'NZ-R*' -ErrorAction SilentlyContinue | ForEach-Object { $desktops += Join-Path $_.FullName 'Desktop' }
$removed = 0
ForEach ($desktop in $desktops) {
    If (Test-Path $desktop) {
        Get-ChildItem -Path $desktop -Filter 'DT Ranking*.lnk' -ErrorAction SilentlyContinue | ForEach-Object {
            Try {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                Write-Log "Removed shortcut $($_.FullName)" 'PASS'
                $removed++
            } Catch {
                Fail "Could not remove $($_.FullName) - $($_.Exception.Message)"
            }
        }
    }
}
If ($removed -eq 0) { Write-Log 'No DT Ranking shortcuts found on the store-user or Public desktops' 'INFO' }

# --- Summary -----------------------------------------------------------------
If ($script:Failed -gt 0) {
    Write-Log "FINISHED WITH $($script:Failed) FAILED ACTION(S) - fix these before continuing the runsheet" 'FAIL'
    Write-Host "Log: $LogFile"
    Exit 1
}
Write-Log 'Finished - no failed actions' 'PASS'
Write-Host "Log: $LogFile"
Exit 0
