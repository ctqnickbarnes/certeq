##############################################################################
#
# Script to send the config to the Store Controller VHDs & apply the 2nd nic
# Some of the recent change History
# v1.00	23/04/2022	Initial build (Ben Coulson - BBC Vision)
# v1.01 20/09/2022  Modified script to update virtual SOE with trunked network adapter
# v1.02 17/12/2024  Modified script to use 2022 Server
# v1.03 19/08/2026  Full VM SOE conversion in the same run (restore, wizard wait, SOE setup,
#                   restart + GP check) - Nick Barnes, Certeq. -NoConvert = old behaviour.
#
##############################################################################
param(
    [int]$Site = 0,                      # default: digits in the hostname (NZ00443RHS02 -> 443)
    [string]$SoeIp = '',                 # default: this box's 10.56.x.93 -> 10.56.x.1
    [string]$DriverDir = '',             # default: X:\Certeq\Printer Drivers
    [switch]$SkipRestore,                # the restore already ran for this store
    [switch]$NoBeer,                     # plain output (no progress panel)
    [switch]$NoConvert                   # only create/start the VM (the pre-v1.03 behaviour)
)

# --- self-elevate (guarded - never loops) --------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if ($env:SOEFIX_ELEVATED -eq '1') {
        Write-Host 'Still not elevated after a RunAs relaunch - stopping. Run this from an elevated PowerShell:' -ForegroundColor Red
        Write-Host ("  powershell -NoProfile -ExecutionPolicy Bypass -File ""{0}""" -f $MyInvocation.MyCommand.Path) -ForegroundColor Yellow
        Read-Host 'Press Enter to close' | Out-Null
        exit 1
    }
    $env:SOEFIX_ELEVATED = '1'
    $argLine = '-NoProfile -ExecutionPolicy Bypass -NoExit -File "{0}"' -f $MyInvocation.MyCommand.Path
    foreach ($kv in $PSBoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) { if ($kv.Value) { $argLine += " -$($kv.Key)" } }
        else { $argLine += " -$($kv.Key) ""$($kv.Value)""" }
    }
    Start-Process powershell -Verb RunAs -ArgumentList $argLine
    exit
}

$vmExisted = $false
$Cores = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
$VMName = "Server 2022 SOE"
$vhdPath1 = 'C:\OS\Virtual\SOE_2022\SOEOS.vhdx'
$vhdPath2 = 'C:\OS\Virtual\SOE_2022\SOEData.vhdx'
$logfile = 'C:\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\Logs\SOE_VM_Config.log'

Function Write-Log($Message)
{
    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $Line = "$Stamp $Message"
    Add-Content $logfile -Value $Line
    Write-Host $Message
}

If ( -not (Test-Path -Path "C:\OS\Virtual\SOE_2022" -PathType Container))
    {
        # Extract VHDs
        Write-Log "Extracting VM HDDs. This may take a few minutes.."
        New-Item -ItemType Directory -Path "C:\OS\Virtual\SOE_2022" -Force
        Start-Sleep -Seconds 2
        Start-Process "C:\Program Files\7-Zip\7z.exe" -Wait -Argumentlist " x C:\Images\Virtual\SOE_2022\SOE.7z -oC:\OS\Virtual\SOE_2022"
        Start-Sleep -Seconds 5

        #Create VM
        Write-Log 'Creating new Server 2022 SOE, This will take a few minutes, please wait...'
        New-VM -Name $VMName -Generation 2 -SwitchName VLAN1 | Set-VM -AutomaticStartAction Start -AutomaticStartDelay 5
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $True -StartupBytes 8192MB -MinimumBytes 8192MB -MaximumBytes 32768MB
        Set-VMProcessor -VMName $VMName -Count $Cores -Maximum 100
        Add-VMHardDiskDrive -Path $vhdPath1 -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0
        Add-VMHardDiskDrive -Path $vhdPath2 -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1
        #Resize-VHD -Path $vhdPath1 -SizeBytes 200Gb
        #Resize-VHD -Path $vhdPath2 -SizeBytes 200Gb
        Set-VMNetworkAdapterVlan -VMName $VMName -Access -VlanId 10
        $bootorder = Get-VMFirmware $VMName
        $pxe = $bootorder.BootOrder[0]
        $hdd0 = $bootorder.BootOrder[1]
        $hdd1 = $bootorder.BootOrder[2]
        Set-VMFirmware -VMName $VMName -BootOrder $hdd0,$pxe,$hdd1
        Start-Sleep -Seconds 2
        Set-VMNetworkAdapter "Server 2022 SOE" -VmqWeight 0
        Set-VMNetworkAdapter "Server 2022 SOE" -IPsecOffloadMaximumSecurityAssociation 0
        Set-VMNetworkAdapter "Server 2022 SOE" -NotMonitoredInCluster $True
        $Store_Type = (Get-ItemProperty -Path HKLM:\SOFTWARE\McDonalds -Name "Store_Type")."Store_Type"
        If ($Store_Type -ne "KVS_Zero")
        {
            Set-VMNetworkAdapterVlan -VMName $VMName -VMNetworkAdapterName "Network Adapter" -Untagged
        }
        Start-Sleep -Seconds 2
        Write-Log 'Waiting for VM to start. This will also take a few minutes, grab a coffee...'
        Start-VM -Name $VMName
        Wait-VM -Name $VMName -For Heartbeat -Delay 120
    }
Else
    {
        Write-Log 'VM already exists'
        $vmExisted = $true
    }

# ============================================================================
# v1.03 - conversion: everything after the VM exists, in this same run.
# Derives site / SOE IP from this RHS02; prompts once for the VM SOE Administrator
# password; pauses only for the restore screenshot, the guest wizard and the printer
# driver click-through; waits through the VM's restarts itself.
# -NoConvert stops here (pre-v1.03 behaviour).
# ============================================================================
if ($NoConvert) { Write-Log 'NoConvert: VM step only, stopping here.'; return }
if ($vmExisted) {
    $go = Read-Host "The VM already existed - run the conversion steps now (restore, wizard wait, SOE setup)? [Y/n]"
    if ($go -and $go.Trim().ToLower().StartsWith('n')) { Write-Log 'Conversion skipped by operator.'; return }
}
$lines    = @()
$t0       = Get-Date

