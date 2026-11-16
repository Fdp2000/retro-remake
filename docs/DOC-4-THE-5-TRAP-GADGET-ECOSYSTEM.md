# DOC 4: THE 5\-TRAP &amp; GADGET ECOSYSTEM

**Parent Document:** Master GDD \(v3\.2\)<br>**Purpose:** Complete behavioral specification, setup/trigger/counter rules, Hot\-Potato Time Bomb workflow, and lo\-fi Godot 4 architecture for all 4 traps and the DVD Dart Gun\.<br>**Note on Numbers:** Values marked `\[TUNABLE\]` are starting playtest baselines\.

## 1\. Design Intent &amp; Global Trap Rules

1. **Zero Pre\-Armed RNG \(`starting\_prearmed\_traps = 0`\):** Matches begin with zero active traps on the map\. Every trap encountered was planted by a player, making trap awareness a true deduction skill\.
2. **Universal Owner\-Trigger Rule:** All traps trigger identically on **both** the rival and the trap's owner \(`peer\_id` does not grant immunity\)\. If you forget which door or drawer you rigged, you pay the price\.
3. **One Right\-Hand Slot Economy:** Spies can carry only **1 trap or gadget** at a time in their Right Hand \(picking up or stealing a new one drops the currently held Right\-Hand item onto the floor\)\.
4. **Uniform Knockout &amp; Replay Payoff:** Every successful trap or dart hit inflicts a **`15\-second` in\-place Ragdoll KO** \(unless the target is in their `2\.0 s` wake\-up blink immunity window\), forces the victim to **drop all items in both hands**, and triggers the **`3\.0\-second` CRT Trap\-Cam Replay** for the trap owner \(when hitting a rival\)\.

## 2\. Master Trap &amp; Gadget Matrix

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545535712&cot=14)*

| Trap / Gadget | Where Found | Placement Target | Trigger Condition | Counter / Steal Method |
| --- | --- | --- | --- | --- |
| 1\. Water Bucket | Open world \(floors / corners; 3–4 per map\) | Top edge of a closed Door \(0\.8 s setup\) | Door swings past 25° \(hits spies within 1\.2 m of threshold\) | Look up \-&gt; aim at bucket \-&gt; Hold E \(1\.0 s\) to steal, or open door from 1\.8 m reach to spill |
| 2\. Tripwire | Searchable Drawers | Across floor / doorway at 0\.35 m shin height \(0\.8 s setup\) | Walking or sprinting through wire | Jump \(Space\) over wire, or Silent Crouch \(Ctrl\) \+ Hold E \(1\.0 s\) to steal |
| 3\. Spring Trap | Searchable Drawers | Front inner lip of a Drawer \(arms on drawer close\) | Fast Slam \(Tap E\) on armed drawer | Slow Peek \(Hold E\) \-&gt; Left\-Click Spring to unlatch \-&gt; drag to Right Hand or re\-arm |
| 4\. Time Bomb | Searchable Drawers | Inside a Drawer or dropped Briefcase \(arms on close\) | Any open \(Tap E or Hold E\) ignites a 2\.5s–4\.0s fuse | Left\-Click lit Bomb in container \-&gt; auto\-closes &amp; equips in FPS \-&gt; throw \(9\.0 m\) out of 5\.0 m blast |
| 5\. DVD Dart Gun | Searchable Drawers | Fired 1\-handed from Right Hand \(1 shot only\) | Direct dart hit using bouncing DVD\-logo crosshair | Break line of sight / erratic strafing |

## 3\. Individual Trap &amp; Gadget Specifications

### 1\. Water Bucket \(Doorway Ambush Trap\)

- **Spawning:** Placed visibly in open hallways, bathrooms, or utility corners \(`3–4` buckets per match `\[TUNABLE\]`\)\. Picked up directly into Right Hand with `Tap E`\.
- **Placement \(`Left\-Click` on Closed Door\):** Aiming at a closed door while holding a Water Bucket displays a ghost outline on the top edge of the door leaf\. Holding `Left\-Click` for **`0\.8 s`** `\[TUNABLE\]` perches the bucket on top of the door \(propping the door open by `~5°` as a subtle visual tell\)\.
- **Trigger &amp; Spill Physics:**
    - When the door swings past **`25°`**, gravity drops the bucket straight down at the doorway threshold\.
    - **Hit \(`≤ 1\.2 m` from doorway\):** Crashes onto the spy's head \-&gt; `15s` Ragdoll KO \+ full hand drop\.
    - **Harmless Spill \(`1\.3 m – 1\.8 m` max reach\):** If a cautious player opens the door from maximum interaction distance and stays back, the bucket smashes onto the floor \(`12\.0 m` loud *SPLASH \+ CLATTER*\), spilling its water and destroying the trap permanently\.
