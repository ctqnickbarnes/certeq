##############################################################################
#
# Script to send the config to the Store Controller VHDs & apply the 2nd nic
# Some of the recent change History
# v1.00	23/04/2022	Initial build (Ben Coulson - BBC Vision)
# v1.01 20/09/2022  Modified script to update virtual SOE with trunked network adapter
# v1.02 17/12/2024  Modified script to use 2022 Server
#
##############################################################################

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
    }
