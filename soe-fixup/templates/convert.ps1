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
    if ($env:SOEFIX_ELEVATED -eq '1') {
        # we ARE the relaunched copy and still not elevated: never spawn again
        Write-Host 'Still not elevated after a RunAs relaunch - stopping (no more windows).' -ForegroundColor Red
        Write-Host ("  user: {0}" -f $id.Name) -ForegroundColor Red
        Write-Host ("  admin group member: {0}" -f (($id.Groups | ForEach-Object { $_.Value }) -contains 'S-1-5-32-544')) -ForegroundColor Red
        Write-Host '  Log in as a local Administrator, or right-click PowerShell > Run as administrator and run:' -ForegroundColor Yellow
        Write-Host ("  powershell -NoProfile -ExecutionPolicy Bypass -File ""{0}""" -f $MyInvocation.MyCommand.Path) -ForegroundColor Yellow
        Read-Host 'Press Enter to close'
        exit 1
    }
    $env:SOEFIX_ELEVATED = '1'
    Start-Process powershell -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}"' -f $MyInvocation.MyCommand.Path)
    exit
}
try { Start-Transcript -Path (Join-Path $here 'transcript.txt') -Append | Out-Null } catch { }

{{BEER}}
$script:BeerTotal = 7   # Maxtel, driver, desktop exe, PLS, Java, generatekvs, summary

Write-Host ''
Write-Host "SOE convert - site $site $siteName (ref $refId) - $env:COMPUTERNAME - $env:USERNAME" -ForegroundColor Cyan
Write-Host ''

# --- 1. Maxtel ----------------------------------------------------------------
Show-Beer 'Maxtel'
$mx = 'E:\Ghost Images\Waystation\AppStore\Maxtel.ps1'
if (Test-Path $mx) {
    Write-Host 'Running Maxtel.ps1 in its own window - wait for it to complete...' -ForegroundColor Yellow
    $mp = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $mx) -PassThru
    $rc = Wait-Beer $mp 'Maxtel'
    if ($rc -eq 0) { $lines += "[PASS] Maxtel:        completed (exit 0)" }
    else           { $lines += "[FAIL] Maxtel:        exit code $rc - check output above" }
} else {
    $lines += "[FAIL] Maxtel:        $mx not found (soefix push copies it from RHS02)"
}

