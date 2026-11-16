# DOC 3: UNIFIED BIDIRECTIONAL DOORS & TOP-DOWN DRAWER SEARCH SYSTEM

**Parent Document:** Master GDD (v3.2)  
**Purpose:** Complete behavioral specification, asymmetric risk-reward workflows, and clutter/coat interaction rules for embassy doors, searchable containers, and Briefcase inspection.  
**Note on Numbers:** Values marked `[TUNABLE]` are starting playtest baselines.

## 1. Design Intent & Core Rules

1. **Zero Doorway Clipping (Bidirectional Swing):** Every door in the embassy swings **away from whichever side the player approaches from**, eliminating awkward back-pedaling, camera clipping, and hallway blockages.
2. **The Doorway Sightline Test:** Doors never auto-open when walking normally. Players who sprint blindly bash straight into doorway Water Buckets; players who stop, look up at the top edge of the door leaf, or open from max reach (`1.8 m`) can steal or spill the bucket safely.
3. **Asymmetric Drawer Gamble (`Tap E` vs. `Hold E`):** Every drawer forces a tactical choice with opposite trap outcomes — **Fast Slam (`Tap E`)** is loud and triggers Springs, while **Slow Peek (`Hold E`)** is silent and bypasses Springs, *but* burns precious escape time if a Time Bomb fuse ignites inside.
4. **Unified Container Architecture:** Searchable desk drawers, filing cabinets, and a dropped **Compact Briefcase** all share the exact same **Top-Down Container View**, letting players inspect contents, drag items into their Left Hand or **3-Slot Inner Jacket**, or plant Time Bombs inside a dropped Briefcase.

## 2. Unified Bidirectional Door System

### A. Door Opening Modes & Audio Footprints

| Interaction Method | Input | Swing Duration [TUNABLE] | Audio Emission Radius [TUNABLE] | Physical & Trap Behavior |
| --- | --- | --- | --- | --- |
| Fast Open | Tap E (aimed at door) | 0.25 s (90° away) | 8.0 m (adjacent rooms) | Swings open briskly; triggers any perched Water Bucket once angle passes 25°. |
| Sprint Auto-Bash | Hold Shift + walk into door | 0.12 s (90° away) | 14.0 m (heard 1–2 rooms away) | Automatically slams door open on chest contact with zero slowdown; triggers Water Bucket. |
| Slow Peek Open | Hold E (0.6 s) | 0.60 s (90° away) | 0.0 m (silent creak-free) | Opens quietly without alerting nearby rivals — still triggers an armed Water Bucket if not disarmed first! |
| Close Door | Tap E (on open door) | 0.30 s (returns to 0°) | 5.0 m soft click | Resets door to closed state so a new Water Bucket can be rigged onto it. |

### B. Bidirectional Swing Math & Water Bucket Edge Cases

- **Always Opens Away (`Dot Product Rule`):** When triggered, the door checks which side the player is standing on relative to the door's forward normal (`sign(door_forward.dot(player_pos - door_pos))`) and rotates `90°` in the opposite direction.
- **The `25°` Water Bucket Release Rule:**
    - A rigged Water Bucket sits perched on the **top edge of the door leaf itself** (propping the door slightly ajar by `~5°` as a subtle visual tell).
    - The instant the door swings past **`25°`**, gravity releases the bucket straight downward at the door's threshold:
    - **Standard Range (`≤ 1.2 m` from doorway):** Bucket crashes onto the player's head -> **15s Ragdoll KO + Full Left-Hand & 3-Slot Inner Jacket Scatter**.
    - **Max-Reach Bait (`1.3 m – 1.8 m` away):** If a cautious player stands at maximum interaction reach, taps `E` to swing the door open, and stays back, the bucket **crashes onto the floor empty** (`12.0 m` loud *SPLASH + CLATTER*), ruining the bucket so neither spy can reuse it while missing the player completely.
    - **Stealing a Bucket (`Hold E` on Bucket):** Aiming directly at the bucket on top of a closed door and holding `E` (`1.0 s`) lifts it cleanly into the **first empty Inner Jacket Slot** (or swaps with the active slot if all 3 Jacket Slots are full).

### C. Door Interaction Workflow (Visual Flow)

