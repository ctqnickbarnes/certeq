'============================================================
'
': Script: 2 - SOE Provisioning Files Back Up
': Version: 11
': Published: 19-Jul-26
': Author: Daniel Phillips (Certeq)
': Notes: Pulls provisioning files from the Waystation
'
'============================================================

Option Explicit

Dim oFSO, w, ReadTextFile
Dim StoreID, ipAddress, ipGateway, ipGSC01, ipRHS01, ipRHS02
Dim Textline, f, successConn
Dim response, basePath, storePath

Set oFSO = CreateObject("Scripting.FileSystemObject")
Set w = CreateObject("Wscript.Shell")

'================================
' Obtain RHS01 IP
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

If ipGSC01 = "" Then
    manualIP = InputBox( _
        "Unable to determine the RHS01 IP address from the current network adapter." & vbNewLine & vbNewLine & _
        "Please enter the RHS01 IP address manually." & vbNewLine & _
        "Example: 10.56.200.94", _
        "RHS01 IP Error" _
    )

    If Trim(manualIP) = "" Then
        MsgBox "No IP address entered. Script cancelled.", vbExclamation, "Cancelled"
        WScript.Quit
    End If

    ipParts = Split(Trim(manualIP), ".")

    If UBound(ipParts) <> 3 Then
        MsgBox "The IP address entered is invalid." & vbNewLine & vbNewLine & _
               "Expected format: 10.56.200.124", _
               vbCritical, "Invalid IP Address"
        WScript.Quit
    End If

    ipGSC01 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".124"
    ipRHS01 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".94"
    ipRHS02 = ipParts(0) & "." & ipParts(1) & "." & ipParts(2) & ".93"
End If

'================================
' Obtain Store ID from GSC01
'================================

Dim nsExec, nsResult, nsLines, nsLine
Dim hostName, hostShort

Set nsExec = w.Exec("cmd.exe /c nslookup " & ipGSC01)
nsResult = nsExec.StdOut.ReadAll

hostName = ""
StoreID = ""

nsLines = Split(nsResult, vbCrLf)

For Each nsLine In nsLines
    If InStr(LCase(nsLine), "name:") > 0 Then
        hostName = Trim(Split(nsLine, ":")(1))
        Exit For
    End If
Next

If hostName <> "" Then
    ' Example: NZ00449GSC01.APR.NA.MCDCORP
    hostShort = UCase(Split(hostName, ".")(0))  ' Returns NZ00449GSC01
    StoreID = Replace(hostShort, "NZ", "")      ' Returns 00449GSC01
    StoreID = Replace(StoreID, "GSC01", "")     ' Returns 00449
    StoreID = Replace(StoreID, "WAY01", "")     ' Returns 00449
Else
    StoreID = InputBox( _
        "Unable to determine Store ID from nslookup." & vbNewLine & vbNewLine & _
        "GSC01 IP: " & ipGSC01 & vbNewLine & vbNewLine & _
        "Please enter the Store Number manually.", _
        "Store Number" _
    )

    If StoreID = "" Then
        MsgBox "No store number entered. Script cancelled.", vbExclamation, "Cancelled"
        WScript.Quit
    End If
End If

If StoreID = "" Then
    MsgBox "Store ID could not be determined. Script cancelled.", vbCritical, "Store ID Error"
    WScript.Quit
End If

'================================
' Create Local Folders
'================================

basePath = "C:\Certeq\site_data\"
storePath = basePath & StoreID & "\"

CreateFolderIfMissing "C:\Certeq"
CreateFolderIfMissing basePath
CreateFolderIfMissing "C:\Certeq\site_data\current_site"
CreateFolderIfMissing storePath
CreateFolderIfMissing storePath & "RBT"
CreateFolderIfMissing storePath & "RFM"

Dim results
Set results = CreateObject("Scripting.Dictionary")

'================================
' Copy Seasame Build Files to Backup
'================================

results.Add "product.specification", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\product.specification", "C:\Certeq\site_data\current_site\product.specification")

'================================
' Remove old DTR shortcut
'================================

