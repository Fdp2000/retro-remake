# MASTER GAME DESIGN DOCUMENT (GDD v3.2 — Synced Playtest Baseline)

**Project:** *Spy vs. Spy: 3D Remake* (Working Title)  
**Genre:** 3D First-Person Slapstick Sabotage & Spatial Deduction  
**Players:** 1v1 Classic Duel (Core) / 2–4 Player Free-For-All (Week 3 Stretch)  
**Engine & Networking:** Godot 4 (`4.7.2-stable`) + Epic Online Services (EOS)  
**Note on Numbers:** All durations and speeds marked `[TUNABLE]` are starting playtest baselines meant to be tweaked during Week 2–3 greybox testing.

## 1. High Concept & Design Pillars

A first-person 3D reimagining of the 1984 NES classic *Spy vs. Spy*. Rival spies infiltrate a modular embassy to search furniture for **4 Secret Objective Items** (*Key, Bag of Money, Passport, Secret Plans*) and a **compact Attaché Briefcase**, pack all 4 items inside the Briefcase, and escape through the **single shared Airport Exit Door** before their personal countdown timer hits zero.

### The 4 Non-Negotiable Pillars

1. **Trap & Gadget Warfare Over Gunplay:** Traps and slapstick gadgets are the primary drivers of friction and comedy. Melee combat is a slow, telegraphed ambush tool with zero button-mashing.
2. **Spatial Audio & Wearable Spy Deception:** Without split-screen, players rely on directional 3D audio, **proximity voice chat**, and a wearable **Spy Watch / Smart Glasses** to communicate and project directional audio bluffs.
3. **Asymmetric Risk-Reward Interactions:** Every door and drawer forces a split-second gamble between **speed** (loud, gives full escape window on Time Bombs, triggers Springs/Buckets) and **caution** (quiet, spots Springs/Buckets, forces a "Hot Potato" Bomb toss).
4. **Tactile Slapstick Physicality:** Physical hands and open inner trenchcoat pockets inside drawers, hot-potato bomb throws, ragdoll knockouts, and a **3.0-second CRT Trap-Cam Replay** showing the actual past footage of your rival getting hit by your trap.

## 2. Core Gameplay Loop (Visual Workflow)

```
[SPAWN IN EMBASSY CORNER] (Clock: 03:00 | Club on Back | 3-Slot Inner Jacket Empty | Wearable Watch/Glasses | 0 Pre-Armed Traps)
         │
         ▼
[EXPLORE, LISTEN & BLUFF] ──► Proximity Voice + Wearable Spy Device (Comms & Directional Bluffs)
         │
         ├──► [PICK UP FLOOR WATER BUCKET] ──► Stows in Inner Jacket (Slots 1–3) ──► Rig Top of Closed Door (0.8s)
         │
         ▼
[APPROACH DRAWER / CABINET]
         │
         ├──► FAST SLAM (Tap E)  ──► Loud | Gives Full Bomb Escape Time | Triggers Spring
         └──► SLOW PEEK (Hold E) ──► Quiet | Click-Unlatch & Steal Spring | Forces Bomb "Hot Potato"
         │
         ▼
[TOP-DOWN DRAWER VIEW] (Cursor Unlocked | Left Hand + 3-Slot Inner Jacket Shown | Press A/S/D to Back Out & Close)
         │
         ├──► Drag Clutter Aside ──► Find Objective Item OR Compact Briefcase (+10s Clock)
         └──► Find / Plant Trap  ──► Drag Between Drawer & 3 Inner Jacket Slots (Spring, Bomb, Tripwire, DVD Dart Gun)
         │
         ▼
[PACK ALL 4 OBJECTIVES INTO BRIEFCASE] (Left Hand holds Briefcase | 3-Slot Inner Jacket & Right Hand stay free)
         │
         ▼
[SPRINT TO SINGLE AIRPORT EXIT DOOR] ──► Touch Exit with 4-Item Briefcase ──► [INSTANT VICTORY]
```

## 3. Win, Loss & Timer Rules (Faithful to 1984 OG)

| Outcome | Trigger Condition | Design Purpose |
| --- | --- | --- |
| Escape Victory | A spy touches the single shared Airport Exit Door while holding the Briefcase containing all 4 Objective Items. | Zero unlock channel at the exit prevents unfair doorway camping on the final step. |
| OG Clock Elimination | When Spy A's private timer hits 0:00, Spy A explodes/is eliminated — AND Spy B must still complete the 4-Item Briefcase Escape before Spy B's own timer hits 0:00! | Preserves the intense 1984 endgame pressure: surviving your rival doesn't hand you a free win if you waste time. |
| Mutual Loss (Draw) | Both spies run out of time before anyone reaches the Airport Exit. | Forces proactive searching and tempo management throughout the match. |

### The Private Timer Economy

