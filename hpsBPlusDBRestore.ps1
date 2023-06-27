#requires -version 3
#---------------------------------------------------------[Script Parameters]------------------------------------------------------
[CmdletBinding()]
Param (
  [String]
  [Parameter( Position = 0, Mandatory = $true)]
  #Specifies the BusinessPlus environment to restore
  $BPEnvironment,
  
  [ValidateNotNullOrEmpty()]
  [ValidateScript( {Test-Path $_ -IsValid} )]
  [Parameter( Position = 1 )]
  [String]
  #Specifies the path to the aspnet database backup file.
  $aspnetFilePath,

  
  [ValidateNotNullOrEmpty()]
  [ValidateScript( {Test-Path $_ -IsValid} )]
  [Parameter( Position = 2, Mandatory = $true )]
  [String]
  #Specifies the path to the ifas database backup file.
  $ifasFilePath,

  
  [ValidateNotNullOrEmpty()]
  [ValidateScript( {Test-Path $_ -IsValid} )]
  [Parameter( Position = 3, Mandatory = $true )]
  [String]
  #Specifies the path to the syscat database backup file.
  $syscatFilePath,

  [Parameter( Position = 4, Mandatory = $false)]
  [switch]
  #Specifies the option to enable additional accounts for Testing.
  $testingMode = $false,

  [Parameter( Position = 5, Mandatory = $false)]
  [switch]
  #Specifies the option to copy dashboard files to the environment.
  $restoreDashboards = $false
)

# <TODO>
#   Need to add Try/Catch logic and possibly add custom errors and handling

#---------------------------------------------------------[Initializations]--------------------------------------------------------

#Set Error Action to Silently Continue
$ErrorActionPreference = 'SilentlyContinue'

#Verify required Modules are installed

#Import Modules & Snap-ins
Add-Module PSLogging
Add-Module dbatools
Add-Module PsIni
#Add-Module SqlServer

#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Script Version
$sScriptVersion = '1.3'

#Log File Info
$sLogPath = $PSScriptRoot
$sLogName = 'hpsBPlusDBRestore.log'
$sLogFile = Join-Path -Path $sLogPath -ChildPath $sLogName

#-----------------------------------------------------------[Functions]------------------------------------------------------------

<#

Function <FunctionName> {
  Param ()

  Begin {
    Write-LogInfo -LogPath $sLogFile -Message '<description of what is going on>...'
  }

  Process {
    Try {
      <code goes here>
    }

    Catch {
      Write-LogError -LogPath $sLogFile -Message $_.Exception -ExitGracefully
      Break
    }
  }

  End {
    If ($?) {
      Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
      Write-LogInfo -LogPath $sLogFile -Message ' '
    }
  }
}

#>

function Add-Module ($m) {

    Begin {
        Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Attempting to install or load PowerShell Module: $($m)"
    }

    Process {
        Try {
            # If module is imported say that and do nothing
            if (Get-Module | Where-Object {$_.Name -eq $m}) {
                Write-LogInfo -LogPath $sLogFile -Message  "Module $m is already imported."
            }
            else {
        
                # If module is not imported, but available on disk then import
                if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
                    Import-Module $m -Verbose
                }
                else {
        
                    # If module is not imported, not available on disk, but is in online gallery then install and import
                    if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                        Install-Module -Name $m -Force -Verbose -Scope CurrentUser
                        Import-Module $m -Verbose
                    }
                    else {
        
                        # If the module is not imported, not available and not in the online gallery then abort
                        Write-LogError -LogPath $sLogFile -Message  "Module $m not imported, not available and not in an online gallery, exiting."
                        Break
                    }
                }
            }
            }
        Catch {
            Write-LogError -LogPath $sLogFile -Message $_.Exception -ExitGracefully
            Break
            }
        }

    End {
            If ($?) {
            Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
            Write-LogInfo -LogPath $sLogFile -Message ' '
            }
        }
    }
## ----------------------------------------------------------------------------------------------------------------------------- ##
##                                                          [Execution]                                                          ##
## ----------------------------------------------------------------------------------------------------------------------------- ##


## ----------------------------------------------------------------------------------------------------------------------------- ##
## Start the log file for the script                                                                                             ##
## ----------------------------------------------------------------------------------------------------------------------------- ##
Start-Log -LogPath $sLogPath -LogName $sLogName -ScriptVersion $sScriptVersion
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) starting restore of $($BPEnvironment) environment"


## ----------------------------------------------------------------------------------------------------------------------------- ##
## Get settings from .ini file for the appropriate environment and create variables for use in script                            ##
## TO-DO: Setup Error checking and fail out if a required setting is not found                                                   ##
## ----------------------------------------------------------------------------------------------------------------------------- ##
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Parsing .ini file for $($BPEnvironment)"
$bpEnvironmentInfo = Get-IniContent "$($sLogPath)\hpsBPlusDBRestore.ini"

