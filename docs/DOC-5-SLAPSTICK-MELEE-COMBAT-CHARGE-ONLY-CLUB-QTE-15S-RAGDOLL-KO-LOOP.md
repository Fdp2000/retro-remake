# DOC 5: SLAPSTICK MELEE COMBAT, CHARGE\-ONLY CLUB QTE &amp; 15S RAGDOLL KO LOOP

**Parent Document:** Master GDD \(v3\.2\)<br>**Purpose:** Complete behavioral specification, RPG quick\-time charge bar rules, self\-stumble penalties, 15\-second ragdoll KO physics, and lo\-fi Godot 4 architecture for melee combat and knockouts\.<br>**Note on Numbers:** Values marked `\[TUNABLE\]` are starting playtest baselines\.

## 1\. Design Intent &amp; Core Rules

1. **Ambush Tool, Not a Brawler:** Direct melee combat is intentionally slow, heavily telegraphed, and impossible to button\-mash\. The Two\-Handed Club exists to punish distracted searchers \(e\.g\., rivals stuck in Top\-Down Drawer View\) or cornered briefcase carriers\.
2. **Risk\-Reward Skill Check \(No Spamming\):** Tapping `Left\-Click` deals zero damage\. Landing an instant\-KO slam requires committing to a slow `35%`\-speed wind\-up and timing a randomized **RPG Quick\-Time Event \(QTE\) bar** — while holding too long causes the attacker to lose balance and ragdoll themselves\.
3. **In\-Place Knockout Loop:** Spies never teleport back to spawn when knocked out\. Every trap, dart, or club hit collapses the victim into a **`15\-second` in\-place ragdoll** right where they fell, scattering their held items onto the floor for opportunistic theft\.

## 2\. Two\-Handed Club Mechanics

### A\. Equipping &amp; Stance Rules

- **Ownership:** Every spy starts with a personal **Two\-Handed Club** holstered visibly on their back \(`BackClubSocket`\)\.
- **Draw / Holster \(`Press 1`\):**
    - Pressing `1` draws the Club into the Right Hand \(`100%` idle movement speed — zero speed penalty just for holding it\)\.
    - Drawing the Club forces any held Right\-Hand trap or gadget to drop onto the floor at the player's feet, but **does not** drop Left\-Hand items\.
    - The Club can never be permanently dropped or stolen; getting knocked out automatically re\-holsters it onto the spy's spine\.

### B\. Charge\-Only QTE Bar &amp; Release Outcomes

Holding `Left\-Click` with the Club equipped raises the Club high overhead \(clearly visible in third\-person to nearby rivals\), drops the **Compact Briefcase** onto the floor if held in the Left Hand \(loose single objectives remain held\), locks movement speed to **`35%`** `\[TUNABLE\]`, and fills a **`1\.6 s` `\[TUNABLE\]` RPG timing bar** on the HUD\.

- **Randomized Sweet\-Spot:** On each wind\-up, a **`18%`\-wide green target zone** \(`~0\.29 s` window\) `\[TUNABLE\]` spawns at a random position between **`55%` and `75%`** along the charge bar — preventing blind muscle\-memory timing\.

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545593572&cot=14)*

| Input / Release Timing | Bar Zone | Move Speed | Audio &amp; Visual Feedback | Gameplay Effect |
| --- | --- | --- | --- | --- |
| Quick Tap \(under 0\.20 s\) | Pre\-Charge | 100% | Harmless low\-range horizontal swipe \+ loud WHOOSH | Feint / Bait: Deals 0 damage \(0\.4 s cooldown\)\. Used to trick rivals into panicking or burning a jump\. |
| Early Release \(0\.20 s to Green Start\) | Grey \(Under\-Charged\) | 35% \-&gt; 100% | Clumsy off\-balance swing \+ hollow THUNK | Whiff: Deals 0 damage; locks attacker in a 0\.6 s \[TUNABLE\] recovery animation\. |
| Timed Release \(Inside Green Zone\) | Green Sweet\-Spot | 35% \-&gt; 100% | Cartoon CRACK\! impact \+ camera shake | Instant KO Slam: Checks a 2\.0 m \[TUNABLE\] forward melee cone; any hit spy enters the 15s Ragdoll KO state\. |
| Over\-Charge \(100% Bar Reached\) | Red End\-Cap | 35% \-&gt; 0% | Cartoon SLIP / WHOOPS\! whistle | Self\-Stumble Ragdoll: Attacker loses balance from the heavy Club and collapses into a 2\.0 s \[TUNABLE\] backward ragdoll, dropping any loose Left\-Hand objective\. |

