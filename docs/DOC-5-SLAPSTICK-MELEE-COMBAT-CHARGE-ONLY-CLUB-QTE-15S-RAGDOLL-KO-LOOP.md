# DOC 5: SLAPSTICK MELEE COMBAT, CHARGE-ONLY CLUB QTE & 15S RAGDOLL KO LOOP

**Parent Document:** Master GDD (v3.2)  
**Purpose:** Complete behavioral specification, RPG quick-time charge bar rules, self-stumble penalties, and 15-second ragdoll KO & full-scatter rules for melee combat and knockouts.  
**Note on Numbers:** Values marked `[TUNABLE]` are starting playtest baselines.

## 1. Design Intent & Core Rules

1. **Ambush Tool, Not a Brawler:** Direct melee combat is intentionally slow, heavily telegraphed, and impossible to button-mash. The Two-Handed Club exists to punish distracted searchers (e.g., rivals stuck in Top-Down Drawer View) or cornered briefcase carriers.
2. **Risk-Reward Skill Check (No Spamming):** Tapping `Left-Click` deals zero damage. Landing an instant-KO slam requires committing to a slow `35%`-speed wind-up and timing a randomized **RPG Quick-Time Event (QTE) bar** — while holding too long causes the attacker to lose balance and ragdoll themselves.
3. **In-Place Knockout & Full-Scatter Loop:** Spies never teleport back to spawn when knocked out. Every trap, dart, or club hit collapses the victim into a **`15-second` in-place ragdoll** right where they fell, dropping their Left-Hand item/Briefcase and **scattering all traps/gadgets stored across all 3 Inner Jacket Slots** onto the floor for opportunistic theft.

## 2. Two-Handed Club Mechanics

### A. Equipping, Stance & 3-Slot Inner Jacket Harmony

- **Ownership:** Every spy starts with a personal **Two-Handed Club** holstered visibly on their back.
- **Draw / Holster (`Press 4` or `R`):**
    - Pressing `4` or `R` toggles the Club from the spy's back (`100%` idle movement speed — zero speed penalty just for holding it).
    - **Inner Jacket Harmony (No Trap Drop):** Toggling the Two-Handed Club **no longer drops held traps onto the floor** — any held trap or gadget simply tucks back into its **Inner Jacket Slot (`Slots 1–3`)** while the Club is drawn. Pressing `1`, `2`, or `3` (or scrolling the mouse wheel) holsters the Club back to the spine and brings out that Jacket Slot's gadget.
    - Drawing the Club **does not** drop Left-Hand items (the Compact Briefcase only auto-drops if the player actively begins holding `Left-Click` to charge an overhead swing).
    - The Club can never be permanently dropped or stolen; getting knocked out automatically re-holsters it onto the spy's spine.

### B. Charge-Only QTE Bar & Release Outcomes

Holding `Left-Click` with the Club equipped raises the Club high overhead (clearly visible in third-person to nearby rivals), drops the **Compact Briefcase** onto the floor if held in the Left Hand (loose single objectives remain held), locks movement speed to **`35%`** `[TUNABLE]`, and fills a **`1.6 s` `[TUNABLE]` RPG timing bar** on the HUD.

- **Randomized Sweet-Spot:** On each wind-up, a **`18%`-wide green target zone** (`~0.29 s` window) `[TUNABLE]` spawns at a random position between **`55%` and `75%`** along the charge bar — preventing blind muscle-memory timing.

| Input / Release Timing | Bar Zone | Move Speed | Audio & Visual Feedback | Gameplay Effect |
| --- | --- | --- | --- | --- |
| Quick Tap (under 0.20 s) | Pre-Charge | 100% | Harmless low-range horizontal swipe + loud WHOOSH | Feint / Bait: Deals 0 damage (0.4 s cooldown). Used to trick rivals into panicking or burning a jump. |
| Early Release (0.20 s to Green Start) | Grey (Under-Charged) | 35% -> 100% | Clumsy off-balance swing + hollow THUNK | Whiff: Deals 0 damage; locks attacker in a 0.6 s [TUNABLE] recovery animation. |
| Timed Release (Inside Green Zone) | Green Sweet-Spot | 35% -> 100% | Cartoon CRACK! impact + camera shake | Instant KO Slam: Checks a 2.0 m [TUNABLE] forward melee cone (occluded by solid walls and closed doors); any hit spy enters the 15s Ragdoll KO state. |
| Over-Charge (100% Bar Reached) | Red End-Cap | 35% -> 0% | Cartoon SLIP / WHOOPS! whistle | Self-Stumble Ragdoll: Attacker loses balance from the heavy Club and collapses into a 2.0 s [TUNABLE] backward ragdoll, dropping any loose Left-Hand objective. |

## 3. Club Ambush Workflow (Visual Flow)

