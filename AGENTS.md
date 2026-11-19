# Project: Spy vs. Spy 3D Remake (Godot 4.7.2)

## 1. Engine & Architectural Constraints
- **Engine Version:** Godot 4.7.2-stable (GDScript 2.0 only). Use strict static typing (`var speed: float = 4.5`) and Godot 4 annotations (`@export`, `@onready`, `@rpc`). Never use deprecated Godot 3 syntax.
- **Assets-When-Available / Greybox-Fallback Principle:** Use finished project models and prefabs (`res://Assets/Prefabs_Agents/`, `res://Assets/Models/Prefabs/`, etc.) when available; fall back to clean primitive meshes (`MeshInstance3D`, `CSGBox3D`), readable silhouettes, and minimal procedural animations (`Tween`) when no asset exists yet. Prioritize responsiveness and network determinism over visual bloat. Never treat GDD Markdown files as hardcoded `.tscn` node-tree mandates—design the optimal Godot 4 node trees, script architectures, and RPC structures based on the actual codebase.
- **Centralized Tunables (`res://core/game_config.gd`):** Never hardcode magic gameplay numbers across scripts. Expose all `[TUNABLE]` baselines (movement speeds, timer durations, fuse ranges, audio radii) in `GameConfig` or cleanly grouped `@export` inspector variables.
- **Component Modularity (Avoid Monolith Bloat):** `res://entities/player/player.gd` and `res://entities/props/searchable_container.gd` are already large. Whenever adding or reworking a subsystem, prefer extracting focused child components (following `SpyInventoryComponent` and `SpyRagdollController`) rather than growing monolith scripts further.

## 2. Multiplayer & Authority Architecture
- **Dual-Backend Listen-Server:** Local ENet (`port 8910`) and Epic Online Services P2P (`EOSGMultiplayerPeer`, socket `"SpyVsSpySocket"`, 2 players core / 4 max stretch).
- **Spawning:** `MultiplayerSpawner` watching a shared `Players` container. Spawned player node names must strictly match stringified peer IDs (`str(peer_id)`).
- **Client-Authoritative Locomotion (`MultiplayerSynchronizer`):**
  - Each player instance runs `set_multiplayer_authority(name.to_int())` for zero-lag FPS movement and stances, and derives `spy_role` deterministically from peer ID in `_enter_tree()` (`peer 1` = Spy Green / `AgentGreen.tscn`, `peer != 1` = Spy Purple / `AgentPurple.tscn`).
  - Replicate **only** `:position`, `:rotation:y` (body yaw), `head_pitch: float`, `spy_role: int`, and `stance_state: int` via `MultiplayerSynchronizer`.
  - **Never** add server-authoritative inventory fields (`left_hand_item_id`, `briefcase_objectives`, `jacket_slots`, `active_jacket_slot`, `right_hand_mode`, `is_charging_club`) to `MultiplayerSynchronizer`—those are owned by Host (`peer_id == 1`) and broadcast via reliable RPC (`_rpc_sync_inventory`).
- **Server-Authoritative World, Inventory & Trap Interactions:**
  - Clients request world/inventory interactions (opening doors/drawers, picking up/dropping items, arming/stealing traps, catching/throwing live bombs, triggering KOs) via server RPCs (`rpc_id(1, ...)`).
  - Host (`peer_id == 1`) validates state (single-user container lock, item ownership, `2.0s` wake-up immunity) and broadcasts deterministic updates to all peers via reliable sync RPCs.
- **Low-Bandwidth Ragdoll & Pelvis-Only Wake-Up Sync:**
  - Never stream per-bone `PhysicalBone3D` transforms across the network. Broadcast the knockout impulse once so all peers run local 13-bone `PhysicalBoneSimulator3D` physics simultaneously on the `AgentGreen` / `AgentPurple` `Skeleton3D`, send lightweight `~5 Hz` victim-authoritative pelvis position hints for gentle remote pull, lock the victim's first-person `Camera3D` permanently onto `spine.006` (with an unculled keepalive mesh so the local skeleton stays active), and snap the **pelvis wake-up position** to valid floor with 8-way radial wall/prop clearance when standing up at `15.0s` (no `NavigationRegion3D` required).
- **Deterministic Match Randomization:**
  - Never use unseeded global `randi()` or `randf()` for level/loot generation.
  - Host generates `match_seed: int` at match start and syncs it via RPC. All peers use a local `RandomNumberGenerator.new()` initialized with `rng.seed = match_seed` to spawn identical room prefabs, drawer loot, and floor buckets.

