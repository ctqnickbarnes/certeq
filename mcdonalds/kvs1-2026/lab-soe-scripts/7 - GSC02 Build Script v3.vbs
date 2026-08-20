'============================================================
'
': Script: 7 - GSC02 Build Script
': Version: 3
': Published: 20-Aug-26
': Author: Daniel Phillips (Certeq)
': Notes: Remove the GSC02 NIC Flipper
':        v3: push the VM SOE package (C:\Certeq\VM_SOE_Files) to RHS02 c$\certeq (Nick Barnes)
'
'============================================================

Option Explicit

Dim w, ReadTextFile
Dim StoreID, ipAddress, ipGateway, ipGSC01, ipRHS01, ipRHS02
Dim Textline, f, successConn
Dim response, basePath, storePath

Dim oFSO : Set oFSO = CreateObject("Scripting.FileSystemObject")
Dim sScriptDir : sScriptDir = oFSO.GetParentFolderName(WScript.ScriptFullName)
Set oFSO = CreateObject("Scripting.FileSystemObject")
Set w = CreateObject("Wscript.Shell")

'================================
' Obtain RHS02 IP
'================================

Dim objWMIService, colAdapters, objAdapter
Dim currentIP, ipParts

ipGSC01 = ""
ipRHS01 = ""
ipRHS02 = ""
ipAddress = ""

Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")

Set colAdapters = objWMIService.ExecQuery( _
    "SELECT * FROM Win32_NetworkAdapterConfiguration " & _
    "WHERE IPEnabled = True AND Description LIKE '%Ethernet%'" _
)

For Each objAdapter In colAdapters
    If Not IsNull(objAdapter.IPAddress) Then
        currentIP = objAdapter.IPAddress(0)
        ipAddress = currentIP

        ipParts = Split(currentIP, ".")

        If UBound(ipParts) = 3 Then
            ipGSC01 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".124"
            ipRHS01 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".94"
			ipRHS02 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".93"
            Exit For
        End If
    End If
Next

Dim manualIP

If ipRHS02 = "" Then
    manualIP = InputBox( _
        "Unable to determine the RHS02 IP address from the current network adapter." & vbNewLine & vbNewLine & _
        "Please enter the RHS02 IP address manually." & vbNewLine & _
        "Example: 10.56.200.93", _
        "RHS02 IP Error" _
    )

    If Trim(manualIP) = "" Then
        MsgBox "No IP address entered. Script cancelled.", vbExclamation, "Cancelled"
        WScript.Quit
    End If

    ipParts = Split(Trim(manualIP), ".")

    If UBound(ipParts) <> 3 Then
        MsgBox "The IP address entered is invalid." & vbNewLine & vbNewLine & _
               "Expected format: 10.56.200.93", _
               vbCritical, "Invalid IP Address"
        WScript.Quit
    End If

    ipGSC01 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".124"
    ipRHS01 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".94"
    ipRHS02 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".93"
End If

'================================
' RHS02 Connection Test
'================================

Dim RHS02filetestResult
Dim uncPath
uncPath = "\\" & ipRHS02 & "\l$"

	w.Run "cmd.exe /C net use l: " & Chr(34) & uncPath & Chr(34) & _
         " /user:" & Chr(34) & "administrator" & Chr(34) & _
         " " & Chr(34) & "Jvr963*14" & Chr(34), 1, True

If oFSO.FolderExists(uncPath) Then
    RHS02filetestResult = "Connected"
    w.Run "explorer.exe " & Chr(34) & uncPath & Chr(34), 1, False
Else
    RHS02filetestResult = "FAILED"
End If


'================================
' VM SOE Package - Preflight
'================================

Dim pkgSource, pkgDest
pkgSource = "C:\Certeq\VM_SOE_Files\"
pkgDest = "\\" & ipRHS02 & "\c$\certeq\"

Dim requiredItems, missingItems, pkgItem
requiredItems = Array( _
    "SOE_Reboot_eOPS.exe", _
    "jre-7u1-windows-x64.exe", _
    "Maxtel.ps1", _
    "Maxtel", _
    "generatekvs.exe", _
    "NZ_VM_SOE_Clean_Up.ps1" _
)

missingItems = ""

For Each pkgItem In requiredItems
    If Not (oFSO.FileExists(pkgSource & pkgItem) Or oFSO.FolderExists(pkgSource & pkgItem)) Then
        missingItems = missingItems & vbTab & pkgItem & vbNewLine
    End If
Next

If missingItems <> "" Then
    MsgBox "VM SOE package incomplete under " & pkgSource & vbNewLine & vbNewLine & _
           "Missing:" & vbNewLine & missingItems & vbNewLine & _
           "Nothing was copied. Script cancelled.", vbCritical, "GSC02 Build Script - v3"
    WScript.Quit
End If

'================================
' Copy Seasame Build Files to Backup
'================================
Dim results
Set results = CreateObject("Scripting.Dictionary")
results.Add "AUSetup_GSC", CopyFile("E:\Ghost Images\Waystation\AppStore\AUSetup_GSC.ps1","l:\Configuration\Provisioning\Appstore\AUSetup_GSC.ps1")

