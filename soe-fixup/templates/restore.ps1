# soefix restore - paste into a normal (non-elevated) PowerShell on RHS02 (site {{SITE}})
# so the X: mapping is visible; the restore exe elevates itself via UAC (click Yes).
# Copies X:\SOE_Backup to C:\SOE_Backup, runs the Server 2022 restore and waits,
# then lists the X:\Certeq driver folders for `soefix push --driver`.
& {
$ErrorActionPreference = 'Continue'
$site  = '{{SITE}}'
$soeIp = '{{IP_SOE}}'
$lines = @()

{{BEER}}
function Resolve-X {
    # elevated consoles often can't see per-user mapped drives - fall back to the UNC
    if (Test-Path 'X:\') { return 'X:' }
    $m = (net use 2>$null) | Select-String -Pattern '\sX:\s+(\\\\\S+)'
    if ($m) { return $m.Matches[0].Groups[1].Value }
    # elevated consoles are a different logon session - persistent mappings live in HKCU
    $r = (Get-ItemProperty 'HKCU:\Network\X' -ErrorAction SilentlyContinue).RemotePath
    if ($r) { return $r }
    return $null
}

Init-Beer "SOE restore - site $site" 4   # X: drive, backup copy, restore, driver list
Write-Host ''
Write-Host "SOE restore - site $site - $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host ''

Show-Beer 'X: drive'
$x = Resolve-X
if (-not $x) {
    $lines += "[FAIL] X: drive:      not visible here (elevated console?) - paste in a normal PowerShell, or: net use X: \\<server>\<share>"
} else {
    $lines += "[PASS] X: drive:      $x"

    # --- 1. copy the backup ---------------------------------------------------
    Show-Beer 'Backup copy'
    $src = Join-Path $x 'SOE_Backup'
    $dst = 'C:\SOE_Backup'
    if (-not (Test-Path $src)) {
        $lines += "[FAIL] Backup copy:   $src not found"
    } else {
        Write-Host "Copying $src -> $dst ..." -ForegroundColor Yellow
        $t0 = Get-Date
        $rp = Start-Process -FilePath 'robocopy.exe' -ArgumentList @("""$src""", """$dst""", '/E', '/R:2', '/W:5', '/NP', '/NFL', '/NDL', '/NJH') -NoNewWindow -PassThru
        $rc = Wait-Beer $rp 'Backup copy'
        $mins = [int]((Get-Date) - $t0).TotalMinutes
        if ($rc -lt 8) {
            $lines += "[PASS] Backup copy:   robocopy exit $rc ($mins min)"
        } else {
            $lines += "[FAIL] Backup copy:   robocopy exit $rc - check $src"
        }
    }

    # --- 2. run the restore, elevated, and wait --------------------------------
    Show-Beer 'Restore'
    $exe = Join-Path $dst 'SOE_Server2022_Restore.exe'
    if (-not (Test-Path $exe)) {
        $lines += "[FAIL] Restore:       $exe not found"
    } else {
        Write-Host 'Running SOE_Server2022_Restore.exe - about 10 minutes, do NOT interrupt...' -ForegroundColor Yellow
        $t0 = Get-Date
        try {
            $p = Start-Process -FilePath $exe -Verb RunAs -PassThru
            $rc = Wait-Beer $p 'Restore'
            $mins = [int]((Get-Date) - $t0).TotalMinutes
            $lines += "[PASS] Restore:       finished, exit code $rc ($mins min)"
        } catch {
            $lines += "[FAIL] Restore:       $($_.Exception.Message)"
        }
    }

    # --- 3. driver folders available for `soefix push --driver` ----------------
    Show-Beer 'Driver folders'
    $certeq = Join-Path $x 'Certeq'
    if (Test-Path $certeq) {
        $dirs = @(Get-ChildItem $certeq | Where-Object { $_.PSIsContainer } | Sort-Object Name)
        $lines += "[INFO] Drivers:       folders under $certeq (use the name, or a subfolder path, with --driver):"
        foreach ($d in $dirs) {
            $lines += "        $($d.Name)"
            $subs = @(Get-ChildItem $d.FullName -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Sort-Object Name)
            foreach ($s in $subs) { $lines += "            $($d.Name)\$($s.Name)" }
        }
    } else {
        $lines += "[FAIL] Drivers:       $certeq not found"
    }
}

# --- Summary -----------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host ''
Write-Host "==== SOE RESTORE SUMMARY - site $site - $env:COMPUTERNAME - $stamp ====" -ForegroundColor Green
foreach ($l in $lines) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*INFO*') { Write-Host $l -ForegroundColor Cyan }
    else { Write-Host $l -ForegroundColor Green }
}
Write-Host ''
Write-Host 'NEXT (manual):' -ForegroundColor Yellow
Write-Host '  1. Take a clear full-screen image of the completed restore result.'
Write-Host '  2. Hyper-V Manager: start the SOE VM > Connect. Country (AU/NZ), four-digit Store ID,'
Write-Host "     Store IP $soeIp, site time zone. Let both restarts finish (~15 min)."
Write-Host '  3. On the VM: sign out the store user, log in as Administrator, then on the Mac:'
Write-Host "     soefix push $site --driver ""<folder from the list above>""" -ForegroundColor Cyan
Finish-Beer 'Restore done - cheers'
}
