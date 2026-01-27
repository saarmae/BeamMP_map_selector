BeamMP Map Selector – Target Specification
=========================================

## Context

- Office BeamNG competitions use two PCs connected via a dedicated LAN link (USB/Ethernet dongles) plus normal corporate Internet.
- The BeamMP server runs in `BeamMP_server` and currently relies on a PowerShell map selector plus several helper scripts/text files.
- Manual map management is tedious, especially when quickly setting up matches between coworkers. This spec defines the desired, streamlined behavior.

## Primary Objective

Deliver a **single self-contained batch file** (`map_selector.bat`) that automates map rotation, server restarts, and mod hygiene without dependencies on extra scripts or data files.

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
   - Keep logs in the console; avoid external log files to preserve the single-file requirement.

8. **Networking Awareness (Optional Enhancements)**
   - After launching the server, optionally display the detected LAN IP + port to simplify office LAN matches.
   - Future improvements may include automatic detection of the dedicated dongle IPs.

## Non-Functional Requirements

- **Portability:** Works on Windows 10/11 without requiring extra PowerShell modules.
- **Performance:** Initial scanning and menu rendering should complete within a few seconds even with dozens of zips.
- **Maintainability:** Code should be commented only where behavior is non-obvious; keep everything ASCII for compatibility.
- **Safety:** Never delete mods; only move between `map_files` and `Resources\Client`. Always create config backups before edits.

## Open Questions / Future Considerations

1. Should the selector optionally sync chosen maps to the second office PC automatically?
2. Do we want to expose presets (e.g., “best of 5 random maps”) for tournament play?
3. Should the selector track historical usage to avoid repeating the same map until all others are used?

These can be addressed in follow-up iterations once the baseline batch selector is in place.