function Add-Line($text) {
    $script:lines += $text
    $stamp = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
    try { Add-Content -Path $logfile -Value "$stamp $text" } catch { }
    if ($text -like '*FAIL*') { Write-Host $text -ForegroundColor Red }
    elseif ($text -like '*SKIP*' -or $text -like '*INFO*') { Write-Host $text -ForegroundColor Yellow }
    else { Write-Host $text -ForegroundColor Green }
}

try { Start-Transcript -Path (Join-Path $env:TEMP 'SOE_VM_Config_convert_transcript.txt') -Append | Out-Null } catch { }

# ---- begin: verbatim copy of soe-fixup/templates/_beer.ps1 (a test keeps them identical) ----
# --- beer progress -------------------------------------------------------------
# A status panel pinned to the BOTTOM of the console: a mug that fills as steps complete
# and pours (bubbles, flickering foam) while we wait, with the step/label/elapsed next to it.
# The log scrolls in the rows above it (VT scroll region). Drawn via [Console] calls so it
# never lands in the transcript. Silent if the console is too small or VT can't be enabled.
$script:BeerStep  = 0
$script:BeerTotal = 1
$script:BeerTitle = ''
$script:MugOn     = $false
$script:MugH      = 8      # inner rows (beer height)
$script:MugW      = 14     # inner width
$script:PanelRows = 13     # separator + 2 head rows + 8 inner + base + label
$script:ESC       = [string][char]27
function Enable-VT {
    # Windows PowerShell 5.1 doesn't turn on VT processing for a -File run; do it via kernel32.
    if ($env:OS -ne 'Windows_NT') { return $true }
    try {
        if (-not ('SoeFixVT' -as [type])) {
            $def = '[DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int h);' + "`n" +
                   '[DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetConsoleMode(IntPtr h, out uint m);' + "`n" +
                   '[DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetConsoleMode(IntPtr h, uint m);'
            Add-Type -Name SoeFixVT -Namespace Win32 -MemberDefinition $def -ErrorAction Stop | Out-Null
        }
        $h = [Win32.SoeFixVT]::GetStdHandle(-11)
        $m = [uint32]0
        if (-not [Win32.SoeFixVT]::GetConsoleMode($h, [ref]$m)) { return $false }
        return [Win32.SoeFixVT]::SetConsoleMode($h, ($m -bor 4))   # ENABLE_VIRTUAL_TERMINAL_PROCESSING
    } catch { return $false }
}
function Init-Beer([string]$title, [int]$total) {
    $script:BeerTitle = $title
    $script:BeerTotal = [Math]::Max(1, $total)
    $script:BeerStep  = 0
    try {
        if ([Console]::WindowWidth -lt 70 -or [Console]::WindowHeight -lt ($script:PanelRows + 8)) { return }
        if (-not (Enable-VT)) { return }
        Clear-Host
        $bottom = [Console]::WindowHeight - $script:PanelRows      # last text row (1-based, viewport)
        [Console]::Write($script:ESC + '[1;' + $bottom + 'r')          # scroll region = rows 1..bottom
        [Console]::SetCursorPosition(0, [Console]::WindowTop)
        $script:MugOn = $true
        Write-Mug 0 0 ''
    } catch { $script:MugOn = $false }
}
function Get-FoamRow([int]$w, [int]$tick, [switch]$Light) {
    # a row of foam: dense (mostly medium shade, a few light gaps) or light (airy, with bubbles); shifts with $tick
    $dk = [string][char]0x2592; $lt = [string][char]0x2591; $deg = [string][char]0xB0
    $dense = @($dk, $dk, $lt, $dk, $dk, $dk, $lt, $dk, $dk, $lt, $dk)
    $airy  = @($lt, $lt, ' ', $lt, 'o', $lt, $lt, ' ', $lt, $deg, $lt)
    $s = ''
    for ($c = 0; $c -lt $w; $c++) {
        $r = ($c * 7 + $tick * 3 + ($c % 3)) % 11
        if ($Light) { $s += $airy[$r] } else { $s += $dense[$r] }
    }
    return $s
}
function Get-HeadRows([int]$w, [int]$tick) {
    # the head over the rim when the mug is full: a domed, bubbling cap slightly wider than the glass
    $deg = [string][char]0xB0
    $bub = @('o', 'O', $deg, 'o', $deg, 'O', 'o', 'O', $deg)
    $dome = ''
    for ($c = 0; $c -lt ($w - 2); $c++) { $dome += @('o', 'O', 'o', '-')[($c + $tick) % 4] }
    $cap = ''
    for ($c = 0; $c -lt ($w + 2); $c++) { $cap += $bub[($c * 5 + $tick) % $bub.Count] }
    return @(('   .-' + $dome + '-.'), ('  (' + $cap + ')'))
}
function Write-Mug([double]$frac, [int]$tick, [string]$label) {
    if (-not $script:MugOn) { return }
    if ($frac -lt 0) { $frac = 0 }; if ($frac -gt 1) { $frac = 1 }
    $H = $script:MugH; $W = $script:MugW
    $fill  = [int][Math]::Round($H * $frac)
    $beer  = [string][char]0x2588
    $shine = [string][char]0x2593
    $hline = [string][char]0x2500
    # each line = array of (text, color) pairs; ArrayList.Add keeps the nesting PowerShell would flatten
    $art = New-Object System.Collections.ArrayList
    $full = ($fill -ge $H)
    if ($full) {
        foreach ($hr in (Get-HeadRows $W $tick)) { [void]$art.Add(@(,@($hr.PadRight($W + 9), 'White'))) }
        $fill = $H - 1          # top inner row is the base of the head, not beer
    } else {
        [void]$art.Add(@(,@((' ' * ($W + 9)), 'Gray')))
        [void]$art.Add(@(,@((' ' * ($W + 9)), 'Gray')))
    }
    for ($i = 1; $i -le $H; $i++) {
        $fromBottom = $H - $i + 1
        $segs = @(,@('  |', 'Gray'))
        if ($full -and $i -eq 1) {
            $segs += ,@((Get-FoamRow $W $tick), 'White')                       # dense foam under the head
        } elseif ($fromBottom -le $fill) {
            $segs += ,@($shine, 'Yellow')                     # glass reflection
            $body = $W - 1
            if ($tick -gt 0 -and (($i + $tick) % 3) -eq 0) {
                $pos = ($tick * 7 + $i * 5) % $body
                $segs += ,@(($beer * $pos), 'DarkYellow'); $segs += ,@('o', 'Yellow'); $segs += ,@(($beer * ($body - $pos - 1)), 'DarkYellow')
            } else { $segs += ,@(($beer * $body), 'DarkYellow') }
        } elseif ($fill -gt 0 -and $fromBottom -eq ($fill + 1)) {
            $segs += ,@((Get-FoamRow $W $tick), 'White')                       # dense foam on the beer
        } elseif ($fill -gt 0 -and $fromBottom -eq ($fill + 2)) {
            $segs += ,@((Get-FoamRow $W $tick -Light), 'Gray')                 # airy foam above it
        } else { $segs += ,@((' ' * $W), 'Gray') }
        $segs += ,@('|', 'Gray')
        switch ($i) {
            2 { $segs += ,@('___ ', 'Gray') }
            3 { $segs += ,@('   \', 'Gray') }
            4 { $segs += ,@('   |', 'Gray') }
            5 { $segs += ,@('___/', 'Gray') }
            default { $segs += ,@('    ', 'Gray') }
        }
        [void]$art.Add($segs)
    }
    [void]$art.Add(@(,@(("  '" + ('-' * $W) + "'    "), 'Gray')))
    $pct = [int](100 * $frac)
    [void]$art.Add(@(,@((("  {0,3}% full" -f $pct)).PadRight($W + 9), 'Yellow')))
    # text block to the right of the mug
    $elapsed = [TimeSpan]::FromSeconds([int]($tick * 0.4)).ToString('mm\:ss')
    $stepTxt = if ($script:BeerStep -gt 0) { "step {0}/{1}  {2}" -f $script:BeerStep, $script:BeerTotal, $label } else { 'starting...' }
    $stateTxt = if ($tick -gt 0) { "pouring... $elapsed" } elseif ($frac -ge 1) { 'cheers!' } else { '' }
    $info = @(('', 'Gray'), ($script:BeerTitle, 'Cyan'), ($stepTxt, 'Yellow'), ($stateTxt, 'DarkYellow'))
    try {
        $winW  = [Console]::WindowWidth
        $top0  = [Console]::WindowTop + [Console]::WindowHeight - $script:PanelRows   # first panel row (buffer coords)
        $cl = [Console]::CursorLeft; $ct = [Console]::CursorTop
        $fg = [Console]::ForegroundColor
        # separator
        [Console]::SetCursorPosition(0, $top0)
        [Console]::ForegroundColor = 'DarkGray'
        [Console]::Write($hline * ($winW - 1))
        for ($n = 0; $n -lt $art.Count; $n++) {
            [Console]::SetCursorPosition(0, $top0 + 1 + $n)
            foreach ($seg in $art[$n]) { [Console]::ForegroundColor = $seg[1]; [Console]::Write($seg[0]) }
            $col = $script:MugW + 12
            $txt = ''
            $clr = 'Gray'
            if ($n -ge 1 -and $n -le $info.Count) { $txt = [string]$info[$n - 1][0]; $clr = $info[$n - 1][1] }
            [Console]::SetCursorPosition($col, $top0 + 1 + $n)
            [Console]::ForegroundColor = $clr
            $room = $winW - $col - 1
            if ($txt.Length -gt $room) { $txt = $txt.Substring(0, $room) }
            [Console]::Write($txt.PadRight($room))
        }
        [Console]::ForegroundColor = $fg
        [Console]::SetCursorPosition($cl, $ct)
    } catch { }
}
function Show-Beer([string]$label) {
    # call at the start of each step: the mug shows the level reached so far
    $script:BeerStep++
    Write-Mug (($script:BeerStep - 1) / $script:BeerTotal) 0 $label
}
function Test-BeerDone($p) {
    if (-not $p) { return $true }
    if ($p -is [System.Diagnostics.Process]) { try { return $p.HasExited } catch { return $true } }
    if ($p.PSObject.Properties['State']) { return -not ($p.State -eq 'Running' -or $p.State -eq 'NotStarted') }   # a Job
    return $true
}
function Wait-Beer($proc, [string]$label) {
    # pour while $proc (a Process or a Job) runs; returns the process exit code ($null for jobs)
    $base  = ($script:BeerStep - 1) / $script:BeerTotal
    $slice = 1 / $script:BeerTotal
    $tick  = 1
    while (-not (Test-BeerDone $proc)) {
        $frac = $base + $slice * (1 - [Math]::Exp(-$tick / 60.0))
        Write-Mug $frac $tick $label
        Start-Sleep -Milliseconds 400
        $tick++
    }
    Write-Mug ($base + $slice) 0 $label
    if ($proc -is [System.Diagnostics.Process]) { try { return $proc.ExitCode } catch { return $null } }
    return $null
}
function Read-Beer([string]$prompt) {
    # Read-Host inside the scroll region: conhost can leave the cursor one row below the region
    # afterwards, so pull it back and repaint the panel.
    $ans = Read-Host $prompt
    if ($script:MugOn) {
        try {
            $bottomIdx = [Console]::WindowTop + [Console]::WindowHeight - $script:PanelRows - 1   # last text row (buffer)
            if ([Console]::CursorTop -gt $bottomIdx) {
                [Console]::SetCursorPosition(0, $bottomIdx)
                [Console]::Write("`n")
            }
        } catch { }
        Write-Mug (($script:BeerStep - 1) / $script:BeerTotal) 0 ''
    }
    return $ans
}
function Finish-Beer([string]$label) {
    if (-not $script:MugOn) { return }
    $script:BeerStep = $script:BeerTotal
    Write-Mug 1 1 $label
    try {
        # release the scroll region and park the cursor under the panel so the prompt/next output starts clean
        [Console]::Write($script:ESC + '[r')
        [Console]::SetCursorPosition(0, [Console]::WindowTop + [Console]::WindowHeight - 1)
        [Console]::Write("`n")
    } catch { }
    $script:MugOn = $false
}
# ---- end: _beer.ps1 ----

# --- waiting helpers (poll a condition while the mug pours) ---------------------
function Wait-BeerUntil([scriptblock]$Condition, [string]$label, [int]$TimeoutSec, [int]$IntervalSec = 15) {
    # returns $true when $Condition returns a truthy value before the timeout
    $base  = ($script:BeerStep - 1) / $script:BeerTotal
    $slice = 1 / $script:BeerTotal
    $start = Get-Date
    $tick  = 1
    while (((Get-Date) - $start).TotalSeconds -lt $TimeoutSec) {
        $ok = $false
        try { $ok = [bool](& $Condition) } catch { $ok = $false }
        if ($ok) { Write-Mug ($base + $slice) 0 $label; return $true }
        $el = [int]((Get-Date) - $start).TotalSeconds
        $frac = $base + $slice * (1 - [Math]::Exp(-$el / 600.0))
        if ($script:MugOn) { Write-Mug $frac $tick ("{0}  ({1:mm\:ss})" -f $label, [TimeSpan]::FromSeconds($el)) }
        elseif (($tick % 8) -eq 1) { Write-Host ("  ... {0} ({1:mm\:ss})" -f $label, [TimeSpan]::FromSeconds($el)) -ForegroundColor DarkGray }
        Start-Sleep -Seconds $IntervalSec
        $tick++
    }
    return $false
}
function Read-Pause([string]$prompt) {
    # a manual step: say it loudly, wait for Enter (console) - works with or without the panel
    Write-Host ''
    Write-Host ('=' * 78) -ForegroundColor Yellow
    Write-Host $prompt -ForegroundColor Yellow
    Write-Host ('=' * 78) -ForegroundColor Yellow
    Read-Beer 'Press Enter here when done' | Out-Null
}

# --- helpers: X: drive, static files ---------------------------------------------
function Resolve-X {
    if (Test-Path 'X:\') { return 'X:' }
    $m = (net use 2>$null) | Select-String -Pattern '\sX:\s+(\\\\\S+)'
    if ($m) { return $m.Matches[0].Groups[1].Value }
    $r = (Get-ItemProperty 'HKCU:\Network\X' -ErrorAction SilentlyContinue).RemotePath
    if ($r) { return $r }
    return $null
}
function Find-StaticDir($x) {
    # where generatekvs.exe (2025) + jre-7u1-windows-x64.exe live: deployed Appstore folder,
    # X:\Certeq, or the tech's redirected drive (\\tsclient\<share>[\SOE_Static_Files])
    $cands = @('C:\Configuration\Provisioning\Appstore\SOE_Static_Files')
    if ($x) { $cands += (Join-Path $x 'Certeq\SOE_Static_Files') }
    try {
        foreach ($s in @(Get-ChildItem '\\tsclient' -ErrorAction Stop | ForEach-Object { $_.Name })) {
            $cands += "\\tsclient\$s\SOE_Static_Files"; $cands += "\\tsclient\$s"
            $cands += "\\tsclient\$s\Certeq\SOE_Static_Files"; $cands += "\\tsclient\$s\Documents\Certeq\SOE_Static_Files"
        }
    } catch { }
    foreach ($c in $cands) { if (Test-Path (Join-Path $c 'generatekvs.exe')) { return $c } }
    return $null
}

# ================================================================================
$beerTotal = 8
Init-Beer 'SOE convert' $beerTotal
if ($NoBeer) { $script:MugOn = $false }

# --- 1. Preflight ---------------------------------------------------------------
Show-Beer 'Preflight'
if (-not $Site) {
    if ($env:COMPUTERNAME -match '^[A-Za-z]{2}0*(\d+)RHS\d*$') { $Site = [int]$matches[1] }
    else { $Site = [int](Read-Beer "Site number (hostname $env:COMPUTERNAME doesn't contain it)") }
}
$siteTag = $Site.ToString('D5')                 # NZ00443SOE01 / NZ-R0443 patterns
$soeHost = "NZ${siteTag}SOE01"
if (-not $SoeIp) {
    $ip = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '10.56.*' } | Select-Object -First 1)
    if ($ip.Count -gt 0) { $SoeIp = ($ip[0].IPAddress -replace '\.\d+$', '.1') }
    else { $SoeIp = Read-Beer 'VM SOE IP (10.56.x.1)' }
}
$script:BeerTitle = "SOE convert - site $Site - VM '$VMName' - SOE $SoeIp"
Write-Log ''
Write-Log "SOE convert - site $Site ($soeHost) - SOE $SoeIp - host $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Add-Line "[INFO] Site:          $Site  (SOE $SoeIp, VM '$VMName')"

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    Add-Line '[FAIL] Hyper-V:       PowerShell module not available on this box - cannot continue'
    Finish-Beer 'stopped'; Read-Host 'Press Enter to close' | Out-Null; exit 1
}
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Add-Line "[FAIL] VM:            '$VMName' does not exist - the VM creation above failed; see $logfile"
    Finish-Beer 'stopped'; Read-Host 'Press Enter to close' | Out-Null; exit 1
}
Add-Line "[PASS] VM:            '$VMName' exists (state $($vm.State))"
$x = Resolve-X
if ($x) { Add-Line "[PASS] X: drive:      $x" } else { Add-Line '[FAIL] X: drive:      not visible (map X: / run from a session that has it)' }
if (-not $DriverDir -and $x) { $DriverDir = Join-Path $x 'Certeq\Printer Drivers' }
if ($DriverDir -and (Test-Path $DriverDir)) { Add-Line "[PASS] Driver folder: $DriverDir" } else { Add-Line "[FAIL] Driver folder: $DriverDir not found (driver step will be fully manual)" }
$static = Find-StaticDir $x
if ($static) { Add-Line "[PASS] Static files:  $static" } else { Add-Line '[FAIL] Static files:  generatekvs.exe / JRE not found (Appstore\SOE_Static_Files, X:\Certeq\SOE_Static_Files or \\tsclient) - generatekvs/JRE steps will FAIL' }
$cred = $null
try { $cred = Get-Credential -Message "VM SOE local Administrator (site $Site)" -UserName "$soeHost\Administrator" } catch { }
if (-not $cred) { Add-Line '[FAIL] Credential:    none given - cannot talk to the SOE'; Finish-Beer 'stopped'; Read-Host 'Press Enter to close' | Out-Null; exit 1 }
Add-Line "[PASS] Credential:    $($cred.UserName)"

