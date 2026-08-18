# soefix verify - paste into PowerShell on RHS02 after the SOE (site {{SITE}}) has rebooted.
# Checks the store-user desktop over c$, pings the SOE, and copies the convert summary
# back to {{STATIC_UNC}}\soefix-logs\{{SITE}}.txt for `soefix log {{SITE}}`.
& {
$ErrorActionPreference = 'Continue'
$site     = '{{SITE}}'
$siteName = '{{NAME}}'
$soeIp    = '{{IP_SOE}}'
$logDir   = '{{STATIC_UNC}}\soefix-logs'
$expected = 'E:\Ghost Images\Waystation\Tools\SOE_Reboot_eOPS.exe'
$lines    = @()

{{CONNECT}}
Write-Host ''
Write-Host "SOE verify - site $site $siteName - SOE $soeIp" -ForegroundColor Cyan
Write-Host ''
$soeHost = Connect-Soe $soeIp $site
if (-not $soeHost) { $soeHost = $soeIp }
$c = "\\$soeHost\c$"

# --- 1. ping ----------------------------------------------------------------
if (Test-Connection -ComputerName $soeIp -Count 2 -Quiet) {
    $lines += "[PASS] Ping:          $soeIp replies"
} else {
    $lines += "[FAIL] Ping:          $soeIp no reply"
}

# --- 2. desktop: shortcut present, targets Tools exe, no real exe ---------------
if (-not (Test-Path "$c\Users")) {
    $lines += "[FAIL] Desktop:       cannot open $c\Users - paste in a NORMAL (non-elevated) PowerShell, or: net use \\$soeIp\c`$ /user:Administrator"
} else {
    $desktops = @(Get-ChildItem "$c\Users" | Where-Object { $_.PSIsContainer } | ForEach-Object { Join-Path $_.FullName 'Desktop' } | Where-Object { Test-Path $_ })
    $lnks = @()
    $exes = @()
    foreach ($d in $desktops) {
        $lnks += @(Get-ChildItem $d -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'DT Ranking*' })
        $exes += @(Get-ChildItem $d -Filter 'SOE_Reboot_eOPS.exe' -ErrorAction SilentlyContinue)
    }
    if ($lnks.Count -eq 0) {
        $lines += "[FAIL] Shortcut:      no 'DT Ranking Reboot' shortcut on any desktop - Group Policy has not run yet"
        $lines += "[INFO] Fix:           restart the VM again (see below), then re-run soefix verify $site"
    } else {
        $sh = New-Object -ComObject WScript.Shell
        foreach ($l in $lnks) {
            $target = ''
            try { $target = $sh.CreateShortcut($l.FullName).TargetPath } catch { }
            $who = Split-Path (Split-Path $l.FullName -Parent) -Parent | Split-Path -Leaf
            if ($target -eq $expected) {
                $lines += "[PASS] Shortcut:      $who\Desktop\$($l.Name) -> $target"
            } else {
                $lines += "[FAIL] Shortcut:      $who\Desktop\$($l.Name) -> '$target' (expected $expected)"
            }
        }
    }
    if ($exes.Count -eq 0) {
        $lines += "[PASS] Desktop exe:   no real SOE_Reboot_eOPS.exe on any desktop"
    } else {
        $lines += "[FAIL] Desktop exe:   real exe still on: $(($exes | ForEach-Object { $_.FullName }) -join ', ')"
    }
}

# --- 3. bring the convert summary back to the Mac ---------------------------------
$sum = "$c\Temp\soefix\summary.txt"
if (Test-Path $sum) {
    try {
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Copy-Item $sum (Join-Path $logDir "$site.txt") -Force
        $tr = "$c\Temp\soefix\transcript.txt"
        if (Test-Path $tr) { Copy-Item $tr (Join-Path $logDir "$site-transcript.txt") -Force }
        $lines += "[PASS] Summary:       copied to $logDir\$site.txt - run: soefix log $site"
    } catch {
        $lines += "[FAIL] Summary:       could not copy to $logDir - $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] Summary:       $sum not found - did convert.ps1 finish on the SOE?"
}

# --- Summary -----------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host ''
Write-Host "==== SOE VERIFY SUMMARY - site $site $siteName - $stamp ====" -ForegroundColor Green
foreach ($l in $lines) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*INFO*') { Write-Host $l -ForegroundColor Cyan }
    else { Write-Host $l -ForegroundColor Green }
}
if ($lnks -eq $null -or $lnks.Count -eq 0) {
    Write-Host ''
    Write-Host 'To restart the VM from here (graceful shutdown via integration services, then start):' -ForegroundColor Yellow
    try {
        $vms = @(Get-VM -ErrorAction Stop)
        foreach ($v in $vms) { Write-Host "  Stop-VM -Name '$($v.Name)'; Start-VM -Name '$($v.Name)'   # state: $($v.State)" -ForegroundColor Cyan }
    } catch {
        Write-Host '  (Hyper-V module not available in this console - restart the VM from Windows inside it)'
    }
}
Write-Host ''
Write-Host 'Remaining manual checks: thin-client USB printer via Have Disk from C:\Temp, test page;' -ForegroundColor Yellow
Write-Host 'then normal RDP to the VM SOE - printer shows as (redirected #), test page from the SOE.'
}
