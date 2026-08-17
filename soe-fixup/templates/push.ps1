# soefix push ({{MODE}}) - paste into PowerShell on RHS02 with the VM SOE for site {{SITE}} up.
# Stages {{SCRIPT_NAME}} + go.cmd on the SOE (C:\Temp\soefix), copies Maxtel / driver folder /
# generatekvs.exe / JRE installer as needed. Then on the SOE:  Win+R  ->  C:\Temp\soefix\go
& {
$ErrorActionPreference = 'Continue'
$site     = '{{SITE}}'
$siteName = '{{NAME}}'
$mode     = '{{MODE}}'
$driver   = '{{DRIVER}}'
$soeIp    = '{{IP_SOE}}'
$c        = "\\$soeIp\c$"
$e        = "\\$soeIp\e$"
$stat     = '{{STATIC_UNC}}'
$appstore = 'C:\Configuration\Provisioning\Appstore'
$lines    = @()

$soeScript = @'
{{SOE_SCRIPT}}
'@
$goCmd = @'
{{GO_CMD}}
'@

function Resolve-X {
    if (Test-Path 'X:\') { return 'X:' }
    $m = (net use 2>$null) | Select-String -Pattern '\sX:\s+(\\\\\S+)'
    if ($m) { return $m.Matches[0].Groups[1].Value }
    # elevated consoles are a different logon session - persistent mappings live in HKCU
    $r = (Get-ItemProperty 'HKCU:\Network\X' -ErrorAction SilentlyContinue).RemotePath
    if ($r) { return $r }
    return $null
}
function Write-Ascii($path, $text) {
    $t = ($text -split "`r?`n") -join "`r`n"
    [IO.File]::WriteAllText($path, $t, [Text.Encoding]::ASCII)
}

Write-Host ''
Write-Host "SOE push ($mode) - site $site $siteName - SOE $soeIp" -ForegroundColor Cyan
Write-Host ''

# --- 0. reachability ----------------------------------------------------------
if (Test-Connection -ComputerName $soeIp -Count 2 -Quiet) { $lines += "[PASS] Ping:          $soeIp replies" }
else                                                       { $lines += "[FAIL] Ping:          $soeIp no reply (VM up? IP set?)" }
$cOk = Test-Path $c
$eOk = Test-Path $e
if ($cOk) { $lines += "[PASS] Share c`$:      $c" } else { $lines += "[FAIL] Share c`$:      cannot open $c" }
if ($eOk) { $lines += "[PASS] Share e`$:      $e" } else { $lines += "[FAIL] Share e`$:      cannot open $e" }
if (Test-Path (Join-Path $stat 'generatekvs.exe')) {
    $lines += "[PASS] tsclient:      $stat"
} else {
    # configured share missing (old psm function? mstsc without drive redirection?) - look at what IS redirected
    $shares = @()
    try { $shares = @((net view \\tsclient 2>$null) | Select-String -Pattern '^(\S+)\s+Disk' | ForEach-Object { $_.Matches[0].Groups[1].Value }) } catch { }
    $found = $null
    foreach ($s in $shares) {
        foreach ($cand in @("\\\\tsclient\$s", "\\\\tsclient\$s\SOE_Static_Files", "\\\\tsclient\$s\Certeq\SOE_Static_Files", "\\\\tsclient\$s\Documents\Certeq\SOE_Static_Files")) {
            if (Test-Path (Join-Path $cand 'generatekvs.exe')) { $found = $cand; break }
        }
        if ($found) { break }
    }
    if ($found) {
        $lines += "[INFO] tsclient:      $stat not visible; using $found instead (fix static_unc in soefix.toml / re-source .zshrc)"
        $stat = $found
    } elseif ($shares.Count -gt 0) {
        $lines += "[FAIL] tsclient:      $stat not visible; redirected shares here: $($shares -join ', ') - none has generatekvs.exe (reconnect: source ~/.zshrc then psm)"
    } else {
        $lines += "[FAIL] tsclient:      no \\\\tsclient shares at all - reconnect with drive redirection on (psm / mstsc Local Resources > Drives)"
    }
}

if ($cOk) {
    # --- 1. drop the SOE script + launcher ------------------------------------
    $dst = Join-Path $c 'Temp\soefix'
    try {
        if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
        Write-Ascii (Join-Path $dst '{{SCRIPT_NAME}}') $soeScript
        Write-Ascii (Join-Path $dst 'go.cmd') $goCmd
        if (Test-Path (Join-Path $dst 'summary.txt')) { Remove-Item (Join-Path $dst 'summary.txt') -Force }
        $lines += "[PASS] Scripts:       {{SCRIPT_NAME}} + go.cmd written to $dst"
    } catch {
        $lines += "[FAIL] Scripts:       $($_.Exception.Message)"
    }

    if ($mode -eq 'convert') {
        # --- 2. Maxtel -> SOE E:\Ghost Images\Waystation\AppStore ---------------
        $mxDst = Join-Path $e 'Ghost Images\Waystation\AppStore'
        if (-not $eOk) {
            $lines += "[FAIL] Maxtel:        e$ unreachable - copy $appstore\Maxtel.ps1 + Maxtel\ to E:\Ghost Images\Waystation\AppStore\ by hand"
        } elseif (-not (Test-Path (Join-Path $appstore 'Maxtel.ps1'))) {
            $lines += "[FAIL] Maxtel:        $appstore\Maxtel.ps1 not found on RHS02"
        } else {
            try {
                if (-not (Test-Path $mxDst)) { New-Item -ItemType Directory -Path $mxDst -Force | Out-Null }
                Copy-Item (Join-Path $appstore 'Maxtel.ps1') (Join-Path $mxDst 'Maxtel.ps1') -Force
                if (Test-Path (Join-Path $appstore 'Maxtel')) {
                    Copy-Item (Join-Path $appstore 'Maxtel') $mxDst -Recurse -Force
                    $n = @(Get-ChildItem (Join-Path $mxDst 'Maxtel') -Recurse | Where-Object { -not $_.PSIsContainer }).Count
                    $lines += "[PASS] Maxtel:        Maxtel.ps1 + Maxtel\ ($n files) copied to SOE E:\Ghost Images\Waystation\AppStore"
                } else {
                    $lines += "[FAIL] Maxtel:        Maxtel.ps1 copied but $appstore\Maxtel folder not found on RHS02"
                }
            } catch {
                $lines += "[FAIL] Maxtel:        $($_.Exception.Message)"
            }
        }

        # --- 3. driver folder X:\Certeq\<driver> -> SOE C:\Temp\<driver> --------
        if (-not $driver) {
            $lines += "[SKIP] Driver:        no --driver given (SOE script will skip the driver step)"
        } else {
            $x = Resolve-X
            if (-not $x -and $driver -notmatch '^\\\\') {
                $lines += "[FAIL] Driver:        X: not visible here (elevated console?) - paste in a normal PowerShell"
            } else {
                # --driver may be: a folder under X:\Certeq, a path under X:\, or a full X:\... / UNC path
                $dsrc = $null
                if ($driver -match '^[A-Za-z]:\\|^\\\\') {
                    if ($driver -match '^[Xx]:' -and $x -ne 'X:') { $driver = $x + $driver.Substring(2) }
                    $dsrc = $driver
                } else {
                    foreach ($cand in @((Join-Path (Join-Path $x 'Certeq') $driver), (Join-Path $x $driver))) {
                        if (Test-Path $cand) { $dsrc = $cand; break }
                    }
                    if (-not $dsrc) { $dsrc = Join-Path (Join-Path $x 'Certeq') $driver }
                }
                $leaf = Split-Path $dsrc -Leaf
                if (-not (Test-Path $dsrc)) {
                    $lines += "[FAIL] Driver:        $dsrc not found. Folders under $x\Certeq:"
                    foreach ($d in @(Get-ChildItem (Join-Path $x 'Certeq') -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Sort-Object Name)) {
                        $lines += "        $($d.Name)"
                        foreach ($s in @(Get-ChildItem $d.FullName -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | Sort-Object Name)) { $lines += "            $($d.Name)\$($s.Name)" }
                    }
                } else {
                    try {
                        Copy-Item $dsrc (Join-Path $c 'Temp') -Recurse -Force
                        $n = @(Get-ChildItem (Join-Path (Join-Path $c 'Temp') $leaf) -Recurse | Where-Object { -not $_.PSIsContainer }).Count
                        $lines += "[PASS] Driver:        $dsrc ($n files) copied to SOE C:\Temp\$leaf"
                    } catch {
                        $lines += "[FAIL] Driver:        $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    # --- 4. generatekvs.exe (2025 build) ------------------------------------------
    $gkDst = Join-Path $c 'Helpdesk\tools\generatekvs.exe'
    $gkSrc = Join-Path $stat 'generatekvs.exe'
    $needGk = $true
    if (Test-Path $gkDst) {
        $d = (Get-Item $gkDst).LastWriteTime
        if ($d.Year -ge 2025) { $needGk = $false; $lines += "[PASS] generatekvs:   SOE already has $($d.ToString('dd/MM/yyyy')) build" }
        else                  { $lines += "[INFO] generatekvs:   SOE has OLD $($d.ToString('dd/MM/yyyy')) build - replacing" }
    } else {
        $lines += "[INFO] generatekvs:   missing on SOE - installing"
    }
    if ($needGk) {
        if (-not (Test-Path $gkSrc)) {
            $lines += "[FAIL] generatekvs:   $gkSrc not found - put generatekvs.exe in your SOE_Static_Files folder"
        } else {
            try {
                $tdir = Split-Path $gkDst -Parent
                if (-not (Test-Path $tdir)) { New-Item -ItemType Directory -Path $tdir -Force | Out-Null }
                if (Test-Path $gkDst) { Copy-Item $gkDst "$gkDst.2015.bak" -Force }
                Copy-Item $gkSrc $gkDst -Force
                $d = (Get-Item $gkDst).LastWriteTime
                if ($d.Year -ge 2025) { $lines += "[PASS] generatekvs:   replaced, SOE now has $($d.ToString('dd/MM/yyyy')) build" }
                else                  { $lines += "[FAIL] generatekvs:   copied but LastWriteTime is $($d.ToString('dd/MM/yyyy')) - is the source the 2025 build?" }
            } catch {
                $lines += "[FAIL] generatekvs:   $($_.Exception.Message)"
            }
        }
    }

    # --- 5. JRE installer, only if the SOE doesn't have it -------------------------
    $jreDst = Join-Path $e 'Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
    $jreSrc = Join-Path $stat 'jre-7u1-windows-x64.exe'
    if (-not $eOk) {
        $lines += "[FAIL] JRE installer: e$ unreachable - cannot check E:\...\AppStore\PLS"
    } elseif (Test-Path $jreDst) {
        $lines += "[PASS] JRE installer: already on SOE"
    } elseif (-not (Test-Path $jreSrc)) {
        $lines += "[FAIL] JRE installer: missing on SOE and $jreSrc not found"
    } else {
        Write-Host 'Copying jre-7u1-windows-x64.exe (21 MB) to the SOE...' -ForegroundColor Yellow
        try {
            $jd = Split-Path $jreDst -Parent
            if (-not (Test-Path $jd)) { New-Item -ItemType Directory -Path $jd -Force | Out-Null }
            Copy-Item $jreSrc $jreDst -Force
            $lines += "[PASS] JRE installer: copied to SOE E:\Ghost Images\Waystation\AppStore\PLS"
        } catch {
            $lines += "[FAIL] JRE installer: $($_.Exception.Message)"
        }
    }
}

# --- Summary -----------------------------------------------------------------
$stamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
Write-Host ''
Write-Host "==== SOE PUSH SUMMARY ($mode) - site $site $siteName - $stamp ====" -ForegroundColor Green
foreach ($l in $lines) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*SKIP*' -or $l -like '*INFO*') { Write-Host $l -ForegroundColor Yellow }
    else { Write-Host $l -ForegroundColor Green }
}
Write-Host ''
if ($cOk) {
    Write-Host 'NEXT: on the VM SOE (logged in as Administrator):  Win+R  ->  C:\Temp\soefix\go' -ForegroundColor Cyan
    if ($mode -eq 'convert') { Write-Host "      then, after it reboots:  soefix verify $site" -ForegroundColor Cyan }
    else                     { Write-Host "      when it finishes:  soefix verify $site   (pulls the summary back)" -ForegroundColor Cyan }
} else {
    Write-Host 'Fix the c$ share access first, then re-run this paste.' -ForegroundColor Red
}
}
