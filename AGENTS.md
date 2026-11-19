# Project: Spy vs. Spy 3D Remake (Godot 4.7.2)

## 1. Engine & Code Rules
- **Godot 4.7.2-stable (GDScript 2.0):** Use strict static typing and Godot 4 annotations (`@export`, `@onready`, `@rpc`). Never use Godot 3 syntax.
- **Assets-When-Available / Greybox-Fallback:** Use `res://Assets/` prefabs when present; otherwise use clean primitives (`MeshInstance3D`, `CSGBox3D`) and `Tween`s. Never treat `res://docs/` Markdown as hardcoded node-tree mandates.
- **Tunables (`res://core/game_config.gd`):** Expose `[TUNABLE]` gameplay numbers in `GameConfig` or `@export` vars, not magic constants.
- **Modularity:** `player.gd` and `searchable_container.gd` are already large—prefer extracting focused child components (like `SpyInventoryComponent`, `SpyRagdollController`) for new subsystems.
- **Godot MCP Speed Tip:** When editing `.gd` scripts with Godot MCP active, prefer `script_patch` (reloads in place and avoids stale `preload()` cache re-runs during `test_run`).

## 2. Multiplayer & Authority
- **Listen-Server:** Local ENet (`port 8910`) & EOS P2P (`EOSGMultiplayerPeer`, socket `"SpyVsSpySocket"`, 2 core / 4 max).
- **Spawning:** `MultiplayerSpawner` on `Players` container; spawned player node names must equal `str(peer_id)`.
- **Client-Authoritative Locomotion (`MultiplayerSynchronizer`):** `set_multiplayer_authority(name.to_int())`; `spy_role` derived in `_enter_tree()` (`peer 1` = Green/`AgentGreen.tscn`, `peer != 1` = Purple/`AgentPurple.tscn`). Sync **only** `:position`, `:rotation:y`, `head_pitch`, `spy_role`, `stance_state`. **Never** put inventory/briefcase/club fields in `MultiplayerSynchronizer`—those are Host-owned (`peer_id == 1`) and broadcast via reliable RPC (`_rpc_sync_inventory`).
- **Server-Authoritative Interactions:** Clients request door/drawer/pickup/trap/KO actions via `rpc_id(1, ...)`; Host validates (locks, ownership, `2.0s` immunity) and broadcasts via reliable RPCs.
- **Ragdoll & Wake-Up Sync:** Broadcast KO impulse once; run local 13-bone `PhysicalBoneSimulator3D` on `Skeleton3D` with `~5 Hz` pelvis hints, `Camera3D` locked to `spine.006` (keepalive mesh unculled), and floor-snapped 8-way wall-cleared pelvis wake-up at `15.0s`.
- **Deterministic Randomization:** Host generates `match_seed` and syncs via RPC; peers use local `RandomNumberGenerator` seeded with `match_seed`.

## 3. Physics & Collision Layers
- **Layer 1 (`1` `Environment`):** Solid walls, floors, ceilings, **closed** door leaves (blocks movement + occludes `5.0m` Bomb blasts / `2.0m` Club slams).
- **Layer 2 (`2` `Interactable`):** Doors, containers/drawers, dropped Briefcase, pickups, planted traps (`InteractRayCast` `2.2m`).
- **Layer 3 (`4` `Player`):** Standing (`1.8m`) / crouched (`1.0m`) capsules.
- **Layer 4 (`8` `Ragdoll_KO`):** Active during `15.0s` KO (collides Layer 1, ignores Layer 3).
- **Layer 5 (`16` `Triggers_And_Zones`):** `RoomZone`, `DoorBashDetector`, `Tripwire`, `WaterBucket` splash, airborne `TimeBomb` catch colliders.
- **Layer 6 (`32` `Drawer_Contents`):** 3D interior clutter, stored items, and drawer traps (Top-Down View only).

## 4. Gameplay Pillars & Playtest Override
> **Playtest Override:** Live user playtest feedback overrides GDD micro-details. Implement what feels right; **do not** edit `res://docs/` unless asked.

1. **No HP:** Valid traps, DVD Dart hits, and green-zone Club slams inflict `15.0s` ragdoll KO, drop Left Hand + scatter all 3 Jacket Slots (Club re-holsters), and grant `2.0s` wake-up blink immunity.
2. **Physical Left Hand & 3-Slot Jacket:**
   - **Left Hand (`Q` drop):** `1` loose Objective (`KEY`/`MONEY`/`PASSPORT`/`PLANS`) OR `CompactBriefcase` (`0.90` speed, `0–4` Objectives).
   - **3-Slot Jacket (`1/2/3`/Scroll, `G` drop):** Up to `3` traps/gadgets (`BUCKET`, `TRIPWIRE`, `SPRING`, unlit `BOMB`, `DART_GUN`); fills first empty slot, swaps only when all `3` are full.
   - **Club (`4`/`R`):** Toggling tucks held gadget back into Jacket (`1.00` idle / `0.35` charging `Hold LMB`, auto-drops Briefcase).
   - **Watch/Glasses:** Permanent (`Hold V` radio, `B`/`Tab` bluffs); uses no slots.
3. **100% Player-Driven Traps:** `starting_prearmed_traps = 0`; all traps trigger identically on owner and rival.
4. **Hot-Potato Time Bomb:** Rigged drawer/briefcase ignites `2.5s–4.0s` un-defusable fuse on open. Lit Bombs cannot be stowed in Jacket; clicking one in Top-Down View slams container shut and equips it live in FPS (`9.0m` throw); mid-air rival hit auto-equips it live in their hand.
5. **Audio (`res://core/audio_bridge.gd`):** Route all world sounds via `AudioBridge.request_world_cue(...)` / `play_world_cue(...)`.
6. **CRT Trap-Cam Replay:** Local `3.0s` (`~12 FPS`, `240x135`) `SubViewport` buffer on remote rival's head camera; never stream video over network.

## 5. Boundaries
- **Read-Only Unless Asked:** `res://scenes/NoahWorkspace/`, `res://scenes/AgnetesTests/`, and raw imported art/scenes in `res://Assets/`.

## 6. Fast Verification & Local Git Checkpoints
- **Targeted Verification:** After gameplay edits, check syntax/diagnostics and run the **relevant** suite(s) via `test_run(suite=...)` (skip full-suite runs on small UI/tweak edits unless core state changed, or if the user asks to skip tests for quick playtesting).
- **Explicit Local Commit:** Stage only files you edited (`git add <file1> ...` — never `git add .`; keep `.vscode/`, `.godot/`, logs untracked) and commit locally (`<type>(<scope>): <summary>`). **Never run `git push`** unless explicitly asked.
  - *(Windows git path if missing from `PATH`: `C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd\git.exe`.)*
