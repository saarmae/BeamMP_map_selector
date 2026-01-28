@echo off
setlocal

set "_marker=###EMBEDDED_POWERSHELL###"
set "_temp=%TEMP%\map_selector_embedded_%RANDOM%.ps1"

for /f "delims=: tokens=1" %%L in ('findstr /n "^%_marker%" "%~f0"') do set "_line=%%L"
if not defined _line (
    echo Could not locate embedded PowerShell payload.
    exit /b 1
)
more +%_line% "%~f0" > "%_temp%"

set "_root=%~dp0"
if "%_root:~-1%"=="\" set "_root=%_root:~0,-1%"
if "%_root:~-1%"=="/" set "_root=%_root:~0,-1%"

set "_debugEnabled=0"
if defined MAP_SELECTOR_DEBUG (
    if /I not "%MAP_SELECTOR_DEBUG%"=="0" (
        set "_debugEnabled=1"
    )
)

:parseArgs
if "%~1"=="" goto :afterParse
if /i "%~1"=="--zip" (
    if "%~2"=="" (
        echo --zip expects a value.
        exit /b 1
    )
    set "_zipArg=%~2"
    shift
    shift
    goto :parseArgs
)
if /i "%~1"=="--map" (
    if "%~2"=="" (
        echo --map expects a value.
        exit /b 1
    )
    set "_mapArg=%~2"
    shift
    shift
    goto :parseArgs
)
if /i "%~1"=="--random" (
    set "_randomArg=1"
    shift
    goto :parseArgs
)
if /i "%~1"=="--help" (
    set "_helpArg=1"
    shift
    goto :parseArgs
)
if /i "%~1"=="--stock" (
    if "%~2"=="" (
        echo --stock expects a value.
        exit /b 1
    )
    set "_stockArg=%~2"
    shift
    shift
    goto :parseArgs
)
echo Unknown argument: %1
exit /b 1

:afterParse
if not defined _zipArg set "_zipArg="
if not defined _mapArg set "_mapArg="
if not defined _randomArg set "_randomArg=0"
if not defined _helpArg set "_helpArg=0"
if not defined _stockArg set "_stockArg="

set "_psSwitches="
if "%_randomArg%"=="1" set "_psSwitches=%_psSwitches% -RandomMode"
if "%_helpArg%"=="1" set "_psSwitches=%_psSwitches% -ShowHelp"
if "%_debugEnabled%"=="1" set "_psSwitches=%_psSwitches% -DebugMode"

powershell -NoProfile -ExecutionPolicy Bypass -File "%_temp%" -RepoRoot "%_root%" -ZipName "%_zipArg%" -MapName "%_mapArg%" -StockName "%_stockArg%"%_psSwitches%
set "_code=%ERRORLEVEL%"
if "%_debugEnabled%"=="1" (
    echo MAP_SELECTOR_DEBUG is set; preserved temporary PowerShell script at "%_temp%"
) else (
    del "%_temp%" >nul 2>&1
)
exit /b %_code%

###EMBEDDED_POWERSHELL###
param(
    [string]$RepoRoot,
    [string]$ZipName,
    [string]$MapName,
    [string]$StockName,
    [switch]$RandomMode,
    [switch]$ShowHelp,
    [switch]$DebugMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$RepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)

$resourcesClient = Join-Path $RepoRoot 'Resources\Client'
$mapFilesDir = Join-Path $RepoRoot 'map_files'
$serverExe = Join-Path $RepoRoot 'BeamMP-Server.exe'
$configFile = Join-Path $RepoRoot 'ServerConfig.toml'
$configBackupDir = Join-Path $RepoRoot 'config_backups'
$logFile = Join-Path $RepoRoot 'map_selector.log'
$logMaxBytes = 524288

try {
    if (-not (Test-Path $logFile)) {
        New-Item -ItemType File -Path $logFile -Force | Out-Null
    }
} catch {
    # Logging is best-effort; continue even if file creation fails.
}