## 3. Physics & Collision Layers
- **Layer 1 (`1` — `Environment`):** Solid walls, floors, ceilings, and **closed** door leaves (blocks movement AND occludes `5.0m` Time Bomb blasts / `2.0m` Club slams).
- **Layer 2 (`2` — `Interactable`):** Doors, searchable drawers, dropped Briefcase, loose objectives, and planted traps (queried by player `InteractRayCast` at `2.2m` reach).
- **Layer 3 (`4` — `Player`):** Active standing/crouching `SpyCharacter` capsules (`1.8m` standing -> `1.0m` crouched).
- **Layer 4 (`8` — `Ragdoll_KO`):** Active during the `15.0s` in-place `PhysicalBoneSimulator3D` knockout state (collides with `Layer 1 Environment`, ignores `Layer 3 Player` to prevent hallway body-blocking).
- **Layer 5 (`16` — `Triggers_And_Zones`):** `RoomZone` volumes (`20.0s` Anti-Camp Sneeze & Watch map targets), `DoorBashDetector`, `Tripwire` rays, `WaterBucket` splash zones, and airborne `TimeBomb` direct-hit catch colliders.
- **Layer 6 (`32` — `Drawer_Contents`):** 3D interior clutter, stored items, and drawer traps inside `SearchableContainer` trays (queried only in Top-Down Container View).

## 4. Core Gameplay Pillars & Playtest Override Rule
> **Playtest Override Rule:** The pillars below define the game's identity and should not be broken casually, **but live user playtest feedback always overrides specific GDD UX/control micro-details**. When playtesting changes a control flow or interaction rule, implement what feels right and update the affected doc/spec to stay in sync.

1. **No Health Bars or Generic Gunplay:** Spies do not have HP. Every valid trap trigger, DVD Dart hit, or green-zone Club slam inflicts the unified **`15.0s` in-place Ragdoll KO**, forces a **full drop of the Left Hand AND scatters all traps/gadgets stored across all 3 Inner Jacket Slots** onto the floor around the ragdoll (while the personal Club re-holsters to the back), and grants **`2.0s` wake-up blink immunity** upon standing up at the floor-snapped, wall-cleared pelvis position.
2. **Physical Left Hand & 3-Slot Inner Trenchcoat Jacket Inventory (No Hidden Grids):**
   - **Left Hand (`Q` to drop):** Holds `1` loose Objective (`KEY`, `MONEY`, `PASSPORT`, `PLANS`) OR the `CompactBriefcase` (`0.90` move speed; stores `0–4` Objectives).
   - **3-Slot Inner Trenchcoat Jacket (`Keys 1, 2, 3` / `Scroll Wheel` to select; `G` to drop active slot item):** Holds up to **`3` Traps/Gadgets** (`WaterBucket`, `Tripwire`, `SpringTrap`, unlit `TimeBomb`, `DVDDartGun`). Picking up or looting a trap/gadget fills the first empty Jacket Slot, only swapping/dropping onto the floor if **all 3 Jacket Slots are full**.
   - **Two-Handed Club Harmony (`Key 4` or `R` to toggle personal Club from back):** Toggling the Two-Handed Club tucks any held trap safely back into its Inner Jacket slot rather than dropping it (`1.00` speed idle; `0.35` speed while charging `Hold LMB`, which auto-drops the **Briefcase** from the Left Hand if held).
   - **Wearable Spy Watch / Smart Glasses:** Permanent non-droppable utility (`Hold V` radio; `B` / `Tab` directional audio bluffs). Never occupies hand or jacket slots.
3. **100% Player-Driven Traps & Owner-Trigger Parity:**
   - Matches start with `starting_prearmed_traps = 0`.
   - All traps (`WaterBucket`, `Tripwire`, `SpringTrap`, `TimeBomb`) trigger identically on **both** the rival and the trap's owner (`peer_id` grants zero immunity).
4. **Hot-Potato Time Bomb Rules:**
   - Opening a rigged drawer or Briefcase (`Tap E` or `Hold E`) ignites a `2.5s–4.0s` fuse that cannot be defused.
   - While *unlit* Time Bombs can be stored in the 3 Jacket Slots, a **lit/sparking Time Bomb cannot be stowed in the coat**. `Left-Clicking` a lit Bomb inside Top-Down Container View automatically slams the container shut, snaps the camera to FPS, and equips the live Bomb into the player's active hand in FPS view (tucking any held unlit gadget back into its Jacket Slot) to throw (`9.0m` arc).
   - If a thrown live Bomb hits a rival's body mid-air, that rival **instantly catches and equips the live Bomb into their active hand in FPS view** (tucking any held unlit gadget into its Jacket Slot / holstering the Club) so they can throw it right back.
