BeamMP Map Selector Implementation Plan
======================================

## 1. Repository Hygiene
- Add/maintain ignores so only required files (batch selector, docs) are tracked.
- Keep large binaries (server exe, logs, config backups) untracked.

## 2. Self-Contained Batch Wrapper
- Write `map_selector.bat` that determines repo root relative to itself.
- Launch embedded PowerShell payload (here-string) without auxiliary scripts.
- Clean up any temporary files before exit.

## 3. Map Discovery & Classification
- Scan `Resources\Client` and `map_files` for `*.zip`.
- Use `System.IO.Compression.ZipArchive` to find `levels/<folder>/info.json` entries.
- Build dictionary `{zip -> [map folders]}`.
- Move map zips from `Resources\Client` into `map_files`; keep general/unknown zips in `Resources\Client`.

## 4. Menu Interaction
- Implement console UI (arrow keys, PageUp/PageDown, Home/End, Enter, Esc).
- First menu lists zips plus `random` option.
- Second menu appears only if zip has multiple maps; auto-select single-map zips.
- Show current selection status and counts.

## 5. Random Selection
- For `random`, choose random zip then random map using `System.Security.Cryptography.RandomNumberGenerator`.
- Reseed per selection to avoid deterministic patterns.

## 6. Activation Workflow
1. Move all non-selected map zips from `Resources\Client` back to `map_files`.
2. Move chosen zip into `Resources\Client`.
3. Backup `ServerConfig.toml` to `ServerConfig.toml.<timestamp>.bak`.
4. Update or insert `Map = "/levels/<map>/info.json"` (UTF-8 encoding).
5. Stop existing `BeamMP-Server.exe` processes (warn if permission denied).
6. Start new server process from repo root.

## 7. Persistent Session Loop
- After launching server, print active zip/map summary.
- Return to menu automatically so the tool stays open for future swaps.
- Provide explicit exit option that leaves server running.

## 8. Error Handling
- Missing directories/files → clear guidance and option to rescan.
- Zip read failures → skip zip, keep as general mod, show warning.
- Permission issues → prompt user to rerun as admin.
- No map zips anywhere → instruct user to place zips in `map_files` or `Resources\Client`.

## 9. Testing & Verification
- Manual tests: map detection, random selection, config update, server restart.
- Optional dry-run flag for safe testing without file moves.
- Document assumptions, prerequisites, and usage in README.

## Progress Snapshot
- Single-file batch wrapper with embedded PowerShell is live; it auto-discovers repo root, scans zip locations, and renders the full interactive menu loop.
- Random selection uses `System.Security.Cryptography.RandomNumberGenerator` and honors single vs. multi-map zips automatically.
- Activation workflow (zip moves, config backups/edits, server restart) is validated in both interactive and CLI flag modes.
- CLI parameters (`--zip`, `--map`, `--random`, `--help`) plus the new `MAP_SELECTOR_DEBUG` flag support both automation and troubleshooting.
- Structured logging now writes every critical action to `map_selector.log`, and general mod zips are confidently left in `Resources\Client` during activation.

## Next Steps
- Monitor `map_selector.log` for recurring interactive crashes (especially around the soapbox map) and capture any new anomalies.
- Add optional log rotation or size limits so `map_selector.log` doesn’t grow unbounded during tournaments.
- Build a smoke-test/dry-run mode that exercises map detection and config edits without touching files, making regression testing safer.
- Harden general-mod detection further (e.g., cache zip metadata between runs) if new edge cases appear.