$stockMaps = @(
    [pscustomobject]@{ Name = 'gridmap_v2';           Label = 'Gridmap v2';             Path = '/levels/gridmap_v2/info.json' }
    [pscustomobject]@{ Name = 'johnson_valley';        Label = 'Johnson Valley';          Path = '/levels/johnson_valley/info.json' }
    [pscustomobject]@{ Name = 'automation_test_track'; Label = 'Automation Test Track';   Path = '/levels/automation_test_track/info.json' }
    [pscustomobject]@{ Name = 'east_coast_usa';        Label = 'East Coast USA';          Path = '/levels/east_coast_usa/info.json' }
    [pscustomobject]@{ Name = 'hirochi_raceway';       Label = 'Hirochi Raceway';         Path = '/levels/hirochi_raceway/info.json' }
    [pscustomobject]@{ Name = 'italy';                 Label = 'Italy';                   Path = '/levels/italy/info.json' }
    [pscustomobject]@{ Name = 'jungle_rock_island';    Label = 'Jungle Rock Island';      Path = '/levels/jungle_rock_island/info.json' }
    [pscustomobject]@{ Name = 'industrial';            Label = 'Industrial Site';         Path = '/levels/industrial/info.json' }
    [pscustomobject]@{ Name = 'small_island';          Label = 'Small Island';            Path = '/levels/small_island/info.json' }
    [pscustomobject]@{ Name = 'smallgrid';             Label = 'Small Grid';              Path = '/levels/smallgrid/info.json' }
    [pscustomobject]@{ Name = 'utah';                  Label = 'Utah';                    Path = '/levels/utah/info.json' }
    [pscustomobject]@{ Name = 'west_coast_usa';        Label = 'West Coast USA';          Path = '/levels/west_coast_usa/info.json' }
    [pscustomobject]@{ Name = 'driver_training';       Label = 'Driver Training';         Path = '/levels/driver_training/info.json' }
    [pscustomobject]@{ Name = 'derby';                 Label = 'Derby';                   Path = '/levels/derby/info.json' }
)
$stockMapLookup = [System.Collections.Generic.Dictionary[string,object]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($map in $stockMaps) { $stockMapLookup[$map.Name] = $map }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$ZipName = if ([string]::IsNullOrWhiteSpace($ZipName)) { $null } else { $ZipName }
$MapName = if ([string]::IsNullOrWhiteSpace($MapName)) { $null } else { $MapName }
$StockName = if ([string]::IsNullOrWhiteSpace($StockName)) { $null } else { $StockName }
$logLock = New-Object object
$script:MapZipNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Write-Log {
    param([string]$Message)
    if (-not $Message) { return }
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$timestamp] $Message"
    try {
        [System.Threading.Monitor]::Enter($logLock)
        Add-Content -Path $logFile -Value $line -Encoding UTF8
        Enforce-LogSizeLimit -Path $logFile -MaxBytes $logMaxBytes
    } catch {
        # ignore logging failures
    } finally {
        [System.Threading.Monitor]::Exit($logLock)
    }
}

function Enforce-LogSizeLimit {
    param(
        [string]$Path,
        [int]$MaxBytes
    )

    if (-not $Path -or $MaxBytes -le 0) { return }
    try {
        if (-not (Test-Path $Path)) { return }
        $info = Get-Item -Path $Path -ErrorAction Stop
        if ($info.Length -le $MaxBytes) { return }

        $bytes = [System.IO.File]::ReadAllBytes($Path)
        if ($bytes.Length -le $MaxBytes) { return }

        $cut = $bytes.Length - $MaxBytes
        $trimmed = [System.Text.Encoding]::UTF8.GetString($bytes, $cut, $MaxBytes)
        [System.IO.File]::WriteAllText($Path, $trimmed, [System.Text.Encoding]::UTF8)

        $notice = "[{0}] Log truncated to maintain {1} byte limit" -f ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')), $MaxBytes
        Add-Content -Path $Path -Value $notice -Encoding UTF8
    } catch {
        Write-Warning "Failed to enforce log size limit: $($_.Exception.Message)"
    }
}

function Write-Usage {
    @'
BeamMP Map Selector (console version)

Usage:
  map_selector.bat                # Interactive mode
  map_selector.bat --zip <zip> [--map <mapFolder>]
  map_selector.bat --random
  map_selector.bat --stock <stockMapName>

Options:
  --zip <zipfile>    Choose the given zip (case-insensitive) automatically.
  --map <folder>     When a zip has multiple maps, pick this folder.
  --random           Pick a random zip and random map without prompting.
  --stock <name>     Activate a built-in BeamNG map (e.g., gridmap_v2, italy).
  --help             Show this message.

If a chosen zip contains exactly one map, --map is optional.
'@ | Write-Host
}


