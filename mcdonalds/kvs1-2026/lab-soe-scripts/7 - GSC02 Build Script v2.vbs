'============================================================
'
': Script: 7 - GSC02 Build Script 
': Version: 2
': Published: 29-Jul-26
': Author: Daniel Phillips (Certeq)
': Notes: Remove the GSC02 NIC Flipper
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
' Copy Seasame Build Files to Backup
'================================
Dim results
Set results = CreateObject("Scripting.Dictionary")
results.Add "AUSetup_GSC", CopyFile("E:\Ghost Images\Waystation\AppStore\AUSetup_GSC.ps1","l:\Configuration\Provisioning\Appstore\AUSetup_GSC.ps1")

'========================
' Confirmation Message
'========================

Dim msg
msg = "AUSetup_GSC.ps1 Replacement:" & vbTab & results("AUSetup_GSC") 
MsgBox msg, 1, "GSC02 Build Script - v2"

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
' Clean Up
'========================

Set oFSO = Nothing
Set w = Nothing
Set ReadTextFile = Nothing
Set results = Nothing