- **Stealing:** Looking up at the top of a closed door, aiming directly at the perched bucket, and holding `E` for **`1\.0 s`** lifts it down into your Right Hand\.

```
[HOLD BUCKET IN RIGHT HAND] ──► [AIM AT CLOSED DOOR + HOLD LMB (0.8s)] ──► [PERCHED ON TOP EDGE]
                                                                                  │
                                                            ┌─────────────────────┴─────────────────────┐
                                                            ▼                                           ▼
                                               [RIVAL LOOKS UP + HOLD E]                  [DOOR OPENS PAST 25°]
                                                            │                                           │
                                                            ▼                             ┌─────────────┴─────────────┐
                                                [STOLEN TO RIGHT HAND]                    ▼                           ▼
                                                                             [SPY ≤ 1.2m THRESHOLD]      [SPY > 1.2m REACH]
                                                                                (15s Ragdoll KO)         (Spills & Destroyed)
```

### 2\. Tripwire \(Floor &amp; Chokepoint Trap\)

- **Spawning:** Found inside searchable drawers; dragged to Right Hand as a compact wire\-and\-peg coil\.
- **Placement \(`Left\-Click` on Floor\):** Aiming at a flat floor surface within `2\.2 m` of a wall or doorframe projects two ground pegs and a thin wire at **`0\.35 m` shin height**\. Pressing `Left\-Click` \(`0\.8 s` `\[TUNABLE\]`\) anchors the wire across the path\.
- **Trigger:** Any spy \(including the owner\) **walking or sprinting** through the wire's collision ray trips forward \-&gt; `15s` Ragdoll KO \+ full hand drop\.
- **Counter &amp; Stealing:**
    - **Bypass:** Press `Space` to jump cleanly over the `0\.35 m` wire\.
    - **Disarm / Steal:** Enter **Silent Crouch \(`Hold Ctrl`\)**, aim at either anchor peg, and hold `E` for **`1\.0 s`** `\[TUNABLE\]` to coil the Tripwire back into your Right Hand\.

```
[HOLD COIL IN RIGHT HAND] ──► [AIM AT FLOOR/DOORWAY + LMB (0.8s)] ──► [TAUT WIRE AT 0.35m HEIGHT]
                                                                               │
                                              ┌────────────────────────────────┼────────────────────────────────┐
                                              ▼                                ▼                                ▼
                                   [WALK / SPRINT INTO WIRE]          [JUMP OVER (SPACE)]             [CROUCH + HOLD E (1.0s)]
                                              │                                │                                │
                                              ▼                                ▼                                ▼
                                     [15s RAGDOLL KO]                  [SAFE BYPASS]                  [STOLEN TO RIGHT HAND]
```

### 3\. Spring Trap \(Drawer Fast\-Slam Trap\)

- **Spawning:** Found inside searchable drawers; dragged to Right Hand as a coiled mechanical spring\-glove\.
- **Placement \(Drawers Only\):** Inside Top\-Down Drawer View, drag the Spring from your Right Hand onto the drawer's front inner lip socket \(`SpringLipSocket`\)\. It arms automatically the moment you press `A/S/D` to close the drawer\. *\(Cannot be planted inside the Compact Briefcase\)\.*
- **Trigger:** Any spy \(including the owner\) performing a **Fast Slam \(`Tap E`\)** on the armed drawer triggers the spring instantly \-&gt; launches a boxing glove into the victim's jaw \(`15s` Ragdoll KO \+ full hand drop\) before Top\-Down View can open\.
- **Counter &amp; Stealing:**
    1. **Slow Peek \(`Hold E`, `0\.70 s`\):** Slides the drawer open gently without tripping the spring, entering Top\-Down View\.
    2. **Unlatch \(`Left\-Click` on Spring\):** Clicking the tensioned Spring unhooks it \(`clack` audio cue\)\.
    3. **Drag Choice:** Drag the unlatched Spring to your **Right Hand** \(steal it\) or drag it **back onto the Drawer Lip** \(re\-arm it before closing\)\.