function Get-StockMapByName {
    param([string]$Name)
    if (-not $Name) { return $null }
    if ($stockMapLookup.ContainsKey($Name)) { return $stockMapLookup[$Name] }
    return $null
}



$zipLabel = if ($ZipName) { $ZipName } else { '<none>' }
$mapLabel = if ($MapName) { $MapName } else { '<none>' }
$stockLabel = if ($StockName) { $StockName } else { '<none>' }
$modeLabel = if ($RandomMode -or $ZipName -or $StockName) { 'NonInteractive' } else { 'Interactive' }

if ($StockName -and ($ZipName -or $RandomMode -or $MapName)) {
    Write-Error '--stock cannot be combined with --zip, --map, or --random.'
    exit 9
}

Write-Log "Session start (Mode=$modeLabel, Zip=$zipLabel, Map=$mapLabel, Stock=$stockLabel, Random=$RandomMode, Debug=$DebugMode)"
if ($DebugMode) {
    Write-Host 'Debug mode enabled. Temporary PowerShell file preserved by MAP_SELECTOR_DEBUG.' -ForegroundColor DarkYellow
    Write-Log 'Debug mode enabled via MAP_SELECTOR_DEBUG.'
}


function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-ZipMapInfo {
    param(
        [string]$ZipPath,
        [string]$Area
    )

    $obj = [PSCustomObject]@{
        Name       = [System.IO.Path]::GetFileName($ZipPath)
        FullPath   = $ZipPath
        Area       = $Area
        MapFolders = @()
        IsMap      = $false
        Error      = $null
    }

    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    } catch {
        $obj.Error = $_.Exception.Message
        Write-Log "Failed to open zip $($obj.Name): $($obj.Error)"
        return $obj
    }

    try {
        $folders = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $zip.Entries) {
            $normalized = $entry.FullName -replace '\\','/'
            if ($normalized -match '^levels/([^/]+)/info\.json$') {
                [void]$folders.Add($matches[1])
            }
        }
        if ($folders.Count -gt 0) {
            $obj.MapFolders = @($folders | Sort-Object)
            $obj.IsMap = $true
        }
    } finally {
        $zip.Dispose()
    }

    return $obj
}

function Get-MapZips {
    Ensure-Dir $resourcesClient
    Ensure-Dir $mapFilesDir

    Write-Log "Scanning for map zips in $resourcesClient and $mapFilesDir"

    $results = New-Object System.Collections.Generic.List[object]
    $sources = @(
        @{ Path = $resourcesClient; Area = 'Resources' },
        @{ Path = $mapFilesDir;     Area = 'MapFiles'  }
    )

    foreach ($src in $sources) {
        if (-not (Test-Path $src.Path)) { continue }
        Get-ChildItem -Path $src.Path -Filter '*.zip' -File -ErrorAction SilentlyContinue | ForEach-Object {
            $info = Get-ZipMapInfo -ZipPath $_.FullName -Area $src.Area
            if ($info.Error) {
                Write-Warning "Failed to inspect $($info.Name): $($info.Error). Treating as non-map."
                Write-Log "Zip inspection failed for $($info.Name): $($info.Error)"
            }
            $results.Add($info)
        }
    }

    foreach ($info in $results) {
        if ($info.IsMap -and $info.Area -eq 'Resources') {
            $dest = Join-Path $mapFilesDir $info.Name
            try {
                Move-Item -Path $info.FullPath -Destination $dest -Force
                $info.FullPath = $dest
                $info.Area = 'MapFiles'
            } catch {
                Write-Warning "Unable to move $($info.Name) to map_files: $($_.Exception.Message)"
                Write-Log "Unable to move $($info.Name) to map_files: $($_.Exception.Message)"
            }
        } elseif (-not $info.IsMap -and $info.Area -eq 'MapFiles') {
            $dest = Join-Path $resourcesClient $info.Name
            try {
                Move-Item -Path $info.FullPath -Destination $dest -Force
                $info.FullPath = $dest
                $info.Area = 'Resources'
            } catch {
                Write-Warning "Unable to move $($info.Name) back to Resources\\Client: $($_.Exception.Message)"
                Write-Log "Unable to move $($info.Name) back to Resources\\Client: $($_.Exception.Message)"
            }
        }
    }

    $mapList = New-Object System.Collections.Generic.List[object]
    foreach ($info in $results | Where-Object { $_.IsMap }) {
        $mapList.Add($info)
    }
    if (-not $script:MapZipNameSet) {
        $script:MapZipNameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    } else {
        $script:MapZipNameSet.Clear()
    }
    foreach ($info in $mapList) {
        [void]$script:MapZipNameSet.Add($info.Name)
    }
    $mapCount = $mapList.Count
    $generalCount = $results.Count - $mapCount
    Write-Log "Scan complete: $mapCount map zip(s), $generalCount general zip(s)"
    return $mapList
}

