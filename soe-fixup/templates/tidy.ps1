# soefix tidy - paste into PowerShell on RHS02 as the LAST step for site {{SITE}} (after the
# thin-client printer is done - it copies the driver from the SOE's C:\Temp). Removes every
# artefact the process left on RHS02 and on the SOE (via c$). Nothing else is touched.
& {
$ErrorActionPreference = 'Continue'
$site     = '{{SITE}}'
$siteName = '{{NAME}}'
$soeIp    = '{{IP_SOE}}'
$driver   = '{{DRIVER}}'
$c        = "\\$soeIp\c$"
$logDir   = '{{STATIC_UNC}}\soefix-logs'
$lines    = @()

function Remove-Artefact($path, $label) {
    if (-not (Test-Path $path)) { $script:lines += "[PASS] $label already gone ($path)"; return }
    try {
        Remove-Item $path -Recurse -Force -ErrorAction Stop
        if (Test-Path $path) { $script:lines += "[FAIL] $label still present after delete: $path" }
        else                 { $script:lines += "[PASS] $label removed: $path" }
    } catch {
        $script:lines += "[FAIL] $label $path - $($_.Exception.Message)"
    }
}

Write-Host ''
Write-Host "SOE tidy - site $site $siteName - SOE $soeIp" -ForegroundColor Cyan
Write-Host ''

if (-not (Test-Path "$c\Temp")) {
    $lines += "[FAIL] SOE:           cannot open $c - nothing on the SOE was removed"
} else {
    # keep a copy of the summary/transcript on the Mac before deleting them (verify normally did this)
    $sum = "$c\Temp\soefix\summary.txt"
    if (Test-Path $sum) {
        try {
            if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
            if (-not (Test-Path (Join-Path $logDir "$site.txt"))) { Copy-Item $sum (Join-Path $logDir "$site.txt") -Force }
            $tr = "$c\Temp\soefix\transcript.txt"
            if ((Test-Path $tr) -and -not (Test-Path (Join-Path $logDir "$site-transcript.txt"))) { Copy-Item $tr (Join-Path $logDir "$site-transcript.txt") -Force }
            $lines += "[PASS] Summary:       kept in $logDir"
        } catch {
            $lines += "[FAIL] Summary:       could not copy to $logDir ($($_.Exception.Message)) - NOT deleting C:\Temp\soefix"
        }
    }
    if (-not ($lines -like '*NOT deleting*')) {
        Remove-Artefact "$c\Temp\soefix" 'SOE C:\Temp\soefix'
    }
    if ($driver) {
        Remove-Artefact (Join-Path "$c\Temp" $driver) "SOE C:\Temp\$driver"
    } else {
        $lines += "[SKIP] SOE driver:    no --driver recorded for this site - check C:\Temp on the SOE by hand"
    }
    Remove-Artefact "$c\Helpdesk\soe_fixup_summary.txt" 'SOE soe_fixup_summary.txt'
    Remove-Artefact "$c\Helpdesk\tools\generatekvs.exe.2015.bak" 'SOE generatekvs.exe.2015.bak'
    $left = @(Get-ChildItem "$c\Temp" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($left.Count -gt 0) { $lines += "[INFO] SOE C:\Temp:    still contains: $($left -join ', ') (not ours, left alone)" }
    else                   { $lines += "[PASS] SOE C:\Temp:    empty" }
}

# RHS02: the restore staging copy
Remove-Artefact 'C:\SOE_Backup' 'RHS02 C:\SOE_Backup'

# --- Summary -----------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host ''
Write-Host "==== SOE TIDY SUMMARY - site $site $siteName - $stamp ====" -ForegroundColor Green
foreach ($l in $lines) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*SKIP*' -or $l -like '*INFO*') { Write-Host $l -ForegroundColor Yellow }
    else { Write-Host $l -ForegroundColor Green }
}
Write-Host ''
}
