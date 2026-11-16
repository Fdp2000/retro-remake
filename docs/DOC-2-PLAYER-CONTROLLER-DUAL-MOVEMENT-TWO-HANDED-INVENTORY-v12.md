# DOC 2: PLAYER CONTROLLER, DUAL MOVEMENT &amp; TWO\-HANDED INVENTORY \(v1\.2\)

**Parent Document:** Master GDD \(v3\.2\)<br>**Purpose:** Complete behavioral specification, state workflows, input mapping, and lo\-fi Godot 4 architecture for player locomotion, stances, wearable spy gadget, and physical hand slots\.<br>**Note on Numbers:** Values marked `\[TUNABLE\]` are starting playtest baselines\.

## 1\. Design Intent &amp; Core Rules

1. **Movement Is Information &amp; Risk:** Walking is quiet and controlled; sprinting is loud and physically bashes closed doors open—exposing the player to doorway traps in exchange for speed; crouching is completely silent and brisk enough \(`75%` speed\) to reliably sneak up behind a distracted rival\.
2. **Zero Hidden Pockets:** Every held item is physically visible on the spy's character model \(Left Hand, Right Hand, Club on Back\) alongside a **Wearable Spy Comms Device \(Wristwatch or Smart Glasses\)** that never occupies a hand slot\. There is no inventory grid, weapon wheel, or magic backpack\.
3. **100% Player\-Driven Trap Ecosystem:** Matches begin with **zero pre\-armed traps** \(`starting\_prearmed\_traps = 0` `\[TUNABLE\]` playtest toggle in `MatchManager`\)\. Every active trap encountered in the embassy was deliberately planted by a player—ensuring trap encounters provide genuine tactical deduction rather than random RNG\.
4. **Predictable Priority:** Movement modifiers, hand swaps, mouse\-driven drawer interactions, and forced drops follow strict, deterministic rules so players never fight the controls during high\-panic moments\.

## 2\. Dual Movement &amp; Stance System

### A\. Base Movement States

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545472253&cot=14)*

| Stance / Mode | Input | Move Speed \[TUNABLE\] | Audio Emission Radius \[TUNABLE\] | Physical World Behavior |
| --- | --- | --- | --- | --- |
| Quiet Walk \(Default\) | W A S D | 4\.5 m/s \(100%\) | 3\.0 m \(same room only\) | Stops against closed doors; safe from auto\-triggering doorway traps\. |
| Loud Sprint | Hold Shift \+ W A S D | 6\.8 m/s \(150%\) | 14\.0 m \(heard 1–2 rooms away\) | Auto\-Bashes closed doors on contact; triggers floor Tripwires; cannot be used while Crouching or Charging Club\. |
| Silent Crouch | Hold Ctrl | 3\.4 m/s \(75%\) | 0\.0 m \(completely silent\) | Brisk silent sneak for closing distance behind unaware rivals; shrinks collision capsule height from 1\.8 m to 1\.0 m and lowers camera to inspect/disarm shin\-height Tripwires\. |
| Jump | Tap Space | Upward impulse \(4\.2 m/s vertical\) | 5\.0 m landing thud | Clears 0\.35 m shin\-height floor Tripwires; disabled while Crouching, Searching Drawers, or Charging Club\. |

### B\. Speed Multiplier Stack \(How Modifiers Combine\)

To avoid conflicting speed states, the controller calculates final horizontal velocity using a single formula every physics frame:

```
Final_Speed = Base_Stance_Speed × Hand_Encumbrance_Multiplier × Action_Override_Multiplier
```

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545472256&cot=14)*

