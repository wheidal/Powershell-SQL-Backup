<#
.SYNOPSIS
    Parallel SQL Server Database Backup Script

.DESCRIPTION
    This script performs parallel backups of multiple SQL Server databases.
    It includes diagnostic information, validation checks, and reporting.

.PARAMETER SqlInstance
    The SQL Server instance name to connect to.

.PARAMETER BackupPath
    The local folder path where backups will be stored.

.PARAMETER Databases
    Array of database names to backup. If not specified, all non-system databases will be backed up.

.PARAMETER MaxParallel
    Maximum number of parallel backup operations. Default is 3.

.EXAMPLE
    .\Backup-SqlDatabases.ps1 -SqlInstance "SQLSERVER01" -BackupPath "D:\Backups"

.EXAMPLE
    .\Backup-SqlDatabases.ps1 -SqlInstance "SQLSERVER01\INSTANCE1" -BackupPath "D:\Backups" -Databases "DB1","DB2","DB3" -MaxParallel 4
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$SqlInstance,
    
    [Parameter(Mandatory = $true)]
    [string]$BackupPath,
    
    [Parameter(Mandatory = $false)]
    [string[]]$Databases,
    
    [Parameter(Mandatory = $false)]
    [int]$MaxParallel = 3
)

# Import SQL Server module
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Error "SqlServer module not found. Install it with: Install-Module -Name SqlServer -Force -AllowClobber"
    exit 1
}
Import-Module SqlServer

