##############################################################################
#
# Script to send the config to the Store Controller VHDs & apply the 2nd nic
# Some of the recent change History
# v1.00	23/04/2022	Initial build (Ben Coulson - BBC Vision)
# v1.01 20/09/2022  Modified script to update virtual SOE with trunked network adapter
# v1.02 17/12/2024  Modified script to use 2022 Server
# v2.00 20/08/2026  Place the VM SOE package (C:\certeq, pushed by Lab SOE script 7)
#                   into the SOE VHDs before first boot. Software setup now runs on
#                   the staged SOE via NZ_VM_SOE_Clean_Up.ps1. (Nick Barnes - Certeq)
#
##############################################################################

$Cores = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
$VMName = "Server 2022 SOE"
$vhdPath1 = 'C:\OS\Virtual\SOE_2022\SOEOS.vhdx'
$vhdPath2 = 'C:\OS\Virtual\SOE_2022\SOEData.vhdx'
$logfile = 'C:\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\Logs\SOE_VM_Config.log'
$pkgSource = 'C:\certeq'

Function Write-Log($Message)
{
    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $Line = "$Stamp $Message"
    Add-Content $logfile -Value $Line
    Write-Host $Message
}

##############################################################################
# v2.00 - package placement
# Script 7 on the Lab SOE pushes the VM SOE package to C:\certeq on this box.
# Before the VM boots for the first time we mount its VHDs and move every item
# to the location the build expects (Flow 36). No installers run here - that
# happens on the staged SOE via NZ_VM_SOE_Clean_Up.ps1.
##############################################################################

# Move one item into a mounted VHD volume and confirm it landed. -KeepSource
# leaves the source in place so it can be placed a second time.
Function Place-Item($sourcePath, $destPath, [switch]$KeepSource)
{
    If (-not (Test-Path -LiteralPath $sourcePath)) {
        Write-Log "FAIL: missing $sourcePath (wanted at $destPath)"
        Return $false
    }
    $destParent = Split-Path -Path $destPath -Parent
    If (-not (Test-Path -LiteralPath $destParent)) {
        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
    }
    Try {
        If (Test-Path -LiteralPath $sourcePath -PathType Container) {
            If (Test-Path -LiteralPath $destPath) { Remove-Item -LiteralPath $destPath -Recurse -Force }
            Copy-Item -LiteralPath $sourcePath -Destination $destPath -Recurse -Force -ErrorAction Stop
        } Else {
            Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force -ErrorAction Stop
        }
    } Catch {
        Write-Log "FAIL: could not copy $sourcePath to $destPath - $($_.Exception.Message)"
        Return $false
    }
    If (-not (Test-Path -LiteralPath $destPath)) {
        Write-Log "FAIL: $destPath not found after copy from $sourcePath"
        Return $false
    }
    If (-not $KeepSource) {
        Remove-Item -LiteralPath $sourcePath -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log "Placed $destPath"
    Return $true
}

# Mount a VHD and return its usable volume as a drive string ("F:"), or $null.
Function Mount-SoeVhd($vhdPath)
{
    $mountedVHD = Mount-VHD -Path $vhdPath -PassThru
    Start-Sleep -Seconds 3
    $volume = Get-Disk | Where-Object { $_.Number -eq $mountedVHD.DiskNumber } | Get-Partition | Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -ne $null } | Select-Object -First 1
    If (-not $volume) {
        Write-Log "FAIL: no usable volume found in $vhdPath"
        Dismount-VHD -Path $vhdPath
        Return $null
    }
    Return "$($volume.DriveLetter):"
}

