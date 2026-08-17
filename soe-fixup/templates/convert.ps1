# soefix convert - runs ON the VM SOE (site {{SITE}} {{NAME}}) from C:\Temp\soefix\go.
# Staged there by `soefix push`. Interactive where the runbook needs a click.
$ErrorActionPreference = 'Continue'
$site     = '{{SITE}}'
$siteName = '{{NAME}}'
$refId    = '{{REF}}'
$driver   = '{{DRIVER}}'
$rhsIp    = '{{IP_RHS}}'
$here     = 'C:\Temp\soefix'
$lines    = @()

# --- self-elevate ------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}"' -f $MyInvocation.MyCommand.Path)
    exit
}
try { Start-Transcript -Path (Join-Path $here 'transcript.txt') -Append | Out-Null } catch { }

Write-Host ''
Write-Host "SOE convert - site $site $siteName (ref $refId) - $env:COMPUTERNAME - $env:USERNAME" -ForegroundColor Cyan
Write-Host ''

# --- 1. Maxtel ----------------------------------------------------------------
$mx = 'E:\Ghost Images\Waystation\AppStore\Maxtel.ps1'
if (Test-Path $mx) {
    Write-Host 'Running Maxtel.ps1 - wait for it to complete...' -ForegroundColor Yellow
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mx
    $rc = $LASTEXITCODE
    if ($rc -eq 0) { $lines += "[PASS] Maxtel:        completed (exit 0)" }
    else           { $lines += "[FAIL] Maxtel:        exit code $rc - check output above" }
} else {
    $lines += "[FAIL] Maxtel:        $mx not found (soefix push copies it from RHS02)"
}