# Function to display formatted messages
function Write-FormattedMessage {
    param (
        [string]$Message,
        [string]$Type = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Type) {
        "INFO"  { "White" }
        "ERROR" { "Red" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] [$Type] $Message" -ForegroundColor $color
}

# Script start time
$scriptStartTime = Get-Date
Write-FormattedMessage "Script started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-FormattedMessage "SQL Instance: $SqlInstance"
Write-FormattedMessage "Backup Path: $BackupPath"

# Check if backup path exists
if (-not (Test-Path -Path $BackupPath -PathType Container)) {
    Write-FormattedMessage "Backup path does not exist. Creating directory..." "WARNING"
    try {
        New-Item -Path $BackupPath -ItemType Directory -Force | Out-Null
        Write-FormattedMessage "Backup directory created successfully." "SUCCESS"
    }
    catch {
        Write-FormattedMessage "Failed to create backup directory: $_" "ERROR"
        exit 1
    }
}

# Get destination drive information
$backupDrive = (Get-Item $BackupPath).PSDrive.Name
$driveInfo = Get-PSDrive -Name $backupDrive
$freeSpaceGB = [math]::Round($driveInfo.Free / 1GB, 2)
$totalSpaceGB = [math]::Round(($driveInfo.Free + $driveInfo.Used) / 1GB, 2)
$usedSpaceGB = [math]::Round($driveInfo.Used / 1GB, 2)
$percentFree = [math]::Round(($driveInfo.Free / ($driveInfo.Free + $driveInfo.Used)) * 100, 2)

Write-FormattedMessage "Destination Drive ($backupDrive`:) Information:" "INFO"
Write-FormattedMessage "  - Total Space: $totalSpaceGB GB" "INFO"
Write-FormattedMessage "  - Used Space: $usedSpaceGB GB" "INFO"
Write-FormattedMessage "  - Free Space: $freeSpaceGB GB ($percentFree%)" "INFO"

# Verify SQL Server instance is available
Write-FormattedMessage "Checking SQL Server instance availability..."
try {
    $connectionString = "Data Source=$SqlInstance;Integrated Security=True;Initial Catalog=master;Connect Timeout=5;"
    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()
    if ($connection.State -eq 'Open') {
        Write-FormattedMessage "Successfully connected to SQL Server instance." "SUCCESS"
        # Check for sysadmin or appropriate backup permissions
        $permissionQuery = @"
SELECT 
    CASE 
        WHEN IS_SRVROLEMEMBER('sysadmin') = 1 THEN 1
        WHEN IS_MEMBER('db_backupoperator') = 1 THEN 1
        WHEN HAS_PERMS_BY_NAME(null, null, 'BACKUP DATABASE') = 1 THEN 1
        ELSE 0
    END AS HasBackupPermission
"@
        $command = New-Object System.Data.SqlClient.SqlCommand($permissionQuery, $connection)
        $hasPermission = $command.ExecuteScalar()
        
        if ($hasPermission -eq 1) {
            Write-FormattedMessage "Current user has necessary permissions to perform backups." "SUCCESS"
        }
        else {
            Write-FormattedMessage "Current user does not have necessary permissions to perform backups!" "ERROR"
            $connection.Close()
            exit 1
        }
        $connection.Close()
    }
}
catch {
    Write-FormattedMessage "Failed to connect to SQL Server instance: $_" "ERROR"
    exit 1
}

# Get database list and sizes
Write-FormattedMessage "Retrieving database information..."
try {
    $sqlServerConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
    $sqlServerConnection.ServerInstance = $SqlInstance
    $sqlServerConnection.LoginSecure = $true
    
    $sqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server($sqlServerConnection)
    
    # Get all databases or specified databases
    if ($Databases) {
        $databaseList = $sqlServer.Databases | Where-Object { $Databases -contains $_.Name }
        # Check if all specified databases exist
        $missingDatabases = $Databases | Where-Object { $sqlServer.Databases[$_] -eq $null }
        if ($missingDatabases) {
            Write-FormattedMessage "The following specified databases do not exist: $($missingDatabases -join ', ')" "WARNING"
        }
    }
    else {
        $databaseList = $sqlServer.Databases | Where-Object { -not $_.IsSystemObject }
    }
    
    if ($databaseList.Count -eq 0) {
        Write-FormattedMessage "No databases found to backup!" "ERROR"
        exit 1
    }
    
    # Get database sizes
    $totalSizeGB = 0
    $databaseSizes = @()
    
    foreach ($database in $databaseList) {
        $dbSizeBytes = $database.Size * 1024 * 1024
        $dbSizeGB = [math]::Round($dbSizeBytes / 1GB, 2)
        $totalSizeGB += $dbSizeGB
        
        $databaseSizes += [PSCustomObject]@{
            Name = $database.Name
            SizeGB = $dbSizeGB
        }
    }
    
    # Display database sizes
    Write-FormattedMessage "Found $($databaseList.Count) databases to backup:" "INFO"
    $databaseSizes | ForEach-Object {
        Write-FormattedMessage "  - $($_.Name): $($_.SizeGB) GB" "INFO"
    }
    Write-FormattedMessage "Total size of all databases: $totalSizeGB GB" "INFO"
    
    # Check if there's enough free space
    if ($freeSpaceGB -lt ($totalSizeGB * 1.1)) {
        Write-FormattedMessage "Warning: Free space ($freeSpaceGB GB) may not be sufficient for backing up all databases ($totalSizeGB GB plus overhead)." "WARNING"
    }
    
    # Create a timestamp for backup folder
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFolderPath = Join-Path -Path $BackupPath -ChildPath $timestamp
    New-Item -Path $backupFolderPath -ItemType Directory -Force | Out-Null
    Write-FormattedMessage "Created backup folder: $backupFolderPath" "INFO"

    # Function to perform backup for a single database
    function Backup-Database {
        param (
            [Microsoft.SqlServer.Management.Smo.Database]$Database,
            [string]$BackupFolderPath
        )
        
        $dbName = $Database.Name
        $backupFileName = "$dbName`_$timestamp.bak"
        $backupFilePath = Join-Path -Path $BackupFolderPath -ChildPath $backupFileName
        
        $startTime = Get-Date
        Write-FormattedMessage "Started backup of database: $dbName" "INFO"
        
        try {
            $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
            $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
            $backup.BackupSetDescription = "Full backup of $dbName"
            $backup.BackupSetName = "$dbName backup"
            $backup.Database = $dbName
            $backup.MediaDescription = "Disk"
            $backup.Devices.AddDevice($backupFilePath, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
            $backup.Incremental = $false
            
            # Add progress handler
            $percentCompleteHandler = [Microsoft.SqlServer.Management.Smo.PercentCompleteEventHandler] {
                param($sender, $e)
                if ($e.Percent -eq 100) {
                    Write-FormattedMessage "  Database $dbName backup is 100% complete" "INFO"
                }
            }
            $backup.add_PercentComplete($percentCompleteHandler)
            
            # Execute the backup
            $backup.SqlBackup($sqlServer)
            
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Get file size
            $backupFileInfo = Get-Item $backupFilePath
            $backupSizeGB = [math]::Round($backupFileInfo.Length / 1GB, 2)
            
            Write-FormattedMessage "Completed backup of database: $dbName" "SUCCESS"
            Write-FormattedMessage "  - Duration: $duration seconds" "INFO"
            Write-FormattedMessage "  - Backup size: $backupSizeGB GB" "INFO"
            Write-FormattedMessage "  - Backup file: $backupFilePath" "INFO"
            
            return [PSCustomObject]@{
                DatabaseName = $dbName
                BackupPath = $backupFilePath
                BackupSize = $backupSizeGB
                Duration = $duration
                StartTime = $startTime
                EndTime = $endTime
                Status = "Success"
            }
        }
        catch {
            Write-FormattedMessage "Failed to backup database $dbName : $_" "ERROR"
            return [PSCustomObject]@{
                DatabaseName = $dbName
                BackupPath = $backupFilePath
                BackupSize = 0
                Duration = 0
                StartTime = $startTime
                EndTime = Get-Date
                Status = "Failed: $_"
            }
        }
    }
    
    # Perform parallel backups
    Write-FormattedMessage "Starting parallel backup of $($databaseList.Count) databases with maximum $MaxParallel concurrent operations..." "INFO"
    
    $backupResults = @()
    $throttleLimit = $MaxParallel
    
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $throttleLimit)
    $runspacePool.Open()
    
    $runspaces = @()
    
    foreach ($database in $databaseList) {
        $scriptBlock = {
            param($database, $backupFolderPath, $timestamp, $sqlInstance)
            
            # Need to re-establish connection in this runspace
            Import-Module SqlServer
            
            $sqlServerConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection
            $sqlServerConnection.ServerInstance = $sqlInstance
            $sqlServerConnection.LoginSecure = $true
            
            $sqlServer = New-Object Microsoft.SqlServer.Management.Smo.Server($sqlServerConnection)
            $db = $sqlServer.Databases[$database.Name]
            
            $dbName = $db.Name
            $backupFileName = "$dbName`_$timestamp.bak"
            $backupFilePath = Join-Path -Path $backupFolderPath -ChildPath $backupFileName
            
            $startTime = Get-Date
            
            try {
                $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
                $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
                $backup.BackupSetDescription = "Full backup of $dbName"
                $backup.BackupSetName = "$dbName backup"
                $backup.Database = $dbName
                $backup.MediaDescription = "Disk"
                $backup.Devices.AddDevice($backupFilePath, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
                $backup.Incremental = $false
                
                # Execute the backup
                $backup.SqlBackup($sqlServer)
                
                $endTime = Get-Date
                $duration = ($endTime - $startTime).TotalSeconds
                
                # Get file size
                $backupFileInfo = Get-Item $backupFilePath
                $backupSizeGB = [math]::Round($backupFileInfo.Length / 1GB, 2)
                
                return [PSCustomObject]@{
                    DatabaseName = $dbName
                    BackupPath = $backupFilePath
                    BackupSize = $backupSizeGB
                    Duration = $duration
                    StartTime = $startTime
                    EndTime = $endTime
                    Status = "Success"
                }
            }
            catch {
                return [PSCustomObject]@{
                    DatabaseName = $dbName
                    BackupPath = $backupFilePath
                    BackupSize = 0
                    Duration = 0
                    StartTime = $startTime
                    EndTime = Get-Date
                    Status = "Failed: $_"
                }
            }
        }
        
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddParameter("database", $database).AddParameter("backupFolderPath", $backupFolderPath).AddParameter("timestamp", $timestamp).AddParameter("sqlInstance", $SqlInstance)
        $powershell.RunspacePool = $runspacePool
        
        $runspaces += [PSCustomObject]@{
            Powershell = $powershell
            AsyncResult = $powershell.BeginInvoke()
            Database = $database.Name
        }
    }
    
    # Wait for all runspaces to complete and collect results
    while ($runspaces.AsyncResult | Where-Object { -not $_.IsCompleted }) {
        Start-Sleep -Milliseconds 500
        
        # Show which databases are still being processed
        $inProgress = $runspaces | Where-Object { -not $_.AsyncResult.IsCompleted } | Select-Object -ExpandProperty Database
        if ($inProgress.Count -gt 0) {
            Write-FormattedMessage "Still processing databases: $($inProgress -join ', ')" "INFO"
        }
    }
    
    # Collect all results
    foreach ($runspace in $runspaces) {
        $result = $runspace.Powershell.EndInvoke($runspace.AsyncResult)
        $backupResults += $result
        $runspace.Powershell.Dispose()
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    # Display summary
    $successCount = ($backupResults | Where-Object { $_.Status -like "Success*" }).Count
    $failedCount = ($backupResults | Where-Object { $_.Status -like "Failed*" }).Count
    $totalBackupSizeGB = ($backupResults | Measure-Object -Property BackupSize -Sum).Sum
    
    Write-FormattedMessage "Backup operations completed." "INFO"
    Write-FormattedMessage "Summary:" "INFO"
    Write-FormattedMessage "  - Total databases processed: $($backupResults.Count)" "INFO"
    Write-FormattedMessage "  - Successful backups: $successCount" "INFO"
    if ($failedCount -gt 0) {
        Write-FormattedMessage "  - Failed backups: $failedCount" "ERROR"
        $backupResults | Where-Object { $_.Status -like "Failed*" } | ForEach-Object {
            Write-FormattedMessage "    - $($_.DatabaseName): $($_.Status)" "ERROR"
        }
    }
    Write-FormattedMessage "  - Total backup size: $totalBackupSizeGB GB" "INFO"
    
    $scriptEndTime = Get-Date
    $scriptDuration = ($scriptEndTime - $scriptStartTime).TotalMinutes
    
    Write-FormattedMessage "Script completed in $([math]::Round($scriptDuration, 2)) minutes." "SUCCESS"
    Write-FormattedMessage "Backup folder: $backupFolderPath" "INFO"
    
    # Return results object
    return $backupResults
}
catch {
    Write-FormattedMessage "An error occurred during script execution: $_" "ERROR"
    exit 1
}