```
[APPROACH CLOSED EMBASSY DOOR]
       │
       ├──► LOOK UP AT TOP EDGE OF DOOR ──► Spot Water Bucket? ──► Aim at Bucket + Hold E (1.0s) ──► [STEAL TO INNER JACKET (SLOTS 1–3)]
       │
       ├──► SPRINT INTO DOOR (Shift) ────► Auto-Bashes 90° Away (0.12s | 14m Loud) ──┐
       ├──► TAP E ON DOOR ───────────────► Fast Opens 90° Away (0.25s | 8m Audio) ───┼──► [DOOR PASSES 25°]
       └──► HOLD E ON DOOR (0.6s) ───────► Silent Open 90° Away (0.60s | 0m Silent) ──┘          │
                                                                                                 ▼
                                                                                     [IS WATER BUCKET ARMED?]
                                                                                       ├── NO  ──► Walk Through Safely
                                                                                       └── YES ──► Bucket Drops at Threshold:
                                                                                                   • Player ≤ 1.2m -> [15s RAGDOLL KO]
                                                                                                   • Player > 1.2m -> [SPILLS ON FLOOR / RUINED]
```

## 3. Searchable Drawers: Fast Slam (`Tap E`) vs. Slow Peek (`Hold E`)

### A. Private Clock Exploration Reward (`+10s`) & Single-User Lock

- **Exploration Bonus (`+10s`):** Every searchable container tracks which spies have already opened it. The **first time** a spy opens a container (and survives initial Spring contact to enter Top-Down View), **`+10 seconds`** `[TUNABLE]` is immediately added to that spy's private countdown clock with a crisp *ding* audio cue. Both spies can independently earn `+10s` from the same drawer once, rewarding both players for sweeping the entire embassy rather than camping.
- **Single-User Container Lock:** Only one spy can occupy a drawer or Briefcase's Top-Down View at a time. If a rival approaches an occupied container, the interaction prompt reads `[IN USE]` (though they can still ambush the distracted searcher with a Club or throw a live Bomb into the room!).

### B. Asymmetric Drawer Opening Matrix

| Drawer Contents | Fast Slam (Tap E — 0.15 s, 10 m Loud) | Slow Peek (Hold E — 0.70 s [TUNABLE], 0 m Silent) |
| --- | --- | --- |
| Empty / Clutter Only | Opens instantly; awards +10s (if first visit); enters Top-Down View. | Opens silently; awards +10s (if first visit); enters Top-Down View. |
| Objective / Briefcase / Gadget | Opens instantly; awards +10s; enters Top-Down View to drag item to Left Hand or 3-Slot Inner Jacket. | Opens silently; awards +10s; enters Top-Down View to drag item to Left Hand or 3-Slot Inner Jacket. |
| Armed Spring Trap | INSTANT KO! Spring snaps into spy's jaw immediately (15s Ragdoll KO; does not enter Top-Down View). | SAFE BYPASS! Drawer slides open gently without tripping the Spring; enters Top-Down View with Spring visible on front lip. |
| Armed Time Bomb | FULL ESCAPE WINDOW: Fuse (2.5s–4.0s random) ignites at 0.0s; drawer opens at 0.15s, leaving 2.35s–3.85s to hit S and sprint out of the 5.0 m occluded blast — or Left-Click the Bomb to equip & throw it! | PANIC HOT POTATO: Fuse (2.5s–4.0s random) ignites the instant slow-slide starts (0.0s), burning 0.70s before Top-Down View opens — leaving 1.80s–3.30s where Left-Clicking the Bomb to equip & throw (9.0 m) is often your only survival play! |

## 4. Top-Down Drawer View & 3-Slot Inner Jacket Manipulation

When a drawer opens cleanly (or a dropped **Compact Briefcase** is interacted with on the floor), the player transitions into **Top-Down Container View**:

### A. Camera, Controls & Visual Framing

- **Camera Transition:** First-person camera smoothly interpolates (`0.18 s`) to a top-down vantage positioned directly above the open drawer/Briefcase looking straight down (`-90°` pitch).
- **Left Hand & 3-Slot Inner Jacket Framing:** Player locomotion locks (`0 m/s`), the mouse cursor unlocks, the stylized **Left Hand** frames the left screen edge, and **on the right side of the screen the spy holds open their Inner Trenchcoat Jacket displaying all 3 slots (`Slots 1–3`)**, allowing direct click-and-drag between the container and any of the 3 coat slots.
- **Exit & Close (`A`, `S`, `D`, or `Esc`):** Pressing any lateral/back movement key immediately snaps the camera back to FPS view, re-locks the cursor, and slides the drawer shut (`0.25 s`) — *unless* a lit Time Bomb has jammed the drawer open.

### B. Inside-the-Drawer Mouse Interactions

