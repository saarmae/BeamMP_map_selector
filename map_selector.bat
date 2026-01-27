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

powershell -NoProfile -ExecutionPolicy Bypass -File "%_temp%" -RepoRoot "%_root%"
set "_code=%ERRORLEVEL%"
del "%_temp%" >nul 2>&1
exit /b %_code%

###EMBEDDED_POWERSHELL###
param(
    [string]$RepoRoot
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

Add-Type -AssemblyName System.IO.Compression.FileSystem
$script:Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

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
            }
        } elseif (-not $info.IsMap -and $info.Area -eq 'MapFiles') {
            $dest = Join-Path $resourcesClient $info.Name
            try {
                Move-Item -Path $info.FullPath -Destination $dest -Force
                $info.FullPath = $dest
                $info.Area = 'Resources'
            } catch {
                Write-Warning "Unable to move $($info.Name) back to Resources\\Client: $($_.Exception.Message)"
            }
        }
    }

    $mapList = New-Object System.Collections.Generic.List[object]
    foreach ($info in $results | Where-Object { $_.IsMap }) {
        $mapList.Add($info)
    }
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

function Update-ServerConfig {
    param([string]$MapFolder)

    if (-not (Test-Path $configFile)) {
        Write-Warning "ServerConfig.toml not found at $configFile. Skipping config update."
        return
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backup = "$configFile.$timestamp.bak"
    Copy-Item -Path $configFile -Destination $backup -Force

    $content = Get-Content -Path $configFile -Raw -Encoding UTF8
    $mapLine = "Map = `"/levels/$MapFolder/info.json`""
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
}

function Restart-Server {
    $procs = Get-Process -Name 'BeamMP-Server' -ErrorAction SilentlyContinue
    if ($procs) {
        Write-Host "Stopping BeamMP-Server (process count: $($procs.Count))." -ForegroundColor Yellow
        foreach ($proc in $procs) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            } catch {
                Write-Warning "Failed to stop process Id $($proc.Id): $($_.Exception.Message)"
            }
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "No running BeamMP-Server process detected." -ForegroundColor DarkGray
    }

    if (Test-Path $serverExe) {
        Write-Host "Starting BeamMP-Server..." -ForegroundColor Yellow
        try {
            Start-Process -FilePath $serverExe -WorkingDirectory $RepoRoot | Out-Null
            Write-Host "Server launched." -ForegroundColor Green
        } catch {
            Write-Warning "Failed to start BeamMP-Server.exe: $($_.Exception.Message)"
        }
    } else {
        Write-Warning "BeamMP-Server.exe not found at $serverExe"
    }
}

function Activate-Selection {
    param(
        [pscustomobject]$ZipInfo,
        [string]$MapFolder
    )

    Write-Host "\nActivating $($ZipInfo.Name) -> $MapFolder" -ForegroundColor Green

    Ensure-Dir $resourcesClient
    Ensure-Dir $mapFilesDir

    $targetPath = Join-Path $resourcesClient $ZipInfo.Name

    Get-ChildItem -Path $resourcesClient -Filter '*.zip' -File -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -ne $ZipInfo.Name) {
            try {
                Move-Item -Path $_.FullName -Destination (Join-Path $mapFilesDir $_.Name) -Force
            } catch {
                Write-Warning "Failed to move inactive map $($_.Name) to map_files: $($_.Exception.Message)"
            }
        }
    }

    $sourceCandidates = @(
        Join-Path $mapFilesDir $ZipInfo.Name,
        Join-Path $resourcesClient $ZipInfo.Name,
        $ZipInfo.FullPath
    )
    $sourcePath = $sourceCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($sourcePath -and ($sourcePath -ne $targetPath)) {
        try {
            Move-Item -Path $sourcePath -Destination $targetPath -Force
        } catch {
            Write-Warning "Failed to move $($ZipInfo.Name) into Resources\\Client: $($_.Exception.Message)"
        }
    }

    Update-ServerConfig -MapFolder $MapFolder
    Restart-Server

    Write-Host "\nNow running: $($ZipInfo.Name)  ->  /levels/$MapFolder/info.json" -ForegroundColor Cyan
}

function Wait-ForMapFiles {
    Write-Host ''
    Write-Host 'No map zip files were found.' -ForegroundColor Yellow
    Write-Host 'Place map zips in map_files or Resources\Client, then press Enter to rescan (Esc to quit).' -ForegroundColor DarkGray
    $key = [System.Console]::ReadKey($true)
    if ($key.Key -eq 'Escape') {
        return $false
    }
    return $true
}

function Invoke-MainLoop {
    while ($true) {
        $mapZips = Get-MapZips
        if (-not $mapZips -or $mapZips.Count -eq 0) {
            if (-not (Wait-ForMapFiles)) { return }
            else { continue }
        }

        $options = Build-MainOptions -MapZips $mapZips
        $selection = Invoke-Menu -Title 'Select a map file' -Options $options
        if (-not $selection) { return }

        switch ($selection.Kind) {
            'Exit'   { return }
            'Rescan' { continue }
            'Random' {
                $zipInfo = Get-SecureRandomItem $mapZips
                $mapName = Get-SecureRandomItem $zipInfo.MapFolders
                Activate-Selection -ZipInfo $zipInfo -MapFolder $mapName
            }
            'Zip' {
                $zipInfo = $selection.Zip
                $mapName = $null
                if ($zipInfo.MapFolders.Count -le 1) {
                    $mapName = $zipInfo.MapFolders[0]
                } else {
                    $mapOptions = Build-MapOptions -MapFolders $zipInfo.MapFolders
                    $mapChoice = Invoke-Menu -Title "Select a map inside $($zipInfo.Name)" -Options $mapOptions -Footer 'Use arrows to choose a map, Enter to select, Esc to go back.'
                    if (-not $mapChoice) { continue }
                    if ($mapChoice.Kind -eq 'Back') { continue }
                    $mapName = $mapChoice.Map
                }
                Activate-Selection -ZipInfo $zipInfo -MapFolder $mapName
            }
        }

        Write-Host ''
        Write-Host 'Press Enter to choose another map or Esc to exit.' -ForegroundColor Yellow
        $nextKey = [System.Console]::ReadKey($true)
        if ($nextKey.Key -eq 'Escape') { return }
    }
}

try {
    Invoke-MainLoop
} catch {
    Write-Host ''
    Write-Error $_
    Read-Host 'Press Enter to exit'
    exit 1
} finally {
    if ($script:Rng) { $script:Rng.Dispose() }
}

