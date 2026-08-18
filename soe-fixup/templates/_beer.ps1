# --- beer progress -------------------------------------------------------------
# One mug, parked in the top-right corner of the console window; the log scrolls underneath.
# It fills from the bottom as steps complete and pours (bubbles, flickering foam) while we
# wait on a process. Drawn with [Console] calls, so it never lands in the transcript and is
# never re-printed inline. If there is no real console it stays silent.
$script:BeerStep  = 0
$script:BeerTotal = 1
$script:MugH      = 6      # inner rows (beer height)
$script:MugW      = 12     # inner width
$script:MugRows   = @()    # absolute buffer rows currently occupied by the mug (to wipe when it moves)
$script:MugCol    = 0
function Write-Mug([double]$frac, [int]$tick, [string]$label) {
    if ($frac -lt 0) { $frac = 0 }; if ($frac -gt 1) { $frac = 1 }
    $H = $script:MugH; $W = $script:MugW
    $fill  = [int][Math]::Round($H * $frac)
    $beer  = [string][char]0x2588
    $foamC = [string](@([char]0x2592, [char]0x2591)[$tick % 2])
    # each line = array of (text, color) pairs; ArrayList.Add keeps the nesting PowerShell would otherwise flatten
    $lines = New-Object System.Collections.ArrayList
    if ($fill -ge $H) { [void]$lines.Add(@(,@(('  ' + ($foamC * ($W + 2)) + ' '), 'White'))) }
    else              { [void]$lines.Add(@(,@((' ' * ($W + 5)), 'Gray'))) }
    for ($i = 1; $i -le $H; $i++) {
        $fromBottom = $H - $i + 1
        $segs = @(,@('|', 'Gray'))
        if ($fromBottom -le $fill) {
            if ($tick -gt 0 -and (($i + $tick) % 3) -eq 0) {
                $pos = ($tick * 7 + $i * 5) % $W
                $segs += ,@(($beer * $pos), 'DarkYellow'); $segs += ,@('o', 'Yellow'); $segs += ,@(($beer * ($W - $pos - 1)), 'DarkYellow')
            } else { $segs += ,@(($beer * $W), 'DarkYellow') }
        } elseif ($fill -gt 0 -and $fromBottom -eq ($fill + 1)) { $segs += ,@(($foamC * $W), 'White') }
        else { $segs += ,@((' ' * $W), 'Gray') }
        $segs += ,@('|', 'Gray')
        switch ($i) { 2 { $segs += ,@('--.', 'Gray') } 3 { $segs += ,@('  |', 'Gray') } 4 { $segs += ,@("--'", 'Gray') } default { $segs += ,@('   ', 'Gray') } }
        [void]$lines.Add($segs)
    }
    [void]$lines.Add(@(,@(("'" + ('-' * $W) + "'   "), 'Gray')))
    [void]$lines.Add(@(,@(((("{0,3}% {1}" -f [int](100 * $frac), $label)).PadRight($W + 5).Substring(0, $W + 5)), 'Yellow')))
    try {
        $winW = [Console]::WindowWidth
        $col  = $winW - ($W + 6)
        if ($col -lt 40) { return }               # console too narrow - skip the mug rather than clobber the log
        $top  = [Console]::WindowTop + 1
        $cl = [Console]::CursorLeft; $ct = [Console]::CursorTop
        $fg = [Console]::ForegroundColor
        # wipe the old position if the window has scrolled since the last draw
        if ($script:MugRows.Count -gt 0 -and ($script:MugRows[0] -ne $top -or $script:MugCol -ne $col)) {
            foreach ($r in $script:MugRows) {
                if ($r -ge [Console]::WindowTop -and $r -lt ([Console]::WindowTop + [Console]::WindowHeight)) {
                    [Console]::SetCursorPosition($script:MugCol, $r); [Console]::Write(' ' * ($W + 5))
                }
            }
        }
        $rows = @()
        for ($n = 0; $n -lt $lines.Count; $n++) {
            $r = $top + $n
            if ($r -ge [Console]::BufferHeight) { break }
            [Console]::SetCursorPosition($col, $r)
            foreach ($seg in $lines[$n]) { [Console]::ForegroundColor = $seg[1]; [Console]::Write($seg[0]) }
            $rows += $r
        }
        $script:MugRows = $rows; $script:MugCol = $col
        [Console]::ForegroundColor = $fg
        [Console]::SetCursorPosition($cl, $ct)
    } catch { }
}
function Show-Beer([string]$label) {
    # call at the start of each step: the mug shows the level reached so far
    $script:BeerStep++
    Write-Mug (($script:BeerStep - 1) / $script:BeerTotal) 0 ("{0}/{1} {2}" -f $script:BeerStep, $script:BeerTotal, $label)
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
function Finish-Beer([string]$label) {
    Write-Mug 1 1 $label
}
