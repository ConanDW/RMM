<#
.SYNOPSIS 
    Provide modern Powershell conversion of Sophos Uninstall BAT Script : https://support.sophos.com/support/s/article/KB-000035419?language=en_US

.DESCRIPTION
    Script will attempt to stop all known Sophos services via an easy to update array; $colServices, located at the top of the script
    Script will attempt currently known uninstaller EXE utilities with "--quiet" switch (uninstallcli.exe, uninstallgui.exe, and SophosUninstall.exe)
    Script will automatically export found Sophos Component Uninstall Strings from both 32bit and 64bit Registry Hives and then execute each
    Script will cleanup WMI 'SecurityCenter2' Namespace AntiVirusProduct and FirewallProduct instances
    Script will attempt to detect, log, and handle errors throughout each step in the uninstall process
    Script will output logfile to C:\IT\Log\Sophos_Uninstall
 
.NOTES
    Version        : 0.1.1 (27 January 2023)
    Creation Date  : 25 January 2023
    Purpose/Change : Provide modern Powershell conversion of Sophos Uninstall BAT Script : https://support.sophos.com/support/s/article/KB-000035419?language=en_US
    File Name      : Sophos_Uninstall_0.1.1.ps1 
    Author         : Christopher Bledsoe - cbledsoe@ipmcomputers.com - Khristos#8436
    Requires       : PowerShell Version 2.0+ installed
    Thanks         : Brian Ellis - Third Party Verification and Addition / Change Suggestions

.CHANGELOG
    0.1.0 Initial Release
    0.1.1 Added basic error handling and logging
          Added service and file path existence checks
          Added checks to cleanup some remnant HitmanPro files and folders
          Added OS Type detection for handling WMI 'SecurityCenter2' Namespace instances
          Added 'chkAU' automated update function

.TODO

#>

#region ----- DECLARATIONS ----
  #VERSION FOR SCRIPT UPDATE
  $strSCR             = "Sophos_Uninstall"
  $strVER             = [version]"0.1.0"
  $strREPO            = "RMM"
  $strBRCH            = "dev"
  $strDIR             = "Datto/AVProducts"
  $script:diag        = $null
  $script:bitarch     = $null
  $script:producttype = $null
  $script:blnWARN     = $false
  $script:blnBREAK    = $false
  $strLineSeparator   = "---------"
  $logPath            = "C:\IT\Log\Sophos_Uninstall"
  $colServices        = @(
    "SAVService",
    "Sophos AutoUpdate Service",
    "Sophos Device Encryption Service",
    "Sophos Endpoint Defense Service",
    "Sophos File Scanner Service",
    "Sophos Health Service",
    "Sophos Live Query",
    "Sophos Managed Threat Response",
    "Sophos MCS Agent",
    "Sophos MCS Client",
    "SntpService",
    "Sophos System Protection Service"
  )
#endregion ----- DECLARATIONS ----