# --- 2. Printer driver: stage + Add Driver via printui ------------------------
if (-not $driver) {
    # no --driver given to soefix push: same pause, you do the copy + Have Disk by hand
    Start-Process -FilePath 'printui.exe' -ArgumentList '/s /t2'
    Write-Host ''
    Write-Host 'No driver folder was pushed - do the driver by hand now:' -ForegroundColor Yellow
    Write-Host "   1. Browse \\$rhsIp\x`$\Certeq and copy the printer's driver folder to C:\Temp (extract if needed)." -ForegroundColor Yellow
    Write-Host '   2. In the printui window already open: Drivers > Add > x64 > Have Disk > the .inf in C:\Temp\<folder> > model.' -ForegroundColor Yellow
    Write-Host '   3. Install the driver only - no printer, no port. Confirm it is listed.' -ForegroundColor Yellow
    Read-Host 'Press Enter here once the driver is listed'
    $lines += "[INFO] Driver:        done by hand (no --driver given to soefix push)"
} else {
    $dd = Join-Path 'C:\Temp' $driver
    if (-not (Test-Path $dd)) {
        $lines += "[FAIL] Driver:        $dd not found (soefix push copies it from X:\Certeq)"
    } else {
        $infs = @(Get-ChildItem $dd -Filter '*.inf' -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($infs.Count -eq 0) {
            # nothing at top level: the folder holds packages - expand zips, run the self-extracting exe(s)
            $zips = @(Get-ChildItem $dd -Filter '*.zip' -ErrorAction SilentlyContinue)
            foreach ($z in $zips) {
                Write-Host "Expanding $($z.Name)..." -ForegroundColor Yellow
                try { Expand-Archive -Path $z.FullName -DestinationPath $dd -Force } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
            }
            $exes = @(Get-ChildItem $dd -Filter '*.exe' -ErrorAction SilentlyContinue | Sort-Object Name)
            if ($exes.Count -gt 0) {
                $pick = @($exes[0])
                if ($exes.Count -gt 1) {
                    Write-Host ''
                    Write-Host "Driver packages in $dd (self-extracting):" -ForegroundColor Cyan
                    for ($i = 0; $i -lt $exes.Count; $i++) { Write-Host ("  [{0}] {1}" -f ($i + 1), $exes[$i].Name) }
                    $ans = Read-Host 'Which to run? number, comma-separated for several (Enter = 1)'
                    if ($ans -and $ans.Trim()) {
                        $pick = @()
                        foreach ($n in ($ans -split '[,\s]+')) {
                            if ($n -match '^\d+$' -and [int]$n -ge 1 -and [int]$n -le $exes.Count) { $pick += $exes[[int]$n - 1] }
                        }
                        if ($pick.Count -eq 0) { $pick = @($exes[0]) }
                    }
                }
                foreach ($x in $pick) {
                    Write-Host "Running $($x.Name) - if it asks where to extract, choose $dd ..." -ForegroundColor Yellow
                    try { Start-Process -FilePath $x.FullName -WorkingDirectory $dd -Wait } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
                }
            }
            $infs = @(Get-ChildItem $dd -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Sort-Object Name)
            if ($infs.Count -eq 0) {
                $ans = Read-Host "No .inf found under $dd - folder where the package extracted (Enter to skip)"
                if ($ans -and (Test-Path $ans)) { $infs = @(Get-ChildItem $ans -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Sort-Object Name) }
            }
        }
        if ($infs.Count -eq 0) {
            $lines += "[FAIL] Driver:        no .inf in $dd (even after extract)"
        } else {
            $inf = $infs[0]
            Write-Host "Using top .inf: $($inf.FullName)  ($($infs.Count) found)" -ForegroundColor Cyan
            $models = @(Select-String -Path $inf.FullName -Pattern '^\s*"[^"]+"\s*=\s*[^,;]+,' | ForEach-Object { ($_.Line -split '=')[0].Trim().Trim('"') } | Select-Object -Unique)
            if ($models.Count -gt 0) {
                Write-Host 'Models in that .inf:' -ForegroundColor Cyan
                foreach ($m in $models) { Write-Host "   $m" }
            }
            $pn = & pnputil.exe /add-driver $inf.FullName 2>&1
            $pnText = ($pn | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -or $pnText -match 'successfully|already') {
                $lines += "[PASS] Driver:        staged $($inf.Name) with pnputil"
            } else {
                $lines += "[FAIL] Driver:        pnputil exit $LASTEXITCODE - $pnText"
            }
            Start-Process -FilePath 'printui.exe' -ArgumentList '/s /t2'
            Write-Host ''
            Write-Host 'printui opened: Drivers > Add > x64 > Have Disk >' -ForegroundColor Yellow
            Write-Host "   $($inf.FullName)" -ForegroundColor Yellow
            Write-Host 'Pick the printer model, finish, confirm the driver is listed. Do NOT create a printer.' -ForegroundColor Yellow
            Read-Host 'Press Enter here once the driver is listed'
            $lines += "[INFO] Driver:        Add Driver done by hand from $($inf.FullName)"
        }
    }
}

# --- 3. SOE_Reboot_eOPS.exe: in Tools, not on desktops -------------------------
$tools    = 'E:\Ghost Images\Waystation\Tools'
$toolsExe = Join-Path $tools 'SOE_Reboot_eOPS.exe'
$desktops = @(Get-ChildItem 'C:\Users' | Where-Object { $_.PSIsContainer } | ForEach-Object { Join-Path $_.FullName 'Desktop' } | Where-Object { Test-Path $_ })
$onDesk   = @()
foreach ($d in $desktops) {
    $p = Join-Path $d 'SOE_Reboot_eOPS.exe'
    if (Test-Path $p) { $onDesk += $p }
}
if (-not (Test-Path $tools)) { New-Item -ItemType Directory -Path $tools -Force | Out-Null }
if (-not (Test-Path $toolsExe)) {
    if ($onDesk.Count -gt 0) {
        Move-Item $onDesk[0] $toolsExe -Force
        if (Test-Path $toolsExe) { $lines += "[PASS] Tools exe:     moved from $($onDesk[0]) to $toolsExe" }
        else                     { $lines += "[FAIL] Tools exe:     could not move $($onDesk[0]) to $toolsExe" }
        $onDesk = @($onDesk | Where-Object { Test-Path $_ })
    } else {
        $lines += "[FAIL] Tools exe:     $toolsExe missing and no copy on any desktop"
    }
} else {
    $lines += "[PASS] Tools exe:     present at $toolsExe"
}
$failed = @()
foreach ($p in $onDesk) {
    Remove-Item $p -Force -ErrorAction SilentlyContinue
    if (Test-Path $p) { $failed += $p }
}
if ($failed.Count -gt 0)      { $lines += "[FAIL] Desktop exe:   could not remove: $($failed -join ', ')" }
elseif ($onDesk.Count -gt 0)  { $lines += "[PASS] Desktop exe:   removed from $($onDesk.Count) desktop(s) - GP deploys the shortcut after restart" }
else                          { $lines += "[PASS] Desktop exe:   not on any desktop" }

# --- 4. PLS install (known crash popup - click Close program) -------------------
$plsExe = 'C:\Source\Scripts\SOE_PLS_Install.exe'
if (Test-Path $plsExe) {
    Write-Host 'Running PLS install - when "PLSCleanStart has stopped working" appears, click Close program...' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath $plsExe -Wait -PassThru
        $lines += "[PASS] PLS install:   completed (exit code $($proc.ExitCode))"
    } catch {
        $lines += "[FAIL] PLS install:   $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] PLS install:   $plsExe not found"
}

# --- 5. Java JRE 7u1 silent install --------------------------------------------
$jreExe  = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
$javaBin = 'C:\Program Files\Java\jre7\bin\java.exe'
if (Test-Path $javaBin) {
    $lines += "[PASS] Java JRE 7u1:  already installed"
} elseif (Test-Path $jreExe) {
    Write-Host 'Installing Java JRE 7u1 (silent)...' -ForegroundColor Yellow
    try {
        Start-Process -FilePath $jreExe -ArgumentList '/s' -Wait
        if (Test-Path $javaBin) { $lines += "[PASS] Java JRE 7u1:  installed, verified at $javaBin" }
        else                    { $lines += "[FAIL] Java JRE 7u1:  installer ran but $javaBin not found" }
    } catch {
        $lines += "[FAIL] Java JRE 7u1:  $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] Java JRE 7u1:  installer not found at $jreExe (soefix push copies it from the SOE_Static_Files share)"
}

# --- 6. generatekvs version check - NO recollect on a conversion ------------------
$gk = 'C:\Helpdesk\tools\generatekvs.exe'
if (-not (Test-Path $gk)) {
    $lines += "[FAIL] generatekvs:   not found at $gk"
} else {
    $gkDate = (Get-Item $gk).LastWriteTime
    if ($gkDate.Year -ge 2025) { $lines += "[PASS] generatekvs:   $($gkDate.ToString('dd/MM/yyyy')) build in place (no recollect - new conversion)" }
    else                       { $lines += "[FAIL] generatekvs:   OLD build ($($gkDate.ToString('dd/MM/yyyy'))) - re-run soefix push to replace it" }
}

# --- Summary -----------------------------------------------------------------
$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm'
$header  = "==== SOE CONVERT SUMMARY - site $site $siteName (ref $refId) - $env:COMPUTERNAME - $stamp ===="
$summary = ($header, ($lines -join "`r`n")) -join "`r`n"
Write-Host ''
foreach ($l in ($summary -split "`r`n")) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*SKIP*' -or $l -like '*INFO*') { Write-Host $l -ForegroundColor Yellow }
    else { Write-Host $l -ForegroundColor Green }
}
try { $summary | Out-File -FilePath (Join-Path $here 'summary.txt') -Encoding ASCII } catch { }
try { $summary | Out-File -FilePath 'C:\Helpdesk\soe_fixup_summary.txt' -Append -Encoding ASCII } catch { }
Write-Host ''
Write-Host "Summary saved to $here\summary.txt (soefix verify pulls it back to the Mac)." -ForegroundColor Cyan
try { Stop-Transcript | Out-Null } catch { }

# --- Restart ------------------------------------------------------------------
Write-Host ''
Write-Host 'Restarting the VM SOE in 15 s - press Ctrl+C to abort' -ForegroundColor Yellow
for ($i = 15; $i -gt 0; $i--) { Write-Host -NoNewline "$i "; Start-Sleep -Seconds 1 }
Write-Host ''
Restart-Computer -Force