## 3\. Club Ambush Workflow \(Miro Visual Flow\)

```
[PRESS 1: DRAW TWO-HANDED CLUB] (100% Move Speed | Drops Right-Hand Trap if held)
       │
       ├──► [TAP LMB (under 0.20s)] ──► Harmless Shove / Feint (0 Damage | 0.4s Cooldown)
       │
       └──► [HOLD LMB: OVERHEAD WIND-UP]
                 │
                 ├──► Left Hand holds Briefcase? ──► YES ──► [AUTO-DROP BRIEFCASE AT FEET]
                 ├──► Move Speed locked to 35% (Sprint disabled)
                 └──► HUD RPG Bar fills (0% -> 100% over 1.6s | Green Zone randomized at 55%–75%)
                           │
                           ├──► [RELEASE BEFORE GREEN] ──► Clumsy Whiff (0 Damage | 0.6s Recovery)
                           │
                           ├──► [RELEASE INSIDE GREEN] ──► Overhead Slam (2.0m Cone)
                           │                                   ├── Hit Rival  ──► [RIVAL ENTERS 15s RAGDOLL KO]
                           │                                   └── Miss Swing ──► [0.6s Recovery]
                           │
                           └──► [HOLD TO 100% (OVER-CHARGE)] ──► [SELF-STUMBLE: 2.0s BACKWARD RAGDOLL]
```

## 4\. The 15\-Second In\-Place Ragdoll KO &amp; Wake\-Up Loop

### A\. What Triggers a 15\-Second KO

All lethal slapstick events feed into the exact same unified `apply\_knockout\(impulse\_dir\)` pipeline:

1. Timed **Overhead Club Slam** \(`Green Zone` release\)
2. **Water Bucket** drop \(`≤ 1\.2 m` doorway threshold\)
3. **Floor Tripwire** collision \(`0\.35 m` shin wire\)
4. **Drawer Spring Trap** \(`Tap E` fast\-slam trigger\)
5. **Time Bomb** explosion \(`5\.0 m` wall/door\-occluded blast\)
6. **DVD Dart Gun** direct dart impact

### B\. Step\-by\-Step Knockout Sequence

1. **Immediate Interrupt \(`t = 0\.0 s`\):**
    - If the victim was inside **Top\-Down Drawer View**, the camera immediately snaps out and the drawer closes \(unless jammed by a lit Time Bomb\)\.
    - If the victim was charging a Club, the charge cancels immediately\.
2. **Full Hand Drop &amp; Club Holster \(`t = 0\.0 s`\):**
    - **Left Hand:** Any held **Compact Briefcase** or **Loose Objective Item** detaches and spawns on the floor at the victim's position with a slight upward/outward scatter impulse \(`1\.5 m/s`\)\.
    - **Right Hand:** Any held **Trap** or **DVD Dart Gun** drops onto the floor beside them\. The victim's personal **Two\-Handed Club** automatically re\-holsters onto their back\.
3. **In\-Place Ragdoll Simulation \(`t = 0\.0 s` to `15\.0 s` `\[TUNABLE\]`\):**
    - The victim's character capsule disables collision with moving players \(so rivals don't get stuck tripping over a ragdoll body in narrow hallways\) and activates `PhysicalBoneSimulator3D` with a directional slapstick knockback impulse\.
    - **Camera Perspective:** The victim's FPS camera remains attached to the ragdoll's head bone \(with a subtle dizzy vignette and spinning stars/birds HUD overlay\), letting them watch their rival steal their Briefcase in hilarious first\-person\!
    - **Clock Burn:** No extra penalty seconds are subtracted — the `15\.0 s` stun naturally burns 15 real seconds off the victim's active private clock\.
    - **Trap\-Cam Trigger:** If caused by a rival's trap or dart, the trap owner's corner HUD plays the **3\.0\-second CRT Trap\-Cam Replay** \(detailed in Doc 6\)\.
