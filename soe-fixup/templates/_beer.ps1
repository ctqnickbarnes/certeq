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
function Wait-Beer($proc, [string]$label) {
    # pour while $proc runs; returns its exit code
    $base  = ($script:BeerStep - 1) / $script:BeerTotal
    $slice = 1 / $script:BeerTotal
    $tick  = 1
    while ($proc -and -not $proc.HasExited) {
        $frac = $base + $slice * (1 - [Math]::Exp(-$tick / 60.0))
        Write-Mug $frac $tick $label
        Start-Sleep -Milliseconds 400
        $tick++
    }
    Write-Mug ($base + $slice) 0 $label
    if ($proc) { try { return $proc.ExitCode } catch { return $null } }
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