'================================
' VM SOE Package - Copy to RHS02
'================================

CreateFolderIfMissing "\\" & ipRHS02 & "\c$\certeq"

results.Add "SOE_Reboot_eOPS.exe", CopyFile(pkgSource & "SOE_Reboot_eOPS.exe", pkgDest & "SOE_Reboot_eOPS.exe")
StopIfFailed "SOE_Reboot_eOPS.exe", results("SOE_Reboot_eOPS.exe")

results.Add "jre-7u1-windows-x64.exe", CopyFile(pkgSource & "jre-7u1-windows-x64.exe", pkgDest & "jre-7u1-windows-x64.exe")
StopIfFailed "jre-7u1-windows-x64.exe", results("jre-7u1-windows-x64.exe")

results.Add "Maxtel.ps1", CopyFile(pkgSource & "Maxtel.ps1", pkgDest & "Maxtel.ps1")
StopIfFailed "Maxtel.ps1", results("Maxtel.ps1")

results.Add "Maxtel", CopyFolder(pkgSource & "Maxtel", pkgDest & "Maxtel")
StopIfFailed "Maxtel folder", results("Maxtel")

results.Add "generatekvs.exe", CopyFile(pkgSource & "generatekvs.exe", pkgDest & "generatekvs.exe")
StopIfFailed "generatekvs.exe", results("generatekvs.exe")

results.Add "NZ_VM_SOE_Clean_Up.ps1", CopyFile(pkgSource & "NZ_VM_SOE_Clean_Up.ps1", pkgDest & "NZ_VM_SOE_Clean_Up.ps1")
StopIfFailed "NZ_VM_SOE_Clean_Up.ps1", results("NZ_VM_SOE_Clean_Up.ps1")

If oFSO.FolderExists(pkgSource & "Printer Drivers") Then
    results.Add "Printer Drivers", CopyFolder(pkgSource & "Printer Drivers", pkgDest & "Printer Drivers")
    StopIfFailed "Printer Drivers folder", results("Printer Drivers")
Else
    results.Add "Printer Drivers", "Not found - skipped"
End If

'========================
' Confirmation Message
'========================

Dim msg
msg = "RHS02 Connection (l:):" & vbTab & vbTab & RHS02filetestResult & vbNewLine & vbNewLine & _
      "AUSetup_GSC.ps1 Replacement:" & vbTab & results("AUSetup_GSC") & vbNewLine & vbNewLine & _
      "VM SOE Package (to " & pkgDest & "):" & vbNewLine & vbNewLine & _
      vbTab & "SOE_Reboot_eOPS.exe:" & vbTab & results("SOE_Reboot_eOPS.exe") & vbNewLine & _
      vbTab & "jre-7u1-windows-x64.exe:" & vbTab & results("jre-7u1-windows-x64.exe") & vbNewLine & _
      vbTab & "Maxtel.ps1:" & vbTab & vbTab & results("Maxtel.ps1") & vbNewLine & _
      vbTab & "Maxtel folder:" & vbTab & vbTab & results("Maxtel") & vbNewLine & _
      vbTab & "generatekvs.exe:" & vbTab & vbTab & results("generatekvs.exe") & vbNewLine & _
      vbTab & "NZ_VM_SOE_Clean_Up.ps1:" & vbTab & results("NZ_VM_SOE_Clean_Up.ps1") & vbNewLine & _
      vbTab & "Printer Drivers:" & vbTab & vbTab & results("Printer Drivers")
MsgBox msg, 1, "GSC02 Build Script - v3"

'========================
' Copy Function
'========================

Function CopyFile(sourcePath, destinationPath)
    On Error Resume Next

    oFSO.CopyFile sourcePath, destinationPath, True

    If Err.Number = 0 Then
        CopyFile = "Success"
    Else
        CopyFile = "Failed: " & Err.Description
        Err.Clear
    End If

    On Error GoTo 0
End Function

'========================
' Copy Folder Function
'========================

Function CopyFolder(sourcePath, destinationPath)
    On Error Resume Next

    oFSO.CopyFolder sourcePath, destinationPath, True

    If Err.Number = 0 Then
        CopyFolder = "Success"
    Else
        CopyFolder = "Failed: " & Err.Description
        Err.Clear
    End If

    On Error GoTo 0
End Function

'========================
' Create Folder Function
'========================

Sub CreateFolderIfMissing(path)
    If Not oFSO.FolderExists(path) Then
        oFSO.CreateFolder path
    End If
End Sub

'========================
' Stop On Failed Copy
'========================

Sub StopIfFailed(itemName, result)
    If Left(result, 6) = "Failed" Then
        MsgBox "Copy failed for: " & itemName & vbNewLine & vbNewLine & _
               result & vbNewLine & vbNewLine & _
               "Remaining items were not copied. Script cancelled.", vbCritical, "GSC02 Build Script - v3"
        WScript.Quit
    End If
End Sub

'========================
' Clean Up
'========================

Set oFSO = Nothing
Set w = Nothing
Set ReadTextFile = Nothing
Set results = Nothing