```
[TOP-DOWN DRAWER VIEW] ──► [DRAG SPRING TO FRONT LIP] ──► [PRESS S TO CLOSE] ──► [SPRING ARMED]
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
                                                                                          [DRAG TO RIGHT HAND]     [DRAG TO LIP (RE-ARM)]
```

### 4\. Time Bomb \(Container Trap &amp; Hot\-Potato Throwable\)

- **Spawning:** Found inside searchable drawers; dragged to Right Hand as a spherical cartoon time bomb\.
- **Placement \(Drawers OR Dropped Briefcase\):**
    - Enter Top\-Down View on any **drawer** or a dropped **Compact Briefcase** \(`Q` to set down, `E` to open\)\.
    - Drag the Time Bomb from your Right Hand into the container tray \(and optionally drag loose clutter folders over it to hide it from sight\)\.
    - Pressing `A/S/D` to close the container arms the Bomb \(`soft mechanical click`\)\.
- **Fuse Ignition \(`2\.5 s – 4\.0 s` Randomized `\[TUNABLE\]`\):**
    - The instant **any player** \(including the owner\) initiates opening the rigged drawer or Briefcase — via **Fast Slam \(`Tap E`\)** OR **Slow Peek \(`Hold E`\)** — the Bomb's fuse sparks to life with a loud, unmistakable cartoon hiss \(routed via `PhysicalAudioBridge` across adjacent rooms\)\.
    - Once lit, the Bomb **cannot be defused** — it will detonate when its randomized `2\.5 s – 4\.0 s` timer hits `0\.0 s`\.
- **The "Hot Potato" Grab, Throw &amp; Direct\-Hit Catch Loop:**
    1. **Click\-to\-Equip &amp; Auto\-Close:** Inside Top\-Down Container View, **`Left\-Clicking` the lit Time Bomb** immediately slams the container shut, snaps the camera back to **FPS view**, and equips the live Bomb directly into the player's **Right Hand** \(dropping any previously held Right\-Hand item onto the floor\)\.
    2. **Hurl \(`Left\-Click` in FPS\):** Pressing `Left\-Click` throws the live Bomb in a **`9\.0 m` `\[TUNABLE\]`** ballistic arc in the player's look direction\.
    3. **Direct\-Hit Catch \("Hot Potato" Pass\):** If a thrown live Bomb physically collides with another player's body before detonating, **that player instantly catches and equips the live Bomb into their Right Hand** \(force\-dropping any existing Right\-Hand item onto the floor\), allowing them to immediately press `Left\-Click` to hurl it right back\!
    4. **Floor Re\-Grab \(`Tap E`\):** If a live Bomb is lying on the floor before detonation, aiming at it and pressing `E` also equips it into your Right Hand for a last\-second re\-throw\.
- **Explosion Geometry \(`5\.0 m` Occluded Sphere `\[TUNABLE\]`\):**
    - Detonates in a **`5\.0 m` radius** sphere regardless of whether it is inside a drawer, inside a Briefcase, on the floor, or in a player's hand\.
    - **Line\-of\-Sight Occlusion:** Solid walls and **closed room doors** block the explosion completely \(closing a wooden desk drawer does *not* block the blast\)\.
    - Any spy inside the unobstructed `5\.0 m` radius suffers a `15s` Ragdoll KO \+ full hand drop\.

```
[PLANT BOMB IN DRAWER / BRIEFCASE] ──► [CLOSE CONTAINER] ──► [BOMB ARMED]
                                                                  │
                                             [ANY PLAYER OPENS (TAP E OR HOLD E)]
                                                                  │
                                                                  ▼
                                               [FUSE IGNITES: 2.5s–4.0s RANDOM]
                                                                  │
                       ┌──────────────────────────────────────────┴──────────────────────────────────────────┐
                       ▼                                                                                     ▼
        [PRESS S + SPRINT OUT OF ROOM]                                                       [LEFT-CLICK BOMB IN DRAWER]
        (Works best after Fast Slam)                                                                         │
                       │                                                                                     ▼
                       │                                                                   [AUTO-CLOSE + SNAP TO FPS + EQUIP]
                       │                                                                                     │
                       │                                                                                     ▼
                       │                                                                      [LEFT-CLICK TO THROW (9.0m)]
                       │                                                                                     │
                       │                                                                    ┌────────────────┴────────────────┐
                       │                                                                    ▼                                 ▼
                       │                                                       [DIRECT HIT ON RIVAL!]              [LANDS ON FLOOR / AIR]
                       │                                                       (Rival Instantly Equips ->                    │
                       │                                                        Can Left-Click Throw Back!)                   │
                       │                                                                    │                                 │
                       └────────────────────────────────────────────────────────────────────┼─────────────────────────────────┘
                                                                                            ▼
                                                                             [FUSE HITS 0.0s: 5.0m BLAST]
                                                                         (Blocked by Walls & Closed Room Doors)
```