# --- 2. Restore ------------------------------------------------------------------
Show-Beer 'Restore'
if ($SkipRestore) {
    Add-Line '[SKIP] Restore:       -SkipRestore'
} elseif (-not $x) {
    Add-Line '[FAIL] Restore:       no X: drive - X:\SOE_Backup unavailable'
} else {
    $src = Join-Path $x 'SOE_Backup'; $dst = 'C:\SOE_Backup'
    if (-not (Test-Path $src)) {
        Add-Line "[FAIL] Backup copy:   $src not found"
    } else {
        Write-Log "Copying $src -> $dst ..."
        $rp = Start-Process -FilePath 'robocopy.exe' -ArgumentList @("""$src""", """$dst""", '/E', '/R:2', '/W:5', '/NP', '/NFL', '/NDL', '/NJH') -NoNewWindow -PassThru
        $rc = Wait-Beer $rp 'Backup copy'
        if ($rc -lt 8) { Add-Line "[PASS] Backup copy:   robocopy exit $rc" } else { Add-Line "[FAIL] Backup copy:   robocopy exit $rc" }
        $exe = Join-Path $dst 'SOE_Server2022_Restore.exe'
        if (-not (Test-Path $exe)) {
            Add-Line "[FAIL] Restore:       $exe not found"
        } else {
            Write-Log 'Running SOE_Server2022_Restore.exe - about 10 minutes, do NOT interrupt...'
            $tr = Get-Date
            try {
                $p = Start-Process -FilePath $exe -PassThru
                $rc = Wait-Beer $p 'Restore'
                Add-Line ("[PASS] Restore:       finished, exit code {0} ({1} min)" -f $rc, [int]((Get-Date) - $tr).TotalMinutes)
                Read-Pause 'Take a clear full-screen image of the completed restore result now.'
            } catch { Add-Line "[FAIL] Restore:       $($_.Exception.Message)" }
        }
    }
}