```
[PRESS 4 OR R: DRAW TWO-HANDED CLUB] (100% Move Speed | Held Trap Tucks into Inner Jacket Slot 1–3)
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
                           ├──► [RELEASE INSIDE GREEN] ──► Overhead Slam (2.0m Occluded Cone)
                           │                                   ├── Hit Rival  ──► [RIVAL ENTERS 15s RAGDOLL KO]
                           │                                   └── Miss Swing ──► [0.6s Recovery]
                           │
                           └──► [HOLD TO 100% (OVER-CHARGE)] ──► [SELF-STUMBLE: 2.0s BACKWARD RAGDOLL]
```

## 4. The 15-Second In-Place Ragdoll KO & Wake-Up Loop

### A. What Triggers a 15-Second KO

All lethal slapstick events feed into the exact same unified knockout pipeline:

1. Timed **Overhead Club Slam** (`Green Zone` release within unobstructed `2.0 m` cone)
2. **Water Bucket** drop (`≤ 1.2 m` doorway threshold)
3. **Floor Tripwire** collision (`0.35 m` shin wire)
4. **Drawer Spring Trap** (`Tap E` fast-slam trigger)
5. **Time Bomb** explosion (`5.0 m` wall/door-occluded blast)
6. **DVD Dart Gun** direct dart impact

### B. Step-by-Step Knockout Sequence

1. **Immediate Interrupt (`t = 0.0 s`):**
    - If the victim was inside **Top-Down Drawer View**, the camera immediately snaps out and the drawer closes (unless jammed by a lit Time Bomb).
    - If the victim was charging a Club, the charge cancels immediately.
2. **Knockout Full-Scatter Rule & Club Holster (`t = 0.0 s`):**
    - **Left Hand:** Any held **Compact Briefcase** or **Loose Objective Item** detaches and spawns on the floor at the victim's position with a slight upward/outward scatter impulse (`1.5 m/s`).
    - **3-Slot Inner Jacket (Full-Scatter):** **All traps and gadgets stored across all 3 Inner Jacket Slots** (plus any active hand item) are forcibly scattered onto the floor around the ragdoll (`1.5 m/s` radial scatter).
    - **Two-Handed Club:** The victim's personal **Two-Handed Club** automatically re-holsters onto their back.
3. **In-Place Ragdoll Simulation (`t = 0.0 s` to `15.0 s` `[TUNABLE]`):**
    - The victim's character capsule disables collision with moving players (so rivals don't get stuck tripping over a ragdoll body in narrow hallways) and enters a full ragdoll simulation with a directional slapstick knockback impulse.
    - **Camera Perspective:** The victim's FPS camera remains attached to the ragdoll's head (with a subtle dizzy vignette and spinning stars/birds HUD overlay), letting them watch their rival steal their Briefcase and scattered coat gadgets in hilarious first-person!
    - **Clock Burn:** No extra penalty seconds are subtracted — the `15.0 s` stun naturally burns 15 real seconds off the victim's active private clock.
    - **Trap-Cam Trigger:** If caused by a rival's trap or dart, the trap owner's corner HUD plays the **3.0-second CRT Trap-Cam Replay** (detailed in Doc 6).
4. **In-Place Wake-Up & Spawn-Blink Immunity (`t = 15.0 s` to `17.0 s`):**
    - At `15.0 s`, the ragdoll blends smoothly back (`0.35 s`) into a standing upright pose **at the exact floor coordinates where the pelvis landed** (clamped safely inside room navigation bounds so the spy never wakes up stuck inside furniture or walls).
    - **Wake-Up Protection (`2.0 s` `[TUNABLE]`):** The revived spy blinks semi-transparently (`50%` alpha) for **`2.0 seconds`**, during which they are **immune to Club slams, Darts, and Trap triggers** — preventing unfair spawn-camping loops while giving them a fair chance to grab dropped loot or flee.

## 5. Ragdoll KO & Recovery Workflow (Visual Flow)

```
[HIT BY CLUB QTE / TRAP / DART] (Ignored if Wake-Up Blink Immunity is active)
       │
       ▼
[FORCE EXIT DRAWER VIEW + CANCEL ACTIONS]
       │
       ├──► Left Hand (Briefcase / Objective) ──► [DROP TO FLOOR WITH 1.5m SCATTER]
       ├──► 3-Slot Inner Jacket (Slots 1–3)   ──► [SCATTER ALL STORED TRAPS/GADGETS TO FLOOR] (Club holsters to back)
       └──► Rival's Trap? ──► YES ──────────────► [TRIGGER 3.0s CRT TRAP-CAM REPLAY ON RIVAL HUD]
       │
       ▼
[15.0s IN-PLACE RAGDOLL KO]
 • In-place ragdoll physics active (First-person camera follows tumbling head)
 • Player collision layer disabled for other spies (no hallway body-blocking)
 • Private countdown clock continues ticking down naturally
       │
       ▼ (At t = 15.0s)
[STAND UP AT PELVIS LOCATION + 2.0s WAKE-UP BLINK IMMUNITY]
 • Semi-transparent blink visual (Cannot be re-stunned for 2.0s)
 • Normal movement & hands restored
```