# --- 2. Printer driver: stage + Add Driver via printui ------------------------
# Whatever happens below, printui is opened and the script pauses so the step can always be finished by hand.
Show-Beer 'Printer driver'
$inf = $null
$driverNote = ''
if (-not $driver) {
    $driverNote = 'no --driver given to soefix push'
} else {
    $dd = Join-Path 'C:\Temp' $driver
    if (-not (Test-Path $dd)) {
        $driverNote = "$dd not found (soefix push copies it from X:\Certeq)"
    } else {
        $infs = @(Get-ChildItem $dd -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($infs.Count -eq 0) {
            # the folder holds packages: expand zips, run the self-extracting exe(s)
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
                # extractors like HP's unpack to C:\<PackageName> - snapshot so we can find what they create
                $roots  = @('C:\', 'C:\Temp')
                $before = @()
                foreach ($r in $roots) { $before += @(Get-ChildItem $r -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object { $_.FullName }) }
                foreach ($x in $pick) {
                    Write-Host "Running $($x.Name) - if it asks where to extract, click Yes / accept the default ..." -ForegroundColor Yellow
                    try {
                        $xp = Start-Process -FilePath $x.FullName -WorkingDirectory $dd -PassThru
                        Wait-Beer $xp $x.Name | Out-Null
                    } catch { Write-Host $_.Exception.Message -ForegroundColor Red }
                }
                $after = @()
                foreach ($r in $roots) { $after += @(Get-ChildItem $r -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object { $_.FullName }) }
                foreach ($n in $after) {
                    if ($before -contains $n) { continue }
                    if ($n -eq $dd -or $n -like "$dd\*") { continue }
                    # bring the extracted folder under the driver folder (thin client copies from there later)
                    $dest = Join-Path $dd (Split-Path $n -Leaf)
                    try {
                        Move-Item $n $dest -Force -ErrorAction Stop
                        Write-Host "Moved extracted $n -> $dest" -ForegroundColor Cyan
                    } catch {
                        Write-Host "Extracted to $n (could not move it under $dd - using it in place)" -ForegroundColor Yellow
                        $infs += @(Get-ChildItem $n -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Sort-Object Name)
                    }
                }
            }
            $infs = @($infs) + @(Get-ChildItem $dd -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Sort-Object Name)
            $infs = @($infs | Sort-Object FullName -Unique | Sort-Object Name)
            if ($infs.Count -eq 0) {
                $ans = Read-Host "No .inf found under $dd - folder where the package extracted (Enter to skip)"
                if ($ans -and (Test-Path $ans)) { $infs = @(Get-ChildItem $ans -Filter '*.inf' -Recurse -ErrorAction SilentlyContinue | Sort-Object Name) }
            }
        }
        if ($infs.Count -eq 0) {
            $driverNote = "no .inf found under $dd even after extracting"
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
        }
    }
}
Start-Process -FilePath 'printui.exe' -ArgumentList '/s /t2'
Write-Host ''
if ($inf) {
    Write-Host 'printui opened: Drivers > Add > x64 > Have Disk >' -ForegroundColor Yellow
    Write-Host "   $($inf.FullName)" -ForegroundColor Yellow
} else {
    Write-Host "printui opened. Driver not staged automatically ($driverNote) - do it by hand:" -ForegroundColor Yellow
    Write-Host "   1. Get the printer's driver folder onto C:\Temp (from \\$rhsIp\x`$\Certeq if needed) and extract the package." -ForegroundColor Yellow
    Write-Host '   2. In printui: Drivers > Add > x64 > Have Disk > the extracted .inf > model.' -ForegroundColor Yellow
}
Write-Host 'Pick the printer model, finish, confirm the driver is listed. Do NOT create a printer.' -ForegroundColor Yellow
Read-Host 'Press Enter here once the driver is listed'
if ($inf) { $lines += "[INFO] Driver:        Add Driver done by hand from $($inf.FullName)" }
else      { $lines += "[INFO] Driver:        done by hand ($driverNote)" }

# --- 3. SOE_Reboot_eOPS.exe: in Tools, not on desktops -------------------------
Show-Beer 'SOE_Reboot_eOPS.exe'
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
Show-Beer 'PLS install'
$plsExe = 'C:\Source\Scripts\SOE_PLS_Install.exe'
if (Test-Path $plsExe) {
    Write-Host 'Running PLS install - when "PLSCleanStart has stopped working" appears, click Close program...' -ForegroundColor Yellow
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

# --- 5. Java JRE 7u1 silent install --------------------------------------------
Show-Beer 'Java JRE 7u1'
$jreExe  = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
$javaBin = 'C:\Program Files\Java\jre7\bin\java.exe'
if (Test-Path $javaBin) {
    $lines += "[PASS] Java JRE 7u1:  already installed"
} elseif (Test-Path $jreExe) {
    Write-Host 'Installing Java JRE 7u1 (silent)...' -ForegroundColor Yellow
    try {
        $jp = Start-Process -FilePath $jreExe -ArgumentList '/s' -PassThru
        Wait-Beer $jp 'Java JRE 7u1' | Out-Null
        if (Test-Path $javaBin) { $lines += "[PASS] Java JRE 7u1:  installed, verified at $javaBin" }
        else                    { $lines += "[FAIL] Java JRE 7u1:  installer ran but $javaBin not found" }
    } catch {
        $lines += "[FAIL] Java JRE 7u1:  $($_.Exception.Message)"
    }
} else {
    $lines += "[FAIL] Java JRE 7u1:  installer not found at $jreExe (soefix push copies it from the SOE_Static_Files share)"
}

# --- 6. generatekvs version check - NO recollect on a conversion ------------------
Show-Beer 'generatekvs check'
$gk = 'C:\Helpdesk\tools\generatekvs.exe'
if (-not (Test-Path $gk)) {
    $lines += "[FAIL] generatekvs:   not found at $gk"
} else {
    $gkDate = (Get-Item $gk).LastWriteTime
    if ($gkDate.Year -ge 2025) { $lines += "[PASS] generatekvs:   $($gkDate.ToString('dd/MM/yyyy')) build in place (no recollect - new conversion)" }
    else                       { $lines += "[FAIL] generatekvs:   OLD build ($($gkDate.ToString('dd/MM/yyyy'))) - re-run soefix push to replace it" }
}

# --- Summary -----------------------------------------------------------------
Show-Beer 'Summary'
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
Finish-Beer 'Cheers - all steps done'
try { Stop-Transcript | Out-Null } catch { }

# --- Restart ------------------------------------------------------------------
Write-Host ''
Write-Host 'Restarting the VM SOE in 15 s - press Ctrl+C to abort' -ForegroundColor Yellow
for ($i = 15; $i -gt 0; $i--) { Write-Host -NoNewline "$i "; Start-Sleep -Seconds 1 }
Write-Host ''
Restart-Computer -Force
