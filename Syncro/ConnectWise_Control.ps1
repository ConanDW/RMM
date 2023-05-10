#connectwise control in UDF :: redux build 2, march 23/seagull
#Modified by : Chris Bledsoe | cbledsoe@ipmcomputers.com
Import-Module $env:SyncroModule
$script:blnBREAK = $false
$varSite = "$($strSite)"
$varCompany = "$($strCompany)"
$strLineSeparator = "-------------------"
$CWKeyThumbprint = "$($ConnectWiseControlPublicKeyThumbprint)"
$CWControlInstallURL = "$($ConnectWiseControlInstallerUrl)"
if ($CWControlInstallURL -match "|") {
  $CWControlInstallURL = $CWControlInstallURL.replace('|','&')
}
if (-not $varCompany) {
  $script:blnBREAK = $true
}
if ($varCompany -match ' ') {
  $varCompany = $varCompany.replace(' ','%20')
}
$CWControlInstallURL = "$($CWControlInstallURL)&y=Guest&c=$($varCompany)"
if (-not $varSite) {
  $CWControlInstallURL = "$($CWControlInstallURL)&c=&c=&c=&c=&c=&c=&c="
} elseif ($varSite) {
  if ($varSite -match ' ') {
    $varSite = $varSite.replace(' ','%20')
  }
  $CWControlInstallURL = "$($CWControlInstallURL)&c=$($varSite)&c=&c=&c=&c=&c=&c="
}
write-host "`r`n==================================="
write-host "SC Site : $($varSite)"
write-host "SC Company : $($varCompany)"
write-host "SC Thumbprint : $($CWKeyThumbprint)"
write-host "SC Install URL : $($CWControlInstallURL)"
write-host "SC Base URL : $($ConnectWiseControlBaseUrl)"
write-host "===================================`r`n"

#function provided by Datto
function verifyPackage ($file, $certificate, $thumbprint, $name, $url) {
  $varChain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
  try {
    $varChain.Build((Get-AuthenticodeSignature -FilePath "$($file)").SignerCertificate) | out-null
  } catch [System.Management.Automation.MethodInvocationException] {
    $err = "`r`n$($_.Exception)`r`n$($_.scriptstacktrace)`r`n$($_)`r`n$($strLineSeparator)"
    write-host "- ERROR: $($name) installer did not contain a valid digital certificate."
    write-host "  This could suggest a change in the way $($name) is packaged; it could"
    write-host "  also suggest tampering in the connection chain."
    write-host "- Please ensure $($url) is whitelisted and try again."
    write-host "  If this issue persists across different devices, please file a support ticket.`r`n$($err)"
  }

  $varIntermediate=($varChain.ChainElements | ForEach-Object {$_.Certificate} | Where-Object {$_.Subject -match "$certificate"}).Thumbprint

  if ($varIntermediate -ne $thumbprint) {
    write-host "- ERROR: $($file) did not pass verification checks for its digital signature."
    write-host "  This could suggest that the certificate used to sign the $($name) installer"
    write-host "  has changed; it could also suggest tampering in the connection chain."
    if ($varIntermediate) {
      write-host ": We received: $($varIntermediate)"
      write-host "  We expected: $($thumbprint)"
      write-host "  Please report this issue."
    } else {
      write-host "  The installer's certificate authority has changed."
    }
    write-host "- Installation cannot continue. Exiting."
  } else {
    write-host "- Digital Signature verification passed."
  }
}

function CreateJoinLink {
  $null = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ($CWKeyThumbprint)" -Name ImagePath).ImagePath -Match '(&s=[a-f0-9\-]*)'
  $GUID = $Matches[0] -replace '&s='
  $apiLaunchUrl= "$($env:ConnectWiseControlBaseUrl)/Host#Access///$($GUID)/Join"
  Set-Asset-Field -Name "CW Control URL :" -Value "$($apiLaunchUrl)"
  write-host "- Asset Field 'CW Control URL :' Updated : $($apiLaunchUrl)"
}

Log-Activity -Message "CW Control Install Started" -EventName "CW Control"
if (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\ScreenConnect Client ($CWKeyThumbprint)" ) {
  try {
    write-host "- ConnectWise Control already installed. Establishing link..."
    CreateJoinLink
  } catch {
    Rmm-Alert -Category 'CW Control' -Body 'CW Control Establishing Link Failed'
    Log-Activity -Message "CW Control Establishing Link Failed" -EventName "CW Control"
    exit 1
  }
} else {
  try {
    $tmp = "C:\IT\ConnectWiseControl.ClientSetup.exe"
    Invoke-WebRequest -Uri $CWControlInstallURL -OutFile $tmp
    #cert from 16/August/2022 to 15/August/2025
    verifyPackage "$($tmp)" "ConnectWise, LLC" "4c2272fba7a7380f55e2a424e9e624aee1c14579" "ConnectWise Control Client Setup" "$($CWControlInstallURL)"
    write-host "- Installing ConnectWise Control..."
    Start-Process -Wait -FilePath $tmp -ArgumentList "/qn" -PassThru
    CreateJoinLink
    Close-Rmm-Alert -Category "CW Control" -CloseAlertTicket "true"
    Log-Activity -Message "CW Control Install Completed" -EventName "CW Control"
  } catch {
    Rmm-Alert -Category 'CW Control' -Body 'CW Control Installation Failed'
    Log-Activity -Message "CW Control Installation Failed" -EventName "CW Control"
    exit 1
  }
}