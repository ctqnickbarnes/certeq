# --- beer progress -------------------------------------------------------------
# A mug that fills from the bottom as the steps complete and pours (rising bubbles,
# bubbling foam) while we wait on a process. Redrawn in place; ASCII source - the glyphs
# come from [char] codes.
$script:BeerStep  = 0
$script:BeerTotal = 1
$script:MugTop    = -1
$script:MugH      = 6      # inner rows (beer height)
$script:MugW      = 12     # inner width
function Write-Mug([double]$frac, [int]$tick, [string]$label, [switch]$InPlace) {
    if ($frac -lt 0) { $frac = 0 }; if ($frac -gt 1) { $frac = 1 }
    $H = $script:MugH; $W = $script:MugW
    $fill  = [int][Math]::Round($H * $frac)
    $beer  = [string][char]0x2588
    $foamC = [string](@([char]0x2592, [char]0x2591)[$tick % 2])
    $blank = ' ' * $W
    $saved = $null
    try {
        if ($InPlace -and $script:MugTop -ge 0) {
            $saved = @([Console]::CursorLeft, [Console]::CursorTop)
            [Console]::SetCursorPosition(0, $script:MugTop)
        } else {
            $script:MugTop = [Console]::CursorTop
        }
    } catch { $script:MugTop = -1 }
    # rim / overflow row
    if ($fill -ge $H) { Write-Host ('   ' + ($foamC * ($W + 2)) + '    ') -ForegroundColor White }
    else              { Write-Host ('   ' + ' ' * ($W + 2) + '    ') }
    for ($i = 1; $i -le $H; $i++) {
        $fromBottom = $H - $i + 1
        Write-Host '   |' -NoNewline -ForegroundColor Gray
        if ($fromBottom -le $fill) {
            # beer, with a rising bubble while pouring
            $row = $beer * $W
            if ($tick -gt 0 -and (($i + $tick) % 3) -eq 0) {
                $pos = ($tick * 7 + $i * 5) % $W
                Write-Host ($beer * $pos) -NoNewline -ForegroundColor DarkYellow
                Write-Host 'o' -NoNewline -ForegroundColor Yellow
                Write-Host ($beer * ($W - $pos - 1)) -NoNewline -ForegroundColor DarkYellow
            } else {
                Write-Host $row -NoNewline -ForegroundColor DarkYellow
            }
        } elseif ($fill -gt 0 -and $fromBottom -eq ($fill + 1)) {
            Write-Host ($foamC * $W) -NoNewline -ForegroundColor White
        } else {
            Write-Host $blank -NoNewline
        }
        Write-Host '|' -NoNewline -ForegroundColor Gray
        # handle on rows 2-4
        switch ($i) {
            2 { Write-Host '--.' -NoNewline -ForegroundColor Gray }
            3 { Write-Host '  |' -NoNewline -ForegroundColor Gray }
            4 { Write-Host "--'" -NoNewline -ForegroundColor Gray }
            default { Write-Host '   ' -NoNewline }
        }
        Write-Host ' '
    }
    Write-Host ("   '" + ('-' * $W) + "'   ") -ForegroundColor Gray
    Write-Host ("   {0,3}%  {1}" -f [int](100 * $frac), $label).PadRight(60) -ForegroundColor Yellow
    if ($saved) { try { [Console]::SetCursorPosition($saved[0], $saved[1]) } catch { } }
}
function Show-Beer([string]$label) {
    # call at the start of each step: draws a fresh mug at the current level
    $script:BeerStep++
    Write-Host ''
    Write-Mug (($script:BeerStep - 1) / $script:BeerTotal) 0 ("step {0}/{1}  {2}" -f $script:BeerStep, $script:BeerTotal, $label)
}
function Wait-Beer($proc, [string]$label) {
    # pour into the mug drawn by Show-Beer while $proc runs; returns its exit code
    $base  = ($script:BeerStep - 1) / $script:BeerTotal
    $slice = 1 / $script:BeerTotal
    $tick  = 1
    while ($proc -and -not $proc.HasExited) {
        $frac = $base + $slice * (1 - [Math]::Exp(-$tick / 60.0))
        Write-Mug $frac $tick ("pouring  {0}" -f $label) -InPlace
        Start-Sleep -Milliseconds 400
        $tick++
    }
    Write-Mug ($base + $slice) 0 ("{0} - done" -f $label) -InPlace
    if ($proc) { try { return $proc.ExitCode } catch { return $null } }
    return $null
}
function Finish-Beer([string]$label) {
    Write-Host ''
    Write-Mug 1 1 $label
    Write-Host ''
}