4. **In\-Place Wake\-Up &amp; Spawn\-Blink Immunity \(`t = 15\.0 s` to `17\.0 s`\):**
    - At `15\.0 s`, the ragdoll blends smoothly back \(`0\.35 s`\) into a standing upright pose **at the exact floor coordinates where the pelvis landed** \(clamped safely inside room navigation bounds\)\.
    - **Wake\-Up Protection \(`2\.0 s` `\[TUNABLE\]`\):** The revived spy blinks semi\-transparently \(`50%` alpha\) for **`2\.0 seconds`**, during which they are **immune to Club slams, Darts, and Trap triggers** — preventing unfair spawn\-camping loops while giving them a fair chance to grab dropped loot or flee\.

## 5\. Ragdoll KO &amp; Recovery Workflow \(Miro Visual Flow\)

```
[HIT BY CLUB QTE / TRAP / DART] (Ignored if Wake-Up Blink Immunity is active)
       │
       ▼
[FORCE EXIT DRAWER VIEW + CANCEL ACTIONS]
       │
       ├──► Left Hand (Briefcase / Objective) ──► [DROP TO FLOOR WITH 1.5m SCATTER]
       ├──► Right Hand (Trap / Dart Gun)      ──► [DROP TO FLOOR] (Club auto-holsters to back)
       └──► Rival's Trap? ──► YES ──────────────► [TRIGGER 3.0s CRT TRAP-CAM REPLAY ON RIVAL HUD]
       │
       ▼
[15.0s IN-PLACE RAGDOLL KO]
 • PhysicalBoneSimulator3D active (First-person camera follows tumbling head bone)
 • Player collision layer disabled for other spies (no hallway body-blocking)
 • Private countdown clock continues ticking down naturally
       │
       ▼ (At t = 15.0s)
[STAND UP AT PELVIS LOCATION + 2.0s WAKE-UP BLINK IMMUNITY]
 • Semi-transparent blink visual (Cannot be re-stunned for 2.0s)
 • Normal movement & hands restored
```

## 6\. Lo\-Fi Godot 4 Implementation Guide \(For Miro &amp; Antigravity\)

### A\. Combat &amp; Ragdoll Nodes \(`SpyCharacter\.tscn` Additions\)

```
SpyCharacter (CharacterBody3D)
 ├── ClubHitbox (Area3D: BoxShape3D 1.2m wide × 1.4m tall × 2.0m forward in front of Neck)
 ├── ClubAudio (AudioStreamPlayer3D: routed via PhysicalAudioBridge for whoosh, creak, slam, stumble)
 ├── RagdollRoot (PhysicalBoneSimulator3D)
 │    └── PelvisBone (PhysicalBone3D: tracked for wake-up recovery coordinates)
 └── HUD (CanvasLayer)
      ├── ClubQTEBar (Control: ProgressBar + GreenSweetSpotRect + NeedleIndicator)
      └── DizzyOverlay (TextureRect: animated stars/vignette active during 15s KO)
```

### B\. Key Implementation Rules \(For Antigravity\)

- **Melee Hit Validation:** When the local client releases `Left\-Click` inside `ClubQTEBar`'s green zone, it queries `ClubHitbox\.get\_overlapping\_bodies\(\)` and casts a short `PhysicsRayQueryParameters3D` from `HeadCamera` to the target's chest \(preventing hitting rivals through solid walls or closed doors\)\. On a clean hit, it fires `rpc\_apply\_knockout\.rpc\_id\(victim\_peer\_id, hit\_forward\_vec \* 6\.5\)`\.
- **Deterministic Low\-Bandwidth Ragdoll Sync:** Do **not** sync all 15 `PhysicalBone3D` transforms over EOS\. Instead, broadcast `rpc\_enter\_ko\(impulse\_vec\)` so every client runs Godot's local `PhysicalBoneSimulator3D` simulation simultaneously, and sync only the `PelvisBone\.global\_position` once at `t = 14\.8 s` right before standing up — guaranteeing both clients see the spy stand up in the exact same spot with near\-zero network overhead\.
- **Wall\-Clip Prevention on Wake\-Up:** Before re\-enabling the standing `1\.8 m` capsule at `PelvisBone\.global\_position`, use `NavigationServer3D\.map\_get\_closest\_point\(\)` to snap the wake\-up position onto valid floor navmesh so a ragdoll tumbling into a desk corner never wakes up stuck inside geometry\.

