##############################################################################
#
# Script to send the config to the Store Controller VHDs & apply the 2nd nic
# Some of the recent change History
# v1.00	23/04/2022	Initial build (Ben Coulson - BBC Vision)
# v2.00 13/11/2024  Revised for use with Server 2022 VM
# v3.00 23/05/2025  Revised and Tested Ben's approach to mount the VHDX disks to copy data (Felipe Mercado - Brennan)
#
##############################################################################

$GSCName = (Get-ItemProperty -Path HKLM:\SOFTWARE\McDonalds -Name "GSC_Name")."GSC_Name"
$Cores = (Get-CimInstance -ClassName Win32_ComputerSystem).NumberOfLogicalProcessors
$Server_Model = (Get-ItemProperty -Path HKLM:\SOFTWARE\McDonalds -Name "Server_Model")."Server_Model"
$Store_Type = (Get-ItemProperty -Path HKLM:\SOFTWARE\McDonalds -Name "Store_Type")."Store_Type"
$VMName = "Server 2022 GSC"
$vhdPath1 = 'C:\OS\Virtual\GSC_2022\GSC.vhdx'
$vhdPath2 = 'C:\OS\Virtual\GSC_2022\Data.vhdx'
$logfile = 'C:\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\Logs\VM_Config.log'

Function Write-Log($Message)
{
    $Stamp = (Get-Date).toString("dd/MM/yyyy HH:mm:ss")
    $Line = "$Stamp $Message"
    Add-Content $logfile -Value $Line
    Write-Host $Message
}

If ( -not (Test-Path -Path "C:\OS\Virtual\GSC_2022" -PathType Container))
    {
        # Extract VHDs
        Write-Log "Extracting VM HDDs. This may take a few minutes.."
        New-Item -ItemType Directory -Path "C:\OS\Virtual\GSC_2022" -Force
        Start-Sleep -Seconds 2
        Start-Process "C:\Program Files\7-Zip\7z.exe" -Wait -Argumentlist " x C:\Images\Virtual\GSC_2022\GSC.7z -oC:\OS\Virtual\GSC_2022"
        Start-Sleep -Seconds 5

        #Recover build registry key
        Start-Process "C:\windows\system32\Reg" -Wait -Argumentlist "Export HKLM\SOFTWARE\McDonalds C:\Configuration\Provisioning\Appstore\AUSetup_GSC\McD.reg /y"

        #Create VM
        Write-Log 'Creating new Server 2022 GSC, This will take a few minutes, please wait...'
        New-VM -Name $VMName -Generation 2 -SwitchName VLAN1 | Set-VM -AutomaticStartAction Start -AutomaticStartDelay 5
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $True -StartupBytes 8192MB -MinimumBytes 8192MB -MaximumBytes 65536MB
        Set-VMProcessor -VMName $VMName -Count $Cores -Maximum 100
        Add-VMHardDiskDrive -Path $vhdPath1 -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 0
        Add-VMHardDiskDrive -Path $vhdPath2 -VMName $VMName -ControllerType SCSI -ControllerNumber 0 -ControllerLocation 1
        $bootorder = Get-VMFirmware $VMName
        $pxe = $bootorder.BootOrder[0]
        $hdd0 = $bootorder.BootOrder[1]
        $hdd1 = $bootorder.BootOrder[2]
        Set-VMFirmware -VMName $VMName -BootOrder $hdd0,$pxe,$hdd1
        Start-Sleep -Seconds 2
        Set-VMNetworkAdapter "Server 2022 GSC" -VmqWeight 0
        Set-VMNetworkAdapter "Server 2022 GSC" -IPsecOffloadMaximumSecurityAssociation 0
        Set-VMNetworkAdapter "Server 2022 GSC" -NotMonitoredInCluster $True
        Start-Sleep -Seconds 2

        #Mount VHDX for XML profile and AppStore copy
        $mountedVHD = Mount-VHD -Path "C:\OS\Virtual\GSC_2022\GSC.vhdx" -PassThru
        Start-Sleep -Seconds 3
        # Get the usable volume (has a drive letter and file system)
        $volume = Get-Disk | Where-Object { $_.Number -eq $mountedVHD.DiskNumber } | Get-Partition | Get-Volume | Where-Object { $_.DriveLetter -and $_.FileSystem -ne $null } | Select-Object -First 1
        $drive = "$($volume.DriveLetter):"
        Start-Sleep -Seconds 2
        New-Item -Path "$drive\Configuration\Provisioning" -ItemType Directory -Force
        New-Item -Path "$drive\Program Files (x86)\McDonalds\McDonalds Provisioning Tool" -ItemType Directory -Force
        Copy-Item -Path "C:\Configuration\Provisioning\Appstore" -Destination "$drive\Configuration\Provisioning\Appstore" -Recurse -Force
        Copy-Item -Path "C:\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\Profiles\$GSCName.XML" -Destination "$drive\Configuration\Provisioning\Appstore\$GSCName.XML" -Recurse -Force
        Copy-Item -Path "C:\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\Profiles\$GSCName.XML" -Destination "$drive\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\$GSCName.XML" -Recurse -Force
        Copy-Item -Path "C:\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\RecentProfiles_GSC.txt" -Destination "$drive\Program Files (x86)\McDonalds\McDonalds Provisioning Tool\RecentProfiles.txt" -Recurse -Force
        Start-Sleep -Seconds 2
        Dismount-VHD -Path "C:\OS\Virtual\GSC_2022\GSC.vhdx"
        Start-Sleep -Seconds 3

        #Start VM
        Write-Log 'Waiting for VM to start. This will also take a few minutes, grab a coffee...'
        Start-VM -Name $VMName
        Wait-VM -Name $VMName -For Heartbeat
     }
Else
    {
        Write-Log 'VM already exists'
    }