function Build-MainOptions {
    param([System.Collections.Generic.List[object]]$MapZips)

    $list = New-Object System.Collections.Generic.List[object]
    $list.Add([pscustomobject]@{ Label = '????  Random map'; Kind = 'Random' })
    foreach ($zip in $MapZips | Sort-Object Name) {
        $count = $zip.MapFolders.Count
        $label = "{0}  ({1} map{2})" -f $zip.Name, $count, $(if ($count -eq 1) { '' } else { 's' })
        $list.Add([pscustomobject]@{ Label = $label; Kind = 'Zip'; Zip = $zip })
    }
    $list.Add([pscustomobject]@{ Label = 'Stock maps (built-in BeamNG levels)'; Kind = 'Stock' })
    $list.Add([pscustomobject]@{ Label = '???  Rescan map directories'; Kind = 'Rescan' })
    $list.Add([pscustomobject]@{ Label = 'Exit map selector'; Kind = 'Exit' })
    return $list
}

function Build-MapOptions {
    param([System.Collections.IEnumerable]$MapFolders)

    $list = New-Object System.Collections.Generic.List[object]
    foreach ($map in $MapFolders) {
        $list.Add([pscustomobject]@{ Label = "/levels/$map/info.json"; Kind = 'Map'; Map = $map })
    }
    $list.Add([pscustomobject]@{ Label = '???  Back to map files'; Kind = 'Back' })
    return $list
}


function Build-StockOptions {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($map in $stockMaps) {
        $label = "{0}  ({1})" -f $map.Label, $map.Path
        $list.Add([pscustomobject]@{ Label = $label; Kind = 'StockMap'; Map = $map })
    }
    $list.Add([pscustomobject]@{ Label = '???  Back to map files'; Kind = 'Back' })
    return $list
}

function Invoke-Menu {
    param(
        [string]$Title,
        [System.Collections.Generic.List[object]]$Options,
        [string]$Footer = 'Use Arrow keys / PageUp / PageDown / Home / End. Enter = select, Esc = cancel.'
    )

    if (-not $Options -or $Options.Count -eq 0) { return $null }
    $index = 0
    while ($true) {
        Clear-Host
        Write-Host $Title -ForegroundColor Yellow
        Write-Host ''
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $label = $Options[$i].Label
            if ($i -eq $index) {
                Write-Host ("> $label") -ForegroundColor Cyan
            } else {
                Write-Host ("  $label")
            }
        }
        Write-Host ''
        Write-Host $Footer -ForegroundColor DarkGray

        $key = [System.Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow'   { $index = [Math]::Max(0, $index - 1) }
            'DownArrow' { $index = [Math]::Min($Options.Count - 1, $index + 1) }
            'PageUp'    { $index = [Math]::Max(0, $index - 10) }
            'PageDown'  { $index = [Math]::Min($Options.Count - 1, $index + 10) }
            'Home'      { $index = 0 }
            'End'       { $index = $Options.Count - 1 }
            'Escape'    { return $null }
            'Enter'     { return $Options[$index] }
        }
    }
}