- **Starting Time:** `03:00` (`180 seconds`) `[TUNABLE]`, displayed **only** to its owner on their HUD.
- **Searching a New Container:** **`+10 seconds`** `[TUNABLE]` awarded the first time a spy opens any unsearched drawer/cabinet.
- **Knockout Penalty:** **No arbitrary point subtraction** — the **`15-second` in-place ragdoll stun** naturally burns 15 real seconds off your active clock while your rival loots freely.

## 4. Core Systems Overview

### A. Dual Movement & Stances

- **Quiet Walk (Default — `100%` Speed / `4.5 m/s`):** Low footstep radius (`3.0 m`); safe approach to closed doors without auto-opening them.
- **Loud Sprint (`Hold Shift` — `150%` Speed / `6.8 m/s`):** Heavy footsteps audible `14.0 m` away; **automatically bashes closed doors open** on contact.
- **Silent Crouch (`Hold Ctrl` — `75%` Speed / `3.4 m/s`):** Completely silent (`0.0 m` audio) brisk sneak for closing distance behind unaware rivals and inspecting/disarming shin-level floor Tripwires.
- **Encumbrance Modifiers:**
    - Holding **Compact Briefcase** in Left Hand: `90%` speed (can still sprint and crouch).
    - Holding **Two-Handed Club** (`Key 4` or `R`): `100%` speed while drawn idle; **`35%` speed** while actively holding `Left-Click` to charge the overhead swing.

### B. Physical Left Hand, 3-Slot Inner Trenchcoat Jacket & Wearable Spy Device

- **Left Hand (Objective Slot — `Q` to Drop):** Holds **1 loose Objective Item** (*Key, Bag of Money, Passport, Secret Plans*) OR the **Compact Attaché Briefcase** (capacity: 4 items).
- **3-Slot Inner Trenchcoat Jacket & Right Hand (Trap/Gadget Slots 1–3):**
    - Instead of carrying only 1 weapon/trap in a bare Right Hand, the spy holds open the right side of their **inner jacket/trenchcoat**, which has **3 slots** capable of storing up to **3 Traps/Gadgets** (*Water Bucket, Tripwire Coil, Spring Trap, Unlit Time Bomb, DVD Dart Gun*).
    - **Selecting & Equipping (`Keys 1, 2, 3` / `Scroll Wheel`):** Selects between **Inner Jacket Slots 1–3**, holding out that trap/gadget in the Right Hand for placement or use (`G` manually drops the active slot item).
    - **Picking Up & Stowing (`Tap E` / Drawer Drag):** Picking up a trap/gadget in the world (`Tap E`) or dragging it into the coat in Top-Down Drawer View places it into the **first empty Jacket Slot**. It only swaps/drops an item onto the floor if **all 3 Jacket Slots are full**.
- **Two-Handed Club Harmony (`Key 4` or `R`):**
    - Toggling the personal **Two-Handed Club** from the spy's back **no longer drops held traps onto the floor** — any held trap simply tucks back into its Inner Jacket slot while the Club is drawn (`100%` idle move speed; `35%` speed while charging `Hold Left-Click`).
    - **Briefcase Charge-Drop Rule:** Simply drawing the Two-Handed Club does **not** drop your Left Hand item. However, **actively starting the overhead charge (`Hold Left-Click`)** immediately drops the **Briefcase** onto the floor at your feet (loose single objective items in your Left Hand are **not** dropped when charging).
- **Hot-Potato Live Time Bomb Exception:**
    - While *unlit* Time Bombs can be stored in the 3 Jacket Slots, a **lit/sparking Time Bomb** (clicked inside an open container or caught mid-air from a direct rival throw) **cannot be stowed in the coat** — it immediately equips into the player's active hand in FPS view so they can throw it (`Left-Click`, `9.0 m` arc) before detonation.
- **Knockout Full-Scatter Rule:**
    - Suffering a `15.0 s` Ragdoll KO from **any** trap, dart, or club hit forces the spy to drop their Left-Hand item/Briefcase **AND scatters all traps/gadgets stored across all 3 Inner Jacket Slots** onto the floor around the ragdoll (while the personal Club re-holsters to their back).
- **Wearable Spy Comms & Bluff Device (`Hold V` Voice / `B` or `Tab` Bluffs):** Permanent non-droppable **Spy Wristwatch / Smart Glasses** (never occupies Left Hand or Inner Jacket slots).

### C. The 5-Trap & Special Gadget Roster (All Owner-Triggerable)

Matches start with **`0` pre-armed traps** (`starting_prearmed_traps = 0`). All traps trigger identically on **both** the rival and the trap's owner. **4 Objective Items**, **1 Compact Briefcase**, and **4 Drawer Gadgets** (*Spring, Time Bomb, Tripwire Coil, DVD Dart Gun*) spawn randomly inside drawers; **Water Buckets** spawn out in the open on floors/corners.

