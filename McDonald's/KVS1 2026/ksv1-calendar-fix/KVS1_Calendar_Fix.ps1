<#
KVS1 Calendar Fix - force the MyRestaurant close-time change into eBOS on the LIVE SOE.

Run on the store's current SOE on a KVS1 conversion night (right-click > Run with PowerShell).
Default ("wake", MCD's method): restart the myRestaurant Client service, drop
C:\myRestaurantClientService\data\wakemeup.txt, wait for calendar_*.xml (+ .done) to land in
C:\myRt\From, run C:\IM_Bin\APP_SA_AS400.exe, then tell the tech to do eBOS > Help Desk
Utilities > AS400 Import. -Inject (Certeq's method, or the fallback after the wait times
out): write the calendar_*.xml + .done pair ourselves, then import.

  right-click KVS1_Calendar_Fix.ps1 > Run with PowerShell   # prompts for close time; store from hostname
  powershell -ExecutionPolicy Bypass -File KVS1_Calendar_Fix.ps1 -CloseTime 21:00      # no prompts
  powershell -ExecutionPolicy Bypass -File KVS1_Calendar_Fix.ps1 -CloseTime 21:00 -Inject
  powershell -ExecutionPolicy Bypass -File KVS1_Calendar_Fix.ps1 -Store 2074 -Date 20260819 -CloseTime 21:00 -TimeoutMin 15

Design: docs/2026-08-19-calendar-fix-design.md. Tests dot-source this file with
CALFIX_NO_RUN=1 (functions only), so keep every side effect below the guard line.
#>
param(
    [int]$Store,
    [string]$CloseTime,
    [string]$Date,
    [string]$OpenTime = '00:00',
    [int]$TimeoutMin = 10,
    [switch]$Inject,
    [switch]$NoImport,
    [switch]$Elevated        # set by the RunAs relaunch; never pass it by hand
)
$ErrorActionPreference = 'Continue'

# --- constants ----------------------------------------------------------------
$script:SvcName     = 'myRestaurant Client'                 # display name in services.msc
$script:DataDir     = 'C:\myRestaurantClientService\data'
$script:FromDir     = 'C:\myRt\From'
$script:ImportExe   = 'C:\IM_Bin\APP_SA_AS400.exe'
$script:WorkDir     = 'C:\Temp\calfix'
$script:SummaryFile = 'C:\Helpdesk\calendar_fix_summary.txt'

# --- helpers (pure; unit-tested by dot-sourcing with CALFIX_NO_RUN=1) --------
function Get-StoreFromHost([string]$HostName) {
    # AU00193SOE01 -> 193 ; no digits -> $null
    if ($HostName -match '(\d+)') { return [int]$Matches[1] }
    return $null
}

function Test-ClockTime([string]$Value) {
    # HH:mm, 24 h, zero-padded (what MyRestaurant writes and eBOS expects)
    return [bool]($Value -match '^([01][0-9]|2[0-3]):[0-5][0-9]$')
}

function Get-CalendarStamp([datetime]$Stamp) { return $Stamp.ToString('yyyyMMddHHmmss') }

function New-CalendarDone([datetime]$Stamp) { return $Stamp.ToString('yyyy_MM_dd_HH_mm_ss') }

function New-CalendarXml([int]$Store, [string]$Date, [string]$OpenTime, [string]$CloseTime) {
    # Byte-for-byte the shape the myRestaurant Client writes (see original/calendar_20260819133759.xml):
    # CRLF, two-space indent, no trailing newline.
    $nl = "`r`n"
    $x  = '<?xml version="1.0" encoding="utf-8"?>' + $nl
    $x += '<EBOSDATA xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" TYPE="MYREST" DATE_FORMAT="YYYYMMDD">' + $nl
    $x += ('  <HEADER COUNTRY="AU" STORENUMBER="{0}" />' -f $Store.ToString('00000')) + $nl
    $x += ('  <CalendarChange date="{0}">' -f $Date) + $nl
    $x += '    <weather />' + $nl
    $x += ('    <tradinghours StoreOpen="true" is24hours="false" OpenTime="{0}" CloseTime="{1}" />' -f $OpenTime, $CloseTime) + $nl
    $x += '    <comments />' + $nl
    $x += '  </CalendarChange>' + $nl
    $x += '</EBOSDATA>'
    return $x
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Write-CalendarPair([string]$Folder, [int]$Store, [string]$Date, [string]$OpenTime, [string]$CloseTime, [datetime]$Stamp) {
    # Writes calendar_<stamp>.xml then .done (the .done is the importer's "file complete"
    # sentinel, so it must land second). Returns the .xml path. Refuses to overwrite.
    $base     = Join-Path $Folder ('calendar_' + (Get-CalendarStamp $Stamp))
    $xmlPath  = $base + '.xml'
    $donePath = $base + '.done'
    if ((Test-Path -LiteralPath $xmlPath) -or (Test-Path -LiteralPath $donePath)) {
        throw "already exists: $xmlPath"
    }
    Write-Utf8NoBom $xmlPath (New-CalendarXml $Store $Date $OpenTime $CloseTime)
    Write-Utf8NoBom $donePath (New-CalendarDone $Stamp)
    return $xmlPath
}

function Read-CalendarChanges([string]$XmlPath) {
    # Every <CalendarChange> in a myRestaurant calendar file, as flat objects. Always an array.
    [xml]$doc = Get-Content -LiteralPath $XmlPath -Raw
    $out = @()
    foreach ($c in @($doc.EBOSDATA.CalendarChange)) {
        if ($null -eq $c) { continue }
        $th = $c.tradinghours
        $out += [pscustomobject]@{
            Date      = [string]$c.date
            Is24Hours = [string]$th.is24hours
            OpenTime  = [string]$th.OpenTime
            CloseTime = [string]$th.CloseTime
        }
    }
    return ,$out
}

function Test-CalendarMatches($Changes, [string]$Date, [string]$CloseTime) {
    foreach ($c in @($Changes)) {
        if ($null -eq $c) { continue }
        if ($c.Date -eq $Date -and $c.Is24Hours -eq 'false' -and $c.CloseTime -eq $CloseTime) { return $true }
    }
    return $false
}

$script:Lines  = @()
$script:Failed = $false
function Add-Result([string]$Tag, [string]$Phase, [string]$Message) {
    # Tag: PASS | WARN | FAIL | SKIP.  Same line style as the soefix payloads.
    $line = ('[{0}] {1,-9} {2}' -f $Tag, ($Phase + ':'), $Message)
    $script:Lines += $line
    if ($Tag -eq 'FAIL') { $script:Failed = $true }
    $colour = switch ($Tag) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'SKIP' { 'Yellow' } default { 'Red' } }
    Write-Host $line -ForegroundColor $colour
}

# --- guard: tests stop here ---------------------------------------------------
if ($env:CALFIX_NO_RUN -eq '1') { return }

# --- phase flow -----------------------------------------------------------------
# Everything from here runs only on a real SOE (the guard above returns under test).

# --- self-elevate (service restart and C:\myRt need admin) ---------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($Elevated) {
        # we ARE the relaunched copy and still not elevated: never spawn again
        Write-Host 'Still not elevated after a RunAs relaunch - stopping (no more windows).' -ForegroundColor Red
        Write-Host ("  user: {0}" -f $id.Name) -ForegroundColor Red
        Write-Host '  Log in as a local Administrator, or right-click PowerShell > Run as administrator and run:' -ForegroundColor Yellow
        Write-Host ("  powershell -NoProfile -ExecutionPolicy Bypass -File ""{0}""" -f $MyInvocation.MyCommand.Path) -ForegroundColor Yellow
        Read-Host 'Press Enter to close' | Out-Null
        exit 1
    }
    # forward whatever the tech typed, plus -Elevated
    $fwd = @('-Elevated')
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $fwd += "-$k" } }
        else { $fwd += ('-{0} "{1}"' -f $k, $v) }
    }
    $argLine = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}" {1}' -f $MyInvocation.MyCommand.Path, ($fwd -join ' ')
    Start-Process powershell -Verb RunAs -ArgumentList $argLine
    exit
}

