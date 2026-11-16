# DOC 2: PLAYER CONTROLLER, DUAL MOVEMENT & 3-SLOT INNER JACKET INVENTORY (v1.2)

**Parent Document:** Master GDD (v3.2)  
**Purpose:** Complete behavioral specification, state workflows, and input mapping for player locomotion, stances, wearable spy gadget, physical Left Hand, and 3-Slot Inner Trenchcoat Jacket inventory.  
**Note on Numbers:** Values marked `[TUNABLE]` are starting playtest baselines.

## 1. Design Intent & Core Rules

1. **Movement Is Information & Risk:** Walking is quiet and controlled; sprinting is loud and physically bashes closed doors open—exposing the player to doorway traps in exchange for speed; crouching is completely silent and brisk enough (`75%` speed) to reliably sneak up behind a distracted rival.
2. **Tactile Physical Hands & 3-Slot Inner Trenchcoat Jacket:** Every item carried by a spy is grounded in their physical silhouette: the **Left Hand** holds an Objective or the Compact Briefcase, the right side of the spy's **Inner Trenchcoat Jacket** holds up to **3 Traps/Gadgets** in visible coat slots (`Slots 1–3`), the personal **Two-Handed Club** holsters on the back, and the **Wearable Spy Comms Device (Wristwatch or Smart Glasses)** never occupies a hand or coat slot.
3. **100% Player-Driven Trap Ecosystem:** Matches begin with **zero pre-armed traps** (`starting_prearmed_traps = 0` `[TUNABLE]`). Every active trap encountered in the embassy was deliberately planted by a player—ensuring trap encounters provide genuine tactical deduction rather than random RNG.
4. **Predictable Priority:** Movement modifiers, jacket slot selection, Club toggling, mouse-driven drawer interactions, and forced KO scatters follow strict, deterministic rules so players never fight the controls during high-panic moments.

## 2. Dual Movement & Stance System

### A. Base Movement States

| Stance / Mode | Input | Move Speed [TUNABLE] | Audio Emission Radius [TUNABLE] | Physical World Behavior |
| --- | --- | --- | --- | --- |
| Quiet Walk (Default) | W A S D | 4.5 m/s (100%) | 3.0 m (same room only) | Stops against closed doors; safe from auto-triggering doorway traps. |
| Loud Sprint | Hold Shift + W A S D | 6.8 m/s (150%) | 14.0 m (heard 1–2 rooms away) | Auto-Bashes closed doors on contact; triggers floor Tripwires; cannot be used while Crouching or Charging Club. |
| Silent Crouch | Hold Ctrl | 3.4 m/s (75%) | 0.0 m (completely silent) | Brisk silent sneak for closing distance behind unaware rivals; shrinks collision capsule height from 1.8 m to 1.0 m and lowers camera to inspect/disarm shin-height Tripwires. |
| Jump | Tap Space | Upward impulse (4.2 m/s vertical) | 5.0 m landing thud | Clears 0.35 m shin-height floor Tripwires; disabled while Crouching, Searching Drawers, or Charging Club. |

### B. Speed Multiplier Stack (How Modifiers Combine)

To avoid conflicting speed states, the controller calculates final horizontal velocity using a single formula every physics frame:

```
Final_Speed = Base_Stance_Speed × Hand_Encumbrance_Multiplier × Action_Override_Multiplier
```

| Modifier Source | Condition | Multiplier [TUNABLE] | Notes |
| --- | --- | --- | --- |
| Standard / Club Drawn (Idle) | Holding loose objective, active Jacket Trap/Dart Gun, or idle Two-Handed Club | 1.00 (100%) | Zero speed penalty just for holding a gadget or drawing the Club; lets you reposition freely before committing to a charge. |
| Briefcase Carry | Holding Compact Briefcase in Left Hand | 0.90 (90%) | Can still Sprint (6.8 × 0.90 = 6.12 m/s) and Silent Crouch (3.4 × 0.90 = 3.06 m/s). |
| Club Overhead Charge | Actively holding Left-Click with Club | 0.35 (35%) | Overrides Sprint (forces slow walk/crouch pace); prevents chasing down fleeing targets once the wind-up starts. |
| Drawer Search / KO | In Top-Down Drawer View OR 15s Ragdoll KO | 0.00 (0%) | Movement locked until exiting drawer (A/S/D) or waking up from KO. |

