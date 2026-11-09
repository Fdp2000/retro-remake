# Project: Minimal 3D First-Person Multiplayer Skeleton (Godot 4.x)

## Architectural Constraints
- **Engine Version:** Godot 4.7.2 (GDScript only). Do not use deprecated Godot 3 networking syntax.
- **Perspective:** First-Person (Camera inside Head node at eye level ~1.6m).
- **Multiplayer Architecture:** Listen-server using ENetMultiplayerPeer on port 8910 (2 players max).
- **Authority Boundaries:**
  - Client-authoritative movement (`set_multiplayer_authority(name.to_int())`).
  - Spatial replication: `MultiplayerSynchronizer` syncing `:position`, `:rotation:y` (Body Yaw), and head pitch float.
  - Server-authoritative interactions: clients request interactions via `server_interact.rpc_id(1, ...)`; host validates and state is synchronized to all peers via authority RPC `sync_state.rpc(...)`.
- **Collision Layers:**
  - Layer 1: Environment
  - Layer 2: Interactable
  - Layer 3: Player
- **Spawning:** `MultiplayerSpawner` watching a shared `Players` container. Spawned node names must match stringified peer IDs (`str(peer_id)`).

## Directory Structure
- `res://core/network_manager.gd` (Autoload)
- `res://core/eos_manager.gd` (Autoload)
- `res://entities/player/player.tscn` & `player.gd`
- `res://entities/interactable_box.tscn` & `interactable_box.gd`
- `res://scenes/test_gym.tscn` & `test_gym.gd`