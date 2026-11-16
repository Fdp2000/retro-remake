# DOC 4: THE 5-TRAP & GADGET ECOSYSTEM

**Parent Document:** Master GDD (v3.2)  
**Purpose:** Complete behavioral specification, setup/trigger/counter rules, and Hot-Potato Time Bomb workflow for all 4 traps and the DVD Dart Gun.  
**Note on Numbers:** Values marked `[TUNABLE]` are starting playtest baselines.

## 1. Design Intent & Global Trap Rules

1. **Zero Pre-Armed RNG (`starting_prearmed_traps = 0`):** Matches begin with zero active traps on the map. Every trap encountered was planted by a player, making trap awareness a true deduction skill.
2. **Universal Owner-Trigger Rule:** All traps trigger identically on **both** the rival and the trap's owner (`peer_id` does not grant immunity). If you forget which door or drawer you rigged, you pay the price.
3. **3-Slot Inner Trenchcoat Jacket Economy:** Spies store up to **3 traps or gadgets** at a time inside the **3 slots of their Inner Trenchcoat Jacket** (`Keys 1, 2, 3` or `Scroll Wheel` to select; `Press G` drops the active slot item; `Press 4` or `R` toggles the Two-Handed Club while keeping traps tucked safely inside the coat). Picking up or stealing a trap fills the first empty Jacket Slot and only swaps/drops an item onto the floor if **all 3 Jacket Slots are full**.
4. **Uniform Knockout, Full-Scatter & Replay Payoff:** Every successful trap or dart hit inflicts a **`15-second` in-place Ragdoll KO** (unless the target is in their `2.0 s` wake-up blink immunity window), forces the victim to **drop their Left-Hand item/Briefcase AND scatter all traps/gadgets stored across all 3 Inner Jacket Slots onto the floor**, and triggers the **`3.0-second` CRT Trap-Cam Replay** for the trap owner (when hitting a rival).

## 2. Master Trap & Gadget Matrix

| Trap / Gadget | Where Found | Placement Target | Trigger Condition | Counter / Steal Method |
| --- | --- | --- | --- | --- |
| 1. Water Bucket | Open world (floors / corners; 3–4 per map) | Top edge of a closed Door (0.8 s setup) | Door swings past 25° (hits spies within 1.2 m of threshold) | Look up -> aim at bucket -> Hold E (1.0 s) to steal into Inner Jacket, or open door from 1.8 m reach to spill |
| 2. Tripwire | Searchable Drawers | Across floor / doorway at 0.35 m shin height (0.8 s setup) | Walking or sprinting through wire | Jump (Space) over wire, or Silent Crouch (Ctrl) + Hold E (1.0 s) to steal into Inner Jacket |
| 3. Spring Trap | Searchable Drawers | Front inner lip of a Drawer (arms on drawer close) | Fast Slam (Tap E) on armed drawer | Slow Peek (Hold E) -> Left-Click Spring to unlatch -> drag to 3-Slot Inner Jacket or re-arm |
| 4. Time Bomb | Searchable Drawers | Inside a Drawer or dropped Briefcase (arms on close) | Any open (Tap E or Hold E) ignites a 2.5s–4.0s fuse | Left-Click lit Bomb in container -> auto-closes & equips in active hand in FPS (cannot stow lit Bomb in coat) -> throw (9.0 m) out of 5.0 m blast |
| 5. DVD Dart Gun | Searchable Drawers | Selected from Inner Jacket (1–3) & fired 1-handed (1 shot only) | Direct dart hit using bouncing DVD-logo crosshair | Break line of sight / erratic strafing |

## 3. Individual Trap & Gadget Specifications

### 1. Water Bucket (Doorway Ambush Trap)

