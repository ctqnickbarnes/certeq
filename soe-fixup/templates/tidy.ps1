# soefix tidy - paste into PowerShell on RHS02 as the last step for site {{SITE}}. Removes what
# soefix itself put on the SOE (via c$): C:\Temp\soefix (scripts, summary, transcript),
# C:\Helpdesk\soe_fixup_summary.txt and generatekvs.exe.2015.bak. Leaves the driver folder,
# Maxtel, the JRE installer and RHS02's C:\SOE_Backup alone.
& {
$ErrorActionPreference = 'Continue'
$site     = '{{SITE}}'
$siteName = '{{NAME}}'
$soeIp    = '{{IP_SOE}}'
$logDir   = '{{STATIC_UNC}}\soefix-logs'
$lines    = @()

{{CONNECT}}
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
$soeHost = Connect-Soe $soeIp $site
if (-not $soeHost) { $soeHost = $soeIp }
$c = "\\$soeHost\c$"

if (-not (Test-Path "$c\Temp")) {
    $lines += "[FAIL] SOE:           cannot open $c - nothing removed (paste in a NORMAL PowerShell, or: net use \\$soeIp\c`$ /user:Administrator)"
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
    Remove-Artefact "$c\Helpdesk\soe_fixup_summary.txt" 'SOE soe_fixup_summary.txt'
    Remove-Artefact "$c\Helpdesk\tools\generatekvs.exe.2015.bak" 'SOE generatekvs.exe.2015.bak'
}

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