1. **Rummaging Clutter (`Left-Click + Drag`):**
    - Drawers spawn with `3–5` flat physical clutter objects (manila folders, passports, envelopes, rulers) layered over deeper items.
    - Holding `Left-Click` and dragging pushes clutter smoothly across the drawer's plane (clamped inside the drawer box walls with soft paper-rustle audio).
2. **Looting Objectives & Compact Briefcase:**
    - Dragging a revealed **Objective Item** (*Key, Bag of Money, Passport, Secret Plans*) or **Compact Briefcase** toward the **Left Hand** icon (or double-clicking it) immediately equips/packs it following Doc 2's Left-Hand rules.
    - When inspecting an open **Briefcase**, packed Objectives sit neatly inside its slots and can be dragged out onto the floor if desired.
3. **Looting Gadgets into the 3-Slot Inner Jacket (Tripwire Coil, Unlit Time Bomb, Spring, DVD Dart Gun):**
    - Dragging an unarmed gadget from the container into the open **Inner Jacket** on the right side of the screen places it into the targeted (or first empty) **Jacket Slot (`Slots 1–3`)**.
    - It only swaps/drops a gadget onto the floor next to the furniture if **all 3 Jacket Slots are already full** and the player drags a new gadget onto an occupied slot.
4. **Disarming, Stealing, or Re-Arming a Spring:**
    - After a **Slow Peek (`Hold E`)**, the tensioned Spring sits hooked to the front inner lip of the drawer.
    - **Step 1:** `Left-Click` the Spring to unlatch it (`clack` sound; now safe).
    - **Step 2:** **Drag** the unlatched Spring either into any of your **3 Inner Jacket Slots** (steal it) or **back onto the Drawer Lip** (re-arm it before pressing `A/S/D` to close).
5. **Planting Traps Inside a Drawer or Briefcase:**
    - In Top-Down View, any trap stored in your **3 Inner Jacket Slots** can be dragged directly from its coat slot into the container:
        - **Time Bomb:** Drag an unlit Time Bomb from its Jacket Slot anywhere inside the drawer (then drag loose folders over it to hide it!) or inside a dropped **Briefcase**. Arms automatically the moment you press `A/S/D` to close the container.
        - **Spring:** Drag a Spring from its Jacket Slot onto the front inner lip of a drawer (drawers only; cannot be placed inside Briefcase). Arms automatically when you press `A/S/D` to close.
6. **Hot-Potato Live Bomb Grab (`Left-Click` -> Auto-Close & Active Hand FPS Equip):**
    - While *unlit* Time Bombs can be stowed in the 3 Jacket Slots, a **lit/sparking Time Bomb** inside an open drawer/Briefcase **cannot be stowed in the coat**.
    - **`Left-Clicking` the live Bomb** immediately slams the container shut, snaps the camera back to **FPS view**, and equips the live Bomb directly into the player's **active hand** (while any unlit traps remain safely tucked in their Inner Jacket slots) so you can immediately press `Left-Click` in FPS to hurl it **`9.0 m`** out of the room!

### C. Top-Down Drawer Workflow (Visual Flow)

```
[APPROACH SEARCHABLE DRAWER]
       │
       ├──► TAP E (Fast Slam: 0.15s, Loud) ──► Is Spring Armed? ──► YES ──► [INSTANT 15s RAGDOLL KO]
       │                                            │
       │                                           NO
       │                                            ▼
       └──► HOLD E (Slow Peek: 0.70s, Silent) ──► [ENTER TOP-DOWN DRAWER VIEW]
                                                  (Cursor Unlocked | Left Hand + 3-Slot Inner Jacket Shown | +10s if 1st Visit)
                                                    │
                    ┌───────────────────────────────┼───────────────────────────────┐
                    ▼                               ▼                               ▼
         [DRAG CLUTTER FOLDERS]          [CLICK & DRAG SPRING]            [TIME BOMB IGNITES!]
                    │                     • Click to unlatch               (2.5s–4.0s Random Fuse)
                    ▼                     • Drag to Inner Jacket (1–3)              │
         [REVEAL HIDDEN ITEM]             • Drag to Lip (Re-arm)            ├──► Press S + Sprint Out Door
          • Objective -> Drag to Left Hand                                  └──► Left-Click Lit Bomb -> [AUTO-CLOSE +
          • Gadget    -> Drag to 3-Slot Coat                                     SNAP TO FPS + EQUIP IN ACTIVE HAND]
          • Coat Trap -> Drag In & Cover                                         (Cannot stow lit Bomb in coat!)
                    │
                    ▼
         [PRESS A / S / D TO EXIT] ──► Drawer Slides Shut (Arms Newly Placed Spring/Bomb) ──► Return to FPS
```
