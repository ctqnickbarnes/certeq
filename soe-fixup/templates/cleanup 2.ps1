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
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}"' -f $MyInvocation.MyCommand.Path)
    exit
}
try { Start-Transcript -Path 'C:\Temp\soefix\transcript.txt' -Append | Out-Null } catch { }

Write-Host ''
Write-Host ("SOE fixup - site $site $siteName (ref $refId) - recollect $days days") -ForegroundColor Cyan
Write-Host ''

# --- 1. Remove SOE_Reboot_eOPS.exe from all user desktops -------------------
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
$plsExe = 'C:\Source\Scripts\SOE_PLS_Install.exe'
if (Test-Path $plsExe) {
    Write-Host 'Running PLS install - CLICK OK on the known error popup...' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath $plsExe -Wait -PassThru
        $lines += "[PASS] PLS install:   completed (exit code $($proc.ExitCode))"
    } catch {
        $lines += "[FAIL] PLS install:   $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] PLS install:   $plsExe not found"
}

# --- 3. Java JRE 7u1 silent install -----------------------------------------
$jreExe = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
$javaBin = 'C:\Program Files\Java\jre7\bin\java.exe'
if (Test-Path $javaBin) {
    $lines += "[PASS] Java JRE 7u1:  already installed"
} elseif (Test-Path $jreExe) {
    Write-Host 'Installing Java JRE 7u1 (silent)...'
    try {
        Start-Process -FilePath $jreExe -ArgumentList '/s' -Wait
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
$gk = 'C:\Helpdesk\tools\generatekvs.exe'
if (-not (Test-Path $gk)) {
    $lines += "[FAIL] generatekvs:   not found at $gk"
    $lines += "[SKIP] Recollect:     skipped (no generatekvs.exe)"
} else {
    $gkDate = (Get-Item $gk).LastWriteTime
    if ($gkDate.Year -ge 2025) {
        $lines += "[PASS] generatekvs:   $($gkDate.ToString('dd/MM/yyyy')) build present"
        Write-Host "Running recollect: generatekvs.exe /auto $days (this can take a while)..."
        Push-Location 'C:\Helpdesk\tools'
        & $gk /auto $days
        $gkExit = $LASTEXITCODE
        Pop-Location
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
try { Stop-Transcript | Out-Null } catch { }
