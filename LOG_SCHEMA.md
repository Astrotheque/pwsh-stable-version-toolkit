# PowerShell Version Facade — Log Schema

This document defines the structured JSONL schema used by:

- `PwshVersionFacade.ps1`
- `PwshStableInfo.psm1`
- `PowerShell-Stable-Version-Helpers.ps1`

Logs are written in **JSONL** format — **one JSON object per line**, no indentation.

---

## File Naming

```text
PwshVersionFacade_YYYYMMDD.jsonl
```

Each run on the same day appends entries to this file.

---

## Base Fields (all records)

| Field       | Type   | Description |
|-------------|--------|-------------|
| `timestamp` | string | ISO-8601 timestamp with timezone offset. |
| `runId`     | string | A full GUID identifying a single execution of the facade. |
| `eventType` | string | The category of event (see Event Types section). |

These fields are always present in **every line**.

---

## Event Types

The following `eventType` values are generated:

- `Start`
- `ModuleLoaded`
- `ModuleLoadError`
- `ModuleMissing`
- `HelpersLoaded`
- `HelpersLoadError`
- `HelpersMissing`
- `CheckResult`
- `NoUpdateNeeded`
- `UpdateAvailable`
- `NonInteractiveSkip`
- `UserPrompt`
- `UserSkippedUpdate`
- `OpenInstallerUrl`
- `OpenUrlError`
- `MsiUrlError`
- `IncompleteData`
- `UpdateCheckError`
- `End`

---

## Additional Fields by Event Type

Only base fields are guaranteed across all records.  
All other fields are **event-type dependent**.

---

### Version Fields

Used in:

- **`CheckResult`** — includes all version fields below.
- **`NoUpdateNeeded`**, **`UpdateAvailable`**, **`NonInteractiveSkip`**, **`UserSkippedUpdate`**, **`End`** — include only `currentVersion` and `latestStable`.

| Field            | Type                | Description |
|------------------|---------------------|-------------|
| `currentVersion` | string or object    | Installed PowerShell version. |
| `latestStable`   | string or object    | Latest stable version retrieved from official sources. |
| `updateNeeded`   | bool *(CheckResult only)* | Whether a newer stable version exists. |

> **Note:** PowerShell may serialize versions as plain strings (`"7.5.4"`) or as structured objects. Consumers should treat either form as valid semantic version data.

---

### Path and Environment Fields

Used in:

- `Start`
- `ModuleLoaded`
- `ModuleMissing`
- `HelpersLoaded`
- `HelpersMissing`

| Field          | Type   | Description |
|----------------|--------|-------------|
| `rootPath`      | string | The facade script's directory. |
| `modulePath`    | string | Path to `PwshStableInfo.psm1`. |
| `helperPath`    | string | Path to helper script. |
| `nonInteractive` | bool   | Indicates automation/silent mode. |

---

### User Interaction Fields

Used in:

- `UserPrompt`
- `UserSkippedUpdate`

| Field     | Type   | Description |
|-----------|--------|-------------|
| `prompt`   | string | Prompt text displayed to the user. |
| `response` | string | Raw user response (e.g., `"y"` or `"n"`). |

---

### Update Action Fields

Used in:

- `OpenInstallerUrl`
- `OpenUrlError`
- `MsiUrlError`

| Field | Type   | Description |
|-------|--------|-------------|
| `url` | string | URL attempted to open. |
| `error` | string | Exception message if an error occurred. |

---

## Example Records

### CheckResult Example

```json
{"timestamp":"2025-11-17T17:31:05.9937564-05:00","runId":"84d93e24-39fa-4122-9dc7-c5bd80c6a4a1","eventType":"CheckResult","currentVersion":"7.5.4","latestStable":"7.5.4","updateNeeded":false}
```

### UpdateAvailable Example

```json
{"timestamp":"2025-11-17T17:40:12.1476231-05:00","runId":"abb88d22-8892-4dd6-8c7f-f3b4db8883a2","eventType":"UpdateAvailable","currentVersion":"7.5.4","latestStable":"7.5.5"}
```

### UserSkippedUpdate Example

```json
{"timestamp":"2025-11-17T18:02:55.4430012-05:00","runId":"f84a64dd-d25f-4a31-96b6-35fa99e22f3c","eventType":"UserSkippedUpdate","currentVersion":"7.5.4","latestStable":"7.5.5","response":"n"}
```

### URL Error Example

```json
{"timestamp":"2025-11-17T18:04:10.9903764-05:00","runId":"7a8d0f4f-9780-46d0-9df5-66975d7667f5","eventType":"OpenUrlError","url":"https://github.com/PowerShell/PowerShell/releases/latest","error":"Object not found"}
```

---

## Notes

- All non-base fields are optional and appear only when relevant to the event type.
- Version fields may appear as objects or strings depending on PowerShell serialization.
- `runId` enables SIEM tools to correlate multi-event sequences for a single script execution.
- `timestamp` always conforms to ISO-8601 with timezone offset.

---

If needed, a formal JSON Schema (`.schema.json`) can also be generated for automated validation in CI/CD or SIEM ingestion pipelines.