### 5\. DVD Dart Gun \(1\-Shot Special Gadget\)

- **Spawning:** Found inside searchable drawers \(`1` per match `\[TUNABLE\]`\); dragged to Right Hand\.
- **Aiming Mechanic \(Bouncing DVD\-Logo Crosshair\):**
    - While the Dart Gun is equipped in your Right Hand, normal center\-screen crosshairs are replaced by a glowing retro **DVD\-logo reticle** that glides diagonally across the viewport at `320 px/s` `\[TUNABLE\]` and bounces off all four screen edges \(`corner hits` flash gold for comedy\)\.
    - Pressing `Left\-Click` fires a single dart through the camera ray corresponding to the **reticle's exact current screen position** \(`Camera3D\.project\_ray\_origin` / `project\_ray\_normal`\)\.
- **Effect &amp; Consumption:**
    - **Direct Hit:** Instant `15s` Ragdoll KO \+ full hand drop \(awards `3\.0s` CRT Trap\-Cam Replay if fired from afar, or immediate follow\-up if close\)\.
    - **Single\-Use Break:** Immediately after firing `1` dart \(hit or miss\), the Dart Gun breaks in a puff of smoke and clears the Right\-Hand slot\.

## 4\. Lo\-Fi Godot 4 Implementation Guide \(For Miro &amp; Antigravity\)

### A\. Trap Node Architecture \(`res://scenes/traps/`\)

```
TrapBase (Node3D)  <-- Base class: trap_owner_id: int, is_armed: bool, trigger_trap(victim_peer_id)
 ├── WaterBucketTrap (RigidBody3D / Node3D)
 │    └── TippingAnimation + SplashDetector (Area3D: 1.2m cylinder)
 ├── TripwireTrap (Node3D)
 │    └── PegA, PegB, WireMesh (ImmediateMesh / Cylinder), TripRay (RayCast3D at y=0.35m)
 ├── SpringTrap (Node3D)
 │    └── CoiledMesh + UnlatchedMesh + ClickArea (Area3D for Top-Down mouse unlatch)
 ├── TimeBombTrap (RigidBody3D)
 │    ├── FuseTimer (Timer: wait_time = randf_range(2.5, 4.0))
 │    ├── CatchCollider (Area3D: detects direct body contact during throw -> transfers to victim Right Hand)
 │    ├── BlastArea (Area3D: SphereShape3D radius=5.0m)
 │    └── BlastLOSRay (RayCast3D: checks wall/closed-door occlusion before applying KO)
 └── DVDDartGun (Node3D)
      └── ReticleBounceController (Control node moving DVD TextureRect + firing raycast on LMB)
```

### B\. Key Implementation Rules \(For Antigravity\)

- **Hot\-Potato Catch Authority:** When `TimeBombTrap` is thrown \(`is\_airborne = true`\), its `CatchCollider` ignores `thrower\_peer\_id` for the first `0\.25 s` \(preventing self\-catch on release\)\. On overlapping another `SpyCharacter`, an RPC `rpc\_catch\_live\_bomb\(bomb\_net\_id, remaining\_fuse\_time\)` immediately parents the live bomb to the victim's `RightHandSocket` without resetting `FuseTimer`\.
- **Blast Occlusion Check:** When `FuseTimer` times out, `TimeBombTrap` queries all `SpyCharacter` bodies inside `BlastArea` \(`5\.0 m`\) and casts a `PhysicsRayQueryParameters3D` from the bomb's center to each spy's chest \(`collision\_mask` = World Walls \+ Closed Doors\)\. Only spies with an unobstructed ray receive `apply\_knockout\(\)`\.
- **Audio Integration:** All setup clicks, fuse hiss, and explosion sounds emit through `PhysicalAudioBridge\.play\_world\_cue\(\.\.\.\)` so walls and closed doors occlude them automatically\.