- **Spawning:** Placed visibly in open hallways, bathrooms, or utility corners (`3–4` buckets per match `[TUNABLE]`). Picked up with `Tap E` into the **first empty Inner Jacket Slot** (`Slots 1–3`), or swapped with the active slot if all 3 slots are full.
- **Placement (`Left-Click` on Closed Door):** Selecting the Water Bucket from its Inner Jacket Slot (`Keys 1–3` / `Scroll Wheel`) and aiming at a closed door displays a ghost outline on the top edge of the door leaf. Holding `Left-Click` for **`0.8 s`** `[TUNABLE]` perches the bucket on top of the door (propping the door open by `~5°` as a subtle visual tell).
- **Trigger & Spill Physics:**
    - When the door swings past **`25°`**, gravity drops the bucket straight down at the doorway threshold.
    - **Hit (`≤ 1.2 m` from doorway):** Crashes onto the spy's head -> `15s` Ragdoll KO + full Left-Hand & 3-Slot Inner Jacket scatter.
    - **Harmless Spill (`1.3 m – 1.8 m` max reach):** If a cautious player opens the door from maximum interaction distance and stays back, the bucket smashes onto the floor (`12.0 m` loud *SPLASH + CLATTER*), spilling its water and destroying the trap permanently.
- **Stealing:** Looking up at the top of a closed door, aiming directly at the perched bucket, and holding `E` for **`1.0 s`** lifts it down into your first empty **Inner Jacket Slot** (or swaps with your active slot if all 3 are full).

```
[SELECT BUCKET FROM JACKET (1–3)] ──► [AIM AT CLOSED DOOR + HOLD LMB (0.8s)] ──► [PERCHED ON TOP EDGE]
                                                                                          │
                                                                    ┌─────────────────────┴─────────────────────┐
                                                                    ▼                                           ▼
                                                       [RIVAL LOOKS UP + HOLD E]                  [DOOR OPENS PAST 25°]
                                                                    │                                           │
                                                                    ▼                             ┌─────────────┴─────────────┐
                                                    [STOLEN TO INNER JACKET (1–3)]                ▼                           ▼
                                                                                     [SPY ≤ 1.2m THRESHOLD]      [SPY > 1.2m REACH]
                                                                                        (15s Ragdoll KO)         (Spills & Destroyed)
```

### 2. Tripwire (Floor & Chokepoint Trap)

- **Spawning:** Found inside searchable drawers; dragged into one of the **3 Inner Jacket Slots** as a compact wire-and-peg coil.
- **Placement (`Left-Click` on Floor):** Selecting the Tripwire Coil from its Jacket Slot (`Keys 1–3` / `Scroll Wheel`) and aiming at a flat floor surface within `2.2 m` of a wall or doorframe projects two ground pegs and a thin wire at **`0.35 m` shin height**. Pressing `Left-Click` (`0.8 s` `[TUNABLE]`) anchors the wire across the path.
- **Trigger:** Any spy (including the owner) **walking or sprinting** through the wire's collision ray trips forward -> `15s` Ragdoll KO + full Left-Hand & 3-Slot Inner Jacket scatter.
- **Counter & Stealing:**
    - **Bypass:** Press `Space` to jump cleanly over the `0.35 m` wire.
    - **Disarm / Steal:** Enter **Silent Crouch (`Hold Ctrl`)**, aim at either anchor peg, and hold `E` for **`1.0 s`** `[TUNABLE]` to coil the Tripwire back into your first empty **Inner Jacket Slot**.

```
[SELECT COIL FROM JACKET (1–3)] ──► [AIM AT FLOOR/DOORWAY + LMB (0.8s)] ──► [TAUT WIRE AT 0.35m HEIGHT]
                                                                                       │
                                                      ┌────────────────────────────────┼────────────────────────────────┐
                                                      ▼                                ▼                                ▼
                                           [WALK / SPRINT INTO WIRE]          [JUMP OVER (SPACE)]             [CROUCH + HOLD E (1.0s)]
                                                      │                                │                                │
                                                      ▼                                ▼                                ▼
                                             [15s RAGDOLL KO]                  [SAFE BYPASS]              [STOLEN TO INNER JACKET (1–3)]
```

### 3. Spring Trap (Drawer Fast-Slam Trap)