# --- 3. VM up + guest wizard --------------------------------------------------------
Show-Beer 'VM + wizard'
try {
    if ((Get-VM -Name $VMName).State -ne 'Running') { Start-VM -Name $VMName -ErrorAction Stop; Add-Line "[PASS] VM start:      started '$VMName'" }
    else { Add-Line "[PASS] VM start:      '$VMName' already running" }
} catch { Add-Line "[FAIL] VM start:      $($_.Exception.Message)" }
try { Start-Process -FilePath 'vmconnect.exe' -ArgumentList @('localhost', """$VMName""") } catch { }
Write-Host ''
Write-Host 'In the VM window, complete the setup wizard:' -ForegroundColor Yellow
Write-Host '   Country: Australia or New Zealand (per the job)' -ForegroundColor Yellow
Write-Host ("   Store ID: {0}   Store IP: {1}   Time zone: the site's" -f $Site.ToString('D4'), $SoeIp) -ForegroundColor Yellow
Write-Host 'Both restarts and the automatic store-user login are waited for here - no need to press anything.' -ForegroundColor Yellow
$storeUser = "NZ-R$($Site.ToString('D4'))"
$probe = {
    $u = @(Get-ChildItem 'C:\Users' -ErrorAction SilentlyContinue | Where-Object { $_.PSIsContainer } | ForEach-Object { $_.Name })
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    New-Object PSObject -Property @{ Host = $env:COMPUTERNAME; Users = ($u -join ','); UpMin = [int]((Get-Date) - $boot).TotalMinutes }
}
$script:lastProbe = $null
$script:authFails = 0
$ready = Wait-BeerUntil {
    $hb = (Get-VM -Name $VMName).Heartbeat
    if (-not ("$hb" -like 'Ok*')) { return $false }
    try {
        $r = Invoke-Command -VMName $VMName -Credential $script:cred -ScriptBlock $probe -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match 'credential|password|logon|denied|authentication') {
            $script:authFails++
            if ($script:authFails -ge 3) {
                Write-Host ''
                Write-Host "The SOE rejected the Administrator password ($($_.Exception.Message)) - enter it again:" -ForegroundColor Red
                $c2 = $null
                try { $c2 = Get-Credential -Message "VM SOE local Administrator (site $Site) - retry" -UserName $script:cred.UserName } catch { }
                if ($c2) { $script:cred = $c2 }
                $script:authFails = 0
            }
        }
        return $false
    }
    $script:lastProbe = $r
    return (($r.Users -split ',') -contains $storeUser -and $r.UpMin -ge 2)
} 'waiting for the SOE (wizard, two restarts, auto-login)' 2400 15
if ($ready) { Add-Line "[PASS] SOE up:        $($script:lastProbe.Host) - store user $storeUser logged in, up $($script:lastProbe.UpMin) min" }
else {
    $seen = if ($script:lastProbe) { "last seen: users $($script:lastProbe.Users), up $($script:lastProbe.UpMin) min" } else { 'PowerShell Direct never answered (wrong password? VM not booted?)' }
    Add-Line "[FAIL] SOE up:        not ready after 40 min - $seen"
    Read-Pause "Finish the wizard / login by hand, then continue (or Ctrl+C to stop)."
}