## 3. Player Locomotion & State Workflow (Visual Flow)

```
                        ┌───────────────────────────────────────┐
                        │           IDLE / QUIET WALK           │
                        │       (4.5 m/s | Quiet Footsteps)     │
                        └──────┬────────────┬────────────┬──────┘
                               │            │            │
              [Hold Shift]     │            │ [Hold Ctrl]│ [Tap E / Hold E on Drawer]
                               ▼            ▼            ▼
                 ┌──────────────────┐ ┌───────────┐ ┌───────────────────────────────┐
                 │   LOUD SPRINT    │ │  SILENT   │ │     TOP-DOWN DRAWER LOCK      │
                 │ (6.8 m/s | Loud) │ │  CROUCH   │ │   (0 m/s | Cursor Unlocked)   │
                 └────────┬─────────┘ │ (3.4 m/s) │ │ • Drag clutter/objectives     │
                          │           └─────┬─────┘ │ • Click Spring to unlatch     │
        [Collides with    │                 │       │   -> Drag to 3-Slot Jacket    │
         Closed Door]     │                 │       │   OR Drag back to re-arm      │
                          ▼                 ▼       │ • Press A/S/D to close        │
                 ┌──────────────────┐ ┌───────────┐ └───────────────────────────────┘
                 │ AUTO-BASH DOOR   │ │ DISARM    │
                 │ (Swings 90° away │ │ FLOOR     │
                 │  & triggers any  │ │ TRIPWIRE  │
                 │  Water Bucket!)  │ │ (Hold E)  │
                 └──────────────────┘ └───────────┘

  *INTERRUPT OVERRIDE (From ANY State Above):*
  [Hit by Trap / Club QTE / DVD Dart] ──► [15s IN-PLACE RAGDOLL KO]
                                          (Drops Left Hand & Scatters All 3 Inner Jacket Slots)
```

## 4. Physical Left Hand, 3-Slot Inner Trenchcoat Jacket & Wearable Spy Gadget

### A. Slot Architecture & Match Start State

- **Match Start State:** Spies spawn with an **Empty Left Hand**, **All 3 Inner Jacket Slots Empty**, **Two-Handed Club holstered on back**, **Wearable Spy Gadget** equipped, and **0 pre-armed traps** placed in the embassy.
- **Left Hand (Objective Slot — Max 1 Item):**
    - Holds **either** 1 loose Objective Item (*Key, Bag of Money, Passport, Secret Plans*) **or** the **Compact Attaché Briefcase** (which internally stores `0–4` Objective Items).