$databaseServer = $bpEnvironmentInfo["sqlServer"][$BPEnvironment]
$ifasDatabase = $bpEnvironmentInfo["database"][$BPEnvironment]
$syscatDatabase = $bpEnvironmentInfo["syscat"][$BPEnvironment]
if ($aspnetDatabase) {$aspnetDatabase = $bpEnvironmentInfo["aspnet"][$BPEnvironment]}
$dbServerDataDrive = $bpEnvironmentInfo["filepathData"][$BPEnvironment]
$dbServerLogDrive = $bpEnvironmentInfo["filepathLog"][$BPEnvironment]
$dbServerImagesDrive = $bpEnvironmentInfo["filepathImages"][$BPEnvironment]
$dbFileDrivesIfas = $bpEnvironmentInfo["fileDriveData"][$BPEnvironment].Split(',')
$dbFileDrivesSyscat = $bpEnvironmentInfo["fileDriveSyscat"][$BPEnvironment].Split(',')
if ($aspnetDatabase) {$dbFileDrivesAspnet = $bpEnvironmentInfo["fileDriveAspnet"][$BPEnvironment].Split(',')}
$bpServers = $bpEnvironmentInfo["environmentServers"][$BPEnvironment].Split(',')
$ipcDaemon = $bpEnvironmentInfo["ipc_daemon"][$BPEnvironment]
$smtpServer = $bpEnvironmentInfo["SMTP"]["host"]
$streetAddress = $bpEnvironmentInfo["SMTP"]["mailMessageAddress"]
$replyToEmail = $bpEnvironmentInfo["SMTP"]["replyToEmail"]
$notificationEmail = $bpEnvironmentInfo["SMTP"]["notificationEmail"]
$smtpPort = $bpEnvironmentInfo["SMTP"]["port"]
if (!$smtpPort) { $smtpPort = 25 }
$nuupausyText  = $bpEnvironmentInfo["NUUPAUSY"][$BPEnvironment]
$iusrSource = $bpEnvironmentInfo["IUSRSource"][$BPEnvironment]
$iusrDestination = $bpEnvironmentInfo["IUSRDestination"][$BPEnvironment]
$adminSource = $bpEnvironmentInfo["AdminSource"][$BPEnvironment]
$adminDestination = $bpEnvironmentInfo["AdminDestination"][$BPEnvironment]
$dboSource = $bpEnvironmentInfo["AdminSource"][$BPEnvironment]
$dboDestination = $bpEnvironmentInfo["AdminDestination"][$BPEnvironment]
$dummyEmail = $bpEnvironmentInfo["DummyEmail"][$BPEnvironment]
$managerCodes = $bpEnvironmentInfo["ManagerCode"][$BPEnvironment].Split(',')
if ($testingMode) { $managerCodes = $bpEnvironmentInfo["TestingMode"][$BPEnvironment].Split(',') }
$dashboardURL = $bpEnvironmentInfo["dashboardURL"][$BPEnvironment]
if ($restoreDashboards) { $dashboardPath = $bpEnvironmentInfo["dashboardFiles"][$BPEnvironment] }
$connectionStringIfas = "Data Source=" + $databaseServer + "; Database=" + $ifasDatabase + "; Trusted_Connection=True;"
$connectionStringSyscat = "Data Source=" + $databaseServer + "; Database=" + $syscatDatabase + "; Trusted_Connection=True;"

$dbBackupDate = (Read-DbaBackupHeader -SqlInstance $databaseServer -Path $ifasFilePath).BackupFinishDate

Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") -      DB Backup Date: $($dbBackupDate)"
$nuupausyText = $nuupausyText + $dbBackupDate.AddDays(-1).ToString("yyyyMMdd")
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") -      NUUPAUSY Date: $($dbBackupDate.AddDays(-1).ToString("yyyyMMdd"))"
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") -      NUUPAUSY String: $($nuupausyText)"
Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '


## ----------------------------------------------------------------------------------------------------------------------------- ##
## Create a summary output and have user confirm that they want to run the DB Restore with those options                   ##
## ----------------------------------------------------------------------------------------------------------------------------- ##

#Array to store custom objects for report on screen
$arrReview = @()