# --- SOE transport: PowerShell Direct, else network remoting ---------------------------
function Invoke-Soe([scriptblock]$sb, $arg) {
    if ($script:soeMode -eq 'direct') { return Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock $sb -ArgumentList $arg -ErrorAction Stop }
    return Invoke-Command -ComputerName $SoeIp -Credential $cred -ScriptBlock $sb -ArgumentList $arg -ErrorAction Stop
}
$script:soeMode = $null
try { Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop | Out-Null; $script:soeMode = 'direct' } catch { }
if (-not $script:soeMode) {
    try {
        $th = (Get-Item WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
        if ($th -notlike "*$SoeIp*") { Set-Item WSMan:\localhost\Client\TrustedHosts -Value $SoeIp -Concatenate -Force -ErrorAction Stop }
        Invoke-Command -ComputerName $SoeIp -Credential $cred -ScriptBlock { $env:COMPUTERNAME } -ErrorAction Stop | Out-Null
        $script:soeMode = 'network'
    } catch { }
}
if ($script:soeMode) { Add-Line "[PASS] Transport:     $($script:soeMode) (PowerShell $(if ($script:soeMode -eq 'direct') { 'Direct over VMBus' } else { 'remoting to ' + $SoeIp }))" }
else {
    Add-Line '[FAIL] Transport:     neither PowerShell Direct nor remoting reached the SOE - cannot run the SOE steps from here'
    Add-Line '[INFO] Fallback:      do the SOE steps per the runbook (or soefix push from the Mac), then re-run with -SkipRestore for the checks'
}

# --- 4. Push files to the SOE ------------------------------------------------------------
Show-Beer 'Push files'
$sess = $null
if ($script:soeMode) {
    try {
        if ($script:soeMode -eq 'direct') { $sess = New-PSSession -VMName $VMName -Credential $cred -ErrorAction Stop }
        else { $sess = New-PSSession -ComputerName $SoeIp -Credential $cred -ErrorAction Stop }
    } catch { Add-Line "[FAIL] Session:       $($_.Exception.Message)" }
}
if ($sess) {
    $appstore = 'C:\Configuration\Provisioning\Appstore'
    $mxDst = 'E:\Ghost Images\Waystation\AppStore'
    # Maxtel
    if (Test-Path (Join-Path $appstore 'Maxtel.ps1')) {
        try {
            Invoke-Soe { if (-not (Test-Path $args[0])) { New-Item -ItemType Directory -Path $args[0] -Force | Out-Null } } $mxDst | Out-Null
            Copy-Item -Path (Join-Path $appstore 'Maxtel.ps1') -Destination (Join-Path $mxDst 'Maxtel.ps1') -ToSession $sess -Force -ErrorAction Stop
            if (Test-Path (Join-Path $appstore 'Maxtel')) {
                Copy-Item -Path (Join-Path $appstore 'Maxtel') -Destination $mxDst -ToSession $sess -Recurse -Force -ErrorAction Stop
                Add-Line "[PASS] Maxtel:        Maxtel.ps1 + Maxtel\ copied to SOE $mxDst"
            } else { Add-Line "[FAIL] Maxtel:        Maxtel.ps1 copied but $appstore\Maxtel folder not found on RHS02" }
        } catch { Add-Line "[FAIL] Maxtel:        $($_.Exception.Message)" }
    } else { Add-Line "[FAIL] Maxtel:        $appstore\Maxtel.ps1 not found on RHS02" }
    # driver folder
    $leaf = ''
    if ($DriverDir -and (Test-Path $DriverDir)) {
        $leaf = Split-Path $DriverDir -Leaf
        try {
            Invoke-Soe { if (-not (Test-Path 'C:\Temp')) { New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null } } $null | Out-Null
            Write-Log "Copying $DriverDir to the SOE..."
            Copy-Item -Path $DriverDir -Destination 'C:\Temp' -ToSession $sess -Recurse -Force -ErrorAction Stop
            Add-Line "[PASS] Driver folder: $DriverDir -> SOE C:\Temp\$leaf"
        } catch { Add-Line "[FAIL] Driver folder: $($_.Exception.Message)" }
    } else { Add-Line '[SKIP] Driver folder: none to push (fully manual driver step)' }
    # generatekvs.exe
    $gkInfo = Invoke-Soe { $g = 'C:\Helpdesk\tools\generatekvs.exe'; if (Test-Path $g) { (Get-Item $g).LastWriteTime.Year } else { 0 } } $null
    if ($gkInfo -ge 2025) { Add-Line "[PASS] generatekvs:   SOE already has a $gkInfo build" }
    elseif (-not $static) { $have = if ($gkInfo) { "a $gkInfo build" } else { 'none' }; Add-Line "[FAIL] generatekvs:   SOE has $have and no static files folder to copy from" }
    else {
        try {
            Invoke-Soe { $g = 'C:\Helpdesk\tools\generatekvs.exe'; $d = Split-Path $g; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }; if (Test-Path $g) { Copy-Item $g "$g.2015.bak" -Force } } $null | Out-Null
            Copy-Item -Path (Join-Path $static 'generatekvs.exe') -Destination 'C:\Helpdesk\tools\generatekvs.exe' -ToSession $sess -Force -ErrorAction Stop
            $y = Invoke-Soe { (Get-Item 'C:\Helpdesk\tools\generatekvs.exe').LastWriteTime.Year } $null
            if ($y -ge 2025) { Add-Line "[PASS] generatekvs:   replaced (was $(if ($gkInfo) { $gkInfo } else { 'missing' })), SOE now has a $y build" }
            else { Add-Line "[FAIL] generatekvs:   copied but LastWriteTime year is $y - is the source the 2025 build?" }
        } catch { Add-Line "[FAIL] generatekvs:   $($_.Exception.Message)" }
    }
    # JRE installer
    $jreDst = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'
    $hasJre = Invoke-Soe { Test-Path $args[0] } $jreDst
    if ($hasJre) { Add-Line '[PASS] JRE installer: already on the SOE' }
    elseif (-not $static) { Add-Line '[FAIL] JRE installer: missing on the SOE and no static files folder to copy from' }
    else {
        try {
            Invoke-Soe { $d = Split-Path $args[0]; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } } $jreDst | Out-Null
            Copy-Item -Path (Join-Path $static 'jre-7u1-windows-x64.exe') -Destination $jreDst -ToSession $sess -Force -ErrorAction Stop
            Add-Line '[PASS] JRE installer: copied to SOE E:\Ghost Images\Waystation\AppStore\PLS'
        } catch { Add-Line "[FAIL] JRE installer: $($_.Exception.Message)" }
    }
} else {
    Add-Line '[SKIP] Push:          no session to the SOE'
}

