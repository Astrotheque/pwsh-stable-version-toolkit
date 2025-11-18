# PowerShell Stable Version Tools

A lightweight, security-focused toolkit designed to:

- Ensure consistent PowerShell versions across multiple machines.
- Verify VS Code’s integrated terminal is using your intended pwsh.
- Check for the latest stable, production-ready PowerShell release.
- Provide automatic or interactive update guidance.
- Produce JSONL logs suitable for SIEM / log ingestion.
- Support automation, fleet consistency, and CISSP-aligned practices.

This project consists of:

1. `PwshStableInfo.psm1`
2. `PowerShell-Stable-Version-Helpers.ps1`
3. `PwshVersionFacade.ps1` — the user-friendly entry point

---

## Features

### Detects current pwsh version
Inspects the exact PowerShell binary VS Code is using, via `$PSVersionTable`.

### Retrieves the latest stable version
Pulls authoritative release data from official Microsoft endpoints.

### Determines if an update is needed
Reports:
- “Up to date”
- or “New stable version available”

### Interactive update prompt
If run without `-NonInteractive`, the tool prompts:
> Open the MSI installer page now?

### Automation mode
Use:
```powershell
-NonInteractive -EnableLogging
```
Silent, no user interaction.

### JSONL logging
One log line per event. Schema defined in `LOG_SCHEMA.md`.

---

## Directory Layout

Place all files in:
```
S:\Dev Tools\PowerShell\
```

```
S:\Dev Tools\PowerShell\
├─ PwshStableInfo.psm1
├─ PowerShell-Stable-Version-Helpers.ps1
├─ PwshVersionFacade.ps1
└─ logs\
```

---

## Usage

### Interactive
```powershell
.\PwshVersionFacade.ps1
```

### Enable logging
```powershell
.\PwshVersionFacade.ps1 -EnableLogging
```

### Automation
```powershell
.\PwshVersionFacade.ps1 -EnableLogging -NonInteractive
```

---

## PowerShell Profile Integration

```powershell
Import-Module "S:\Dev Tools\PowerShell\PwshStableInfo.psm1"
```

Functions available globally:
- `Show-VSCodePwshStatus`
- `Get-LatestPwshStableInfo`
- `Get-LatestPwshPreviewInfo`
- `Get-PwshStableInsight`
- `Test-PwshUpdate`

---

## Logging Schema

Full details in:
```
LOG_SCHEMA.md
```

---

## CISSP Alignment

This toolkit reinforces:

- Configuration Baselines
- Change Management
- Predictable Operations
- Monitoring & Auditability
- Defense in Depth

---

## License

MIT license recommended (can generate upon request).

---

## Contributing

Pull requests welcome. Project is minimal, readable, and portable.