Function Place-Package
{
    Write-Log "Placing the VM SOE package from $pkgSource into the SOE VHDs..."

    # Everything script 7 pushed must be there before we touch the VHDs.
    If (-not (Test-Path -LiteralPath $pkgSource)) {
        Write-Log "FAIL: $pkgSource not found - run Lab SOE script '7 - GSC02 Build Script' first."
        Return $false
    }
    $required = @('SOE_Reboot_eOPS.exe', 'jre-7u1-windows-x64.exe', 'Maxtel.ps1', 'Maxtel', 'generatekvs.exe', 'NZ_VM_SOE_Clean_Up.ps1')
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $pkgSource $_)) })
    If ($missing.Count -gt 0) {
        $missing | ForEach-Object { Write-Log "FAIL: $pkgSource\$_ is missing - re-run Lab SOE script '7 - GSC02 Build Script'." }
        Return $false
    }

    # OS disk (the VM's C:)
    $ok = $true
    $osDrive = Mount-SoeVhd $vhdPath1
    If (-not $osDrive) { Return $false }
    Try {
        If (-not (Test-Path "$osDrive\Windows")) {
            Write-Log "FAIL: $vhdPath1 mounted as $osDrive but there is no \Windows on it - wrong disk?"
            $ok = $false
        }
        If ($ok) { $ok = Place-Item "$pkgSource\generatekvs.exe" "$osDrive\Helpdesk\tools\generatekvs.exe" -KeepSource }
        # Spare copy: staging can put the old generatekvs back - NZ_VM_SOE_Clean_Up.ps1
        # restores the current build from here.
        If ($ok) { $ok = Place-Item "$pkgSource\generatekvs.exe" "$osDrive\Source\Scripts\generatekvs.exe" }
        If ($ok) { $ok = Place-Item "$pkgSource\NZ_VM_SOE_Clean_Up.ps1" "$osDrive\Source\Scripts\NZ_VM_SOE_Clean_Up.ps1" }
        If ($ok -and (Test-Path -LiteralPath "$pkgSource\Printer Drivers")) {
            $ok = Place-Item "$pkgSource\Printer Drivers" "$osDrive\Temp\Printer Drivers"
        }
    } Finally {
        Dismount-VHD -Path $vhdPath1
        Start-Sleep -Seconds 3
    }
    If (-not $ok) { Return $false }

    # Data disk (the VM's E: - Ghost Images\Waystation)
    $dataDrive = Mount-SoeVhd $vhdPath2
    If (-not $dataDrive) { Return $false }
    Try {
        $way = "$dataDrive\Ghost Images\Waystation"
        $ok = Place-Item "$pkgSource\SOE_Reboot_eOPS.exe" "$way\Tools\SOE_Reboot_eOPS.exe"
        If ($ok) { $ok = Place-Item "$pkgSource\Maxtel.ps1" "$way\AppStore\Maxtel.ps1" }
        If ($ok) { $ok = Place-Item "$pkgSource\Maxtel" "$way\AppStore\Maxtel" }
        If ($ok) { $ok = Place-Item "$pkgSource\jre-7u1-windows-x64.exe" "$way\AppStore\PLS\jre-7u1-windows-x64.exe" }
    } Finally {
        Dismount-VHD -Path $vhdPath2
        Start-Sleep -Seconds 3
    }
    If (-not $ok) { Return $false }

    # The moves empty C:\certeq - tidy the folder away once nothing is left in it.
    If (-not (Get-ChildItem -LiteralPath $pkgSource -Recurse -File -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $pkgSource -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Log 'VM SOE package placed - all destinations confirmed.'
    Return $true
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

        #Place the VM SOE package into the VHDs before the first boot (v2.00)
        If (-not (Place-Package)) {
            Write-Log 'VM SOE package placement failed - the VM was NOT started. Fix the issue above and re-run this script.'
            Exit 1
        }

        Write-Log 'Waiting for VM to start. This will also take a few minutes, grab a coffee...'
        Start-VM -Name $VMName
        Wait-VM -Name $VMName -For Heartbeat -Delay 120
    }
Else
    {
        Write-Log 'VM already exists'
        # v2.00: re-run after a failed placement - place the package now, but only
        # while the VM is off (a mounted VHD cannot also be attached to a running VM).
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
        If ($vm -and (Test-Path -LiteralPath $pkgSource)) {
            If ($vm.State -eq 'Off') {
                If (Place-Package) {
                    Write-Log 'Waiting for VM to start. This will also take a few minutes, grab a coffee...'
                    Start-VM -Name $VMName
                    Wait-VM -Name $VMName -For Heartbeat -Delay 120
                } Else {
                    Write-Log 'VM SOE package placement failed - the VM was NOT started. Fix the issue above and re-run this script.'
                    Exit 1
                }
            } Else {
                Write-Log "A $pkgSource package is waiting but the VM is running - files were NOT placed. Shut the VM down and re-run this script."
                Exit 1
            }
        }
    }
