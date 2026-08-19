# soefix cleanup - runs ON an already-converted VM SOE (site {{SITE}} {{NAME}}) from
# C:\Temp\soefix\go. Staged there by `soefix push --cleanup`. Desktop exe, PLS, Java,
# generatekvs check and the recollect (generatekvs.exe /auto {{DAYS}}). No restart.
$ErrorActionPreference = 'Continue'
$site     = '{{SITE}}'
$siteName = '{{NAME}}'
$refId    = '{{REF}}'
$days     = {{DAYS}}
$lines    = @()

# --- self-elevate ------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($env:SOEFIX_ELEVATED -eq '1') {
        # we ARE the relaunched copy and still not elevated: never spawn again
        Write-Host 'Still not elevated after a RunAs relaunch - stopping (no more windows).' -ForegroundColor Red
        Write-Host ("  user: {0}" -f $id.Name) -ForegroundColor Red
        Write-Host ("  admin group member: {0}" -f (($id.Groups | ForEach-Object { $_.Value }) -contains 'S-1-5-32-544')) -ForegroundColor Red
        Write-Host '  Log in as a local Administrator, or right-click PowerShell > Run as administrator and run:' -ForegroundColor Yellow
        Write-Host ("  powershell -NoProfile -ExecutionPolicy Bypass -File ""{0}""" -f $MyInvocation.MyCommand.Path) -ForegroundColor Yellow
        Read-Beer 'Press Enter to close' | Out-Null
        exit 1
    }
    $env:SOEFIX_ELEVATED = '1'
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}"' -f $MyInvocation.MyCommand.Path)
    exit
}
try { Start-Transcript -Path 'C:\Temp\soefix\transcript.txt' -Append | Out-Null } catch { }

{{BEER}}
Init-Beer "SOE cleanup - site $site $siteName" 5   # desktop exe, PLS, Java, generatekvs + recollect, summary

Write-Host ''
Write-Host ("SOE fixup - site $site $siteName (ref $refId) - recollect $days days") -ForegroundColor Cyan
Write-Host ''

# --- 1. Remove SOE_Reboot_eOPS.exe from all user desktops -------------------
Show-Beer 'Desktop exe'
$removed = @()
$failed  = @()
$desktops = @(Get-ChildItem 'C:\Users' | Where-Object { $_.PSIsContainer } | ForEach-Object { Join-Path $_.FullName 'Desktop' })
foreach ($d in $desktops) {
    $p = Join-Path $d 'SOE_Reboot_eOPS.exe'
    if (Test-Path $p) {
        Remove-Item $p -Force -ErrorAction SilentlyContinue
        if (Test-Path $p) { $failed += $p } else { $removed += $p }
    }
}
if ($failed.Count -gt 0) {
    $lines += "[FAIL] Desktop exe:   could not remove: $($failed -join ', ')"
} elseif ($removed.Count -gt 0) {
    $lines += "[PASS] Desktop exe:   removed from $($removed.Count) desktop(s)"
} else {
    $lines += "[PASS] Desktop exe:   not present (already clean)"
}

# --- 2. PLS install (known error popup - click OK when it appears) ----------
Show-Beer 'PLS install'
$plsExe = 'C:\Source\Scripts\SOE_PLS_Install.exe'
if (Test-Path $plsExe) {
    Write-Host 'Running PLS install - CLICK OK on the known error popup...' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath $plsExe -PassThru
        $rc = Wait-Beer $proc 'PLS install'
        $lines += "[PASS] PLS install:   completed (exit code $rc)"
    } catch {
        $lines += "[FAIL] PLS install:   $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] PLS install:   $plsExe not found"
}

# --- 3. Java JRE 7u1 silent install -----------------------------------------
Show-Beer 'Java JRE 7u1'
$jreExe = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
$javaBin = 'C:\Program Files\Java\jre7\bin\java.exe'
if (Test-Path $javaBin) {
    $lines += "[PASS] Java JRE 7u1:  already installed"
} elseif (Test-Path $jreExe) {
    Write-Host 'Installing Java JRE 7u1 (silent)...'
    try {
        $jp = Start-Process -FilePath $jreExe -ArgumentList '/s' -PassThru
        Wait-Beer $jp 'Java JRE 7u1' | Out-Null
        if (Test-Path $javaBin) {
            $lines += "[PASS] Java JRE 7u1:  installed, verified at $javaBin"
        } else {
            $lines += "[FAIL] Java JRE 7u1:  installer ran but $javaBin not found"
        }
    } catch {
        $lines += "[FAIL] Java JRE 7u1:  $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] Java JRE 7u1:  installer not found at $jreExe"
}

# --- 4. generatekvs version check + recollect --------------------------------
Show-Beer 'generatekvs + recollect'
$gk = 'C:\Helpdesk\tools\generatekvs.exe'
if (-not (Test-Path $gk)) {
    $lines += "[FAIL] generatekvs:   not found at $gk"
    $lines += "[SKIP] Recollect:     skipped (no generatekvs.exe)"
} else {
    $gkDate = (Get-Item $gk).LastWriteTime
    if ($gkDate.Year -ge 2025) {
        $lines += "[PASS] generatekvs:   $($gkDate.ToString('dd/MM/yyyy')) build present"
        Write-Host "Running recollect: generatekvs.exe /auto $days in its own window (this can take a while)..."
        $gp = Start-Process -FilePath $gk -ArgumentList "/auto $days" -WorkingDirectory 'C:\Helpdesk\tools' -PassThru
        $gkExit = Wait-Beer $gp "recollect /auto $days"
        # eric output folder may land in C:\Helpdesk\eric or next to the exe
        $eric = $null
        foreach ($cand in @('C:\Helpdesk\eric', 'C:\Helpdesk\tools\eric')) {
            if (Test-Path $cand) { $eric = $cand; break }
        }
        if ($eric) {
            $count = @(Get-ChildItem $eric | Where-Object { -not $_.PSIsContainer }).Count
            $lines += "[PASS] Recollect:     /auto $days ran (exit $gkExit), $eric has $count file(s)"
        } else {
            $lines += "[FAIL] Recollect:     /auto $days ran (exit $gkExit) but no eric folder found"
        }
    } else {
        $lines += "[FAIL] generatekvs:   OLD build ($($gkDate.ToString('dd/MM/yyyy'))) - re-run soefix push --cleanup to replace it"
        $lines += "[SKIP] Recollect:     skipped - update generatekvs.exe first, then run: generatekvs.exe /auto $days"
    }
}

# --- Summary: print + push to shared RDP clipboard ---------------------------
Show-Beer 'Summary'
$stamp  = Get-Date -Format 'yyyy-MM-dd HH:mm'
$header = "==== SOE FIXUP SUMMARY - site $site $siteName (ref $refId) - $env:COMPUTERNAME - $stamp ===="
$summary = ($header, ($lines -join "`r`n")) -join "`r`n"
Write-Host ''
foreach ($l in ($summary -split "`r`n")) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*SKIP*') { Write-Host $l -ForegroundColor Yellow }
    else { Write-Host $l -ForegroundColor Green }
}
try { $summary | clip } catch { }
try { $summary | Out-File -FilePath 'C:\Temp\soefix\summary.txt' -Encoding ASCII } catch { }
try { $summary | Out-File -FilePath 'C:\Helpdesk\soe_fixup_summary.txt' -Append -Encoding ASCII } catch { }
Write-Host ''
Write-Host 'Summary saved to C:\Temp\soefix\summary.txt (soefix verify pulls it back to the Mac).' -ForegroundColor Cyan
Finish-Beer 'Cheers - all steps done'
try { Stop-Transcript | Out-Null } catch { }