# --- 5. Printer driver (manual on the VM console) --------------------------------------------
Show-Beer 'Driver (manual)'
$drvWhere = if ($leaf) { "C:\Temp\$leaf (already copied there)" } else { "C:\Temp (copy the folder from \\$env:COMPUTERNAME\x`$\Certeq first)" }
Read-Pause ("On the VM: sign out the store user and log in as Administrator. Run the driver package in {0} (Yes to extract)," -f $drvWhere) `
    + "`nthen Win+R: printui /s /t2 > Drivers > Add > x64 > Have Disk > the extracted .inf > the printer model." `
    + "`nInstall the driver only (no printer, no port) and confirm it is listed. Stay logged in as Administrator."
Add-Line '[INFO] Driver:        added by hand on the VM (Have Disk)'

# --- 6. SOE work (remote, unattended) ---------------------------------------------------------
Show-Beer 'SOE steps'
$soeWork = {
    $out = @()
    # keep the known PLSCleanStart crash dialog from blocking an unattended run
    $wer = 'HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting'
    $werOld = $null
    try { $werOld = (Get-ItemProperty -Path $wer -Name DontShowUI -ErrorAction SilentlyContinue).DontShowUI; New-ItemProperty -Path $wer -Name DontShowUI -Value 1 -PropertyType DWord -Force | Out-Null } catch { }
    # Maxtel
    $mx = 'E:\Ghost Images\Waystation\AppStore\Maxtel.ps1'
    if (Test-Path $mx) {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $mx) -Wait -PassThru
        if ($p.ExitCode -eq 0) { $out += '[PASS] Maxtel:        completed (exit 0)' } else { $out += "[FAIL] Maxtel:        exit code $($p.ExitCode)" }
    } else { $out += "[FAIL] Maxtel:        $mx not found" }
    # SOE_Reboot_eOPS.exe: in Tools, off the desktops
    $tools = 'E:\Ghost Images\Waystation\Tools'; $toolsExe = Join-Path $tools 'SOE_Reboot_eOPS.exe'
    $desktops = @(Get-ChildItem 'C:\Users' | Where-Object { $_.PSIsContainer } | ForEach-Object { Join-Path $_.FullName 'Desktop' } | Where-Object { Test-Path $_ })
    $onDesk = @(); foreach ($d in $desktops) { $p2 = Join-Path $d 'SOE_Reboot_eOPS.exe'; if (Test-Path $p2) { $onDesk += $p2 } }
    if (-not (Test-Path $tools)) { New-Item -ItemType Directory -Path $tools -Force | Out-Null }
    if (-not (Test-Path $toolsExe)) {
        if ($onDesk.Count -gt 0) { Move-Item $onDesk[0] $toolsExe -Force; $onDesk = @($onDesk | Where-Object { Test-Path $_ }) }
        if (Test-Path $toolsExe) { $out += "[PASS] Tools exe:     moved to $toolsExe" } else { $out += "[FAIL] Tools exe:     $toolsExe missing and no copy on any desktop" }
    } else { $out += "[PASS] Tools exe:     present at $toolsExe" }
    $failed = @(); foreach ($p2 in $onDesk) { Remove-Item $p2 -Force -ErrorAction SilentlyContinue; if (Test-Path $p2) { $failed += $p2 } }
    if ($failed.Count -gt 0) { $out += "[FAIL] Desktop exe:   could not remove: $($failed -join ', ')" }
    elseif ($onDesk.Count -gt 0) { $out += "[PASS] Desktop exe:   removed from $($onDesk.Count) desktop(s)" }
    else { $out += '[PASS] Desktop exe:   not on any desktop' }
    # PLS install
    $pls = 'C:\Source\Scripts\SOE_PLS_Install.exe'
    if (Test-Path $pls) {
        try { $p = Start-Process -FilePath $pls -Wait -PassThru; $out += "[PASS] PLS install:   completed (exit code $($p.ExitCode))" } catch { $out += "[FAIL] PLS install:   $($_.Exception.Message)" }
    } else { $out += "[FAIL] PLS install:   $pls not found" }
    # Java
    $jre = 'E:\Ghost Images\Waystation\AppStore\PLS\jre-7u1-windows-x64.exe'; $javaBin = 'C:\Program Files\Java\jre7\bin\java.exe'
    if (Test-Path $javaBin) { $out += '[PASS] Java JRE 7u1:  already installed' }
    elseif (Test-Path $jre) {
        try { Start-Process -FilePath $jre -ArgumentList '/s' -Wait; if (Test-Path $javaBin) { $out += "[PASS] Java JRE 7u1:  installed, verified at $javaBin" } else { $out += "[FAIL] Java JRE 7u1:  installer ran but $javaBin not found" } } catch { $out += "[FAIL] Java JRE 7u1:  $($_.Exception.Message)" }
    } else { $out += "[FAIL] Java JRE 7u1:  installer not found at $jre" }
    # generatekvs check (no recollect on a conversion)
    $gk = 'C:\Helpdesk\tools\generatekvs.exe'
    if (-not (Test-Path $gk)) { $out += "[FAIL] generatekvs:   not found at $gk" }
    else { $y = (Get-Item $gk).LastWriteTime; if ($y.Year -ge 2025) { $out += "[PASS] generatekvs:   $($y.ToString('dd/MM/yyyy')) build in place (no recollect - new conversion)" } else { $out += "[FAIL] generatekvs:   OLD build ($($y.ToString('dd/MM/yyyy')))" } }
    # restore WER setting
    try { if ($null -eq $werOld) { Remove-ItemProperty -Path $wer -Name DontShowUI -ErrorAction SilentlyContinue } else { Set-ItemProperty -Path $wer -Name DontShowUI -Value $werOld } } catch { }
    return $out
}
if ($script:soeMode) {
    Write-Log 'Running Maxtel, desktop exe, PLS, Java and the generatekvs check on the SOE (unattended)...'
    try {
        $job = Start-Job -ScriptBlock {
            param($mode, $vmName, $ip, $cred, $sb)
            $block = [scriptblock]::Create($sb)
            if ($mode -eq 'direct') { Invoke-Command -VMName $vmName -Credential $cred -ScriptBlock $block }
            else { Invoke-Command -ComputerName $ip -Credential $cred -ScriptBlock $block }
        } -ArgumentList $script:soeMode, $VMName, $SoeIp, $cred, $soeWork.ToString()
        Wait-Beer $job 'SOE steps' | Out-Null
        $res = @(Receive-Job $job -ErrorAction Stop)
        Remove-Job $job -Force
        foreach ($l in $res) { if ("$l" -match '^\[') { Add-Line "$l" } }
        if ($res.Count -eq 0) { Add-Line '[FAIL] SOE steps:     remote run returned nothing' }
    } catch { Add-Line "[FAIL] SOE steps:     $($_.Exception.Message)" }
} else {
    Add-Line '[SKIP] SOE steps:     no transport - do Maxtel / desktop exe / PLS / Java / generatekvs by hand on the VM'
    Read-Pause 'Do the SOE steps by hand per the runbook (Maxtel, SOE_Reboot_eOPS.exe into Tools, PLS, Java, generatekvs 2025), then continue.'
}

