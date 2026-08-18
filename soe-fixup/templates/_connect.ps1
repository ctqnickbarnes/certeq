function Connect-Soe($ip, $site) {
    # Return the host (IP or name) whose c$ opens for us. Tries the session's own credentials
    # against the IP and the SOE hostname, then asks for the SOE Administrator login (Explorer
    # usually got in the same way). Returns $null if nothing works.
    $names = @($ip, ('NZ{0:D5}SOE01' -f [int]$site), ('AU{0:D5}SOE01' -f [int]$site))
    foreach ($n in $names) { if (Test-Path "\\$n\c$") { return $n } }
    Write-Host "Cannot open \\$ip\c$ with this session's credentials (elevated console? different account on the SOE)." -ForegroundColor Yellow
    Write-Host 'Enter the SOE Administrator login in the dialog (Cancel to skip):' -ForegroundColor Yellow
    $cred = $null
    # local SOE account, host-qualified (a bare 'Administrator' would be taken as a domain account from RHS02)
    $user = ('NZ{0:D5}SOE01\Administrator' -f [int]$site)
    try { $cred = Get-Credential -Message "SOE $ip - local Administrator login" -UserName $user } catch { }
    if ($cred) {
        $pw = $cred.GetNetworkCredential().Password
        foreach ($n in $names) {
            & net.exe use "\\$n\c$" $pw /user:$($cred.UserName) 2>&1 | Out-Null
            if (Test-Path "\\$n\c$") { return $n }
        }
    }
    return $null
}