| Modifier Source | Condition | Multiplier \[TUNABLE\] | Notes |
| --- | --- | --- | --- |
| Standard / Club Drawn \(Idle\) | Holding loose objective, Trap, Dart Gun, or idle Two\-Handed Club | 1\.00 \(100%\) | Zero speed penalty just for holding the Club; lets you reposition freely before committing to a charge\. |
| Briefcase Carry | Holding Compact Briefcase in Left Hand | 0\.90 \(90%\) | Can still Sprint \(6\.8 × 0\.90 = 6\.12 m/s\) and Silent Crouch \(3\.4 × 0\.90 = 3\.06 m/s\)\. |
| Club Overhead Charge | Actively holding Left\-Click with Club | 0\.35 \(35%\) | Overrides Sprint \(forces slow walk/crouch pace\); prevents chasing down fleeing targets once the wind\-up starts\. |
| Drawer Search / KO | In Top\-Down Drawer View OR 15s Ragdoll KO | 0\.00 \(0%\) | Movement locked until exiting drawer \(A/S/D\) or waking up from KO\. |

## 3\. Player Locomotion &amp; State Workflow \(Miro Visual Flow\)

```
                        ┌───────────────────────────────────────┐
                        │           IDLE / QUIET WALK           │
                        │       (4.5 m/s | Quiet Footsteps)     │
                        └──────┬────────────┬────────────┬──────┘
                               │            │            │
              [Hold Shift]     │            │ [Hold Ctrl]│ [Tap E / Hold E on Drawer]
                               ▼            ▼            ▼
                 ┌──────────────────┐ ┌───────────┐ ┌───────────────────────────┐
                 │   LOUD SPRINT    │ │  SILENT   │ │   TOP-DOWN DRAWER LOCK    │
                 │ (6.8 m/s | Loud) │ │  CROUCH   │ │ (0 m/s | Cursor Unlocked) │
                 └────────┬─────────┘ │ (3.4 m/s) │ │ • Drag clutter/objectives │
                          │           └─────┬─────┘ │ • Click Spring to unlatch │
        [Collides with    │                 │       │   -> Drag to Right Hand   │
         Closed Door]     │                 │       │   OR Drag back to re-arm  │
                          ▼                 ▼       │ • Press A/S/D to close    │
                 ┌──────────────────┐ ┌───────────┐ └───────────────────────────┘
                 │ AUTO-BASH DOOR   │ │ DISARM    │
                 │ (Swings 90° away │ │ FLOOR     │
                 │  & triggers any  │ │ TRIPWIRE  │
                 │  Water Bucket!)  │ │ (Hold E)  │
                 └──────────────────┘ └───────────┘

  *INTERRUPT OVERRIDE (From ANY State Above):*
  [Hit by Trap / Club QTE / DVD Dart] ──► [15s IN-PLACE RAGDOLL KO] (Drops Left & Right Hands)
```

## 4\. Two\-Slot Physical Hand Inventory &amp; Wearable Spy Gadget

### A\. Slot Architecture &amp; Match Start State

- **Match Start State:** Spies spawn with **Empty Left Hand**, **Empty Right Hand** \(Two\-Handed Club holstered on back\), **Wearable Spy Gadget** equipped, and **0 pre\-armed traps** placed in the embassy\.
- **Left Hand \(Objective Slot — Max 1 Item\):**
    - Holds **either** 1 loose Objective Item \(*Key, Bag of Money, Passport, Secret Plans*\) **or** the **Compact Attaché Briefcase** \(which internally stores `0–4` Objective Items\)\.
- **Right Hand \(Action / Tool Slot — Max 1 Item\):**
    - Holds **either** the **Two\-Handed Club** \(every spy owns one; holstered on their back when unequipped\) **or** 1 picked\-up Trap/Gadget \(*Water Bucket, Tripwire Coil, Spring, Time Bomb, DVD Dart Gun*\)\.
- **Wearable Spy Comms &amp; Bluff Device \(Spy Wristwatch or Smart Glasses\):**
    - Replaces a handheld walkie\-talkie as a **permanent, non\-droppable wearable gadget** \(raising the Spy Wristwatch or toggling the Smart Glasses lens overlay\)\.
    - Because it is worn rather than held, it **never occupies Left or Right hand slots** and remains usable even while carrying the Briefcase or Club\. *\(Full map/bluff projection mechanics detailed in Doc 6\)\.*

### B\. Hand &amp; Drawer Interaction Resolution Rules

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545472258&cot=14)*

