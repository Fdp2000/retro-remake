# DOC 6: AUDIO ARCHITECTURE, WEARABLE COMMS & BLUFF DEVICE, 3.0S CRT REPLAY & ANTI-CAMPING

**Parent Document:** Master GDD (v3.2)  
**Purpose:** Complete behavioral specification, playtest theory for the Wearable Spy Comms/Bluff Device (Wristwatch / Smart Glasses), 3.0-second CRT Trap-Cam Replay workflow, Anti-Camping Sneeze rules, and acoustic propagation rules.  
**Note on Numbers:** Values marked `[TUNABLE]` are starting playtest baselines.

## 1. Design Intent & Core Rules

1. **Built on the Physically Based Audio Pipeline:** Every sound event (footsteps, doors, drawers, proximity voice, bluffs, and sneezes) routes through the project's physically based spatial audio pipeline so wall occlusion, doorway propagation, and room reverb behave identically for real actions and bluffs.
2. **Audio = Primary Situational Awareness:** With no always-on split-screen, directional sound is how spies track rivals through walls — and how clever spies feed false information to bait rivals into traps.
3. **Unambiguous Trap Confirmation:** Audio bluffs mimic *setup and movement* cues (arming traps, footsteps, drawer slams), never trap detonation impacts — ensuring the **3.0-second CRT Trap-Cam Replay** remains a 100% trustworthy confirmation when your trap actually hits a rival.

## 2. Acoustic Event Categories & Physically Based Audio Rules

All gameplay interactions emit standardized acoustic triggers into the physically based spatial audio system:

| Acoustic Source | Trigger Event | Base Emission Radius [TUNABLE] | Physical Audio Behavior |
| --- | --- | --- | --- |
| Proximity Voice Chat | Continuous mic input (while not holding V) | 12.0 m | Attenuated by distance and muffled/occluded by closed doors and walls via the physical audio pipeline. |
| Long-Range Comms (Hold V) | Push-to-Talk on Wearable Spy Device | Global (Embassy-wide) | Transmitted with a crisp retro radio filter so both spies can trash-talk, negotiate, or bluff vocally from anywhere. |
| Locomotion Footsteps | Quiet Walk / Loud Sprint / Jump Land | Walk: 3.0 m \| Sprint: 14.0 m \| Crouch: 0.0 m | Propagates down hallways and through open doorways; crouch is completely silent. |
| Doors & Drawers | Fast Slam (Tap E / Sprint Bash) vs. Slow Peek (Hold E) | Fast: 8.0–14.0 m \| Slow: 0.0 m | Tells nearby rivals whether a spy is rushing greedily or carefully inspecting for traps. |
| Trap Setup & Triggers | Bucket clank, Tripwire snap, Spring clack, Bomb fuse hiss | Setup: 5.0 m \| Bomb Fuse: 10.0 m | Subtle setup cues reward close listening; loud Bomb fuse triggers immediate panic. |
| Directional Bluffs (B / Tab) | Emitted via Wearable Spy Device | 12.0 m (matches real action cues) | Routed through the exact same physical occlusion/propagation pipeline as genuine world sounds so rivals cannot distinguish a bluff by audio quality alone. |
| Anti-Camp Sneeze | 20.0 s idle inside one RoomZone | 22.0 m (cross-wing audible) | Loud cartoonish "ACHOO!" that propagates through doorways/walls to reveal a stationary camper's wing. |

## 3. Wearable Spy Comms & Bluff Device (Spy Wristwatch / Smart Glasses)

*Design Note (Refining Doc 2 v1.2):* The device is worn permanently (raising the **Spy Wristwatch** or activating the **Smart Glasses** lens), never occupies the Left Hand or the **3 Inner Jacket Slots**, and cannot be dropped.

### A. The 4 Selectable Bluff Sound Cues

Players cycle between **4 iconic deception cues** (`Scroll Wheel` while holding `Tab`, or tapping `C` to cycle):

1. **Trap-Arming Click/Clank:** Mimics rigging a Water Bucket, Spring, or Time Bomb (tricks rivals into avoiding clean doors/drawers or wasting time slow-peeking).
2. **Fast Drawer Slam & Paper Rustle:** Mimics aggressively looting a container (baits rivals into rushing your room for an ambush — straight into your real Tripwire or Bucket).
3. **Sprint Footstep Burst (`2.0 s`):** Mimics a spy sprinting down a corridor (fakes an approach or retreat).
4. **Door Bash / Swing:** Mimics a door slamming open in another room.

### B. Playtest Design Theory: Mode A (Self-Emitter) vs. Mode B (Map Remote Projector)

Because the team is actively testing how effective directional audio bluffs are in 3D space, **two operating modes** are documented here for Week 2 playtesting:

| Feature / Aspect | Mode A: Self-Position Emitter (Press B) | Mode B: Map-Click Remote Projector (Hold Tab) |
| --- | --- | --- |
| How It Works | Pressing B immediately plays the selected bluff sound from the player's own 3D body position. | Holding Tab raises the Spy Watch / Smart Glasses showing a retro top-down embassy map. Clicking any room on the map spawns a temporary virtual 3D audio source in that room and plays the bluff sound from there. |
| Tactical Strength | Zero UI interruption; great for faking a trap-arming click right behind a closed door while you wait with a Club. | Enables true cross-map misdirection (e.g., playing a fake drawer slam in the North Hall while you sneak through the South Hall). |
| OG Enemy Blip Variable | N/A (No map UI). | Includes a boolean playtest toggle: `show_enemy_room_blip: bool = false` `[TUNABLE]` to test whether seeing the rival's room dot on the watch/glasses improves bluff timing or gives away too much info. |
| Playtest Recommendation | Implement both behind a `bluff_mode` toggle (`SELF_ONLY` vs. `MAP_PROJECTOR`). Mode B directly solves the concern that self-positioned bluffs are too predictable when rivals already hear your footsteps. | |

## 4. The 3.0-Second CRT Trap-Cam Replay (Past Incident Playback)

### A. Functional Behavior

- **When It Triggers:** Exclusively when **your trap or DVD Dart hits a rival** (`trap_owner_id == local_peer_id` AND `victim_peer_id != local_peer_id`). *(Self-inflicted trap hits do not open the CRT window since you experience them live).*
- **What It Shows:** A retro curved CRT monitor frame pops into the top-right corner of the trap owner's HUD for **`3.0 seconds`** `[TUNABLE]` and plays back the **actual past 3.0 seconds** leading up to and including the slapstick impact from the **victim's first-person POV** (including the trap owner themselves if they were standing in front of the victim).
- **Audio:** Plays a subtle CRT *click-on* static burst, muted impact foley, and CRT *click-off* after `3.0 s`.

### B. Image Ring Buffer Workflow (Zero Network Video Streaming)

Because both spies' 3D character meshes, animations, and trap states are replicated locally on every client, no video frames ever need to be sent over the network:

```
[CONTINUOUS BACKGROUND CAPTURE (Every 0.083s = 12 FPS)]
  Rival's HeadCamera -> Low-Res Viewport (240x135) -> Grab Image -> Push to 36-Slot Circular RingBuffer
                                                                             │
                                              [RIVAL TRIGGERS YOUR TRAP!] ◄──┘
                                                       │
                                                       ▼
                                    [FREEZE RINGBUFFER WRITES FOR 3.0s]
                                                       │
                                                       ▼
                        [PLAY FRAMES 0 -> 35 AT 12 FPS ON CORNER CRT MONITOR]
                        (Shows exact past 3.0s from rival's POV, including you if visible!)
                                                       │
                                                       ▼
                                   [CRT STATIC OFF -> RESUME RINGBUFFER]
```

## 5. Anti-Camping "Restless Spy" Sneeze

### A. Purpose & Rules

To prevent passive corner-camping or exit-guarding without adding artificial HUD wallhacks or radar arrows, every spy has a hidden **Restlessness Timer** driven by embassy room zones:

- **Trigger Threshold:** Remaining inside the **same room zone** for **`20.0 seconds`** `[TUNABLE]` without performing an active interaction.
- **Actions That Reset the Timer:**
    1. Entering a **different room zone** (crossing into a new room or hallway).
    2. Opening or closing any **Door** or **Searchable Drawer**.
    3. Picking up, dropping, or packing any **Objective, Briefcase, or Trap**.
    4. Arming or disarming any **Trap** (or projecting a Watch/Glasses bluff).
    5. Charging the **Two-Handed Club** or firing the **DVD Dart Gun**.
- **Escalation Timeline:**
    - **`t = 15.0 s` (Local Warning):** The camping spy hears a subtle personal sniffle/throat-clear (`local_only`) as a fair warning to move or interact.
    - **`t = 20.0 s` (Public Sneeze Reveal):** The spy lets out a loud, echoing cartoon **`"ACHOO!"`** (`22.0 m` radius `[TUNABLE]`) routed through the physically based audio engine — immediately alerting nearby rivals to their exact room direction through walls and doors. *(Repeats every `15.0 s` if the spy still refuses to move).*

## 6. Unified Audio & Replay Workflow (Visual Flow)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                    EXISTING PHYSICALLY BASED SPATIAL AUDIO TECH STACK                   │
│             (Handles Wall Occlusion, Doorway Propagation, Distance & Reverb)            │
└──────▲──────────────────────────▲──────────────────────────▲──────────────────────▲─────┘
       │                          │                          │                      │
 [PROXIMITY VOICE]      [WORLD ACTIONS]            [WEARABLE COMMS / BLUFF]   [20s IDLE IN ROOM]
 (12m Occluded Mic)     (Walk/Sprint/Doors/        • Hold V: Embassy Comms    (15s Local Sniffle ->
                         Drawers/Traps)            • B: Self-Pos Bluff         20s Loud "ACHOO!")
                                                   • Tab Map: Remote Room
                                                     Virtual Emitter Bluff
                                                             │
                                              [DOES REAL TRAP HIT RIVAL?]
                                                             │
                                              ┌──────────────┴──────────────┐
                                              ▼                             ▼
                                           [BLUFF]                     [REAL HIT!]
                                    (No CRT Replay; Rival        (3.0s CRT Trap-Cam Replay
                                     must judge by audio)         plays 36-frame past POV)
```