- **Spawning:** Found inside searchable drawers; dragged into one of the **3 Inner Jacket Slots** as a coiled mechanical spring-glove.
- **Placement (Drawers Only):** Inside Top-Down Drawer View, drag the Spring from any of your **3 Inner Jacket Slots** onto the drawer's front inner lip. It arms automatically the moment you press `A/S/D` to close the drawer. *(Cannot be planted inside the Compact Briefcase).*
- **Trigger:** Any spy (including the owner) performing a **Fast Slam (`Tap E`)** on the armed drawer triggers the spring instantly -> launches a boxing glove into the victim's jaw (`15s` Ragdoll KO + full Left-Hand & 3-Slot Inner Jacket scatter) before Top-Down View can open.
- **Counter & Stealing:**
    1. **Slow Peek (`Hold E`, `0.70 s`):** Slides the drawer open gently without tripping the spring, entering Top-Down View.
    2. **Unlatch (`Left-Click` on Spring):** Clicking the tensioned Spring unhooks it (`clack` audio cue).
    3. **Drag Choice:** Drag the unlatched Spring into one of your **3 Inner Jacket Slots** (steal it) or drag it **back onto the Drawer Lip** (re-arm it before closing).

```
[TOP-DOWN DRAWER VIEW] ──► [DRAG SPRING FROM JACKET TO FRONT LIP] ──► [PRESS S TO CLOSE] ──► [SPRING ARMED]
                                                                                                   │
                                                                         ┌─────────────────────────┴─────────────────────────┐
                                                                         ▼                                                   ▼
                                                                [FAST SLAM (TAP E)]                                [SLOW PEEK (HOLD E)]
                                                                         │                                                   │
                                                                         ▼                                                   ▼
                                                                [INSTANT 15s KO]                                 [LEFT-CLICK TO UNLATCH]
                                                                                                                             │
                                                                                                                 ┌───────────┴───────────┐
                                                                                                                 ▼                       ▼
                                                                                                   [DRAG TO INNER JACKET]    [DRAG TO LIP (RE-ARM)]
```

### 4. Time Bomb (Container Trap & Hot-Potato Throwable)

- **Spawning & Unlit Storage:** Found inside searchable drawers; while **unlit**, the spherical cartoon Time Bomb can be dragged into any of the **3 Inner Jacket Slots** (`Slots 1–3`).
- **Placement (Drawers OR Dropped Briefcase):**
    - Enter Top-Down View on any **drawer** or a dropped **Compact Briefcase** (`Q` to set down, `E` to open).
    - Drag the unlit Time Bomb from its **Inner Jacket Slot** into the container tray (and optionally drag loose clutter folders over it to hide it from sight).
    - Pressing `A/S/D` to close the container arms the Bomb (`soft mechanical click`).
- **Fuse Ignition (`2.5 s – 4.0 s` Randomized `[TUNABLE]`):**
    - The instant **any player** (including the owner) initiates opening the rigged drawer or Briefcase — via **Fast Slam (`Tap E`)** OR **Slow Peek (`Hold E`)** — the Bomb's fuse sparks to life with a loud, unmistakable cartoon hiss (audible across adjacent rooms).
    - Once lit, the Bomb **cannot be defused** — it will detonate when its randomized `2.5 s – 4.0 s` timer hits `0.0 s`.
- **The "Hot Potato" Grab, Throw & Direct-Hit Catch Loop (Live Bomb Exception):**
    - **Live Bombs Cannot Be Stowed in the Coat:** While *unlit* Time Bombs can be stored in the 3 Jacket Slots, a **lit/sparking Time Bomb cannot be stowed in the coat**.
    1. **Click-to-Equip & Auto-Close:** Inside Top-Down Container View, **`Left-Clicking` the lit Time Bomb** immediately slams the container shut, snaps the camera back to **FPS view**, and equips the live Bomb directly into the player's **active hand** (while any unlit traps/gadgets stay tucked in their Inner Jacket slots and the Club stays holstered).
    2. **Hurl (`Left-Click` in FPS):** Pressing `Left-Click` throws the live Bomb in a **`9.0 m` `[TUNABLE]`** ballistic arc in the player's look direction (ignoring the thrower for the first `0.25 s` so they do not self-catch on release).
    3. **Direct-Hit Catch ("Hot Potato" Pass):** If a thrown live Bomb physically collides with another player's body mid-air before detonating, **that player instantly catches and equips the live Bomb into their active hand in FPS view** (tucking any held unlit gadget back into its Jacket Slot / holstering the Club), allowing them to immediately press `Left-Click` to hurl it right back!
    4. **Floor Re-Grab (`Tap E`):** If a live Bomb is lying on the floor before detonation, aiming at it and pressing `E` also equips it directly into your active hand for a last-second re-throw.
