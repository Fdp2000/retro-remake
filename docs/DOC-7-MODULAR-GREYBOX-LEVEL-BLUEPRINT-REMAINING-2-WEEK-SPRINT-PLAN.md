# DOC 7: MODULAR GREYBOX LEVEL BLUEPRINT & REMAINING 2-WEEK SPRINT PLAN

**Parent Document:** Master GDD (v3.2)  
**Purpose:** Complete spatial specification for the modular square-room embassy grid, the 3-tier randomized furniture/loot spawner system, and the remaining 2-week production roadmap for a 4-person team.  
**Note on Numbers:** Values marked `[TUNABLE]` are starting playtest baselines.

## 1. Design Intent & Core Prototype Rules

1. **Fixed Modular Grid Over Procedural Walls:** Instead of complex procedural wall generation, the embassy is built from **identical square 4-walled room modules** snapped together into an interconnected maze (faithful to the 1984 NES layout).
2. **Clean Greybox First (Zero Palette/Art Bloat):** All rooms share uniform, readable greybox architecture during prototype testing. Keeping room geometry consistent isolates player focus onto **spatial audio, trap sightlines, bluffing, and pacing** without art-pipeline bottlenecks.
3. **High Replayability via Prefab & Loot Shuffling:** While the room grid and doorways remain fixed, **which furniture prefabs spawn inside each room** and **which drawers hold objectives, the Briefcase, and gadgets** randomize every match — preventing route memorization while keeping level setup trivial.
4. **Metrics Locked to Trap & Audio Math:** Every room measures **`6.0 m × 6.0 m` (`3.2 m` ceiling)** `[TUNABLE]` — sized specifically so a **`5.0 m` Time Bomb blast** blankets a single room (forcing players to either throw the bomb through a doorway or flee behind a closed door) while allowing clean directional sound propagation across adjacent rooms.

## 2. The Modular Room Grid & Maze Layout (Visual Blueprint)

### A. Standardized Room Module

- **Dimensions:** `6.0 m × 6.0 m` floor footprint, `3.2 m` wall height `[TUNABLE]`.
- **Wall Connectors (4 Cardinal Faces):** Each of the 4 walls has a centered **`1.4 m × 2.2 m` doorway opening**.
    - Interior connections receive a bidirectional **Embassy Door** (or an open archway on select central connectors for sightline variety).
    - Outer perimeter walls are sealed with a solid wall plug.
- **Acoustic & Anti-Camp Volume:** Every room contains a single room zone volume spanning the `6.0 m × 6.0 m` interior that:
    1. Tracks the **`20.0 s` Anti-Camp Sneeze** timer.
    2. Acts as a clickable target region + center-point emitter for the **Spy Watch / Glasses Remote Audio Bluff Map** (Doc 6).

### B. Recommended Prototype Layout (`3 × 3` Interconnected 9-Room Loop)

A `3 × 3` grid (`18 m × 18 m` total footprint) guarantees **zero dead-end traps**, symmetric starting distances for **Spy A** and **Spy B**, and a high-tension contested **Airport Exit Room**:

```
   ┌─────────────────┬─────────────────┬─────────────────┐
   │   [ROOM 0,0]    │   [ROOM 1,0]    │   [ROOM 2,0]    │
   │  SPY A SPAWN    ╫   NORTH HALL    ╫   NE OFFICE     │
   │                 │  (Bucket Spawn) │                 │
   ├════════╪════════┼════════╪════════┼════════╪════════┤
   │   [ROOM 0,1]    │   [ROOM 1,1]    │   [ROOM 2,1]    │
   │   WEST WING     ╫  AIRPORT EXIT   ╫   EAST WING     │
   │                 │  (Shared Door)  │                 │
   ├════════╪════════┼════════╪════════┼════════╪════════┤
   │   [ROOM 0,2]    │   [ROOM 1,2]    │   [ROOM 2,2]    │
   │   SW ARCHIVE    ╫   SOUTH HALL    ╫   SPY B SPAWN   │
   │                 │  (Bucket Spawn) │                 │
   └─────────────────┴─────────────────┴─────────────────┘

   LEGEND:
   ═══ / ╫  = Bidirectional Embassy Door (Rig-able with Water Bucket)
   [0,0] / [2,2] = Opposite-corner Spy Spawn Rooms (Safe from initial loot RNG)
   [1,1]         = Central Contested Room containing the single shared Airport Exit Door
```

*(Note: Once the `3 × 3` grid is playtested, expanding to a `3 × 4` 12-room grid simply requires snapping 3 more identical room modules onto one edge).*

## 3. Three-Tier Match Start Randomization System

At the start of every match, the Host/Server generates a single integer `match_seed` and broadcasts it so every client builds the exact same randomized layout deterministically:

### Tier 1: Furniture Prefab Spawning (`PropSpawnSlot`)

- Each non-spawn room contains **`3` wall-side `PropSpawnSlot` markers** (`21` total slots across 7 rooms; Spawn Rooms `[0,0]` and `[2,2]` have `1` slot each = **`23` total slots**).
- Using `match_seed`, the level spawner randomly assigns prefabs across those slots:
    - **`12` Searchable Containers** `[TUNABLE]` (desks/filing cabinets that open into Top-Down Drawer View).
    - **`6` Static Cover Props** (couches, bookshelves, or pillars to break line-of-sight against the DVD Dart Gun and create crouch ambush angles).
    - **`5` Empty Slots** (keeps floor space open for Tripwires and movement).

### Tier 2: Drawer Loot Pool Distribution

