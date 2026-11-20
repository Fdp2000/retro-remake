# Project: Spy vs. Spy 3D Remake (Godot 4.7.2)

## 1. Workflow & Boundaries (Strict)
- **Read-Only Paths:** Never edit `res://scenes/NoahWorkspace/`, `res://scenes/AgnetesTests/`, raw imported art/scenes in `res://Assets/`, or `res://docs/` unless explicitly asked.
- **Playtest Override:** Live user feedback overrides GDD details. Never treat `res://docs/` as rigid node-tree mandates.

## 2. Engine & Code Standards
- **Godot 4.7.2 (Strict Typed GDScript 2.0):** Use static typing and Godot 4 annotations (`@export`, `@onready`, `@rpc`).
- **Godot MCP:** Prefer `script_patch` when editing `.gd` files to avoid stale cache issues.
- **Modularity:** `player.gd` and `searchable_container.gd` are already large—extract focused child components for new subsystems.
- **Centralized Systems:** Put tunable values in `res://core/game_config.gd` (or `@export` vars). Route all world audio through `res://core/audio_bridge.gd` (`request_world_cue` / `play_world_cue`).
- **Visuals:** Use existing `res://Assets/` prefabs when available; otherwise fall back to clean greybox primitives and `Tween`s.

## 3. Multiplayer & Authority Rules
- **Architecture:** Listen-server (ENet `8910` & EOS P2P `"SpyVsSpySocket"`). `MultiplayerSpawner` on `Players` must name player nodes `str(peer_id)`.
- **Client-Authoritative Movement (`MultiplayerSynchronizer`):** `set_multiplayer_authority(name.to_int())`. Sync **only** `:position`, `:rotation:y`, `head_pitch`, `spy_role`, and `stance_state`.
- **Host-Authoritative State (CRITICAL):** **Never** put inventory, briefcase, or club fields in `MultiplayerSynchronizer`. All interactions (doors, drawers, pickups, traps, KOs) must be requested via `rpc_id(1, ...)`, validated by Host (`peer_id == 1`), and broadcast via reliable RPCs (e.g., `_rpc_sync_inventory`).
- **Determinism & Bandwidth:** Seed match randomization with a Host-synced `match_seed` using a local `RandomNumberGenerator`. Broadcast ragdoll KO impulses once (simulate locally; sync wake-up pelvis only). Never stream video over the network for the CRT replay (use a local `SubViewport` ring buffer).

## 4. Physics & Collision Layers (Bitmasks)
- **Layer 1 (`1` `Environment`):** Walls, floors, ceilings, closed door leaves (occludes Bomb blasts & Club hits).
- **Layer 2 (`2` `Interactable`):** Doors, containers, Briefcase, pickups, planted traps.
- **Layer 3 (`4` `Player`):** Active player capsules.
- **Layer 4 (`8` `Ragdoll_KO`):** Knocked-out ragdolls (collides Layer 1, ignores Layer 3).
- **Layer 5 (`16` `Triggers_And_Zones`):** `RoomZone`, `DoorBashDetector`, `Tripwire`, `WaterBucket` splash, live `TimeBomb` catch.
- **Layer 6 (`32` `Drawer_Contents`):** 3D interior clutter, stored items, and drawer traps.

## 5. Core Design Invariants
- **No HP:** Valid traps, darts, and Club sweet-spot slams inflict `15s` in-place ragdoll KO, drop Left Hand + scatter all 3 Jacket slots (Club re-holsters), and grant `2s` wake-up immunity.
- **Inventory:** Left Hand holds `1` Objective or `CompactBriefcase`; Inner Jacket holds `3` traps/gadgets (Club toggle tucks gadget back into Jacket; charging Club drops Briefcase only); Watch/Glasses uses no slots.
- **Traps:** `0` pre-armed at match start; all traps trigger identically on owner and rival. Lit Time Bombs cannot be stowed in Jacket (equip live for throw / mid-air rival catch).