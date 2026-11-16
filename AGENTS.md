# Project: Spy vs. Spy 3D Remake (Godot 4.7.2 Greybox Prototype)

## 1. Engine & Architectural Constraints
- **Engine Version:** Godot 4.7.2-stable (GDScript 2.0 only). Use strict static typing (`var speed: float = 4.5`) and Godot 4 annotations (`@export`, `@onready`, `@rpc`). Never use deprecated Godot 3 syntax.
- **Greybox-First Principle:** Build mechanics using clean primitive meshes (`CSGBox3D`, `MeshInstance3D`), readable silhouettes, and minimal procedural animations (`Tween`). Prioritize responsiveness and network determinism over visual bloat.
- **Centralized Tunables (`res://core/game_config.gd`):** Never hardcode magic gameplay numbers across scripts. Expose all `[TUNABLE]` baselines (movement speeds, timer durations, fuse ranges, audio radii) in `GameConfig` or cleanly grouped `@export` inspector variables.

## 2. Multiplayer & Authority Architecture
- **Dual-Backend Listen-Server:** Local ENet (`port 8910`) and Epic Online Services P2P (`EOSGMultiplayerPeer`, socket `"SpyVsSpySocket"`, 2 players core / 4 max stretch).
- **Spawning:** `MultiplayerSpawner` watching a shared `Players` container. Spawned player node names must strictly match stringified peer IDs (`str(peer_id)`).
- **Client-Authoritative Locomotion:**
  - Each `player.tscn` runs `set_multiplayer_authority(name.to_int())` for zero-lag FPS movement and stances.
  - Replicate `:position`, `:rotation:y` (body yaw), `head_pitch: float`, `stance_state: int`, `left_hand_item_id: String`, `right_hand_item_id: String`, and `is_charging_club: bool` via `MultiplayerSynchronizer`.
- **Server-Authoritative World & Trap Interactions:**
  - Clients request world interactions (opening doors/drawers, picking up/dropping items, arming/stealing traps, catching/throwing live bombs, triggering KOs) via `server_interact.rpc_id(1, ...)`.
  - Host (`peer_id == 1`) validates state (single-user drawer lock, item ownership, `2.0s` wake-up immunity) and broadcasts deterministic updates to all peers via `sync_state.rpc(...)`.
- **Deterministic Match Randomization:**
  - Never use unseeded global `randi()` or `randf()` for level/loot generation.
  - Host generates `match_seed: int` at match start and syncs it via RPC. All peers use a local `RandomNumberGenerator.new()` initialized with `rng.seed = match_seed` to spawn identical room prefabs, drawer loot, and floor buckets.

## 3. Physics & Collision Layers
- **Layer 1 (`Environment`):** Solid walls, floors, ceilings, and **closed** door leaves (blocks movement AND occludes `5.0m` Time Bomb blasts / `2.0m` Club slams).
- **Layer 2 (`Interactable`):** Doors, searchable drawers, dropped Briefcase, loose objectives, and planted traps (queried by player `InteractRayCast` at `2.2m` reach).
- **Layer 3 (`Player`):** Active standing/crouching `SpyCharacter` capsules (`1.8m` standing -> `1.0m` crouched).
- **Layer 4 (`Ragdoll_KO`):** Active during the `15.0s` in-place `PhysicalBoneSimulator3D` knockout state (collides with `Layer 1 Environment`, ignores `Layer 3 Player` to prevent hallway body-blocking).
- **Layer 5 (`Triggers_And_Zones`):** `RoomZone` volumes (`20.0s` Anti-Camp Sneeze & Watch map targets), `DoorBashDetector`, `Tripwire` rays, `WaterBucket` splash zones, and airborne `TimeBomb` direct-hit catch colliders.

## 4. Non-Negotiable Gameplay Invariants (Do Not Violate)
1. **No Health Bars or Generic Gunplay:** Spies do not have HP. Every valid trap trigger, DVD Dart hit, or green-zone Club slam inflicts the unified **`15.0s` in-place Ragdoll KO**, forces a **full drop of both hands**, and grants **`2.0s` wake-up blink immunity** upon standing up at the pelvis navmesh position.
2. **Strict Two-Handed Physical Inventory (No Hidden Inventory Grids):**
   - **Left Hand (`Q` to drop):** Holds `1` loose Objective (`KEY`, `MONEY`, `PASSPORT`, `PLANS`) OR the `CompactBriefcase` (`0.90` move speed; stores `0–4` Objectives).
   - **Right Hand (`G` to drop traps/gun; `1` to toggle personal Two-Handed Club from back):** Holds `1` Trap/Gadget OR the Club (`1.00` speed idle; `0.35` speed while charging `Hold LMB`, which auto-drops the Briefcase if held in Left Hand).
   - **Wearable Spy Watch / Smart Glasses:** Permanent non-droppable utility (`Hold V` global radio voice; `B` / `Tab` directional audio bluffs). Never occupies hand slots.