# --- 7. Restart + wait + verify ---------------------------------------------------------------
Show-Beer 'Restart + GP'
$restarted = $false
if ($script:soeMode) {
    # the session drops as the SOE goes down - an exception here is expected, not a failure
    try { Invoke-Soe { Restart-Computer -Force } $null | Out-Null } catch { }
    $restarted = $true
}
if (-not $restarted) {
    try { Restart-VM -Name $VMName -Force -ErrorAction Stop; $restarted = $true } catch { Add-Line "[FAIL] Restart:       $($_.Exception.Message)" }
}
if ($restarted) {
    Add-Line '[PASS] Restart:       VM SOE restarting'
    Start-Sleep -Seconds 45
    $check = {
        $sh = New-Object -ComObject WScript.Shell
        $found = @(); $bad = @(); $exes = @()
        foreach ($d in @(Get-ChildItem 'C:\Users' | Where-Object { $_.PSIsContainer } | ForEach-Object { Join-Path $_.FullName 'Desktop' } | Where-Object { Test-Path $_ })) {
            foreach ($l in @(Get-ChildItem $d -Filter '*.lnk' -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'DT Ranking Reboot*' })) {
                $t = ''; try { $t = $sh.CreateShortcut($l.FullName).TargetPath } catch { }
                if ($t -eq 'E:\Ghost Images\Waystation\Tools\SOE_Reboot_eOPS.exe') { $found += $l.FullName } else { $bad += "$($l.FullName) -> $t" }
            }
            if (Test-Path (Join-Path $d 'SOE_Reboot_eOPS.exe')) { $exes += (Join-Path $d 'SOE_Reboot_eOPS.exe') }
        }
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        New-Object PSObject -Property @{ Found = $found; Bad = $bad; Exes = $exes; UpMin = [int]((Get-Date) - $boot).TotalMinutes }
    }
    $script:gp = $null
    $gpOk = $false
    for ($attempt = 1; $attempt -le 2 -and -not $gpOk; $attempt++) {
        $gpOk = Wait-BeerUntil {
            $hb = (Get-VM -Name $VMName).Heartbeat
            if (-not ("$hb" -like 'Ok*')) { return $false }
            $r = Invoke-Soe $check $null
            $script:gp = $r
            return (@($r.Found).Count -gt 0 -and $r.UpMin -le 20)   # fresh boot + shortcut
        } "waiting for the reboot + Group Policy shortcut (try $attempt)" 480 20
        if (-not $gpOk -and $attempt -eq 1) {
            Add-Line '[INFO] GP shortcut:   not there after 8 min - restarting the VM once more'
            try { Invoke-Soe { Restart-Computer -Force } $null | Out-Null } catch { try { Restart-VM -Name $VMName -Force } catch { } }
            Start-Sleep -Seconds 45
        }
    }
    if ($gpOk) { Add-Line "[PASS] GP shortcut:   $($script:gp.Found -join ', ') -> E:\Ghost Images\Waystation\Tools\SOE_Reboot_eOPS.exe" }
    else { Add-Line "[FAIL] GP shortcut:   'DT Ranking Reboot' not on any desktop after two restarts$(if ($script:gp -and @($script:gp.Bad).Count) { ' (found: ' + ($script:gp.Bad -join '; ') + ')' })" }
    if ($script:gp) {
        if (@($script:gp.Exes).Count -eq 0) { Add-Line '[PASS] Desktop exe:   no real SOE_Reboot_eOPS.exe on any desktop' }
        else { Add-Line "[FAIL] Desktop exe:   real exe still on: $($script:gp.Exes -join ', ')" }
    }
}
if (Test-Connection -ComputerName $SoeIp -Count 2 -Quiet) { Add-Line "[PASS] Ping:          $SoeIp replies from RHS02" } else { Add-Line "[FAIL] Ping:          $SoeIp no reply from RHS02" }

