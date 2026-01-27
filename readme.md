BeamMP Map Selector – Target Specification
=========================================

## Context

- This project delivers a Windows-friendly BeamMP map rotation tool so server hosts can swap maps quickly without manual zip juggling.

## Primary Objective

Deliver a **single self-contained batch file** (`map_selector.bat`) that automates map rotation, server restarts, and mod hygiene without dependencies on extra scripts or data files. This file now lives at the repo root; launch it (double-click or run via `cmd`) to start the selector. The batch file extracts its embedded PowerShell payload to a temporary file at runtime, cleans it up on exit, and handles everything else automatically.

## Functional Requirements

1. **Single Artifact**
   - All logic must reside inside `map_selector.bat` (embedded PowerShell/VBScript payloads are allowed if generated at runtime and cleaned up afterward).
   - The batch file must operate correctly when launched from any directory by deriving the BeamMP root relative to its own path.

2. **Map Zip Discovery & Classification**
   - On startup, scan both `Resources\Client` and `map_files` for `*.zip`.
   - Inspect each archive for entries matching `levels/<folder>/info.json`.
   - Zips that contain at least one such entry are **map zips**; all others are **general mods**.
   - Map zips found in `Resources\Client` are moved to `map_files` (reserve `Resources\Client` for active map + general mods only).
   - General mod zips (or archives that failed inspection) are kept/moved to `Resources\Client` so players can correct issues manually.

3. **Dynamic Menu Structure**
   - Build an in-memory structure `[zip file -> [map folders]]` from the inspection results.
   - First-level menu lists map zip files (plus a `random` option); navigation via arrow keys, PageUp/PageDown, Home/End, Enter to select.
   - When a zip contains multiple map folders, show a second-level menu to choose the desired folder; if there is exactly one folder, auto-select it.
   - Menus should clearly display the current selection and total counts.

4. **Random Selection Quality**
   - Selecting `random` first picks a random zip, then a random map within that zip.
   - Use a cryptographically strong RNG (`System.Security.Cryptography.RNGCryptoServiceProvider` or equivalent) to avoid deterministic sequences.

5. **Map Activation Workflow**
   - When a specific zip/map pair is chosen:
     1. Move any other map zips out of `Resources\Client` into `map_files`.
     2. Move the chosen zip into `Resources\Client`.
     3. Backup `ServerConfig.toml` to `ServerConfig.toml.<timestamp>.bak`.
     4. Update (or insert) the line `Map = "/levels/<map>/info.json"` using UTF-8 encoding.
     5. Stop all running `BeamMP-Server.exe` processes.
     6. Start a fresh `BeamMP-Server.exe` with working directory set to the repo root.

6. **Session Persistence**
   - After starting the server, print the active zip and map.
   - Return to the main menu automatically so players can switch maps repeatedly without restarting `map_selector.bat`.
   - Provide an explicit exit option (e.g., `Esc` or menu item) that shuts down the selector without killing the server.

7. **Error Handling & Messaging**
   - If no map zips exist in either directory, display guidance to drop map zips into `map_files` or `Resources\Client` and re-scan on demand.
   - Warn (but continue running) when `BeamMP-Server.exe` or `ServerConfig.toml` is missing, when zip inspection fails, or when process control requires elevation.
   - Mirror every critical action (scans, selections, config edits, server restarts, failures) to both the console and an append-only `map_selector.log` in the repo root so post-mortem debugging is possible even when the console session disappears.

8. **Networking Awareness (Optional Enhancements)**
   - After launching the server, optionally display the detected LAN IP + port to simplify office LAN matches.
   - Future improvements may include automatic detection of dedicated ethernet dongle IPs.

## Non-Functional Requirements

- **Portability:** Works on Windows 10/11 without requiring extra PowerShell modules.
- **Performance:** Initial scanning and menu rendering should complete within a few seconds even with dozens of zips.
- **Maintainability:** Code should be commented only where behavior is non-obvious; keep everything ASCII for compatibility.
- **Safety:** Never delete mods; only move between `map_files` and `Resources\Client`. Always create config backups before edits.

## Diagnostics & Logging

- Write selector activity to `map_selector.log` (adjacent to `map_selector.bat`) in addition to console output so that we can reconstruct actions after non-interactive runs or sudden console exits.
- Log the discovered map count, chosen zip/map, config backup path, server stop/start status, and any warnings/errors with timestamps.
- Ensure the log is created/updated entirely by the self-contained batch/PowerShell bundle—no external scripts or modules.
- Provide a simple environment flag (e.g., `MAP_SELECTOR_DEBUG=1`) that skips deleting the temporary embedded PowerShell file, enabling deeper troubleshooting when required.

## Current Implementation & Usage

- Run `map_selector.bat` from the repo root (double-click or via Command Prompt). It auto-discovers the repo path and launches its embedded PowerShell selector logic.
- On launch it scans `Resources\Client` and `map_files`, rehomes map zips, and builds two-level menus (zip → map). `random` uses a cryptographically strong RNG.
- Selecting a map moves only other **map** zips back to `map_files`, leaves general mods where they belong in `Resources\Client`, places the active map zip beside them, backs up & edits `ServerConfig.toml`, restarts `BeamMP-Server.exe`, and prints the active pairing while keeping the selector running for future swaps.
- The CLI offers `Rescan` and `Exit` entries plus Esc shortcuts; if no maps are found it prompts you to add zips and re-scan.

### Command-Line Usage (non-interactive / debugging)

You can run the selector without the interactive menu—handy when diagnosing issues from a non-interactive console:

```
map_selector.bat --help
map_selector.bat --zip Clickbait_LiquidJumpingV1.0.zip --map WaterJumping2
map_selector.bat --random
```

- `--zip <zipfile>`: select the given zip automatically (case-insensitive).
- `--map <folder>`: specify which map folder inside the zip to use (required if the zip has multiple maps; optional otherwise).
- `--random`: pick a random zip and random map.
- `--help`: print the usage summary.

In non-interactive mode the selector still moves zips, updates the config, restarts the server, prints the selection, and exits when finished.

### Debugging Tips

- Set the environment variable `MAP_SELECTOR_DEBUG=1` before launching the batch file when you want to preserve the extracted PowerShell script for inspection. The batch wrapper will leave the temp file in `%TEMP%` and log the exact path.
- Review `map_selector.log` after any crash or unexpected exit to see the recorded actions (scan results, moves, warnings, server restarts, etc.).

## Open Questions / Future Considerations

1. Should the selector optionally sync chosen maps to the second office PC automatically?
2. Do we want to expose presets (e.g., “best of 5 random maps”) for tournament play?
3. Should the selector track historical usage to avoid repeating the same map until all others are used?

These can be addressed in follow-up iterations once the baseline batch selector is in place.
