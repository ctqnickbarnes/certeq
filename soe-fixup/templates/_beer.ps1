# --- beer progress -------------------------------------------------------------
# A glass that fills as the steps complete and pours (animated foam) while we wait on a process.
$script:BeerStep  = 0
$script:BeerTotal = 1
function Write-Beer([double]$frac, [int]$tick, [string]$label, [switch]$Return) {
    if ($frac -lt 0) { $frac = 0 }; if ($frac -gt 1) { $frac = 1 }
    $w    = 30
    $fill = [int][Math]::Round($w * $frac)
    $beer = [string][char]0x2588
    $foam = [string](@([char]0x2592, [char]0x2591)[$tick % 2])
    $air  = [string][char]0x00B7
    if ($Return) { Write-Host "`r" -NoNewline }
    Write-Host '  |' -NoNewline -ForegroundColor Gray
    if ($fill -gt 1) { Write-Host ($beer * ($fill - 1)) -NoNewline -ForegroundColor DarkYellow }
    if ($fill -gt 0) { Write-Host $foam -NoNewline -ForegroundColor White }
    if ($fill -lt $w) { Write-Host ($air * ($w - $fill)) -NoNewline -ForegroundColor DarkGray }
    Write-Host '|' -NoNewline -ForegroundColor Gray
    Write-Host ("  {0,3}%  {1}" -f [int](100 * $frac), $label).PadRight(45) -NoNewline -ForegroundColor Yellow
}
function Show-Beer([string]$label) {
    # call at the start of each step
    $script:BeerStep++
    Write-Host ''
    Write-Beer (($script:BeerStep - 1) / $script:BeerTotal) 0 ("step {0}/{1}  {2}" -f $script:BeerStep, $script:BeerTotal, $label)
    Write-Host ''
}
function Wait-Beer($proc, [string]$label) {
    # pour while $proc runs; returns its exit code
    $base  = ($script:BeerStep - 1) / $script:BeerTotal
    $slice = 1 / $script:BeerTotal
    $tick  = 0
    while ($proc -and -not $proc.HasExited) {
        $frac = $base + $slice * (1 - [Math]::Exp(-$tick / 60.0))
        Write-Beer $frac $tick ("pouring  {0}" -f $label) -Return
        Start-Sleep -Milliseconds 400
        $tick++
    }
    Write-Beer ($base + $slice) $tick ("{0} - done" -f $label) -Return
    Write-Host ''
    if ($proc) { try { return $proc.ExitCode } catch { return $null } }
    return $null
}
function Finish-Beer([string]$label) {
    Write-Host ''
    Write-Beer 1 1 $label
    Write-Host ''
    Write-Host ''
}