| Player Action | Context / Current State | Resulting Behavior |
| --- | --- | --- |
| Interact \(E\) with Loose Objective | World / Drawer \+ Left Hand Empty | Equips the Objective Item into Left Hand\. |
| Interact \(E\) with Loose Objective | World / Drawer \+ Left Hand holds Briefcase | Automatically packs the Objective inside the Briefcase \(item\_count \+ 1\)\. |
| Interact \(E\) with Loose Objective | World / Drawer \+ Left Hand holds another Objective | Swaps: Drops currently held Objective at feet, equips the new Objective in Left Hand\. |
| Interact \(E\) with Briefcase | World / Drawer \+ Left Hand Empty | Equips the Briefcase into Left Hand\. |
| Interact \(E\) with Briefcase | World / Drawer \+ Left Hand holds Loose Objective | Automatically packs the held Objective inside the Briefcase AND equips the Briefcase in Left Hand\. |
| Click &amp; Drag Armed Spring | Inside Top\-Down Drawer View \(after Slow\-Peek Hold E\) | Left\-Clicking the tensioned Spring unlatches/disarms it \(clack sound\)\. Player then drags it either onto their Right Hand \(steals it\) or back onto the Drawer Lip \(re\-arms it before pressing A/S/D to close\)\. |
| Press Q \(Drop Left Hand\) | Left Hand holds Briefcase or Objective | Gently drops/places the Left Hand item onto the floor in front of the player \(used to set down the Briefcase to inspect/plant inside it\)\. |
| Press 1 \(Toggle Club\) | Club is Holstered on Back | Draws Two\-Handed Club into Right Hand \(100% move speed\)\. \(If Right Hand held a Trap/Gadget, that Trap/Gadget drops onto the floor at feet\)\. Does NOT drop Left Hand item\. |
| Hold Left\-Click \(Charge Club\) | Club is Drawn \+ Left Hand holds Briefcase | Immediately drops the Briefcase onto the floor at player's feet \(RigidBody3D drop \+ loud THUD audio\) and begins overhead charge \(35% speed\)\. |
| Hold Left\-Click \(Charge Club\) | Club is Drawn \+ Left Hand holds Loose Objective | Keeps the Loose Objective in Left Hand while charging the Club \(35% speed\)\. |
| Interact \(E\) with World Trap/Gadget | Right Hand holds Club or Empty | Holsters Club to back \(if drawn\) and equips the Trap/Gadget into Right Hand\. |
| Interact \(E\) with World Trap/Gadget | Right Hand holds another Trap/Gadget | Swaps: Drops currently held Trap/Gadget at feet, equips the new Trap/Gadget into Right Hand\. |
| Press G \(Drop Right Hand\) | Right Hand holds Trap or Dart Gun | Drops the Trap/Gadget onto the floor at player's feet\. \(Cannot drop Club permanently; use 1 to holster\)\. |
| Any Knockout \(KO\) | Any items held | Force\-drops everything in both Left Hand and Right Hand onto the floor at the ragdoll's location\. |

## 5\. Complete Input Map Specification

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545472259&cot=14)*

| Godot Action Name | Default Key / Mouse | Input Type | Behavior |
| --- | --- | --- | --- |
| move\_forward / back / left / right | W S A D | Hold | Directional locomotion \(A/S/D also exits Top\-Down Drawer View and closes the drawer\)\. |
| sprint | Shift | Hold | Activates Loud Sprint \(150% speed\) \+ Auto\-Bash closed doors\. |
| crouch | Ctrl | Hold | Activates Silent Crouch \(75% speed, 1\.0m capsule height\) for sneaking and Tripwire inspection\. |
| jump | Space | Press | Jumps over shin\-height floor Tripwires\. |
| interact\_primary | E | Tap vs\. Hold | Tap: Fast\-slam door/drawer, pick up item, or instant prompt\. Hold \(0\.6s–1\.0s\): Slow\-peek door/drawer, disarm floor Tripwire, or rig Water Bucket\. |
| primary\_action | Left Mouse Button | Tap / Hold / Drag | In World with Club: Tap = harmless feint; Hold = charge QTE bar; Release = slam\. In World with Trap/Gun: Place/arm trap, throw live Bomb, or fire single dart\. In Top\-Down Drawer View: Drag clutter/items, Click Spring to unlatch &amp; drag, or Click lit Time Bomb to auto\-close and equip in FPS\. |
| toggle\_club | 1 | Press | Draws Two\-Handed Club from back \(drops any held Right\-Hand trap\) or holsters Club back onto spine\. |
| drop\_left\_hand | Q | Press | Drops Briefcase or Loose Objective from Left Hand onto the floor\. |
| drop\_right\_hand | G | Press | Drops equipped Trap or Dart Gun from Right Hand onto the floor\. |
| spy\_gadget\_ptt | V | Hold | Transmits long\-range voice across the embassy via Spy Wristwatch / Glasses\. |
| spy\_gadget\_bluff | B / Tab | Press / Hold | Activates Spy Wristwatch / Glasses map &amp; directional audio bluff projector \(detailed in Doc 6\)\. |

