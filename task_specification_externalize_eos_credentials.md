# TASK: Externalize EOS Credentials to Local Config & Secure Git Repository

## Objective
Decouple Epic Online Services (EOS) credentials from source code by removing hardcoded strings from `res://core/eos_manager.gd`. Implement an external `ConfigFile` runtime loader, supply a tracked template file, and configure `.gitignore` so private credentials are never exposed to version control.

---

## File Operations

| Action | Path | Details |
| :--- | :--- | :--- |
| **Modify** | `.gitignore` | Add rules ignoring local config and secret files. |
| **Create** | `res://config/eos_credentials.template.cfg` | Empty template committed to Git for reference. |
| **Create** | `res://config/eos_credentials.cfg` | Local uncommitted file holding real keys. |
| **Modify** | `res://core/eos_manager.gd` | Implement runtime config loading and validation before EOS init. |

---

## Detailed Implementation Steps

### 1. Update `.gitignore`
Add the following entries to `.gitignore` to prevent committing live keys:

```gitignore
# EOS Local Secrets
res://config/eos_credentials.cfg
config/eos_credentials.cfg
*.secret.cfg
```

---

### 2. Create Template Configuration
Create `res://config/eos_credentials.template.cfg` with placeholder fields:

```ini
[eos]
product_id=""
sandbox_id=""
deployment_id=""
client_id=""
client_secret=""
encryption_key=""
```

---

### 3. Setup Local Credentials Configuration
Create `res://config/eos_credentials.cfg`:
- If the file does not already exist, copy the keys currently hardcoded inside `res://core/eos_manager.gd` into this file.
- Structure must match the template:

```ini
[eos]
product_id="YOUR_PRODUCT_ID"
sandbox_id="YOUR_SANDBOX_ID"
deployment_id="YOUR_DEPLOYMENT_ID"
client_id="YOUR_CLIENT_ID"
client_secret="YOUR_CLIENT_SECRET"
encryption_key=""
```

---

### 4. Refactor `res://core/eos_manager.gd`

Update `res://core/eos_manager.gd` to load keys dynamically at startup:

1. **Declare Configuration Variables and Constant:**
```gdscript
const CREDENTIALS_PATH: String = "res://config/eos_credentials.cfg"

var product_id: String = ""
var sandbox_id: String = ""
var deployment_id: String = ""
var client_id: String = ""
var client_secret: String = ""
var encryption_key: String = ""
```

2. **Implement `_load_credentials() -> bool`:**
```gdscript
func _load_credentials() -> bool:
	var config := ConfigFile.new()
	var err := config.load(CREDENTIALS_PATH)
	if err != OK:
		printerr("[EOSManager] CRITICAL: Missing credentials file at: ", CREDENTIALS_PATH)
		printerr("[EOSManager] Copy 'res://config/eos_credentials.template.cfg' to 'eos_credentials.cfg' and add valid keys.")
		return false

	product_id = config.get_value("eos", "product_id", "")
	sandbox_id = config.get_value("eos", "sandbox_id", "")
	deployment_id = config.get_value("eos", "deployment_id", "")
	client_id = config.get_value("eos", "client_id", "")
	client_secret = config.get_value("eos", "client_secret", "")
	encryption_key = config.get_value("eos", "encryption_key", "")

	if product_id.is_empty() or client_id.is_empty() or client_secret.is_empty():
		printerr("[EOSManager] CRITICAL: Required credentials missing in: ", CREDENTIALS_PATH)
		return false

	print("[EOSManager] Credentials successfully loaded from config.")
	return true
```

3. **Integrate into Initialization Flow:**
   - At the beginning of `_ready()` or before `EOS.Platform.platform_create()`:
     ```gdscript
     if not _load_credentials():
         printerr("[EOSManager] Aborting initialization due to missing credentials.")
         return
     ```
   - Replace any hardcoded strings in the platform creation options dictionary with the loaded variables (`product_id`, `sandbox_id`, `deployment_id`, `client_id`, `client_secret`, `encryption_key`).

---

## Verification & Acceptance Criteria

1. **Headless Compilation:**
   - Execute `godot --headless --path . --editor --quit` and verify exit code `0` with no GDScript parse errors.
2. **Git Status Check:**
   - Run `git status`. Verify that `res://config/eos_credentials.cfg` is ignored and does NOT appear in untracked files.
   - Verify that `res://config/eos_credentials.template.cfg` IS staged or tracked.
3. **Runtime Validation:**
   - Launch the game (`F5`). Check the Godot console to confirm:
     - `[EOSManager] Credentials successfully loaded from config.`
     - EOS successfully logs in and returns a valid PUID.