If oFSO.FileExists("H:\SOE_Backup\Desktop\StartDTBrowser - Shortcut.lnk") Then
    oFSO.DeleteFile "H:\SOE_Backup\Desktop\StartDTBrowser - Shortcut.lnk", True
End If

'================================
' Copy DTR file to SOE Desktop
'================================

results.Add "Xdrive_dtr.exe", CopyFile("C:\Certeq\dtr\SOE_Reboot_eOPS.exe", "\\" & ipRHS02 & "\x$\SOE_Backup\Desktop\SOE_Reboot_eOPS.exe")

'================================
' Copy RBT Files to Backup
'================================

results.Add "Selections.exml", CopyFile("\\" & ipGSC01 & "\c$\certeq\KVS1\selections.exml", storePath & "RBT\selections.exml")
results.Add "Selections.xml", CopyFile("\\" & ipGSC01 & "\c$\certeq\KVS1\selections.xml", storePath & "RBT\selections.xml")

results.Add "GCS01_selections.exml", CopyFile("\\" & ipGSC01 & "\c$\certeq\KVS1\selections.exml", "\\" & ipGSC01 & "\d$\source\NewPOS6.X\RestaurantBuilderTool\selections.exml")
results.Add "GCS01_selections.xml", CopyFile("\\" & ipGSC01 & "\c$\certeq\KVS1\selections.xml", "\\" & ipGSC01 & "\d$\source\NewPOS6.X\RestaurantBuilderTool\selections.xml")

results.Add "Xdrive_selections.exml", CopyFile("\\" & ipGSC01 & "\c$\certeq\KVS1\selections.exml", "\\" & ipRHS01 & "\x$\RTPBackup\RBT\selections.exml")
results.Add "Xdrive_selections.xml", CopyFile("\\" & ipGSC01 & "\c$\certeq\KVS1\selections.xml", "\\" & ipRHS01 & "\x$\RTPBackup\RBT\selections.xml")

'================================
' RTP Back Up Size
'================================

Dim rtpBackupSize
rtpBackupSize = GetFolderSizeGB("\\" & ipRHS01 & "\x$\RTPBackup")

'================================
' Copy RFM Files
'================================

results.Add "regdata.gz", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\bin\regdata.gz", storePath & "RFM\regdata.gz")
results.Add "names-db.xml", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\names-db.xml", storePath & "RFM\names-db.xml")
results.Add "prodoutage.xml", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\prodoutage.xml", storePath & "RFM\prodoutage.xml")
results.Add "product-db.xml", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\product-db.xml", storePath & "RFM\product-db.xml")
results.Add "promotion-db.xml", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\promotion-db.xml", storePath & "RFM\promotion-db.xml")
results.Add "screen.xml", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\screen.xml", storePath & "RFM\screen.xml")
results.Add "Security.data", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\Security.data", storePath & "RFM\Security.data")
results.Add "store-db.xml", CopyFile("\\" & ipGSC01 & "\D$\Newpos61\posdata\store-db.xml", storePath & "RFM\store-db.xml")

'================================
' Confirm Store Details
'================================

Dim xmlDoc
Dim rbtStoreID, rbtStoreName
Dim rbtStoreIDValue, rbtStoreNameValue

rbtStoreIDValue = StoreID
rbtStoreNameValue = ""

Set xmlDoc = CreateObject("Microsoft.XMLDOM")
xmlDoc.Async = False
xmlDoc.Load(storePath & "RBT\selections.xml")

If xmlDoc.ParseError.ErrorCode <> 0 Then
    MsgBox "Cannot locate or read RestaurantBuilderTool selections.xml: " & vbNewLine & vbNewLine & _
           xmlDoc.ParseError.Reason, vbExclamation, "RBT XML Error"
Else
    Set rbtStoreID = xmlDoc.SelectNodes("//Parameter[@name='RestaurantNumber']")
    Set rbtStoreName = xmlDoc.SelectNodes("//Parameter[@name='RestaurantName']")

	If rbtStoreID.Length > 0 Then
		rbtStoreIDValue = rbtStoreID(0).getAttribute("value")

		If Len(rbtStoreIDValue) > 2 Then
			rbtStoreIDValue = Mid(rbtStoreIDValue, 3)
		End If
	End If

    If rbtStoreName.Length > 0 Then
        rbtStoreNameValue = rbtStoreName(0).getAttribute("value")
    End If