5. **Decoupled Physical Audio Bridge (`res://core/audio_bridge.gd`):**
   - Never scatter raw `AudioStreamPlayer3D.play()` calls inside gameplay scripts. Route all acoustic events (`footsteps`, `door_open`, `drawer_slam`, `trap_arm`, `bomb_hiss`, `sneeze`, and Watch/Glasses `bluffs`) through `AudioBridge.request_world_cue(...)` / `AudioBridge.play_world_cue(...)` so spatial audio hooks into a single file.
6. **Zero-Bandwidth CRT Trap-Cam Replay:**
   - Never stream video frames over the network. Buffer a local `3.0s` (`~12 FPS`, low-res `240x135`) replay from a `SubViewport` attached to the **remote rival's head camera**, and play it back on the trap owner's HUD when their trap hits the rival. *(Performance note: avoid synchronous GPU→CPU `get_image()` stalls if they cause frame hitches in Forward+; prefer low-overhead texture rings or async readback when tuning.)*

## 5. Directory Structure & Team Boundaries
- `res://core/` — Autoloads & global managers (`network_manager.gd`, `eos_manager.gd`, `game_config.gd`, `match_manager.gd`, `match_spawner.gd`, `audio_bridge.gd`, `session_manager.gd`)
- `res://entities/player/` — Player scene & controller scripts (`player.gd`, `spy_inventory_component.gd`, `spy_ragdoll_controller.gd`)
- `res://entities/props/` — Bidirectional doors, searchable containers/drawers, dropped briefcase & world pickups, airport exit door
- `res://entities/traps/` — Planted/thrown trap scenes & scripts (`Tripwire`, `ThrownTimeBomb`, etc.)
- `res://scenes/` — `lobby.tscn`, `test_gym.tscn`, `BuildingComplex2/`, and upcoming embassy level scenes
- `res://ui/` — Top-Down Container overlay, Club QTE bar, DVD Dart reticle, CRT Replay monitor, Watch Bluff map, Mouse DPI settings
- `res://tests/` — Headless verification scripts (`test_phase0.gd` – `test_phase4.gd`, `door_interaction_check.gd`, etc.)
- `res://docs/` — Design specs (`MASTER-GAME-DESIGN-DOCUMENT...md`, `DOC-2...md` – `DOC-7...md`)
- **Team Workspace Boundaries (Read-Only Unless Asked):** Do not modify teammates' personal sandbox folders (`res://scenes/NoahWorkspace/`, `res://scenes/AgnetesTests/`) or overwrite raw imported art/scenes inside `res://Assets/` unless explicitly requested by the user.

## 6. Local Git Checkpoint & Push Protocol
Whenever you finish implementing, refactoring, or fixing any feature, mechanic, or documentation task:
1. **Pre-Commit Verification:** Use Godot MCP / CLI tools to verify zero GDScript parse errors, broken node paths, or corrupted `.tscn` files, and run relevant headless tests in `res://tests/` when touching gameplay logic.
2. **Stage Only Intentionally Modified Files (Never Blind `git add .`):** Run `git status` and explicitly stage only the files you created or edited (`git add <file1> <file2> ...`), keeping `.godot/`, `.vscode/`, logs, and unrelated files out of commits.
3. **Concise Structured Local Commit:** Commit locally as a clean undo checkpoint (`git commit -m "<header>" -m "<body>"`):
   - **Header:** `<type>(<scope>): <concise summary>` (e.g., `fix(briefcase): hide closed tray geometry and fix duplicate objective pickup`).
   - **Body:** Short bulleted list of files changed, behavior/tunable updates, and any RPC/authority changes.
4. **Push Only When Requested:** **Do NOT run `git push` automatically.** Wait until the user explicitly asks to push (e.g., after playtesting or signing off a mechanic) so unverified mid-loop iterations never hit `origin/main`. Always report the local commit hash and summary in your reply.
   - *(Windows shell note: if `git` is not on the default PowerShell `PATH`, check `C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe` or standard `C:\Program Files\Git\cmd\git.exe`.)*
