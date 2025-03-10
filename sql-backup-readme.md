# SQL Server Parallel Backup Script

A powerful PowerShell script for backing up multiple SQL Server databases simultaneously with comprehensive diagnostics and validation.

## Features

- **Parallel Processing**: Back up multiple databases concurrently to improve overall backup time
- **Diagnostic Information**: Detailed logging of all operations and status checks
- **Validation Checks**:
  - SQL Server instance availability
  - Sufficient backup permissions
  - Destination drive existence and space requirements
  - Database accessibility
- **Detailed Reporting**:
  - Database size information
  - Backup progress tracking
  - Execution time metrics
  - Success/failure summary
- **Robust Error Handling**: Comprehensive error management with informative messages

## Requirements

- PowerShell 5.1 or higher
- SQL Server PowerShell module (`SqlServer`)
- Appropriate SQL Server permissions (sysadmin, db_backupoperator, or equivalent)

## Installation

1. Save the script as `Backup-SqlDatabases.ps1` in your preferred location
2. Ensure the SqlServer module is installed:
   ```powershell
   Install-Module -Name SqlServer -Force -AllowClobber
   ```

## Usage

### Basic Usage

```powershell
.\Backup-SqlDatabases.ps1 -SqlInstance "SQLSERVER01" -BackupPath "D:\Backups"
```

This will back up all non-system databases on the specified instance to the destination path.

### Advanced Usage

```powershell
.\Backup-SqlDatabases.ps1 -SqlInstance "SQLSERVER01\INSTANCE1" -BackupPath "D:\Backups" -Databases "DB1","DB2","DB3" -MaxParallel 4
```

### Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| SqlInstance | SQL Server instance name to connect to | Yes | None |
| BackupPath | Local folder path where backups will be stored | Yes | None |
| Databases | Array of database names to backup | No | All non-system databases |
| MaxParallel | Maximum number of parallel backup operations | No | 3 |

## Output

The script provides detailed output including:

- Connection status
- Permission validation
- Drive space information
- Database size details
- Real-time backup progress
- Backup completion status
- Summary statistics

Example output:
```
[2025-03-10 14:30:00] [INFO] Script started at 2025-03-10 14:30:00
[2025-03-10 14:30:00] [INFO] SQL Instance: SQLSERVER01
[2025-03-10 14:30:00] [INFO] Backup Path: D:\Backups
[2025-03-10 14:30:01] [INFO] Destination Drive (D:) Information:
[2025-03-10 14:30:01] [INFO]   - Total Space: 500.00 GB
[2025-03-10 14:30:01] [INFO]   - Used Space: 125.50 GB
[2025-03-10 14:30:01] [INFO]   - Free Space: 374.50 GB (74.90%)
[2025-03-10 14:30:02] [SUCCESS] Successfully connected to SQL Server instance.
[2025-03-10 14:30:02] [SUCCESS] Current user has necessary permissions to perform backups.
...
```

## Backup File Organization

Backups are organized in timestamped folders with the following structure:
```
D:\Backups\
  └── 20250310_143000\
      ├── Database1_20250310_143000.bak
      ├── Database2_20250310_143000.bak
      └── Database3_20250310_143000.bak
```

## Return Value

The script returns an array of PSCustomObjects with details about each database backup operation, including:
- DatabaseName
- BackupPath
- BackupSize
- Duration
- StartTime
- EndTime
- Status

## Error Handling

The script provides detailed error information for any failures, including:
- Connection issues
- Permission problems
- Space constraints
- Backup failures

## Notes

- The script requires Windows authentication to connect to SQL Server
- For large databases, ensure sufficient disk space is available
- The script automatically creates the backup path if it doesn't exist

## License

This script is provided as-is with no warranties. Use at your own risk.

## Author

Created: March 10, 2025