- **3-Slot Inner Trenchcoat Jacket & Right Hand (Trap/Gadget Slots 1–3 + Club):**
    - **Concept & Visuals:** Instead of carrying only 1 weapon/trap in a bare Right Hand, the spy holds open the right side of their **inner jacket/trenchcoat**, which has **3 slots** capable of storing up to **3 Traps/Gadgets** (*Water Bucket, Tripwire Coil, Spring Trap, Unlit Time Bomb, DVD Dart Gun*).
    - **Selecting & Equipping (`Keys 1, 2, 3` / `Scroll Wheel`):** Pressing `1`, `2`, or `3` (or scrolling the mouse wheel) selects between **Inner Jacket Slots 1–3**, holding out that trap/gadget for placement or use.
    - **Picking Up & Stowing (`Tap E` / Drawer Drag):** Picking up a trap/gadget in the world (`Tap E`) or dragging it into the coat in Top-Down Drawer View places it into the **first empty Jacket Slot** (`Slot 1 -> Slot 2 -> Slot 3`). It only swaps/drops an item onto the floor if **all 3 Jacket Slots are full** (or when pressing `G` to manually drop the active slot item).
    - **Two-Handed Club Harmony (`Key 4` or `R`):** Toggling the personal **Two-Handed Club** from the spy's back **no longer drops held traps onto the floor**—any held trap simply tucks back into its Inner Jacket slot while the Club is drawn (`100%` idle move speed; `35%` speed while charging `Hold Left-Click`, which still auto-drops the **Briefcase** from the Left Hand if held).
    - **Hot-Potato Live Time Bomb Exception:** While *unlit* Time Bombs can be stored in the 3 Jacket Slots, a **lit/sparking Time Bomb** (clicked inside an open container or caught mid-air from a direct rival throw) **cannot be stowed in the coat**—it immediately equips into the player's active hand in FPS view (tucking any held unlit gadget back into its Jacket Slot and holstering the Club) so they can throw it (`Left-Click`, `9.0 m` arc) before detonation.
- **Wearable Spy Comms & Bluff Device (Spy Wristwatch or Smart Glasses):**
    - Replaces a handheld walkie-talkie as a **permanent, non-droppable wearable gadget** (raising the Spy Wristwatch or toggling the Smart Glasses lens overlay).
    - Because it is worn rather than held, it **never occupies Left Hand or Inner Jacket slots** and remains usable even while carrying the Briefcase or Club. *(Full map/bluff projection mechanics detailed in Doc 6).*

### B. Hand, Inner Jacket & Drawer Interaction Resolution Rules

| Player Action | Context / Current State | Resulting Behavior |
| --- | --- | --- |
| Interact (E) with Loose Objective | World / Drawer + Left Hand Empty | Equips the Objective Item into Left Hand. |
| Interact (E) with Loose Objective | World / Drawer + Left Hand holds Briefcase | Automatically packs the Objective inside the Briefcase (`item_count + 1`). |
| Interact (E) with Loose Objective | World / Drawer + Left Hand holds another Objective | Swaps: Drops currently held Objective at feet, equips the new Objective in Left Hand. |
| Interact (E) with Briefcase | World / Drawer + Left Hand Empty | Equips the Briefcase into Left Hand. |
| Interact (E) with Briefcase | World / Drawer + Left Hand holds Loose Objective | Automatically packs the held Objective inside the Briefcase AND equips the Briefcase in Left Hand. |
| Click & Drag Armed Spring | Inside Top-Down Drawer View (after Slow-Peek Hold E) | Left-Clicking the tensioned Spring unlatches/disarms it (clack sound). Player then drags it either into one of the **3 Inner Jacket Slots** (steals it) or back onto the Drawer Lip (re-arms it before pressing A/S/D to close). |
| Press Q (Drop Left Hand) | Left Hand holds Briefcase or Objective | Gently drops/places the Left Hand item onto the floor in front of the player (used to set down the Briefcase to inspect/plant inside it). |
| Press 1, 2, or 3 / Scroll Wheel | Selects Inner Jacket Slot 1–3 | Holsters Two-Handed Club to back (if drawn) and holds out the trap/gadget in the selected Inner Jacket Slot for placement/use. |
| Press 4 or R (Toggle Club) | Club is Holstered on Back | Draws Two-Handed Club (`100%` idle move speed). Any currently held Trap/Gadget **tucks safely back into its Inner Jacket slot** (never drops onto the floor). Does NOT drop Left Hand item. |
| Hold Left-Click (Charge Club) | Club is Drawn + Left Hand holds Briefcase | Immediately drops the Briefcase onto the floor at player's feet (loud THUD audio) and begins overhead charge (`35%` speed). |
| Hold Left-Click (Charge Club) | Club is Drawn + Left Hand holds Loose Objective | Keeps the Loose Objective in Left Hand while charging the Club (`35%` speed). |
| Interact (E) / Drag Unlit Trap or Gadget | At least 1 Inner Jacket Slot is Empty | Places the Trap/Gadget into the **first empty Inner Jacket Slot** (`Slot 1 -> 2 -> 3`) and selects it (holstering Club if drawn). |
| Interact (E) / Drag Unlit Trap or Gadget | All 3 Inner Jacket Slots are Full | Swaps with the currently active Jacket Slot: drops the active slot's Trap/Gadget onto the floor at feet and places the new item into that slot. |
| Click / Catch Lit Time Bomb | Live (Sparking) Fuse Active | **Cannot be stowed in the coat:** immediately slams container shut (if in Top-Down View), tucks any held unlit gadget into its Jacket Slot / holsters Club, and equips the live Bomb into the player's active hand in FPS view to throw (`9.0 m` arc). |
| Press G (Drop Active Jacket Slot) | Active Inner Jacket Slot holds Trap or Dart Gun | Drops the currently selected Jacket Slot's Trap/Gadget onto the floor at player's feet, leaving that slot empty. (Cannot drop Club permanently; use `4` or `R` to holster). |
| Any Knockout (KO) | Any items held or stowed | Force-drops the Left-Hand item/Briefcase **AND scatters all traps/gadgets stored across all 3 Inner Jacket Slots** onto the floor around the ragdoll (while the personal Club re-holsters to the back). |