- All **`12` spawned Searchable Containers** are collected into an array, shuffled using `match_seed`, and populated with the **9 core drawer items**:
    - **Drawers `0–3` (4 Objectives):** `Key`, `Bag of Money`, `Passport`, `Secret Plans` (1 per drawer, hidden beneath `3–5` draggable clutter folders).
    - **Drawer `4` (1 Container):** `Compact Attaché Briefcase` (hidden beneath clutter).
    - **Drawers `5–8` (4 Gadgets):** `Spring Trap`, `Time Bomb`, `Tripwire Coil`, `DVD Dart Gun` (1 per drawer).
    - **Drawers `9–11` (3 Decoy Drawers):** Clutter folders only (still award **`+10 s`** private clock bonus on first search!).

### Tier 3: Open-World Water Bucket Spawns

- Across **`6` designated floor/corner markers** in hallways and side rooms, `match_seed` randomly spawns **`3` open-world Water Buckets** `[TUNABLE]` sitting visibly on the floor ready to be picked up (`Tap E`).

### Match Generation Workflow (Visual Flow)

```
[MATCH START] ──► Host generates `match_seed: int` ──► Broadcasts `match_seed` to all peers
                                                                 │
       ┌─────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┐
       ▼                                                         ▼                                                         ▼
[TIER 1: PREFAB SPAWN]                                [TIER 2: DRAWER SHUFFLE]                                 [TIER 3: FLOOR BUCKETS]
 Shuffle 23 PropSpawnSlots                             Shuffle 12 spawned Drawers:                               Shuffle 6 Floor Markers:
 • Spawn 12 Searchable Drawers                         • 4 Objectives (Key, Money, Passport, Plans)              • Spawn 3 Water Buckets
 • Spawn 6 Cover Props                                 • 1 Compact Briefcase                                       in open hallways/corners
 • Leave 5 Slots Empty                                 • 4 Gadgets (Spring, Bomb, Tripwire, Dart Gun)
                                                       • 3 Clutter-Only Drawers (+10s clock still active)
       │                                                         │                                                         │
       └─────────────────────────────────────────────────────────┼─────────────────────────────────────────────────────────┘
                                                                 ▼
                                            [SPAWN SPIES AT [0,0] & [2,2] WITH 03:00 CLOCK]
                                            (0 Pre-Armed Traps | Ready for Live Playtest)
```

## 4. Remaining 2-Week 4-Person Sprint Plan (Weeks 2 & 3)

With **Week 1** already completed (EOS networking foundation, core project setup, and physically based spatial audio architecture in place), the final **2 weeks** focus strictly on assembling the greybox loop, playtesting every mechanic, and polishing slapstick feedback:

| Role / Owner | Week 2 Goals (Core Greybox Loop Playable End-to-End) | Week 3 Goals (Playtest Tuning, Polish & Stretch) |
| --- | --- | --- |
| 1. Lead Designer / Gameplay Programmer | • Implement Spy dual movement (Walk, Sprint door-bash, 75% Silent Crouch) & Left Hand + 3-Slot Inner Jacket inventory rules (Doc 2). • Build bidirectional Embassy Door swing & Searchable Drawer Top-Down clutter/item drag view (Doc 3). • Wire private 03:00 clock (+10s per new search) & Airport Exit victory. | • Run daily 1v1 team playtests to tune `[TUNABLE]` numbers (clock duration, 2.5s–4.0s Bomb fuse, 35% Club charge speed, 20s Sneeze). • Balance Watch/Glasses bluff modes (`SELF_ONLY` vs. `MAP_PROJECTOR` & `show_enemy_room_blip`). • Prepare exam demo & design presentation. |
| 2. Traps & Combat Programmer | • Implement all 4 Traps (Water Bucket, Tripwire, Spring click-unlatch, Time Bomb 5.0m occluded blast & Hot-Potato catch/throw) + DVD Dart Gun (Doc 4). • Implement Charge-Only Club QTE bar (2.0s overcharge self-stumble) & 15s in-place Ragdoll KO + 3-Slot Jacket scatter + 2.0s blink immunity (Doc 5). | • Fix edge-case physics bugs (ragdoll wake-up clamping, live bomb hand-off sync, bucket spill distance). • Add juice: hit-stop, camera shake, dizzy KO stars, and DVD reticle corner-bounce flash. |
| 3. Audio & Replay Systems Programmer | • Hook all gameplay cues (footsteps, slams, trap arming, 20s Sneeze) into the existing physically based spatial audio pipeline (Doc 6). • Implement Wearable Spy Watch/Glasses comms (Hold V PTT) + bluff sound emitter. • Build the 240×135 12 FPS RingBuffer & 3.0s CRT Trap-Cam Replay HUD. | • Tune wall/door occlusion values so footsteps and bluffs read clearly across the 6m × 6m rooms. • Add CRT scanline shader, static transitions, and distinct cartoon foley (BONK, BOING, SSSSS-BOOM, ACHOO!). |
| 4. Level / Environment & UI Artist | • Build modular 6m × 6m greybox Embassy Room modules + 3 × 3 maze + 3-tier match randomizer spawner (Doc 7). • Create readable greybox models/silhouettes for the 4 Objectives, Compact Briefcase, 5 Traps/Gadgets, and Club. • Build clean HUD elements (Private Clock, Club QTE bar, Watch/Glasses map UI). | • Add clear diegetic signage (overhead Airport Exit signs, distinct prop silhouettes) so players navigate effortlessly without a minimap. • Stretch Goal: Add 2 extra spawn points & spy colors (Grey, Red) to enable 2–4 Player Free-For-All for the final exam demo. |