3. **100% Player-Driven Traps & Owner-Trigger Parity:**
   - Matches start with `starting_prearmed_traps = 0`.
   - All traps (`WaterBucket`, `Tripwire`, `SpringTrap`, `TimeBomb`) trigger identically on **both** the rival and the trap's owner (`peer_id` grants zero immunity).
4. **Hot-Potato Time Bomb Rules:**
   - Opening a rigged drawer or Briefcase (`Tap E` or `Hold E`) ignites a `2.5s–4.0s` fuse that cannot be defused.
   - `Left-Clicking` a lit Bomb inside Top-Down Container View automatically slams the container shut, snaps the camera to FPS, and equips the live Bomb into the player's Right Hand to throw (`9.0m` arc).
   - If a thrown live Bomb hits a rival's body mid-air, that rival **instantly catches and equips it into their Right Hand** (dropping any existing Right-Hand item).
5. **Decoupled Physical Audio Bridge (`res://core/audio_bridge.gd`):**
   - Never scatter raw `AudioStreamPlayer3D.play()` calls inside gameplay scripts. Route all acoustic events (`footsteps`, `door_open`, `drawer_slam`, `trap_arm`, `bomb_hiss`, `sneeze`, and Watch/Glasses `bluffs`) through `AudioBridge.play_world_cue(cue_id, world_pos, radius, source_peer_id)` so the Physically Based Spatial Audio pipeline hooks into a single file.
6. **Zero-Bandwidth CRT Trap-Cam Replay:**
   - Never stream video frames over the network. Capture a continuous `12 FPS` (`36-frame`, `240x135` `FORMAT_RGB8`) circular ring buffer locally from the remote rival's `HeadCamera` `SubViewport` and play it back on the trap owner's HUD when their trap hits the rival.

## 5. Directory Structure
- `res://core/` — Autoloads & global managers (`network_manager.gd`, `eos_manager.gd`, `game_config.gd`, `match_manager.gd`, `audio_bridge.gd`)
- `res://entities/player/` — `player.tscn`, `player.gd`, hand socket controllers, Club QTE & Ragdoll KO handlers
- `res://entities/props/` — `embassy_door.tscn`, `searchable_drawer.tscn`, `compact_briefcase.tscn`, objective pickups
- `res://entities/traps/` — `trap_base.gd`, `water_bucket.tscn`, `tripwire.tscn`, `spring_trap.tscn`, `time_bomb.tscn`, `dvd_dart_gun.tscn`
- `res://scenes/` — `test_gym.tscn`, `embassy_room.tscn` (`6m x 6m` module), `embassy_level.tscn` (`3x3` maze + `match_randomizer.gd`)
- `res://ui/` — Private clock HUD, Top-Down Drawer overlay, Club QTE bar, CRT Replay monitor, Watch/Glasses Bluff Map
- `res://docs/` — Reference GDD Markdown files (`01_master_gdd.md` – `08_miro_quick_reference.md`) and Audio Implementation Plan

## 6. Automated Git Commit & Push Protocol (Mandatory Completion Step)
Whenever you finish implementing, refactoring, or fixing any feature, phase, or documentation task, you **MUST** automatically commit and push your work to GitHub before ending your turn:
1. **Pre-Commit Verification:** Use Godot MCP / CLI tools to verify there are zero GDScript parse errors, broken node paths, or corrupted `.tscn` files before staging.
2. **Stage Cleanly:** Run `git status` and stage all relevant modified/created files (`git add .`), ensuring temporary editor cache files (`.godot/`, logs, build artifacts) remain ignored.
3. **Highly Detailed Commit Message:** Commit using a structured multi-line message (`git commit -m "<header>" -m "<body>"`):
   - **Header:** `<type>(<scope>): <concise summary of what was built/fixed>` (e.g., `feat(traps): implement hot-potato time bomb fuse, throw, and mid-air catch`).
   - **Body:** Include a detailed bulleted breakdown covering:
     - **Scenes & Scripts Changed:** Exact `.tscn` and `.gd` files created or updated.
     - **Mechanics & GDD Alignment:** How the implementation satisfies the locked GDD rules and `[TUNABLE]` variables exposed.
     - **Networking & Authority:** Any new RPCs (`server_interact`, `sync_state`), `MultiplayerSynchronizer` properties, or authority validations added.
4. **Push Immediately:** Run `git push` to push the commit directly to the active remote GitHub branch and report the commit hash and summary in your final response.