## 5. Complete Input Map Specification

| Action Name | Default Key / Mouse | Input Type | Behavior |
| --- | --- | --- | --- |
| `move_forward` / `back` / `left` / `right` | W S A D | Hold | Directional locomotion (`A/S/D` also exits Top-Down Drawer View and closes the drawer). |
| `sprint` | Shift | Hold | Activates Loud Sprint (`150%` speed) + Auto-Bash closed doors. |
| `crouch` | Ctrl | Hold | Activates Silent Crouch (`75%` speed, `1.0 m` capsule height) for sneaking and Tripwire inspection. |
| `jump` | Space | Press | Jumps over shin-height floor Tripwires. |
| `interact_primary` | E | Tap vs. Hold | Tap: Fast-slam door/drawer, pick up item into Left Hand or first empty Inner Jacket Slot, or instant prompt. Hold (`0.6s–1.0s`): Slow-peek door/drawer, disarm floor Tripwire, or steal perched Water Bucket. |
| `primary_action` | Left Mouse Button | Tap / Hold / Drag | In World with Club: Tap = harmless feint; Hold = charge QTE bar; Release = slam. In World with Trap/Gun: Place/arm trap, throw live Bomb, or fire single dart. In Top-Down Drawer View: Drag clutter/items between drawer and Left Hand or the 3 Inner Jacket Slots, Click Spring to unlatch & drag, or Click lit Time Bomb to auto-close and equip in active hand in FPS. |
| `jacket_slot_1` / `2` / `3` | Keys 1, 2, 3 / Scroll Wheel | Press / Scroll | Selects between **Inner Jacket Slots 1–3**, holding out that slot's trap/gadget for placement/use (holsters Club if drawn). |
| `toggle_club` | 4 or R | Press | Draws Two-Handed Club from back (tucking any held trap back into its Inner Jacket slot) or holsters Club back onto spine. |
| `drop_left_hand` | Q | Press | Drops Briefcase or Loose Objective from Left Hand onto the floor. |
| `drop_right_hand` | G | Press | Drops the Trap or Dart Gun from the currently active Inner Jacket slot onto the floor. |
| `spy_gadget_ptt` | V | Hold | Transmits long-range voice across the embassy via Spy Wristwatch / Glasses. |
| `spy_gadget_bluff` | B / Tab | Press / Hold | Activates Spy Wristwatch / Glasses map & directional audio bluff projector (detailed in Doc 6). |