#region ----- FUNCTIONS ----
  function write-DRMMDiag ($messages) {
    write-host "<-Start Diagnostic->"
    foreach ($message in $messages) {$message}
    write-host "<-End Diagnostic->"
  } ## write-DRMMDiag
  
  function write-DRMMAlert ($message) {
    write-host "<-Start Result->"
    write-host "Alert=$($message)"
    write-host "<-End Result->"
  } ## write-DRMMAlert

  function Get-OSArch {                                                                             #Determine Bit Architecture & OS Type
    #OS Bit Architecture
    $osarch = (get-wmiobject win32_operatingsystem).osarchitecture
    if ($osarch -like '*64*') {
      $script:bitarch = "bit64"
    } elseif ($osarch -like '*32*') {
      $script:bitarch = "bit32"
    }
    #OS Type & Version
    $script:computername = $env:computername
    $script:OSCaption = (Get-WmiObject Win32_OperatingSystem).Caption
    $script:OSVersion = (Get-WmiObject Win32_OperatingSystem).Version
    $osproduct = (Get-WmiObject -class Win32_OperatingSystem).Producttype
    Switch ($osproduct) {
      "1" {$script:producttype = "Workstation"}
      "2" {$script:producttype = "DC"}
      "3" {$script:producttype = "Server"}
    }
  } ## Get-OSArch

  function Get-ProcessOutput {
    Param (
      [Parameter(Mandatory=$true)]$FileName,
      $Args
    )
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.WindowStyle = "Hidden"
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $FileName
    if($Args) {$process.StartInfo.Arguments = $Args}
    $out = $process.Start()

    $StandardError = $process.StandardError.ReadToEnd()
    $StandardOutput = $process.StandardOutput.ReadToEnd()

    $output = New-Object PSObject
    $output | Add-Member -type NoteProperty -name StandardOutput -Value $StandardOutput
    $output | Add-Member -type NoteProperty -name StandardError -Value $StandardError
    return $output
  } ## Get-ProcessOutput

  function logERR($intSTG, $strErr) {
    $script:blnWARN = $true
    #CUSTOM ERROR CODES
    switch ($intSTG) {
      1 {                                                                             #'ERRRET'=1 - ERROR DELETING FILE / FOLDER
        $script:diag += "$($strLineSeparator)`r`n$((Get-Date).ToString('dd-MM-yyyy hh:mm:ss'))`t - Sophos_Uninstall - ERROR DELETING FILE / FOLDER`r`n$($strErr)`r`n$($strLineSeparator)`r`n`r`n"
        write-host "$($strLineSeparator)`r`n$((Get-Date).ToString('dd-MM-yyyy hh:mm:ss'))`t - Sophos_Uninstall - ERROR DELETING FILE / FOLDER`r`n$($strErr)`r`n$($strLineSeparator)`r`n"
      }
      2 {                                                                             #'ERRRET'=2 - NOT ENOUGH ARGUMENTS, END SCRIPT
        $script:diag += "$($strLineSeparator)`r`n$((Get-Date).ToString('dd-MM-yyyy hh:mm:ss'))`t - Sophos_Uninstall - NO ARGUMENTS PASSED, END SCRIPT`r`n$($strErr)`r`n$($strLineSeparator)`r`n`r`n"
        write-host "$($strLineSeparator)`r`n$((Get-Date).ToString('dd-MM-yyyy hh:mm:ss'))`t - Sophos_Uninstall - NO ARGUMENTS PASSED, END SCRIPT`r`n$($strErr)`r`n$($strLineSeparator)`r`n"
      }
      default {                                                                       #'ERRRET'=3+
        write-host "$($strLineSeparator)`r`n$((get-date).ToString('dd-MM-yyyy hh:mm:ss'))`t - Sophos_Uninstall - $($strErr)`r`n$($strLineSeparator)`r`n"
        $script:diag += "$($strLineSeparator)`r`n$((get-date).ToString('dd-MM-yyyy hh:mm:ss'))`t - Sophos_Uninstall - $($strErr)`r`n$($strLineSeparator)`r`n`r`n"
      }
    }
  }

  function chkAU {
    param (
      $ver, $repo, $brch, $dir, $scr
    )
    $blnXML = $true
    $xmldiag = $null
    #RETRIEVE VERSION XML FROM GITHUB
    if (($null -eq $strDIR) -or ($strDIR -eq "")) {
      $xmldiag += "Loading : '$($strREPO)/$($strBRCH)' Version XML`r`n"
      write-host "Loading : '$($strREPO)/$($strBRCH)' Version XML" -foregroundcolor yellow
      $srcVER = "https://raw.githubusercontent.com/CW-Khristos/$($strREPO)/$($strBRCH)/version.xml"
    } elseif (($null -ne $strDIR) -and ($strDIR -ne "")) {
      $xmldiag += "Loading : '$($strREPO)/$($strBRCH)/$($strDIR)' Version XML`r`n"
      write-host "Loading : '$($strREPO)/$($strBRCH)/$($strDIR)' Version XML" -foregroundcolor yellow
      $srcVER = "https://raw.githubusercontent.com/CW-Khristos/$($strREPO)/$($strBRCH)/$($strDIR)/version.xml"
    }
    try {
      $verXML = New-Object System.Xml.XmlDocument
      $verXML.Load($srcVER)
    } catch {
      $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
      $xmldiag += "XML.Load() - Could not open $($srcVER)`r`n$($err)`r`n"
      write-host "XML.Load() - Could not open $($srcVER)`r`n$($err)" -foregroundcolor red
      try {
        $web = new-object system.net.webclient
        [xml]$verXML = $web.DownloadString($srcVER)
      } catch {
        $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
        $xmldiag += "Web.DownloadString() - Could not download $($srcVER)`r`n$($err)`r`n"
        write-host "Web.DownloadString() - Could not download $($srcVER)`r`n$($err)" -foregroundcolor red
        try {
          start-bitstransfer -erroraction stop -source $srcVER -destination "C:\IT\Scripts\version.xml"
          [xml]$verXML = "C:\IT\Scripts\version.xml"
        } catch {
          $blnXML = $false
          $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
          $xmldiag += "BITS.Transfer() - Could not download $($srcVER)`r`n$($err)`r`n"
          write-host "BITS.Transfer() - Could not download $($srcVER)`r`n$($err)`r`n" -foregroundcolor red
        }
      }
    }
    #READ VERSION XML DATA INTO NESTED HASHTABLE FOR LATER USE
    try {
      if (-not $blnXML) {
        write-host $blnXML
      } elseif ($blnXML) {
        foreach ($objSCR in $verXML.SCRIPTS.ChildNodes) {
          if ($objSCR.name -match $strSCR) {
            #CHECK LATEST VERSION
            $xmldiag += "`r`n`t$($strLineSeparator)`r`n`t - CHKAU : $($strVER) : GitHub - $($strBRCH) : $($objSCR.innertext)`r`n"
            write-host "`t$($strLineSeparator)`r`n`t - CHKAU : $($strVER) : GitHub - $($strBRCH) : $($objSCR.innertext)"
            if ([version]$objSCR.innertext -gt $strVER) {
              $xmldiag += "`t`t - UPDATING : $($objSCR.name) : $($objSCR.innertext)`r`n"
              write-host "`t`t - UPDATING : $($objSCR.name) : $($objSCR.innertext)`r`n"
              #REMOVE PREVIOUS COPIES OF SCRIPT
              if (test-path -path "C:\IT\Scripts\$($strSCR)_$($strVER).ps1") {
                remove-item -path "C:\IT\Scripts\$($strSCR)_$($strVER).ps1" -force -erroraction stop
              }
              #DOWNLOAD LATEST VERSION OF ORIGINAL SCRIPT
              if (($null -eq $strDIR) -or ($strDIR -eq "")) {
                $strURL = "https://raw.githubusercontent.com/CW-Khristos/$($strREPO)/$($strBRCH)/$($strSCR)_$($objSCR.innertext).ps1"
              } elseif (($null -ne $strDIR) -and ($strDIR -ne "")) {
                $strURL = "https://raw.githubusercontent.com/CW-Khristos/$($strREPO)/$($strBRCH)/$($strDIR)/$($strSCR)_$($objSCR.innertext).ps1"
              }
              Invoke-WebRequest "$($strURL)" | Select-Object -ExpandProperty Content | Out-File "C:\IT\Scripts\$($strSCR)_$($objSCR.innertext).ps1"
              #RE-EXECUTE LATEST VERSION OF SCRIPT
              $xmldiag += "`t`t - RE-EXECUTING : $($objSCR.name) : $($objSCR.innertext)`r`n`r`n"
              write-host "`t`t - RE-EXECUTING : $($objSCR.name) : $($objSCR.innertext)`r`n"
              $output = C:\Windows\System32\cmd.exe "/C powershell -executionpolicy bypass -file `"C:\IT\Scripts\$($strSCR)_$($objSCR.innertext).ps1`" -blnLOG `$$($blnLOG)"
              foreach ($line in $output) {$stdout += "$($line)`r`n"}
              $xmldiag += "`t`t - StdOut : $($stdout)`r`n`t`t$($strLineSeparator)`r`n"
              write-host "`t`t - StdOut : $($stdout)`r`n`t`t$($strLineSeparator)"
              $xmldiag += "`t`t - CHKAU COMPLETED : $($objSCR.name) : $($objSCR.innertext)`r`n`t$($strLineSeparator)`r`n"
              write-host "`t`t - CHKAU COMPLETED : $($objSCR.name) : $($objSCR.innertext)`r`n`t$($strLineSeparator)"
              $script:blnBREAK = $true
            } elseif ([version]$objSCR.innertext -le $strVER) {
              $xmldiag += "`t`t - NO UPDATE : $($objSCR.name) : $($objSCR.innertext)`r`n`t$($strLineSeparator)`r`n"
              write-host "`t`t - NO UPDATE : $($objSCR.name) : $($objSCR.innertext)`r`n`t$($strLineSeparator)"
              $script:blnBREAK = $false
            }
            break
          }
        }
      }
      $script:diag += "$($xmldiag)"
      $xmldiag = $null
    } catch {
      $script:blnBREAK = $false
      $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
      $xmldiag += "CClutter : Error reading Version XML : $($srcVER)`r`n$($err)`r`n"
      write-host "CClutter : Error reading Version XML : $($srcVER)`r`n$($err)"
      $script:diag += "$($xmldiag)"
      $xmldiag = $null
    }
  } ## chkAU

  function StopService($service) {
    try {
      write-host "STOPPING '$($service)'"
      $script:diag += "STOPPING '$($service)'`r`n"
      $result = stop-service -name "$($service)" -force -erroraction stop
      write-host "$($result)"
      $script:diag += "$($result)`r`n"
    } catch {
      $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
      logERR 3 $err
    }
  }

  function RegUninstall($regitem) {
    write-host "$($regitem.displayname):"
    $script:diag += "$($regitem.displayname):`r`n"
    if (($null -ne $regitem.UninstallString) -and ($regitem.UninstallString -ne "")) {
      write-host "`t - UNINSTALLING $($regitem.displayname):"
      $script:diag += "`t - UNINSTALLING $($regitem.displayname):`r`n"
      if ($regitem.UninstallString -like "*msiexec*") {
        try {
          $regitem.UninstallString = $regitem.UninstallString.split(" ")[1]
          write-host "`t`t - USING MSIEXEC : $($regitem.UninstallString):"
          $script:diag += "`t`t - USING MSIEXEC : $($regitem.UninstallString):`r`n"
          $output = Get-ProcessOutput -FileName "msiexec.exe" -Args "$($regitem.UninstallString) /quiet /qn /norestart REBOOT=ReallySuppress"
        } catch {
          logERR 3 $err
        }
      } elseif ($regitem.UninstallString -notlike "*msiexec*") {
        try {
          write-host "`t`t - USING EXE : $($regitem.UninstallString):"
          $script:diag += "`t`t - USING EXE : $($regitem.UninstallString):`r`n"
          $output = Get-ProcessOutput -FileName "$($regitem.UninstallString)" -Args "/quiet"
        } catch {
          logERR 3 $err
        }
      }
      #PARSE SMARTCTL OUTPUT LINE BY LINE
      $lines = $output.StandardOutput.split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
      $lines
    } else {
      write-host "$($regitem.displayname) : No Uninstall String`r`n"
      $script:diag += "$($regitem.displayname) : No Uninstall String`r`n`r`n"
    }
  }

  function StopClock {
    #Stop script execution time calculation
    $script:sw.Stop()
    $Days = $sw.Elapsed.Days
    $Hours = $sw.Elapsed.Hours
    $Minutes = $sw.Elapsed.Minutes
    $Seconds = $sw.Elapsed.Seconds
    $Milliseconds = $sw.Elapsed.Milliseconds
    $ScriptStopTime = (Get-Date).ToString('dd-MM-yyyy hh:mm:ss')
    $total = ((((($Hours * 60) + $Minutes) * 60) + $Seconds) * 1000) + $Milliseconds
    $mill = [string]($total / 1000)
    $mill = $mill.split(".")[1]
    $mill = $mill.SubString(0,[math]::min(3,$mill.length))
    $script:diag += "`r`nTotal Execution Time - $($Minutes) Minutes : $($Seconds) Seconds : $($Milliseconds) Milliseconds`r`n"
    write-host "`r`nTotal Execution Time - $($Minutes) Minutes : $($Seconds) Seconds : $($Milliseconds) Milliseconds`r`n"
  }