End If

'========================
' Confirmation Message
'========================

Dim msg

msg = "Store Details:" & vbNewLine & vbNewLine & _
        vbTab & "Store Number:" & vbTab & vbTab & rbtStoreIDValue & vbNewLine & _
        vbTab & "Store Name:" & vbTab & vbTab & rbtStoreNameValue & vbNewLine & _
        vbTab & "Current IP:" & vbTab & vbTab & ipAddress & vbNewLine & _
        vbTab & "GSC01 IP:" & vbTab & vbTab & ipGSC01 & vbNewLine & vbNewLine & _
        "Local RBT Selections:" & vbNewLine & vbNewLine & _
        vbTab & "selections.exml:" & vbTab & vbTab & results("Selections.exml") & vbNewLine & _
        vbTab & "selections.xml:" & vbTab & vbTab & results("Selections.xml") & vbNewLine & vbNewLine & _
        "GSC01 RBT Selections:" & vbNewLine & vbNewLine & _
        vbTab & "GCS01_selections.exml:" & vbTab &  results("GCS01_selections.exml") & vbNewLine & _
        vbTab & "GCS01_selections.xml:" & vbTab &  results("GCS01_selections.xml") & vbNewLine & vbNewLine & _       
        "RHS01 RTP Backup Selections:" & vbNewLine & vbNewLine & _
        vbTab & "X drive_selections.exml:" & vbTab &  results("Xdrive_selections.exml") & vbNewLine & _
        vbTab & "X drive_selections.xml:" & vbTab &  results("Xdrive_selections.xml") & vbNewLine & vbNewLine & _   
        vbTab & "RTP Backup Size:" & vbTab & vbTab & "= " & rtpBackupSize & vbNewLine & _
        vbTab & "Expected Size:" & vbTab & vbTab & "> 15.0 GB" & vbNewLine & vbNewLine & _
		"RHS02 DTR Files:" & vbNewLine & vbNewLine & _
        vbTab &  "Xdrive_dtr.exe:" & vbTab &  vbTab & results("Xdrive_dtr.exe") & vbNewLine & vbNewLine & _
		"RFM Package:" & vbNewLine & vbNewLine & _
        vbTab & "names-db.xml" & vbTab & vbTab & results("names-db.xml") & vbNewLine & _
        vbTab & "product-db.xml" & vbTab & vbTab & results("product-db.xml") & vbNewLine & _
        vbTab & "promotion-db.xml" & vbTab & vbTab & results("promotion-db.xml") & vbNewLine & _
        vbTab & "screen.xml" & vbTab & vbTab & results("screen.xml") & vbNewLine & _
        vbTab & "store-db.xml" & vbTab & vbTab & results("store-db.xml") & vbNewLine & _
        vbTab & "prodoutage.xml" & vbTab & vbTab & results("prodoutage.xml") & vbNewLine & vbNewLine & _
		"License & Users:" & vbNewLine & vbNewLine & _
        vbTab & "regdata.gz" & vbTab & vbTab & results("regdata.gz") & vbNewLine & _
        vbTab & "Security.data" & vbTab & vbTab & results("Security.data") & vbNewLine & vbNewLine & _
        "Sesame:" & vbNewLine & vbNewLine & _
        vbTab & "product.specification" & vbTab & results("product.specification") & vbNewLine 


MsgBox msg, 1, "Provisioning Files Download - v11"

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
' Folder Size Function
'========================

Function GetFolderSizeGB(folderPath)
    Dim folderSizeBytes

    On Error Resume Next
    folderSizeBytes = oFSO.GetFolder(folderPath).Size

    If Err.Number = 0 Then
        GetFolderSizeGB = FormatNumber(folderSizeBytes / 1073741824, 2) & " GB"
    Else
        GetFolderSizeGB = "Failed: " & Err.Description
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
' Clean Up
'========================

Set xmlDoc = Nothing
Set oFSO = Nothing
Set w = Nothing
Set ReadTextFile = Nothing
Set results = Nothing