function Get-SecureRandomInt {
    param([int]$MaxExclusive)
    if ($MaxExclusive -le 0) { throw "Invalid max value for RNG." }

    $bytes = New-Object byte[] 4
    $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$MaxExclusive)
    do {
        $script:Rng.GetBytes($bytes)
        $value = [BitConverter]::ToUInt32($bytes, 0)
    } while ($value -ge $limit)
    return [int]($value % $MaxExclusive)
}

function Get-SecureRandomItem {
    param([System.Collections.IList]$Items)
    if (-not $Items -or $Items.Count -eq 0) { return $null }
    $idx = Get-SecureRandomInt -MaxExclusive $Items.Count
    return $Items[$idx]
}

function Invoke-NonInteractiveRun {
    param(
        [string]$ZipName,
        [string]$MapName,
        [string]$StockName,
        [switch]$RandomMode,
        [System.Collections.Generic.List[object]]$MapZips
    )

    Write-Log "Non-interactive run start. Random=$RandomMode, Zip=$ZipName, Map=$MapName, Stock=$StockName"

    if ($StockName) {
        $stockMap = Get-StockMapByName -Name $StockName
        if (-not $stockMap) {
            $validNames = ($stockMaps | Select-Object -ExpandProperty Name) -join ', '
            Write-Error "Stock map '$StockName' not recognized. Options: $validNames"
            exit 7
        }
        Activate-StockMap -StockMap $stockMap
        Write-Log 'Non-interactive stock activation complete'
        Write-Host 'Selection complete.' -ForegroundColor Green
        return
    }

    if (-not $MapZips -or $MapZips.Count -eq 0) {
        Write-Error 'No map zips available.'
        exit 2
    }

    $zipInfo = $null
    $selectedMap = $null

    if ($RandomMode) {
        $zipInfo = Get-SecureRandomItem $MapZips
        $selectedMap = Get-SecureRandomItem (@($zipInfo.MapFolders))
        Write-Log "Random selection chose $($zipInfo.Name) -> $selectedMap"
    } else {
        if (-not $ZipName) {
            Write-Error '--zip is required unless --random is supplied.'
            exit 6
        }
        $zipInfo = $MapZips | Where-Object { $_.Name -ieq $ZipName } | Select-Object -First 1
        if (-not $zipInfo) {
            Write-Error "Zip '$ZipName' not found."
            exit 3
        }
        Write-Log "Matched zip $($zipInfo.Name) with $($zipInfo.MapFolders.Count) map(s)"
        if ($MapName) {
            $selectedMap = $zipInfo.MapFolders | Where-Object { $_ -ieq $MapName } | Select-Object -First 1
            if (-not $selectedMap) {
                Write-Error "Map '$MapName' not found inside $($zipInfo.Name). Available: $($zipInfo.MapFolders -join ', ')"
                exit 4
            }
            Write-Log "Requested map parameter resolved to $selectedMap"
        } elseif ($zipInfo.MapFolders.Count -eq 1) {
            $selectedMap = $zipInfo.MapFolders[0]
            Write-Log "Zip $($zipInfo.Name) has a single map; defaulting to $selectedMap"
        } else {
            Write-Error "Zip $($zipInfo.Name) contains multiple maps. Specify one via --map <name>. Options: $($zipInfo.MapFolders -join ', ')"
            exit 5
        }
    }

    Write-Log "Activating selection from non-interactive path: $($zipInfo.Name) -> $selectedMap"
    Activate-Selection -ZipInfo $zipInfo -MapFolder $selectedMap
    Write-Log 'Non-interactive activation complete'
    Write-Host 'Selection complete.' -ForegroundColor Green
}