- **Explosion Geometry (`5.0 m` Occluded Sphere `[TUNABLE]`):**
    - Detonates in a **`5.0 m` radius** sphere regardless of whether it is inside a drawer, inside a Briefcase, on the floor, or in a player's hand.
    - **Line-of-Sight Occlusion:** Solid walls and **closed room doors** block the explosion completely (closing a wooden desk drawer does *not* block the blast).
    - Any spy inside the unobstructed `5.0 m` radius suffers a `15s` Ragdoll KO + full Left-Hand & 3-Slot Inner Jacket scatter.

```
[PLANT UNLIT BOMB FROM JACKET INTO DRAWER / BRIEFCASE] ──► [CLOSE CONTAINER] ──► [BOMB ARMED]
                                                                                      │
                                                                 [ANY PLAYER OPENS (TAP E OR HOLD E)]
                                                                                      │
                                                                                      ▼
                                                                   [FUSE IGNITES: 2.5s–4.0s RANDOM]
                                                                                      │
                                           ┌──────────────────────────────────────────┴──────────────────────────────────────────┐
                                           ▼                                                                                     ▼
                            [PRESS S + SPRINT OUT OF ROOM]                                                       [LEFT-CLICK LIT BOMB IN DRAWER]
                            (Works best after Fast Slam)                                                         (Cannot stow lit Bomb in coat!)
                                           │                                                                                     │
                                           │                                                                                     ▼
                                           │                                                                   [AUTO-CLOSE + SNAP TO FPS + EQUIP]
                                           │                                                                                     │
                                           │                                                                                     ▼
                                           │                                                                      [LEFT-CLICK TO THROW (9.0m)]
                                           │                                                                                     │
                                           │                                                                    ┌────────────────┴────────────────┐
                                           │                                                                    ▼                                 ▼
                                           │                                                       [DIRECT HIT ON RIVAL!]              [LANDS ON FLOOR / AIR]
                                           │                                                       (Rival Instantly Equips in Hand ->             │
                                           │                                                        Can Left-Click Throw Back!)                   │
                                           │                                                                    │                                 │
                                           └────────────────────────────────────────────────────────────────────┼─────────────────────────────────┘
                                                                                                                ▼
                                                                                                [FUSE HITS 0.0s: 5.0m BLAST]
                                                                                            (Blocked by Walls & Closed Room Doors)
```

### 5. DVD Dart Gun (1-Shot Special Gadget)

- **Spawning:** Found inside searchable drawers (`1` per match `[TUNABLE]`); dragged into one of the **3 Inner Jacket Slots** and selected via `Keys 1–3` / `Scroll Wheel`.
- **Aiming Mechanic (Bouncing DVD-Logo Crosshair):**
    - While the Dart Gun is held out from its Inner Jacket Slot, normal center-screen crosshairs are replaced by a glowing retro **DVD-logo reticle** that glides diagonally across the viewport at `320 px/s` `[TUNABLE]` and bounces off all four screen edges (`corner hits` flash gold for comedy).
    - Pressing `Left-Click` fires a single dart along the camera ray corresponding to the **reticle's exact current screen position**.
- **Effect & Consumption:**
    - **Direct Hit:** Instant `15s` Ragdoll KO + full Left-Hand & 3-Slot Inner Jacket scatter (awards `3.0s` CRT Trap-Cam Replay if fired from afar, or immediate follow-up if close).
    - **Single-Use Break:** Immediately after firing `1` dart (hit or miss), the Dart Gun breaks in a puff of smoke and clears that Inner Jacket slot.