#Database Server info
$objProperties = [ordered]@{
    "Config Setting" = "Database Server:      "
    "Config Value" = $databaseServer
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "SQL Server Data File Path:      "
    "Config Value" = $bpEnvironmentInfo["filepathData"][$BPEnvironment]
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "SQL Server Log File Path:      "
    "Config Value" = $bpEnvironmentInfo["filepathLog"][$BPEnvironment]
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "SQL Server Images File Path:      "
    "Config Value" = $bpEnvironmentInfo["filepathImages"][$BPEnvironment]
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "IUSR Account:      "
    "Config Value" = "Source: $($iusrSource)`r`nDestination: $($iusrDestination)"
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "BSI Account:      "
    "Config Value" = "Source: $($adminSource)`r`nDestination: $($adminDestination)"
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = "-----------------------------------"
    "Config Value" = "-------------------------------------------------------------------------------"
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties


#ifas Database info
$objProperties = [ordered]@{
    "Config Setting" = "ifas Database"
    "Config Value" = $bpEnvironmentInfo["database"][$BPEnvironment]
}
$arrReview += New-Object PSCustomObject -Property $objProperties


$ifasFileStructure = @{}
foreach ( $dbFileDrive in $dbFileDrivesIfas)
{
    $driveInfo = $dbFileDrive.Split(":")
    Switch ($driveInfo[1])
    {
        "Data" { $ifasFileStructure.Add("$($driveInfo[0])","$($dbServerDataDrive)\$($driveInfo[2])") }
        "Images" { $ifasFileStructure.Add("$($driveInfo[0])","$($dbServerImagesDrive)\$($driveInfo[2])") }
        "Log" { $ifasFileStructure.Add("$($driveInfo[0])","$($dbServerLogDrive)\$($driveInfo[2])") }
    }
}
$ifasFileStructure = $ifasFileStructure.GetEnumerator() | Sort-Object -Property Name
$ifasFileLayout = ""
for ($i=1 ; $i -le $ifasFileStructure.Length ; $i++) 
    { if (($i-$ifasFileStructure.Length) -ne 0 ) {
            $ifasFileLayout += "$($ifasFileStructure[$i-1].Name): $($ifasFileStructure[$i-1].Value)`r`n"
        } else {
           $ifasFileLayout += "$($ifasFileStructure[$i-1].Name): $($ifasFileStructure[$i-1].Value)"
        }
    }

$objProperties = [ordered]@{
    "Config Setting" = "ifas Database File Layout"
    "Config Value" = $ifasFileLayout
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties


#syscat Database info
$objProperties = [ordered]@{
    "Config Setting" = "syscat Database"
    "Config Value" = $bpEnvironmentInfo["syscat"][$BPEnvironment]
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$syscatFileStructure = @{}
foreach ( $dbFileDrive in $dbFileDrivesSyscat)
{
    $driveInfo = $dbFileDrive.Split(":")
    Switch ($driveInfo[1])
    {
        "Data" { $syscatFileStructure.Add("$($driveInfo[0])","$($dbServerDataDrive)\$($driveInfo[2])") }
        "Images" { $syscatFileStructure.Add("$($driveInfo[0])","$($dbServerImagesDrive)\$($driveInfo[2])") }
        "Log" { $syscatFileStructure.Add("$($driveInfo[0])","$($dbServerLogDrive)\$($driveInfo[2])") }
    }
}

$syscatFileStructure = $syscatFileStructure.GetEnumerator() | Sort-Object -Property Name
$syscatFileLayout = ""
for ($i=1 ; $i -le $syscatFileStructure.Length ; $i++) 
    { if (($i-$syscatFileStructure.Length) -ne 0 ) {
            $syscatFileLayout += "$($syscatFileStructure[$i-1].Name): $($syscatFileStructure[$i-1].Value)`r`n"
        } else {
            $syscatFileLayout += "$($syscatFileStructure[$i-1].Name): $($syscatFileStructure[$i-1].Value)"
        }
    }

$objProperties = [ordered]@{
    "Config Setting" = "syscat Database File Layout"
    "Config Value" = $syscatFileLayout
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#aspnet Database info
if ($aspnetDatabase) {
$objProperties = [ordered]@{
    "Config Setting" = "aspnet Database"
    "Config Value" = $bpEnvironmentInfo["aspnet"][$BPEnvironment]
}
$arrReview += New-Object PSCustomObject -Property $objProperties}

if ($aspnetDatabase) {
$aspnetFileStructure = @{}
foreach ( $dbFileDrive in $dbFileDrivesAspnet)
{
    $driveInfo = $dbFileDrive.Split(":")
    Switch ($driveInfo[1])
    {
        "Data" { $aspnetFileStructure.Add("$($driveInfo[0])","$($dbServerDataDrive)\$($driveInfo[2])") }
        "Images" { $aspnetFileStructure.Add("$($driveInfo[0])","$($dbServerImagesDrive)\$($driveInfo[2])") }
        "Log" { $aspnetFileStructure.Add("$($driveInfo[0])","$($dbServerLogDrive)\$($driveInfo[2])") }
    }
}}

if ($aspnetDatabase) {$aspnetFileStructure = $aspnetFileStructure.GetEnumerator() | Sort-Object -Property Name
$aspnetFileLayout = ""
for ($i=1 ; $i -le $aspnetFileStructure.Length ; $i++) 
    { if (($i-$aspnetFileStructure.Length) -ne 0 ) {
            $aspnetFileLayout += "$($aspnetFileStructure[$i-1].Name): $($aspnetFileStructure[$i-1].Value)`r`n"
        } else {
            $aspnetFileLayout += "$($aspnetFileStructure[$i-1].Name): $($aspnetFileStructure[$i-1].Value)"
        }
    }

$objProperties = [ordered]@{
    "Config Setting" = "aspnet Database File Layout"
    "Config Value" = $aspnetFileLayout
}
$arrReview += New-Object PSCustomObject -Property $objProperties }

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = "-----------------------------------"
    "Config Value" = "-------------------------------------------------------------------------------"
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties


#BusinessPlus Environment Info
$bpServerList = ""
for ($i=1 ; $i -le $bpServers.Length ; $i++) { 
    if (($i-$bpServers.Length) -ne 0 ) {
        $bpServerList += "$($bpServers[$i-1])`r`n"
    } else {
        $bpServerList += "$($bpServers[$i-1])"
    }
 }

$objProperties = [ordered]@{
    "Config Setting" = "BusinessPlus Servers"
    "Config Value" = $bpServerList
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "IPC Daemon Service Name"
    "Config Value" = $ipcDaemon
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "NUUPAUSY Text"
    "Config Value" = $nuupausyText
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "Dummy Email Address"
    "Config Value" = $dummyEmail
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$bpManagerList = ""
for ($i=1 ; $i -le $managerCodes.Length ; $i++) { 
    if (($i-$managerCodes.Length) -ne 0 ) {
        $bpManagerList += "$($managerCodes[$i-1])`r`n"
    } else {
        $bpManagerList += "$($managerCodes[$i-1])"
    }
 }
 $objProperties = [ordered]@{
    "Config Setting" = "Manager Codes"
    "Config Value" = $bpManagerList
}
$arrReview += New-Object PSCustomObject -Property $objProperties

 $objProperties = [ordered]@{
    "Config Setting" = "Dashboard URL"
    "Config Value" = $dashboardURL
}
$arrReview += New-Object PSCustomObject -Property $objProperties

if ($restoreDashboards) {
        $dashboards = $dashboardPath.Split(":")
        $objProperties = [ordered]@{
            "Config Setting" = "Dashboard Restore Info"
            "Config Value" = "Source:      $($dashboards[0])`r`nDestination: $($dashboards[1])"
        }
        $arrReview += New-Object PSCustomObject -Property $objProperties
    }


#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = "-----------------------------------"
    "Config Value" = "-------------------------------------------------------------------------------"
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#add empty record to improve readability
$objProperties = [ordered]@{
    "Config Setting" = ""
    "Config Value" = ""
}
$arrReview += New-Object PSCustomObject -Property $objProperties

#Script Resources
$objProperties = [ordered]@{
    "Config Setting" = "SMTP Host"
    "Config Value" = $smtpServer
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "SMTP Port"
    "Config Value" = $smtpPort
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "Street Address"
    "Config Value" = $streetAddress
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "Reply-To Email"
    "Config Value" = $replyToEmail
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$objProperties = [ordered]@{
    "Config Setting" = "Notification Recipients"
    "Config Value" = $notificationEmail
}
$arrReview += New-Object PSCustomObject -Property $objProperties

$arrReview | Format-Table -AutoSize -Wrap

$choiceTitle = "Options Review"
$choiceQuestion = "Continue with DB Refresh of $($BPEnvironment)"
$choices = @(
[System.Management.Automation.Host.ChoiceDescription]::new("&Yes","Yes, proceed with DB Refresh"),
[System.Management.Automation.Host.ChoiceDescription]::new("&No","No, exit the script")
)
$choiceDecision = $Host.UI.PromptForChoice($choiceTitle, $choiceQuestion, $choices, 1)
If ($choiceDecision -ne 0)
{
    exit
}


## ----------------------------------------------------------------------------------------------------------------------------- ##
## Parse $bpEnvironmentInfo for list of servers and stop associated BusinessPlus services                                        ##
## ----------------------------------------------------------------------------------------------------------------------------- ##
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Stoping BusinessPlus services in $($BPEnvironment) Environment"
foreach ($bpServer in $bpServers) {

    #check for BusinessPlus Workflow Service and stop if exists
    Write-LogInfo -LogPath $sLogFile -Message "     Stopping btwfsvc on $($bpServer)"
    $service = Get-Service -ComputerName $bpServer -Name btwfsvc -ErrorAction SilentlyContinue
    if ($service) { $service.Stop() }

    #check for BusinessPlus Data Processing Service and stop if exists
    Write-LogInfo -LogPath $sLogFile -Message "     Stopping BTNETSVC on $($bpServer)"
    $service = Get-Service -ComputerName $bpServer -Name BTNETSVC -ErrorAction SilentlyContinue
    if ($service) { $service.Stop() }

    #check for BusinessPlus Data Processing Service and stop if exists
    Write-LogInfo -LogPath $sLogFile -Message "     Stopping $($ipcDaemon) on $($bpServer)"
    $service = Get-Service -ComputerName $bpServer -Name $ipcDaemon -ErrorAction SilentlyContinue
    if ($service) { $service.Stop() }

    #check for World Wide Web Service and stop if exists
    Write-LogInfo -LogPath $sLogFile -Message "     Stopping W3SVC on $($bpServer)"
    $service = Get-Service -ComputerName $bpServer -Name W3SVC -ErrorAction SilentlyContinue
    if ($service) { $service.Stop() }
}
Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '

## ----------------------------------------------------------------------------------------------------------------------------- ##
## Grab syscat and ifas db config entries from the existing instance for restore later in process.                               ##
## ----------------------------------------------------------------------------------------------------------------------------- ##
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Querying existing $($BPEnvironment) connection values"
    ## syscat database ##
$sqlQuery = "select TOP 1 * from bsi_sys_blob where [category]='CONNECT' and app='CONNECT' and [name]='$($ifasDatabase)'"
$syscatData = New-Object System.Data.DataTable
$Connection = New-Object System.Data.SQLClient.SQLConnection
$Connection.ConnectionString = $connectionStringSyscat
$Connection.Open()
$Command = New-Object System.Data.SQLClient.SQLCommand
$Command.Connection = $Connection
$Command.CommandText = $sqlQuery
$Reader = $Command.ExecuteReader()
$syscatData.Load($Reader)
$Connection.Close()

    ## ifas database ##
$sqlQuery = "select TOP 1 * from ifas_data WHERE [name]='Hostnames' and [category]='Settings' and [app] = 'Admin'"
$ifasData = New-Object System.Data.DataTable
$Connection.ConnectionString = $connectionStringIfas
$Connection.Open()
$Command.Connection = $Connection
$Command.CommandText = $sqlQuery
$Reader = $Command.ExecuteReader()
$ifasData.Load($Reader)
$Connection.Close()
$ifasData.Columns.Remove("unique_key")

if ($ifasData -and $syscatData)
{
    Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
    Write-LogInfo -LogPath $sLogFile -Message ' '
} else {
    Write-LogError -LogPath $sLogFile -Message "BusinessPlus Data not obtained successfully" -ExitGracefully
    Break
}


## ----------------------------------------------------------------------------------------------------------------------------- ##
## Restore Databases                                                                                                             ##
## ----------------------------------------------------------------------------------------------------------------------------- ##
if ($aspnetDatabase) {
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Beginning Database Restores for $($BPEnvironment)."
    ## Restore ASPNET Database ##
$aspnetFileStructure = @{}
foreach ( $dbFileDrive in $dbFileDrivesAspnet)
{
    $driveInfo = $dbFileDrive.Split(":")
    Switch ($driveInfo[1])
    {
        "Data" { $aspnetFileStructure.Add("$($driveInfo[0])","$($dbServerDataDrive)\$($driveInfo[2])") }
        "Images" { $aspnetFileStructure.Add("$($driveInfo[0])","$($dbServerImagesDrive)\$($driveInfo[2])") }
        "Log" { $aspnetFileStructure.Add("$($driveInfo[0])","$($dbServerLogDrive)\$($driveInfo[2])") }
    }
}
Write-LogInfo -LogPath $sLogFile -Message "     $(Get-Date -Format "G") - Restoring $($aspnetDatabase) database in the $($BPEnvironment) environment."
Restore-DbaDatabase -SqlInstance $databaseServer -Path $aspnetFilePath -DatabaseName $aspnetDatabase -FileMapping $aspnetFileStructure -WithReplace | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message "     $(Get-Date -Format "G") - Restoring $($aspnetDatabase) database in the $($BPEnvironment) environment complete."
}
    ## Restore Syscat Database ##
$syscatFileStructure = @{}
foreach ( $dbFileDrive in $dbFileDrivesSyscat)
{
    $driveInfo = $dbFileDrive.Split(":")
    Switch ($driveInfo[1])
    {
        "Data" { $syscatFileStructure.Add("$($driveInfo[0])","$($dbServerDataDrive)\$($driveInfo[2])") }
        "Images" { $syscatFileStructure.Add("$($driveInfo[0])","$($dbServerImagesDrive)\$($driveInfo[2])") }
        "Log" { $syscatFileStructure.Add("$($driveInfo[0])","$($dbServerLogDrive)\$($driveInfo[2])") }
    }
}
Write-LogInfo -LogPath $sLogFile -Message "     $(Get-Date -Format "G") - Restoring $($syscatDatabase) database in the $($BPEnvironment) environment."
Restore-DbaDatabase -SqlInstance $databaseServer -Path $syscatFilePath -DatabaseName $syscatDatabase -FileMapping $syscatFileStructure -WithReplace | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message "     $(Get-Date -Format "G") - Restoring $($syscatDatabase) database in the $($BPEnvironment) environment complete."

    ## Restore IFAS Database ##
$dataFileStructure = @{}
foreach ( $dbFileDrive in $dbFileDrivesIfas)
{
    $driveInfo = $dbFileDrive.Split(":")
    Switch ($driveInfo[1])
    {
        "Data" { $dataFileStructure.Add("$($driveInfo[0])","$($dbServerDataDrive)\$($driveInfo[2])") }
        "Images" { $dataFileStructure.Add("$($driveInfo[0])","$($dbServerImagesDrive)\$($driveInfo[2])") }
        "Log" { $dataFileStructure.Add("$($driveInfo[0])","$($dbServerLogDrive)\$($driveInfo[2])") }
    }
}
Write-LogInfo -LogPath $sLogFile -Message "     $(Get-Date -Format "G") - Restoring $($ifasDatabase) database in the $($BPEnvironment) environment."
Restore-DbaDatabase -SqlInstance $databaseServer -Path $ifasFilePath -DatabaseName $ifasDatabase -FileMapping $dataFileStructure -WithReplace | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message "     $(Get-Date -Format "G") - Restoring $($ifasDatabase) database in the $($BPEnvironment) environment complete."

Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Completed Successfully."
Write-LogInfo -LogPath $sLogFile -Message ' '


## ----------------------------------------------------------------------------------------------------------------------------- ##
## Restore Environment Info                                                                                                      ##
## ----------------------------------------------------------------------------------------------------------------------------- ##
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Restoring $($BPEnvironment) environment connection information"
    #Delete bad syscat Info
    $sqlQuery = "DELETE FROM bsi_sys_blob where [category]='CONNECT' and app='CONNECT' and [name]='ifas'"
    Invoke-Sqlcmd -Query $sqlQuery -Database $syscatDatabase -ServerInstance $databaseServer
    #Restore Syscat Info
    Write-DbaDbTableData -SqlInstance $databaseServer -InputObject $syscatData -Database $syscatDatabase -Table "bsi_sys_blob" -Schema "dbo"

    #Delete bad ifas info
    $sqlQuery = "DELETE FROM ifas_data WHERE [name]='Hostnames' and [category]='Settings' and [app] = 'Admin'"
    Invoke-Sqlcmd -Query $sqlQuery -Database $ifasDatabase -ServerInstance $databaseServer
    #Restore ifas Info
    Write-DbaDbTableData -SqlInstance $databaseServer -InputObject $ifasData -Database $ifasDatabase -Table "ifas_data" -Schema "dbo"

Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '

## ----------------------------------------------------------------------------------------------------------------------------- ##
## Run TSQL Scripts to configure test instance                                                                                   ##
## ----------------------------------------------------------------------------------------------------------------------------- ##

#Setup DB Permissions to remove PROD security and replace it with TESTx security.  Takes values from config file.
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Setting SQL Server secuirty on the restored databases"
#aspnet
if ($aspnetDatabase) {
Write-LogInfo -LogPath $sLogFile -Message "     Setting Permissions on $($aspnetDatabase) Database"
$sqlQuery = @"
--  DATABASE RIGHTS Changes - Required after DB Restore to
--  ensure TESTn Environment is configured as TEST and can be
--  properly setup in the Connection Manager and Admin Console.
--  
--  !!!!!!!!  NEVER RUN THIS SCRIPT IN PRODUCTION  !!!!!!!!
--**************************************************************
USE $($aspnetDatabase)
GO

DROP USER [$($adminSource)]
GO

CREATE USER [$($adminDestination)] FOR LOGIN [$($adminDestination)] WITH DEFAULT_SCHEMA=[dbo]
GO

DROP USER [$($dboSource)]
GO

CREATE USER [$($dboDestination)] FOR LOGIN [$($dboDestination)]
GO

EXEC sp_addrolemember N'db_owner', N'$($dboDestination)'
GO

ALTER DATABASE $($aspnetDatabase) SET RECOVERY SIMPLE
GO
"@
Write-LogInfo -LogPath $sLogFile -Message "     $($sqlQuery)"
Invoke-Sqlcmd -Query $sqlQuery -Database $aspnetDatabase -ServerInstance $databaseServer  | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message '     Completed Successfully.'}

#ifas
Write-LogInfo -LogPath $sLogFile -Message "     Setting Permissions on $($ifasDatabase) Database"
$sqlQuery = @"
--  DATABASE RIGHTS Changes - Required after DB Restore to
--  ensure TESTn Environment is configured as TEST and can be
--  properly setup in the Connection Manager and Admin Console.
--  
--  !!!!!!!!  NEVER RUN THIS SCRIPT IN PRODUCTION  !!!!!!!!
--**************************************************************
USE $($ifasDatabase)
GO

DROP USER [$($iusrSource)]
GO

CREATE USER [$($iusrDestination)] FOR LOGIN [$($iusrDestination)]
GO

EXEC sp_addrolemember N'db_owner', N'$($iusrDestination)'
GO

DROP USER [$($adminSource)]
GO

CREATE USER [$($adminDestination)] FOR LOGIN [$($adminDestination)]
GO

EXEC sp_addrolemember N'db_owner', N'$($adminDestination)'
GO

DROP USER $($dboSource)
GO

CREATE USER [$($dboDestination)] FOR LOGIN [$($dboDestination)]
GO

EXEC sp_addrolemember N'db_owner', NN'$($dboDestination)'
GO

EXEC sp_addrolemember N'db_datareader', N'$($dboDestination)'
GO

EXEC sp_addrolemember N'db_datawriter', N'$($dboDestination)'
GO

EXEC sp_addrolemember N'db_ddladmin', N'$($dboDestination)'
GO

ALTER DATABASE $($ifasDatabase) SET RECOVERY SIMPLE
GO
DBCC OPENTRAN($($ifasDatabase))
GO
CHECKPOINT
GO
USE $($ifasDatabase)
GO
DBCC SHRINKFILE (N'bplus_log',8192)
GO
"@
Write-LogInfo -LogPath $sLogFile -Message "     $($sqlQuery)"
Invoke-Sqlcmd -Query $sqlQuery -Database $ifasDatabase -ServerInstance $databaseServer  | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message '     Completed Successfully.'

#syscat
Write-LogInfo -LogPath $sLogFile -Message "     Setting Permissions on $($syscatDatabase) Database"
$sqlQuery = @"
--  DATABASE RIGHTS Changes - Required after DB Restore to
--  ensure TESTn Environment is configured as TEST and can be
--  properly setup in the Connection Manager and Admin Console.
--  
--  !!!!!!!!  NEVER RUN THIS SCRIPT IN PRODUCTION  !!!!!!!!
--**************************************************************
USE $($syscatDatabase)
GO


DROP USER [syscat]
GO

CREATE USER [syscat] FOR LOGIN [syscat]
GO
EXEC sp_addrolemember N'db_datareader', N'syscat'
GO
EXEC sp_addrolemember N'db_datawriter', N'syscat'
GO
EXEC sp_addrolemember N'db_ddladmin', N'syscat'
GO


DROP USER [$($adminSource)]
GO

CREATE USER [$($adminDestination)] FOR LOGIN [$($adminDestination)]
GO
EXEC sp_addrolemember N'db_owner', N'$($adminDestination)'
GO

ALTER DATABASE $($syscatDatabase) SET RECOVERY SIMPLE
GO
"@
Write-LogInfo -LogPath $sLogFile -Message "     $($sqlQuery)"
Invoke-Sqlcmd -Query $sqlQuery -Database $syscatDatabase -ServerInstance $databaseServer  | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message '     Completed Successfully.'

Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '


#Disable user accounts based on manager code and disable any active workflows with the exception of system required workflows
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Disabling non-tester BusinessPlus accounts for $($BPEnvironment) Environment"
If ($testingMode) { Write-LogInfo -LogPath $sLogFile -Message "     Testing Mode Enabled" }
$managerString = ""
for ($i=1 ; $i -le $managerCodes.Length ; $i++) {
    if (($i-$managerCodes.Length) -ne 0)
    {
        $managerString = $managerString + "'$($managerCodes[$i-1])',"
    } else {
        $managerString = $managerString + "'$($managerCodes[$i-1])'"
    }
}
$sqlQuery = @"
--  WorkFlow and Security Changes that are required at Refresh Time for all TEST Environments
--  !!!!!!!!  NEVER RUN THIS SCRIPT IN PRODUCTION  !!!!!!!!
USE $($ifasDatabase)
GO

--Turn Off WorkFlow Models Triggered
UPDATE wf_model
SET wf_status = 'Z'
WHERE wf_status = 'A' AND wf_model_id NOT IN ('JOB','DO_ARCHIVE','DO_ATTACH','REBUILD_SECURITY','PY_ABSENCE','PY_CANCEL','PY_OVERTIME','PY_TIMETRACKING','TO.NET_APPROVAL')
GO

--Turn Off SCHEDULED WorkFlow Models
UPDATE wf_schedule 
SET wf_status ='Z' 
WHERE wf_status ='A' AND wf_model_id NOT IN ('JOB','REBUILD_SECURITY','DO_ARCHIVE','DO_ATTACH','PY_ABSENCE','PY_CANCEL','PY_OVERTIME','PY_TIMETRACKING','TO.NET_APPROVAL')
GO

--Turn of Instances with Inactive Models
UPDATE wf_instance
SET wf_status = 'H'
WHERE wf_status ='I' and wf_model_id not in ('JOB','REBUILD_SECURITY','DO_ARCHIVE','DO_ATTACH','PY_ABSENCE','PY_CANCEL','PY_OVERTIME','PY_TIMETRACKING','TO.NET_APPROVAL')
GO


-- UPDATE User Email Accounts
UPDATE us_usno_mstr
SET us_email = '$($dummyEmail)'
GO

-- UPDATE User Email Accounts
UPDATE hr_empmstr
SET e_mail = '$($dummyEmail)'
GO

--  Inactivate User Accounts
UPDATE us_usno_mstr
SET us_status = 'I'
WHERE  us_mgr_cd NOT IN ($($managerString))
GO
"@
Write-LogInfo -LogPath $sLogFile -Message "     $($sqlQuery)"
Invoke-Sqlcmd -Query $sqlQuery -Database $ifasDatabase -ServerInstance $databaseServer  | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '

#Set NUUPAUSY Value to the value specified from the config file.
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Updating NUUPAUSY and Dashboard URL for $($BPEnvironment) Environment"

$sqlQuery = @"
UPDATE au_audit_mstr SET au_clnm_l = '$($nuupausyText)', au_clnm = '$($nuupausyText)'

UPDATE us_setting SET value = '$($dashboardURL)' WHERE subsystem = '@@'
"@
Write-LogInfo -LogPath $sLogFile -Message "     $($sqlQuery)"
Invoke-Sqlcmd -Query $sqlQuery -Database $ifasDatabase -ServerInstance $databaseServer
Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '


#Restore Dashboards - If option chosen, will restore dashboards from the source to the destination specified in the config file.
if ($restoreDashboards) {
    Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Restoring Dashboard Files to $($BPEnvironment) Environment"
    $dashboards = $dashboardPath.Split(":")  
    if (Test-Path $dashboards[0]) {
              
        Copy-Item -Force -Recurse -Verbose "$($dashboards[0])\*" -Destination "$($dashboards[1])\" -PassThru | Out-File -FilePath $sLogFile -Append -Encoding "UTF8"
        
    } else {
        Write-LogError -LogPath $sLogFile -Message "Unable to access Dashboards at $($dashboardPath)" -ExitGracefully
        break
    }
    
    Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
    Write-LogInfo -LogPath $sLogFile -Message ' '
}

## ----------------------------------------------------------------------------------------------------------------------------- ##
## Reboot Environment to apply configuration changes                                                                             ##
## ----------------------------------------------------------------------------------------------------------------------------- ##

#Start Services by rebooting servers
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Rebooting $($BPEnvironment) Environment"
foreach ($bpServer in $bpServers) {
    Write-LogInfo -LogPath $sLogFile -Message "     Rebooting $($bpServer)"
	Get-WmiObject -Class Win32_ComputerSystem -ComputerName
    Restart-Computer -ComputerName $bpServer -Force -Wait
	Get-WmiObject -Class Win32_OperatingSystem -ComputerName
}
Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'
Write-LogInfo -LogPath $sLogFile -Message ' '

## ----------------------------------------------------------------------------------------------------------------------------- ##
## Build HTML email and send to notification email address specified in the config file.                                         ##
## ----------------------------------------------------------------------------------------------------------------------------- ##

#Send Email to specified email address upon completion.
Write-LogInfo -LogPath $sLogFile -Message "$(Get-Date -Format "G") - Sending completion notification to $($notificationEmail)"
Write-LogInfo -LogPath $sLogFile -Message "     Adding MailKit DLLs"
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\System.Buffers.4.5.1\lib\net461\System.Buffers.dll"
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\Portable.BouncyCastle.1.8.10\lib\net40\BouncyCastle.Crypto.dll"
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\MimeKit.2.15.1\lib\net45\MimeKit.dll"
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\MailKit.2.15.0\lib\net45\MailKit.dll"
Write-LogInfo -LogPath $sLogFile -Message "     DLL Adding Complete"

Write-LogInfo -LogPath $sLogFile -Message "     Bulding Notification Email"
$smtpClient = New-Object MailKit.Net.Smtp.SmtpClient
$msgObject = New-Object MimeKit.MimeMessage
$msgBuilder = New-Object MimeKit.BodyBuilder

$messageHeaderHTML = ""
$messageHeaderHTML = $messageHeaderHTML + "<!doctype html><html><head>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "<meta http-equiv=`"Content-Type`" content=`"text/html; charset=us-ascii`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    <meta name=`"viewport`" content=`"width=device-width`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    `r`n"
$messageHeaderHTML = $messageHeaderHTML + "    <title>Simple Transactional Email</title>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    <style>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    /* -------------------------------------`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        INLINED WITH htmlemail.io/inline`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    ------------------------------------- */`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    /* -------------------------------------`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        RESPONSIVE AND MOBILE FRIENDLY STYLES`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    ------------------------------------- */`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    @media only screen and (max-width: 620px) {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] h1 {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-size: 28px !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        margin-bottom: 10px !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] p,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            table[class=body] ul,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            table[class=body] ol,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            table[class=body] td,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            table[class=body] span,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            table[class=body] a {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-size: 16px !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .wrapper,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            table[class=body] .article {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        padding: 10px !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .content {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        padding: 0 !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .container {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        padding: 0 !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        width: 100% !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .main {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        border-left-width: 0 !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        border-radius: 0 !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        border-right-width: 0 !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .btn table {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        width: 100% !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .btn a {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        width: 100% !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      table[class=body] .img-responsive {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        height: auto !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        max-width: 100% !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        width: auto !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    /* -------------------------------------`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        PRESERVE THESE STYLES IN THE HEAD`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    ------------------------------------- */`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    @media all {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      .ExternalClass {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        width: 100%;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      .ExternalClass,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            .ExternalClass p,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            .ExternalClass span,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            .ExternalClass font,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            .ExternalClass td,`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            .ExternalClass div {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        line-height: 100%;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      .apple-link a {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        color: inherit !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-family: inherit !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-size: inherit !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-weight: inherit !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        line-height: inherit !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        text-decoration: none !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      #MessageViewBody a {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        color: inherit;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        text-decoration: none;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-size: inherit;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-family: inherit;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        font-weight: inherit;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        line-height: inherit;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      .btn-primary table td:hover {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        background-color: #34495e !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      .btn-primary a:hover {`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        background-color: #34495e !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        border-color: #34495e !important;`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    }`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    </style>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "  </head>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "  <body class=`"`" style=`"background-color: #f6f6f6; font-family: sans-serif; -webkit-font-smoothing: antialiased; font-size: 14px; line-height: 1.4; margin: 0; padding: 0; -ms-text-size-adjust: 100%; -webkit-text-size-adjust: 100%;`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    <span class=`"preheader`" style=`"color: transparent; display: none; height: 0; max-height: 0; max-width: 0; opacity: 0; overflow: hidden; mso-hide: all; visibility: hidden; width: 0;`">$($BPEnvironment) Database Refresh for $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) Complete</span>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "    <table border=`"0`" cellpadding=`"0`" cellspacing=`"0`" class=`"body`" style=`"border-collapse: separate; mso-table-lspace: 0pt; mso-table-rspace: 0pt; width: 100%; background-color: #f6f6f6;`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "      <tr>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        <td style=`"font-family: sans-serif; font-size: 14px; vertical-align: top;`">&nbsp;</td>`r`n"
$messageHeaderHTML = $messageHeaderHTML + "        <td class=`"container`" style=`"font-family: sans-serif; font-size: 14px; vertical-align: top; display: block; Margin: 0 auto; max-width: 580px; padding: 10px; width: 580px;`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "          <div class=`"content`" style=`"box-sizing: border-box; display: block; Margin: 0 auto; max-width: 580px; padding: 10px;`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            <!-- START CENTERED WHITE CONTAINER -->`r`n"
$messageHeaderHTML = $messageHeaderHTML + "            <table class=`"main`" style=`"border-collapse: separate; mso-table-lspace: 0pt; mso-table-rspace: 0pt; width: 100%; background: #ffffff; border-radius: 3px;`">`r`n"
$messageHeaderHTML = $messageHeaderHTML + "`r`n"

$messageBodyHTML = "              <!-- START MAIN CONTENT AREA -->`r`n"
$messageBodyHTML = $messageBodyHTML + "              <tr>`r`n"
$messageBodyHTML = $messageBodyHTML + "                <td class=`"wrapper`" style=`"font-family: sans-serif; font-size: 14px; vertical-align: top; box-sizing: border-box; padding: 20px;`">`r`n"
$messageBodyHTML = $messageBodyHTML + "                  <table border=`"0`" cellpadding=`"0`" cellspacing=`"0`" style=`"border-collapse: separate; mso-table-lspace: 0pt; mso-table-rspace: 0pt; width: 100%;`">`r`n"
$messageBodyHTML = $messageBodyHTML + "                    <tr>`r`n"
$messageBodyHTML = $messageBodyHTML + "                      <td style=`"font-family: sans-serif; font-size: 14px; vertical-align: top;`">`r`n"
$messageBodyHTML = $messageBodyHTML + "                        <p style=`"font-family: sans-serif; font-size: 14px; font-weight: normal; margin: 0; Margin-bottom: 15px;`">Hello,</p>`r`n"
$messageBodyHTML = $messageBodyHTML + "                        <p style=`"font-family: sans-serif; font-size: 14px; font-weight: normal; margin: 0; Margin-bottom: 15px;`">Restore requested by $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)</p>`r`n"
$messageBodyHTML = $messageBodyHTML + "                        <p style=`"font-family: sans-serif; font-size: 14px; font-weight: normal; margin: 0; Margin-bottom: 15px;`">The Database Refresh of the $($BPEnvironment) Environment has been completed.</p>`r`n"
$messageBodyHTML = $messageBodyHTML + "                      </td>`r`n"
$messageBodyHTML = $messageBodyHTML + "                    </tr>`r`n"
$messageBodyHTML = $messageBodyHTML + "                  </table>`r`n"
$messageBodyHTML = $messageBodyHTML + "                </td>`r`n"
$messageBodyHTML = $messageBodyHTML + "              </tr>`r`n"
$messageBodyHTML = $messageBodyHTML + "            <!-- END MAIN CONTENT AREA -->`r`n"
$messageBodyHTML = $messageBodyHTML + "            </table>`r`n"
$messageBodyHTML = $messageBodyHTML + "`r`n"

$messageFooterHTML = "            <!-- START FOOTER -->`r`n"
$messageFooterHTML = $messageFooterHTML + "            <div class=`"footer`" style=`"clear: both; Margin-top: 10px; text-align: center; width: 100%;`">`r`n"
$messageFooterHTML = $messageFooterHTML + "              <table border=`"0`" cellpadding=`"0`" cellspacing=`"0`" style=`"border-collapse: separate; mso-table-lspace: 0pt; mso-table-rspace: 0pt; width: 100%;`">`r`n"
$messageFooterHTML = $messageFooterHTML + "                <tr>`r`n"
$messageFooterHTML = $messageFooterHTML + "                  <td class=`"content-block`" style=`"font-family: sans-serif; vertical-align: top; padding-bottom: 10px; padding-top: 10px; font-size: 12px; color: #999999; text-align: center;`">`r`n"
$messageFooterHTML = $messageFooterHTML + "                    <span class=`"apple-link`" style=`"color: #999999; font-size: 12px; text-align: center;`">Puyallup School District, 302 2nd ST SE, Puyallup, WA 98372</span>`r`n"
$messageFooterHTML = $messageFooterHTML + "                  </td>`r`n"
$messageFooterHTML = $messageFooterHTML + "                </tr>`r`n"
$messageFooterHTML = $messageFooterHTML + "              </table>`r`n"
$messageFooterHTML = $messageFooterHTML + "            </div>`r`n"
$messageFooterHTML = $messageFooterHTML + "            <!-- END FOOTER -->`r`n"
$messageFooterHTML = $messageFooterHTML + "`r`n"
$messageFooterHTML = $messageFooterHTML + "          <!-- END CENTERED WHITE CONTAINER -->`r`n"
$messageFooterHTML = $messageFooterHTML + "          </div>`r`n"
$messageFooterHTML = $messageFooterHTML + "        </td>`r`n"
$messageFooterHTML = $messageFooterHTML + "        <td style=`"font-family: sans-serif; font-size: 14px; vertical-align: top;`">&nbsp;</td>`r`n"
$messageFooterHTML = $messageFooterHTML + "      </tr>`r`n"
$messageFooterHTML = $messageFooterHTML + "    </table>`r`n"
$messageFooterHTML = $messageFooterHTML + "  </body>`r`n"
$messageFooterHTML = $messageFooterHTML + "</html>`r`n"

$msgBuilder.HtmlBody = $messageHeaderHTML + $messageBodyHTML + $messageFooterHTML
$msgBuilder.TextBody = "The Database Refresh of the $($BPEnvironment) Environment has been completed."
$msgBuilder.Attachments.Add("$($sLogPath)\hpsBPlusDBRestore.log")
Write-LogInfo -LogPath $sLogFile -Message "     Email Notification Successfully Built"
Write-LogInfo -LogPath $sLogFile -Message "     Sending Email to $($notificationEmail)"
$msgObject.From.Add($replyToEmail)
foreach ($addr in $notificationEmail.Split(';')) {
    $msgObject.To.Add($addr)
}
$msgObject.Subject = "$($BPEnvironment) Database Refresh Complete"
$msgObject.Body = $msgBuilder.ToMessageBody()
$smtpClient.Connect($smtpServer, $smtpPort, $False)
$smtpClient.Send($msgObject)
$smtpClient.Disconnect($true)
$smtpClient.Dispose()

Write-LogInfo -LogPath $sLogFile -Message 'Completed Successfully.'


Stop-Log -LogPath $sLogFile

<#


.SYNOPSIS
  This script is designed to refresh the databases for a given BusinessPlus environment.

.DESCRIPTION
 This script is designed to take the necessary steps to prep a BusinessPlus environment to recieve a database refresh.  Once complete it sends a notification out if specified.

.INPUTS
 hpsBPlusDBRestore.ini file must be in the same directory as this script.

.OUTPUTS 
 Log File
 The script log file stored in $PSScriptRoot\hpsBPlusDBRestore.log

.EXAMPLE
 hpsBPlusDBRestore.ps1 -BPEnvironment TEST1 -aspnetFilePath "<backup path>\aspnet_db.bak" -ifasFilePath "<backup path>\ifas_db.bak" -syscatFilePath "<backup path>\syscat_db.bak"
 
 Description
 ---------------------------------------
 Restore TEST1 Environment with no extra accounts left active and no dashboards copied
 
.EXAMPLE
 hpsBPlusDBRestore.ps1 -BPEnvironment TEST1 -aspnetFilePath "<backup path>\aspnet_db.bak" -ifasFilePath "<backup path>\ifas_db.bak" -syscatFilePath "<backup path>\syscat_db.bak" -restoreDashboards
 
 Description
 ---------------------------------------
 Restore TEST1 Environment with dashboard file copy
 
.EXAMPLE
 hpsBPlusDBRestore.ps1 -BPEnvironment TEST1 -aspnetFilePath "<backup path>\aspnet_db.bak" -ifasFilePath "<backup path>\ifas_db.bak" -syscatFilePath "<backup path>\syscat_db.bak" -testingMode
 
 Description
 ---------------------------------------
 Restore TEST1 Environment with extra accounts active for testing
 
.EXAMPLE
  hpsBPlusDBRestore.ps1 -BPEnvironment TEST1 -aspnetFilePath "<backup path>\aspnet_db.bak" -ifasFilePath "<backup path>\ifas_db.bak" -syscatFilePath "<backup path>\syscat_db.bak" -testingMode -restoreDashboards
  
  Description
  ---------------------------------------
  Restore TEST1 Environment with dashboard file copy and extra accounts active for testing

.NOTES
 Version:        1.0
 Author:         Birge, Zachary V.
 Creation Date:  2021-12-01
 Purpose/Change: Initial script development

 Version:        1.1
 Author:         Birge, Zachary V.
 Creation Date:  2023-02-09
 Purpose/Change: Set all DBs to SIMPLE Recovery Mode and Shrink IFAS_LOG file to 8GB or as small as it can go

 Version:        1.2
 Author:         Birge, Zachary V.
 Creation Date:  2023-03-06
 Purpose/Change: Made aspnet DB parameter and all related variables/functions/etc optional

 Version:        1.3
 Author:         Birge, Zachary V.
 Creation Date:  2023-04-17
 Purpose/Change: Added an update of hr_empmstr.e_mail field to set it to the dummy email variable

#>