## 6\. Lo\-Fi Godot 4 Implementation Guide \(For Miro &amp; Antigravity\)

### A\. Scene Tree Hierarchy \(`SpyCharacter\.tscn`\)

```
SpyCharacter (CharacterBody3D)
 ├── BodyCollision (CollisionShape3D: CapsuleShape3D, height=1.8m -> 1.0m on crouch)
 ├── DoorBashDetector (Area3D: thin box 0.4m ahead of chest -> triggers Door.bash_open() when is_sprinting)
 ├── FootstepEmitter (AudioStreamPlayer3D: routed via PhysicalAudioBridge; muted on Crouch)
 ├── VisualRig (Node3D: Spy 3D Mesh + AnimationTree)
 │    ├── BackClubSocket (Marker3D: renders holstered Club when not in Right Hand)
 │    ├── LeftHandSocket (Marker3D: attaches Objective mesh or Compact Briefcase mesh)
 │    ├── RightHandSocket (Marker3D: attaches Club, Trap, or DartGun mesh)
 │    └── SpyWearableSocket (Marker3D: Spy Wristwatch on left wrist / Smart Glasses on head)
 ├── Neck (Node3D: y=1.6m standing -> y=0.85m crouched)
 │    └── HeadCamera (Camera3D)
 │         ├── InteractRayCast (RayCast3D: target_position = Vector3(0, 0, -2.2))
 │         └── TrapCamSubViewport (SubViewport: 240x135, feeds 12 FPS RingBuffer for Rival Replay)
 ├── RagdollSkeleton (PhysicalBoneSimulator3D: toggled on during 15s KO)
 └── NetworkSync (MultiplayerSynchronizer)
```

### B\. State &amp; Replication Checklist \(EOS Multiplayer\)

- **Authority Model:** Client\-authoritative movement \(`set\_multiplayer\_authority\(peer\_id\)` on each `SpyCharacter`\) for crisp, zero\-lag FPS controls and immediate `E` tap/hold responsiveness\.
- **Match Initialization \(`MatchManager`\):** Spawns 4 Objectives, 1 Compact Briefcase, and 4 Drawer Gadgets inside random drawers plus floor Water Buckets, with `starting\_prearmed\_traps = 0` \(`\[TUNABLE\]`\)\.
- **Synced Properties \(`MultiplayerSynchronizer`\):**
    - `global\_position` \(Vector3\) &amp; `rotation\.y` \(float\)
    - `neck\_pitch` \(float\)
    - `stance\_state` \(Enum: `WALK, SPRINT, CROUCH, DRAWER\_LOCK, KO`\)
    - `left\_hand\_item\_id` \(String / Enum: `"NONE"`, `"BRIEFCASE"`, `"KEY"`, `"MONEY"`, `"PASSPORT"`, `"PLANS"`\)
    - `right\_hand\_item\_id` \(String / Enum: `"NONE"`, `"CLUB"`, `"BUCKET"`, `"TRIPWIRE"`, `"SPRING"`, `"BOMB"`, `"DART\_GUN"`\)
    - `is\_charging\_club` \(bool — drives third\-person overhead wind\-up animation so rivals can visually spot an ambush\)\.