New-Item -ItemType Directory -Path $script:WorkDir -Force -ErrorAction SilentlyContinue | Out-Null
try { Start-Transcript -Path (Join-Path $script:WorkDir 'transcript.txt') -Append | Out-Null } catch { }

Write-Host ''
Write-Host 'KVS1 Calendar Fix - MyRestaurant close time -> eBOS' -ForegroundColor Cyan
Write-Host ''

$method   = 'wake'      # wake | inject | wake->inject
$calFile  = $null       # the calendar_*.xml we ended up with
$waitSecs = $null       # wakemeup -> file, seconds
$importRc = $null       # APP_SA_AS400.exe exit code
$doInject = [bool]$Inject

# do { ... } while ($false) so a FAIL can `break` straight to the summary.
do {
    # --- 1. Preflight --------------------------------------------------------
    Write-Host '-- Preflight' -ForegroundColor Cyan
    if (-not $Store) { $Store = Get-StoreFromHost $env:COMPUTERNAME }
    while (-not $Store) {
        $in = Read-Host 'Store number (e.g. 2074)'
        if ($in -match '^\d+$') { $Store = [int]$in }
    }
    $storeNum = $Store.ToString('00000')

    if (-not $Date) { $Date = (Get-Date).ToString('yyyyMMdd') }
    if ($Date -notmatch '^\d{8}$') { Add-Result FAIL 'Preflight' "-Date must be yyyyMMdd (got '$Date')"; break }

    while (-not (Test-ClockTime $CloseTime)) {
        if ($CloseTime) { Write-Host ("  '{0}' is not HH:mm (24 h, zero-padded)" -f $CloseTime) -ForegroundColor Yellow }
        $CloseTime = Read-Host ("Close time for {0} (HH:mm, 24 h, e.g. 21:00)" -f $Date)
    }
    if (-not (Test-ClockTime $OpenTime)) { Add-Result FAIL 'Preflight' "-OpenTime must be HH:mm (got '$OpenTime')"; break }

    Write-Host ("  store {0}  date {1}  open {2}  close {3}  mode {4}  host {5}" -f $storeNum, $Date, $OpenTime, $CloseTime, $(if ($Inject) { 'inject' } else { 'wake' }), $env:COMPUTERNAME)

    $svc = $null
    if (-not $Inject) {
        $svc = Get-Service | Where-Object { $_.Name -eq $script:SvcName -or $_.DisplayName -eq $script:SvcName } | Select-Object -First 1
        if ($svc) {
            Add-Result PASS 'Preflight' ("service '{0}' ({1}) is {2}" -f $svc.DisplayName, $svc.Name, $svc.Status)
        } else {
            $near = @(Get-Service | Where-Object { $_.DisplayName -like '*myRest*' -or $_.Name -like '*myRest*' } | ForEach-Object { $_.DisplayName })
            Add-Result FAIL 'Preflight' ("service '{0}' not found (similar: {1}) - re-run with -Inject" -f $script:SvcName, $(if ($near) { $near -join ', ' } else { 'none' }))
        }
        if (Test-Path -LiteralPath $script:DataDir) { Add-Result PASS 'Preflight' "$($script:DataDir) exists" }
        else { Add-Result FAIL 'Preflight' "$($script:DataDir) missing - re-run with -Inject" }
    }
    if (Test-Path -LiteralPath $script:FromDir) { Add-Result PASS 'Preflight' "$($script:FromDir) exists" }
    else { Add-Result FAIL 'Preflight' "$($script:FromDir) missing - is this the eBOS server?" }
    if (Test-Path -LiteralPath $script:ImportExe) { Add-Result PASS 'Preflight' "$($script:ImportExe) exists" }
    elseif ($NoImport) { Add-Result WARN 'Preflight' "$($script:ImportExe) missing (-NoImport, continuing)" }
    else { Add-Result FAIL 'Preflight' "$($script:ImportExe) missing - use -NoImport to skip the importer" }
    if ($script:Failed) { break }

    $before = @(Get-ChildItem -LiteralPath $script:FromDir -Filter 'calendar_*.xml' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Write-Host ("  {0} calendar_*.xml already in {1} (ignored)" -f $before.Count, $script:FromDir)

    if (-not $Inject) {
        # --- 2. Wake ---------------------------------------------------------
        Write-Host ''
        Write-Host "-- Wake: restart '$($svc.DisplayName)' + wakemeup.txt" -ForegroundColor Cyan
        try {
            Restart-Service -Name $svc.Name -Force -ErrorAction Stop
            $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
            Add-Result PASS 'Wake' "service restarted and Running"
        } catch {
            Add-Result FAIL 'Wake' ("service restart failed: {0}" -f $_.Exception.Message)
            break
        }
        $wakeFile = Join-Path $script:DataDir 'wakemeup.txt'
        try {
            Write-Utf8NoBom $wakeFile ''
            Add-Result PASS 'Wake' "created $wakeFile"
        } catch {
            Add-Result FAIL 'Wake' ("could not create {0}: {1}" -f $wakeFile, $_.Exception.Message)
            break
        }

        # --- 3. Wait ---------------------------------------------------------
        Write-Host ''
        Write-Host ("-- Wait: watching {0} for a new calendar_*.xml (+ .done), up to {1} min" -f $script:FromDir, $TimeoutMin) -ForegroundColor Cyan
        $t0       = Get-Date
        $deadline = $t0.AddMinutes($TimeoutMin)
        $nextTick = $t0.AddSeconds(30)
        $wakeGone = $false
        $pending  = @{}           # xml name -> first seen (waiting for its .done)
        while ((Get-Date) -lt $deadline) {
            if (-not $wakeGone -and -not (Test-Path -LiteralPath $wakeFile)) {
                $wakeGone = $true
                Write-Host ("   wakemeup.txt processed after {0}s" -f [int]((Get-Date) - $t0).TotalSeconds) -ForegroundColor Green
            }
            $new = @(Get-ChildItem -LiteralPath $script:FromDir -Filter 'calendar_*.xml' -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Name })
            foreach ($f in $new) {
                $donePath = [IO.Path]::ChangeExtension($f.FullName, '.done')
                if (Test-Path -LiteralPath $donePath) { $calFile = $f.FullName; break }
                if (-not $pending.ContainsKey($f.Name)) {
                    $pending[$f.Name] = Get-Date
                    Write-Host ("   {0} appeared, waiting for its .done" -f $f.Name)
                } elseif (((Get-Date) - $pending[$f.Name]).TotalSeconds -ge 20) {
                    Add-Result WARN 'Wait' ("{0} has no .done after 20s - using it anyway" -f $f.Name)
                    $calFile = $f.FullName
                    break
                }
            }
            if ($calFile) { break }
            if ((Get-Date) -ge $nextTick) {
                Write-Host ("   ...{0}s, nothing yet" -f [int]((Get-Date) - $t0).TotalSeconds)
                $nextTick = $nextTick.AddSeconds(30)
            }
            Start-Sleep -Seconds 2
        }
        if ($calFile) {
            $waitSecs = [int]((Get-Date) - $t0).TotalSeconds
            $changes  = Read-CalendarChanges $calFile
            Write-Host ("   {0}:" -f (Split-Path $calFile -Leaf))
            foreach ($c in $changes) { Write-Host ("     {0}  24h={1}  {2}-{3}" -f $c.Date, $c.Is24Hours, $c.OpenTime, $c.CloseTime) }
            if (Test-CalendarMatches $changes $Date $CloseTime) {
                Add-Result PASS 'Wait' ("calendar file arrived after {0}s with {1} close {2}" -f $waitSecs, $Date, $CloseTime)
            } else {
                Add-Result WARN 'Wait' ("calendar file arrived after {0}s but has no {1} close {2} entry - if eBOS still shows the wrong close, re-run with -Inject" -f $waitSecs, $Date, $CloseTime)
            }
        } else {
            Add-Result WARN 'Wait' ("no calendar file after {0} min" -f $TimeoutMin)
            $ans = Read-Host ("No calendar file after {0} min. Inject one manually (Certeq method)? [Y/N]" -f $TimeoutMin)
            if ($ans -match '^[Yy]') {
                $method   = 'wake->inject'
                $doInject = $true
            } else {
                Add-Result FAIL 'Wait' 'not injecting - stopped (L2 can still update via VISDATA)'
                break
            }
        }
    }

    # --- 4. Inject -----------------------------------------------------------
    if ($doInject) {
        if ($Inject) { $method = 'inject' }
        Write-Host ''
        Write-Host ("-- Inject: writing calendar pair into {0}" -f $script:FromDir) -ForegroundColor Cyan
        try {
            $calFile = Write-CalendarPair $script:FromDir $Store $Date $OpenTime $CloseTime (Get-Date)
            Add-Result PASS 'Inject' ("wrote {0} (+ .done): {1} open {2} close {3}" -f (Split-Path $calFile -Leaf), $Date, $OpenTime, $CloseTime)
        } catch {
            Add-Result FAIL 'Inject' $_.Exception.Message
            break
        }
    }

    # --- 5. Import -----------------------------------------------------------
    Write-Host ''
    if ($NoImport) {
        Add-Result SKIP 'Import' ("-NoImport: run {0} and the eBOS AS400 Import yourself" -f $script:ImportExe)
    } else {
        Write-Host ("-- Import: running {0}" -f $script:ImportExe) -ForegroundColor Cyan
        try {
            $p = Start-Process -FilePath $script:ImportExe -WorkingDirectory (Split-Path $script:ImportExe) -PassThru -ErrorAction Stop
            if ($p.WaitForExit(120000)) {
                $importRc = $p.ExitCode
                if ($importRc -eq 0) { Add-Result PASS 'Import' 'APP_SA_AS400.exe exit 0' }
                else { Add-Result WARN 'Import' ("APP_SA_AS400.exe exit {0}" -f $importRc) }
            } else {
                $importRc = 'running'
                Add-Result WARN 'Import' 'APP_SA_AS400.exe still running after 120s - leaving it, check its window'
            }
        } catch {
            Add-Result FAIL 'Import' ("could not start APP_SA_AS400.exe: {0}" -f $_.Exception.Message)
            break
        }
        if ($calFile) {
            if (Test-Path -LiteralPath $calFile) { Write-Host ("   {0} still in {1} (the importer may move it later)" -f (Split-Path $calFile -Leaf), $script:FromDir) }
            else { Write-Host ("   {0} consumed from {1}" -f (Split-Path $calFile -Leaf), $script:FromDir) -ForegroundColor Green }
        }
        Write-Host ''
        Write-Host 'NOW IN eBOS:  Help Desk Utilities > AS400 Import.' -ForegroundColor Yellow
        Write-Host ("Then open System Calendar and check {0} shows {1} - {2} (not '24 Hours'). Then retry the eBOS close." -f $Date, $OpenTime, $CloseTime) -ForegroundColor Yellow
        Read-Host 'Press Enter here when done' | Out-Null
    }
} while ($false)