# --- 8. Tidy + summary ------------------------------------------------------------------------
Show-Beer 'Tidy + summary'
if ($script:soeMode) {
    try { Invoke-Soe { foreach ($f in @('C:\Helpdesk\soe_fixup_summary.txt', 'C:\Helpdesk\tools\generatekvs.exe.2015.bak', 'C:\Temp\soefix')) { if (Test-Path $f) { Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue } } } $null | Out-Null; Add-Line '[PASS] Tidy:          soefix files removed from the SOE (driver folder, Maxtel, JRE left in place)' } catch { Add-Line "[FAIL] Tidy:          $($_.Exception.Message)" }
}
if ($sess) { try { Remove-PSSession $sess } catch { } }
$stamp   = Get-Date -Format 'yyyy-MM-dd HH:mm'
$header  = "==== SOE CONVERT SUMMARY - site $Site ($soeHost) - SOE $SoeIp - $env:COMPUTERNAME - $stamp ({0} min) ====" -f [int]((Get-Date) - $t0).TotalMinutes
$summary = ($header, ($lines -join "`r`n")) -join "`r`n"
Write-Host ''
Write-Host $header -ForegroundColor Green
foreach ($l in $lines) {
    if ($l -like '*FAIL*') { Write-Host $l -ForegroundColor Red }
    elseif ($l -like '*SKIP*' -or $l -like '*INFO*') { Write-Host $l -ForegroundColor Yellow }
    else { Write-Host $l -ForegroundColor Green }
}
$saved = @()
$logDirs = @()
if ($x) { $logDirs += (Join-Path $x 'Certeq\soefix-logs') }
if ($static -and $static -like '\\tsclient\*') { $logDirs += (Join-Path $static 'soefix-logs') }   # the tech's Mac: soefix log <site>
foreach ($dir in $logDirs) {
    try {
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $summary | Out-File -FilePath (Join-Path $dir "$Site.txt") -Encoding ASCII
        $saved += (Join-Path $dir "$Site.txt")
    } catch { }
}
try { Add-Content -Path $logfile -Value $summary } catch { }
Write-Host ''
if ($saved.Count -gt 0) { Write-Host "Summary saved to: $($saved -join '; ')" -ForegroundColor Cyan }
Write-Host "Log: $logfile" -ForegroundColor Cyan
Write-Host ''
Write-Host 'Remaining by hand:' -ForegroundColor Yellow
Write-Host "  - Thin client: connect + power the USB printer, sign in as local Administrator, copy the driver folder from \\$SoeIp\c`$\Temp," -ForegroundColor Yellow
Write-Host '    control printers > Add a printer > local > USB001/USB002 > Have Disk, do not share, print a test page.' -ForegroundColor Yellow
Write-Host '  - Sign out, let the normal RDP to the VM SOE connect: printer shows as (redirected #), test page from the SOE.' -ForegroundColor Yellow
Write-Host '  - SME approval of the restore screenshot and printer evidence.' -ForegroundColor Yellow
Finish-Beer 'Conversion done - cheers'
try { Stop-Transcript | Out-Null } catch { }