#endregion ----- FUNCTIONS ----

#------------
#BEGIN SCRIPT
clear-host
#Start script execution time calculation
$ScrptStartTime = (Get-Date).ToString('dd-MM-yyyy hh:mm:ss')
$script:sw = [Diagnostics.Stopwatch]::StartNew()
#CHECK 'PERSISTENT' FOLDERS
if (-not (test-path -path "C:\temp")) {
  new-item -path "C:\temp" -itemtype directory
}
if (-not (test-path -path "C:\IT")) {
  new-item -path "C:\IT" -itemtype directory
}
if (-not (test-path -path "C:\IT\Log")) {
  new-item -path "C:\IT\Log" -itemtype directory
}
if (-not (test-path -path "C:\IT\Scripts")) {
  new-item -path "C:\IT\Scripts" -itemtype directory
}
#REMOVE PREVIOUS LOGFILE
remove-item -path "$($logPath)" -force -erroraction silentlycontinue
#CHECK FOR UPDATE
chkAU $strVER $strREPO $strBRCH $strDIR $strSCR
if (-not $script:blnBREAK) {
  #STOP SERVICES
  write-host "$($strLineSeparator)`r`nSTOPPING SOPHOS SERVICES`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nSTOPPING SOPHOS SERVICES`r`n$($strLineSeparator)`r`n"
  foreach ($service in $colServices) {StopService $service}
  write-host "$($strLineSeparator)`r`nCOMPLETED STOPPING SOPHOS SERVICES`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nCOMPLETED STOPPING SOPHOS SERVICES`r`n$($strLineSeparator)`r`n"
  #PROCESS UNINSTALLS
  write-host "$($strLineSeparator)`r`nPROCESSING SOPHOS EXE UNINSTALLS`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nPROCESSING SOPHOS EXE UNINSTALLS`r`n$($strLineSeparator)`r`n"
  try {
    if (test-path -path "C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe") {
      write-host "$($strLineSeparator)`r`nTRYING 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe'"
      $script:diag += "$($strLineSeparator)`r`nTRYING 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe'`r`n"
      $output = Get-ProcessOutput -FileName "C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe" -Args "--quiet"
      #PARSE OUTPUT LINE BY LINE
      $lines = $output.StandardOutput.split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
      $lines
    } else {
      write-host "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe'"
      $script:diag += "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallcli.exe'`r`n"
    }
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    logERR 3 $err
  }
  try {
    if (test-path -path "C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe") {
      write-host "$($strLineSeparator)`r`nTRYING 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe'"
      $script:diag += "$($strLineSeparator)`r`nTRYING 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe'`r`n"
      $output = Get-ProcessOutput -FileName "C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe" -Args "--quiet"
      #PARSE OUTPUT LINE BY LINE
      $lines = $output.StandardOutput.split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
      $lines
    } else {
      write-host "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe'"
      $script:diag += "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe'`r`n"
    }
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    logERR 3 $err
  }
  try {
    if (test-path -path "C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe") {
      write-host "$($strLineSeparator)`r`nTRYING 'C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe'"
      $script:diag += "$($strLineSeparator)`r`nTRYING 'C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe'`r`n"
      $output = Get-ProcessOutput -FileName "C:\Program Files\Sophos\Sophos Endpoint Agent\SophosUninstall.exe" -Args "--quiet"
      #PARSE OUTPUT LINE BY LINE
      $lines = $output.StandardOutput.split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
      $lines
    } else {
      write-host "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe'"
      $script:diag += "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files\Sophos\Sophos Endpoint Agent\uninstallgui.exe'`r`n"
    }
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    logERR 3 $err
  }
  write-host "$($strLineSeparator)`r`nCOMPLETED SOPHOS EXE UNINSTALLS`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nCOMPLETED SOPHOS EXE UNINSTALLS`r`n$($strLineSeparator)`r`n"
  write-host "$($strLineSeparator)`r`nPROCESSING SOPHOS REG UNINSTALLS`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nPROCESSING SOPHOS REG UNINSTALLS`r`n$($strLineSeparator)`r`n"
  #RETRIEVE UNINSTALL STRINGS FROM REGISTRY
  $key32 = get-itemproperty -path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*" -erroraction stop | where {(($_.DisplayName -like "*Sophos*") -and 
    (($_.DisplayName -notmatch "Sophos Connect") -and ($_.DisplayName -notmatch "Sophos SSL VPN Client")))}
  $key64 = get-itemproperty -path "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -erroraction stop | where {(($_.DisplayName -like "*Sophos*") -and 
    (($_.DisplayName -notmatch "Sophos Connect") -and ($_.DisplayName -notmatch "Sophos SSL VPN Client")))}
  #LOOP THROUGH EACH UNINSTALL STRING
  try {
    foreach ($string32 in $key32) {
      write-host "$($string32)`r`n$($strLineSeparator)`r`n"
      RegUninstall $string32
    }
    foreach ($string64 in $key64) {
      write-host $string64
      RegUninstall $string64
    }
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    logERR 3 $err
  }
  write-host "$($strLineSeparator)`r`nCOMPLETED SOPHOS REG UNINSTALLS`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nCOMPLETED SOPHOS REG UNINSTALLS`r`n$($strLineSeparator)`r`n"
  write-host "$($strLineSeparator)`r`nPROCESSING FINAL EXE UNINSTALLS`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nPROCESSING FINAL EXE UNINSTALLS`r`n$($strLineSeparator)`r`n"
  #UNINSTALL HITMAN PRO
  try {
    if (test-path -path "C:\Program Files (x86)\HitmanPro.Alert\Uninstall.exe") {
      write-host "$($strLineSeparator)`r`nTRYING `"C:\Program Files (x86)\HitmanPro.Alert\Uninstall.exe`" -Args `"--quiet`""
      $script:diag += "$($strLineSeparator)`r`nTRYING `"C:\Program Files (x86)\HitmanPro.Alert\Uninstall.exe`" -Args `"--quiet`"`r`n"
      $output = Get-ProcessOutput -FileName "C:\Program Files (x86)\HitmanPro.Alert\Uninstall.exe" -Args "--quiet"
      #PARSE OUTPUT LINE BY LINE
      $lines = $output.StandardOutput.split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
      $lines
    } else {
      write-host "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files (x86)\HitmanPro.Alert\Uninstall.exe'"
      $script:diag += "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files (x86)\HitmanPro.Alert\Uninstall.exe'`r`n"
    }
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    logERR 3 $err
  }
  try {
    if (test-path -path "C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe") {
      write-host "$($strLineSeparator)`r`nTRYING `"C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe`" -Args `"/uninstall /quiet`""
      $script:diag += "$($strLineSeparator)`r`nTRYING `"C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe`" -Args `"/uninstall /quiet`"`r`n"
      $output = Get-ProcessOutput -FileName "C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe" -Args "/uninstall /quiet"
      #PARSE OUTPUT LINE BY LINE
      $lines = $output.StandardOutput.split("`r`n", [StringSplitOptions]::RemoveEmptyEntries)
      $lines
    } else {
      write-host "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe'"
      $script:diag += "$($strLineSeparator)`r`nNON-EXISTENT : 'C:\Program Files (x86)\HitmanPro.Alert\hmpalert.exe'`r`n"
    }
  } catch {
    $err = "$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)"
    logERR 3 $err
  }
  write-host "$($strLineSeparator)`r`nCOMPLETED FINAL EXE UNINSTALLS`r`n$($strLineSeparator)"
  $script:diag += "$($strLineSeparator)`r`nCOMPLETED FINAL EXE UNINSTALLS`r`n$($strLineSeparator)`r`n"
  #CLEANUP REMAINING FOLDERS
  if (test-path -path "C:\Program Files (x86)\HitmanPro.Alert") {
    get-childitem -path "C:\Program Files (x86)\HitmanPro.Alert" -recurse | remove-item
    remove-item -path "C:\Program Files (x86)\HitmanPro.Alert" -force
  }
  #CLEANUP WMI INSTANCES
  if ($script:producttype -ne "Workstation") {
    (Get-WmiObject -Namespace "root/SecurityCenter2" -Class FirewallProduct | ?{$_.displayname -like 'sophos*'}).delete()
    (Get-WmiObject -Namespace "root/SecurityCenter2" -Class AntiVirusProduct | ?{$_.displayname -like 'sophos*'}).delete()
  }
}
#Stop script execution time calculation
StopClock
#WRITE LOGFILE
$script:diag | out-file $logPath
#DATTO OUTPUT
if ($script:blnBREAK) {
  write-DRMMAlert "Uninstall_Sophos : Execution Failed : See Diagnostics"
  write-DRMMDiag "$($script:diag)"
  exit 1
} elseif (-not $script:blnBREAK) {
  if ($script:blnWARN) {
    write-DRMMAlert "Uninstall_Sophos : Warning : See Diagnostics"
    write-DRMMDiag "$($script:diag)"
    exit 1
  } elseif (-not $script:blnWARN) {
    write-DRMMAlert "Uninstall_Sophos : Completed Execution"
    write-DRMMDiag "$($script:diag)"
    exit 0
  }
}
#END SCRIPT
#------------