# --- 6. Summary -------------------------------------------------------------------
$stamp    = Get-Date -Format 'yyyy-MM-dd HH:mm'
$result   = if ($script:Failed) { 'FAIL' } else { 'PASS' }
$waitTxt  = if ($null -ne $waitSecs) { "${waitSecs}s" } else { '-' }
$rcTxt    = if ($null -ne $importRc) { "$importRc" } else { '-' }
$storeTxt = if ($Store) { $Store.ToString('00000') } else { '?' }
$header   = "==== KVS1 CALENDAR FIX - store $storeTxt - $env:COMPUTERNAME - $stamp ===="
$oneLine  = "$stamp store=$storeTxt date=$Date open=$OpenTime close=$CloseTime method=$method wait=$waitTxt import=$rcTxt result=$result"
$summary  = ($header, ($script:Lines -join "`r`n"), $oneLine) -join "`r`n"
Write-Host ''
foreach ($l in ($summary -split "`r`n")) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*WARN*' -or $l -like '*SKIP*') { Write-Host $l -ForegroundColor Yellow }
    else { Write-Host $l -ForegroundColor Green }
}
try { $summary | Out-File -FilePath (Join-Path $script:WorkDir 'summary.txt') -Encoding ASCII } catch { }
try {
    $sumDir = Split-Path $script:SummaryFile
    if (-not (Test-Path -LiteralPath $sumDir)) { New-Item -ItemType Directory -Path $sumDir -Force | Out-Null }
    $summary | Out-File -FilePath $script:SummaryFile -Append -Encoding ASCII
} catch { }
Write-Host ''
Write-Host ("Summary saved to {0} and appended to {1}. Send the one-line result back to SME." -f (Join-Path $script:WorkDir 'summary.txt'), $script:SummaryFile) -ForegroundColor Cyan
try { Stop-Transcript | Out-Null } catch { }
# Always pause: launched by right-click > Run with PowerShell the window closes on exit.
Read-Host ("Finished with {0} - press Enter to close" -f $result) | Out-Null
if ($script:Failed) { exit 1 }