| Trap / Gadget | Where Found & Placed | Trigger Condition | Optimal Counter & "Hot Potato" Rule |
| --- | --- | --- | --- |
| 1. Water Bucket | Found on floors/corners -> stowed in Inner Jacket (1–3) -> placed on top edge of a closed Door (0.8 s) | Door swings past 25° (drops on anyone within 1.2 m doorway zone; falls & spills harmlessly if opened from 1.8 m max reach) | Look up at doorframe -> aim at bucket -> Hold E (1.0 s) to steal into Inner Jacket |
| 2. Tripwire | Found in drawers -> stowed in Inner Jacket (1–3) -> stretched across floor/doorway at 0.35 m shin height | Walking or sprinting through the wire | Jump (Space) over it, or Silent Crouch (Ctrl) + Hold E (1.0 s) to steal into Inner Jacket |
| 3. Spring | Found in drawers -> stowed in Inner Jacket (1–3) -> hooked to front inner lip of a Drawer | Fast Slam (Tap E) | Slow Peek (Hold E) -> Left-Click Spring to unlatch -> drag to any of the 3 Inner Jacket Slots or re-arm |
| 4. Time Bomb | Found in drawers -> stowed unlit in Inner Jacket (1–3) -> planted inside a Drawer (under clutter) or dropped Briefcase | Any open ignites a randomized 2.5 s–4.0 s fuse (5.0 m blast blocked by walls & closed doors) | Left-Click lit Bomb in Top-Down View to auto-close & equip in active hand in FPS (cannot stow lit Bomb in coat) -> Left-Click throw (9.0 m); direct body hit forces rival to catch & equip ("Hot Potato") |
| 5. DVD Dart Gun | Found in drawers -> stowed in Inner Jacket (1–3) -> fired 1-handed (1-shot disposable gadget) | Direct dart hit with a bouncing DVD-screensaver crosshair | Erratic movement / cover (single shot only; breaks and clears Jacket Slot after firing) |

### D. Slapstick Melee Combat (Charge-Only Club) & Knockout State

- **Two-Handed Club (`Key 4` or `R` — Zero Button-Mashing):**
    - *No Quick-Tap Damage:* Tapping `Left-Click` (`under 0.20 s`) only performs a harmless low-range **shove/feint** (`0` damage, preventing click-spam duels).
    - *Hold `Left-Click` (Overhead Ambush Charge):* Drops Briefcase if held, slows player to `35%` speed, and displays a randomized **RPG quick-time sweet-spot bar**. Releasing inside the green zone delivers an **instant KO overhead slam**. Over-charging past `100%` causes the attacker to lose balance and **ragdoll backward for `2.0 s`**.
- **Knockout (KO) State:** Victim turns into a **`15-second`** in-place ragdoll, drops their Left-Hand item/Briefcase **and scatters all traps/gadgets stored across all 3 Inner Jacket Slots** onto the floor (while the Club holsters to the back), and stands back up in place with **`2.0 s`** of wake-up blink immunity.

### E. Audio, Wearable Spy Device, CRT Trap-Cam Replay & Anti-Camping

- **Proximity Voice Chat:** Real-time spatial voice attenuated and muffled by walls/closed doors via the physically based spatial audio pipeline.
- **Wearable Spy Watch / Smart Glasses (`Hold V` Global Comms / `B` or `Tab` Bluffs):** Enables long-range radio voice and projects directional audio bluffs (*trap arming, drawer slam, sprint steps, door bash*) through the physical audio engine.
- **3.0-Second CRT Trap-Cam Replay:** Each client captures a continuous `3.0 s` (`36-frame` @ `12 FPS`) low-res (`240x135`) image ring buffer from the rival's head camera. When your trap hits your rival, the buffered `3.0 s` replay plays back on your corner HUD CRT screen.
- **Anti-Camping Sneeze:** Staying inside the same room volume for **`20.0 seconds`** `[TUNABLE]` without interacting with any prop triggers a loud, echoing cartoon **Sneeze** (`"ACHOO!"`, `22.0 m` radius).

## 5. Documentation Index

1. **Master GDD (v3.2 — Synced Playtest Baseline)** *(This Document)*
2. **Doc 2: Player Controller, Dual Movement & 3-Slot Inner Jacket Inventory**
3. **Doc 3: Unified Bidirectional Doors & Top-Down Drawer Search System**
4. **Doc 4: The 5-Trap & Gadget Ecosystem (Bucket, Tripwire, Spring, Hot-Potato Bomb, DVD Dart Gun)**
5. **Doc 5: Slapstick Melee Combat, Charge-Only Club QTE & 15s Ragdoll KO Loop**
6. **Doc 6: Audio Architecture, Wearable Comms & Bluff Device, 3.0s CRT Replay & Anti-Camping**
7. **Doc 7: Modular Greybox Level Blueprint & Remaining 2-Week Sprint Plan**