function Prune-ConfigBackups {
    param([int]$MaxCount = 20)

    if ($MaxCount -le 0) { return }
    try {
        if (-not (Test-Path $configBackupDir)) { return }
        $backups = @(Get-ChildItem -Path $configBackupDir -Filter 'ServerConfig.*.bak' -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending)
        if ($backups.Count -eq 0) { return }
        if ($backups.Count -le $MaxCount) { return }
        $toRemove = $backups | Select-Object -Skip $MaxCount
        foreach ($backup in $toRemove) {
            try {
                Remove-Item -Path $backup.FullName -Force
                Write-Log "Pruned old config backup $($backup.Name)"
            } catch {
                Write-Warning "Failed to delete backup $($backup.FullName): $($_.Exception.Message)"
                Write-Log "Failed to delete backup $($backup.Name): $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Warning "Unable to enumerate config backups: $($_.Exception.Message)"
        Write-Log "Unable to enumerate config backups: $($_.Exception.Message)"
    }
}

function Update-ServerConfig {
    param(
        [string]$MapFolder,
        [string]$MapPath
    )

    if (-not (Test-Path $configFile)) {
        Write-Warning "ServerConfig.toml not found at $configFile. Skipping config update."
        return
    }

    Ensure-Dir $configBackupDir
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupName = "ServerConfig.$timestamp.bak"
    $backup = Join-Path $configBackupDir $backupName
    Copy-Item -Path $configFile -Destination $backup -Force
    Write-Log "Created backup $backupName in config_backups"

    $content = Get-Content -Path $configFile -Raw -Encoding UTF8
    if (-not $MapPath) {
        if (-not $MapFolder) { throw 'MapFolder or MapPath is required.' }
        $MapPath = "/levels/$MapFolder/info.json"
    }
    $mapLine = "Map = `"$MapPath`""
    $mapRegex = New-Object System.Text.RegularExpressions.Regex('^[ \t]*Map\s*=.*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($mapRegex.IsMatch($content)) {
        $content = $mapRegex.Replace($content, $mapLine, 1)
        Write-Host "Updated existing Map line." -ForegroundColor Gray
    } else {
        $playersRegex = New-Object System.Text.RegularExpressions.Regex('^[ \t]*MaxPlayers\s*=.*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        if ($playersRegex.IsMatch($content)) {
            $content = $playersRegex.Replace($content, { param($m) ($m.Value + [Environment]::NewLine + $mapLine) }, 1)
            Write-Host "Inserted Map line after MaxPlayers." -ForegroundColor Gray
        } else {
            $content += [Environment]::NewLine + $mapLine + [Environment]::NewLine
            Write-Host "Appended Map line to end of file." -ForegroundColor Gray
        }
    }

    Set-Content -Path $configFile -Value $content -Encoding UTF8
    Write-Host "Backed up config to $backup and set map." -ForegroundColor Green
    Write-Log "Updated ServerConfig.toml with map $MapPath"
    Prune-ConfigBackups -MaxCount 20
    return $MapPath
}

function Stop-ServerProcesses {
    $procs = Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue
    $procList = @()
    if ($procs) { $procList = @($procs) }
    if ($procList.Count -gt 0) {
        Write-Host "Stopping BeamMP-Server (process count: $($procList.Count))." -ForegroundColor Yellow
        Write-Log "Stopping $($procList.Count) BeamMP-Server process(es)"
        foreach ($proc in $procList) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            } catch {
                Write-Warning "Failed to stop process Id $($proc.Id): $($_.Exception.Message)"
                Write-Log "Failed to stop process $($proc.Id): $($_.Exception.Message)"
            }
        }
        Start-Sleep -Seconds 1
        return $true
    }

    Write-Host "No running BeamMP-Server process detected." -ForegroundColor DarkGray
    Write-Log 'No running BeamMP-Server process detected'
    return $false
}

function Start-ServerProcess {
    if (Test-Path $serverExe) {
        Write-Host "Starting BeamMP-Server..." -ForegroundColor Yellow
        Write-Log 'Starting BeamMP-Server.exe'
        try {
            Start-Process -FilePath $serverExe -WorkingDirectory $RepoRoot | Out-Null
            Write-Host "Server launched." -ForegroundColor Green
            Write-Log 'BeamMP-Server.exe launched'
            return $true
        } catch {
            Write-Warning "Failed to start BeamMP-Server.exe: $($_.Exception.Message)"
            Write-Log "Failed to start BeamMP-Server.exe: $($_.Exception.Message)"
            return $false
        }
    }

    Write-Warning "BeamMP-Server.exe not found at $serverExe"
    Write-Log "BeamMP-Server.exe not found at $serverExe"
    return $false
}

function Move-OtherMapZips {
    param([string]$ActiveZipName)

    Ensure-Dir $resourcesClient
    Ensure-Dir $mapFilesDir

    if (-not $script:MapZipNameSet -or $script:MapZipNameSet.Count -eq 0) {
        [void](Get-MapZips)
    }

    $existingZips = Get-ChildItem -Path $resourcesClient -Filter '*.zip' -File -ErrorAction SilentlyContinue
    foreach ($zip in $existingZips) {
        if ($ActiveZipName -and $zip.Name -ieq $ActiveZipName) { continue }

        $isMapZip = $false
        if ($script:MapZipNameSet -and $script:MapZipNameSet.Contains($zip.Name)) {
            $isMapZip = $true
        } else {
            $scanInfo = Get-ZipMapInfo -ZipPath $zip.FullName -Area 'Resources'
            $isMapZip = $scanInfo.IsMap
            if ($isMapZip -and $script:MapZipNameSet) {
                [void]$script:MapZipNameSet.Add($zip.Name)
            }
        }

        if (-not $isMapZip) {
            Write-Log "Leaving general mod zip $($zip.Name) in Resources\\Client"
            continue
        }

        try {
            Move-Item -Path $zip.FullName -Destination (Join-Path $mapFilesDir $zip.Name) -Force
            Write-Log "Moved inactive map zip $($zip.Name) to map_files"
        } catch {
            Write-Warning "Failed to move inactive map $($zip.Name) to map_files: $($_.Exception.Message)"
            Write-Log "Failed to move inactive map $($zip.Name): $($_.Exception.Message)"
        }
    }
}

function Activate-Selection {
    param(
        [pscustomobject]$ZipInfo,
        [string]$MapFolder
    )

    Write-Host "`nActivating $($ZipInfo.Name) -> $MapFolder" -ForegroundColor Green
    Write-Log "Activating selection: $($ZipInfo.Name) -> $MapFolder"

    $targetPath = Join-Path $resourcesClient $ZipInfo.Name

    Stop-ServerProcesses | Out-Null
    Move-OtherMapZips -ActiveZipName $ZipInfo.Name

    $sourceCandidates = @(
        (Join-Path $mapFilesDir $ZipInfo.Name)
        (Join-Path $resourcesClient $ZipInfo.Name)
        $ZipInfo.FullPath
    )
    $sourcePath = $sourceCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($sourcePath -and ($sourcePath -ne $targetPath)) {
        try {
            Move-Item -Path $sourcePath -Destination $targetPath -Force
            Write-Log "Moved $($ZipInfo.Name) into Resources\\Client"
        } catch {
            Write-Warning "Failed to move $($ZipInfo.Name) into Resources\\Client: $($_.Exception.Message)"
            Write-Log "Failed to move $($ZipInfo.Name) into Resources\\Client: $($_.Exception.Message)"
        }
    } elseif (-not $sourcePath) {
        Write-Log "Zip $($ZipInfo.Name) was not found at expected locations; continuing with path $targetPath"
    } else {
        Write-Log "Zip $($ZipInfo.Name) already resides in Resources\\Client"
    }

    $mapPath = Update-ServerConfig -MapFolder $MapFolder
    Start-ServerProcess | Out-Null

    Write-Host "`nNow running: $($ZipInfo.Name)  ->  $mapPath" -ForegroundColor Cyan
    Write-Log "Activation finished: $($ZipInfo.Name) -> $mapPath"
}


function Activate-StockMap {
    param([pscustomobject]$StockMap)

    if (-not $StockMap) {
        throw 'Stock map data missing.'
    }

    Write-Host "`nActivating stock map: $($StockMap.Label)" -ForegroundColor Green
    Write-Log "Activating stock map: $($StockMap.Label) -> $($StockMap.Path)"

    Stop-ServerProcesses | Out-Null
    Move-OtherMapZips

    $mapPath = Update-ServerConfig -MapPath $StockMap.Path
    Start-ServerProcess | Out-Null

    Write-Host "`nNow running stock map: $($StockMap.Path)" -ForegroundColor Cyan
    Write-Log "Stock map activation finished: $($StockMap.Path)"
}

function Wait-ForMapFiles {
    Write-Host ''
    Write-Host 'No map zip files were found.' -ForegroundColor Yellow
    Write-Host 'Place map zips in map_files or Resources\Client, then press Enter to rescan (Esc to quit).' -ForegroundColor DarkGray
    Write-Log 'No map zips found; awaiting user input to rescan or exit'
    $key = [System.Console]::ReadKey($true)
    if ($key.Key -eq 'Escape') {
        Write-Log 'User exited without adding map zips'
        return $false
    }
    Write-Log 'User requested rescan after adding map zips'
    return $true
}

function Invoke-MainLoop {
    while ($true) {
        $mapZips = Get-MapZips
        if (-not $mapZips -or $mapZips.Count -eq 0) {
            if (-not (Wait-ForMapFiles)) { return }
            else { continue }
        }

        Write-Log "Main menu ready with $($mapZips.Count) map zip(s)"
        $options = Build-MainOptions -MapZips $mapZips
        $selection = Invoke-Menu -Title 'Select a map file' -Options $options
        if (-not $selection) { return }

        switch ($selection.Kind) {
            'Exit'   { Write-Log 'User selected Exit from main menu'; return }
            'Rescan' { Write-Log 'User requested rescan from main menu'; continue }
            'Random' {
                $zipInfo = Get-SecureRandomItem $mapZips
                $mapName = Get-SecureRandomItem $zipInfo.MapFolders
                Write-Log "Interactive random selection chose $($zipInfo.Name) -> $mapName"
                Activate-Selection -ZipInfo $zipInfo -MapFolder $mapName
            }
            'Stock' {
                $stockOptions = Build-StockOptions
                $stockChoice = Invoke-Menu -Title 'Select a built-in BeamNG map' -Options $stockOptions -Footer 'Use arrows to pick a stock map, Enter to select, Esc to go back.'
                if (-not $stockChoice) { continue }
                if ($stockChoice.Kind -eq 'Back') { Write-Log 'User returned from stock map menu'; continue }
                Write-Log "Interactive stock selection chose $($stockChoice.Map.Label)"
                Activate-StockMap -StockMap $stockChoice.Map
            }
            'Zip' {
                $zipInfo = $selection.Zip
                $mapName = $null
                if ($zipInfo.MapFolders.Count -le 1) {
                    $mapName = $zipInfo.MapFolders[0]
                } else {
                    $mapOptions = Build-MapOptions -MapFolders $zipInfo.MapFolders
                    $mapChoice = Invoke-Menu -Title "Select a map inside $($zipInfo.Name)" -Options $mapOptions -Footer 'Use arrows to choose a map, Enter to select, Esc to go back.'
                    if (-not $mapChoice) {
                        Write-Log "User cancelled map selection for $($zipInfo.Name)"
                        continue
                    }
                    if ($mapChoice.Kind -eq 'Back') {
                        Write-Log "User returned to zip list without choosing a map for $($zipInfo.Name)"
                        continue
                    }
                    $mapName = $mapChoice.Map
                }
                Write-Log "Interactive selection chose $($zipInfo.Name) -> $mapName"
                Activate-Selection -ZipInfo $zipInfo -MapFolder $mapName
            }
        }

        Write-Host ''
        Write-Host 'Press Enter to choose another map or Esc to exit.' -ForegroundColor Yellow
        $nextKey = [System.Console]::ReadKey($true)
        if ($nextKey.Key -eq 'Escape') {
            Write-Log 'User exited after activation prompt'
            return
        }
        Write-Log 'User opted to continue selecting maps'
    }
}

try {
    if ($ShowHelp) {
        Write-Usage
        Write-Log 'Displayed help text via --help'
        exit 0
    }

    if ($RandomMode -or $ZipName -or $StockName) {
        $mapZips = Get-MapZips
        Invoke-NonInteractiveRun -ZipName $ZipName -MapName $MapName -StockName $StockName -RandomMode:$RandomMode -MapZips $mapZips
        Write-Log 'Non-interactive session completed'
        exit 0
    }

    Invoke-MainLoop
    Write-Log 'Interactive session completed'
} catch {
    Write-Host ''
    Write-Error $_
    Write-Log "Unhandled error: $($_.Exception.Message)"
    Read-Host 'Press Enter to exit'
    exit 1
} finally {
    if ($script:Rng) { $script:Rng.Dispose() }
    Write-Log 'Session ended; RNG disposed'
}

