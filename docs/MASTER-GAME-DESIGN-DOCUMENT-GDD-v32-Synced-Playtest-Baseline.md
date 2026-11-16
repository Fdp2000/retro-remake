# MASTER GAME DESIGN DOCUMENT \(GDD v3\.2 — Synced Playtest Baseline\)

**Project:** *Spy vs\. Spy: 3D Remake* \(Working Title\)<br>**Genre:** 3D First\-Person Slapstick Sabotage &amp; Spatial Deduction<br>**Players:** 1v1 Classic Duel \(Core\) / 2–4 Player Free\-For\-All \(Week 3 Stretch\)<br>**Engine &amp; Networking:** Godot 4 \(`4\.7\.2\-stable`\) \+ Epic Online Services \(EOS\)<br>**Note on Numbers:** All durations and speeds marked `\[TUNABLE\]` are starting playtest baselines meant to be tweaked during Week 2–3 greybox testing\.

## 1\. High Concept &amp; Design Pillars

A first\-person 3D reimagining of the 1984 NES classic *Spy vs\. Spy*\. Rival spies infiltrate a modular embassy to search furniture for **4 Secret Objective Items** \(*Key, Bag of Money, Passport, Secret Plans*\) and a **compact Attaché Briefcase**, pack all 4 items inside the Briefcase, and escape through the **single shared Airport Exit Door** before their personal countdown timer hits zero\.

### The 4 Non\-Negotiable Pillars

1. **Trap &amp; Gadget Warfare Over Gunplay:** Traps and slapstick gadgets are the primary drivers of friction and comedy\. Melee combat is a slow, telegraphed ambush tool with zero button\-mashing\.
2. **Spatial Audio &amp; Wearable Spy Deception:** Without split\-screen, players rely on directional 3D audio, **proximity voice chat**, and a wearable **Spy Watch / Smart Glasses** to communicate and project directional audio bluffs\.
3. **Asymmetric Risk\-Reward Interactions:** Every door and drawer forces a split\-second gamble between **speed** \(loud, gives full escape window on Time Bombs, triggers Springs/Buckets\) and **caution** \(quiet, spots Springs/Buckets, forces a "Hot Potato" Bomb toss\)\.
4. **Tactile Slapstick Physicality:** Physical hands inside open drawers, hot\-potato bomb throws, ragdoll knockouts, and a **3\.0\-second CRT Trap\-Cam Replay** showing the actual past footage of your rival getting hit by your trap\.

## 2\. Core Gameplay Loop \(Visual Workflow\)

```
[SPAWN IN EMBASSY CORNER] (Clock: 03:00 | Club on Back | Wearable Watch/Glasses | 0 Pre-Armed Traps)
         │
         ▼
[EXPLORE, LISTEN & BLUFF] ──► Proximity Voice + Wearable Spy Device (Comms & Directional Bluffs)
         │
         ├──► [PICK UP FLOOR WATER BUCKET] ──► Rig Top of Closed Door (0.8s)
         │
         ▼
[APPROACH DRAWER / CABINET]
         │
         ├──► FAST SLAM (Tap E)  ──► Loud | Gives Full Bomb Escape Time | Triggers Spring
         └──► SLOW PEEK (Hold E) ──► Quiet | Click-Unlatch & Steal Spring | Forces Bomb "Hot Potato"
         │
         ▼
[TOP-DOWN DRAWER VIEW] (Cursor Unlocked | Press A/S/D to Back Out & Close)
         │
         ├──► Drag Clutter Aside ──► Find Objective Item OR Compact Briefcase (+10s Clock)
         └──► Find / Plant Trap  ──► Spring, Time Bomb, Tripwire Coil, or DVD Dart Gun
         │
         ▼
[PACK ALL 4 OBJECTIVES INTO BRIEFCASE] (Left Hand holds Briefcase | Right Hand stays free)
         │
         ▼
[SPRINT TO SINGLE AIRPORT EXIT DOOR] ──► Touch Exit with 4-Item Briefcase ──► [INSTANT VICTORY]
```

## 3\. Win, Loss &amp; Timer Rules \(Faithful to 1984 OG\)

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545409171&cot=14)*

| Outcome | Trigger Condition | Design Purpose |
| --- | --- | --- |
| Escape Victory | A spy touches the single shared Airport Exit Door while holding the Briefcase containing all 4 Objective Items\. | Zero unlock channel at the exit prevents unfair doorway camping on the final step\. |
| OG Clock Elimination | When Spy A's private timer hits 0:00, Spy A explodes/is eliminated — AND Spy B must still complete the 4\-Item Briefcase Escape before Spy B's own timer hits 0:00\! | Preserves the intense 1984 endgame pressure: surviving your rival doesn't hand you a free win if you waste time\. |
| Mutual Loss \(Draw\) | Both spies run out of time before anyone reaches the Airport Exit\. | Forces proactive searching and tempo management throughout the match\. |

### The Private Timer Economy

- **Starting Time:** `03:00` \(`180 seconds`\) `\[TUNABLE\]`, displayed **only** to its owner on their HUD\.
- **Searching a New Container:** **`\+10 seconds`** `\[TUNABLE\]` awarded the first time a spy opens any unsearched drawer/cabinet\.
- **Knockout Penalty:** **No arbitrary point subtraction** — the **`15\-second` in\-place ragdoll stun** naturally burns 15 real seconds off your active clock while your rival loots freely\.

## 4\. Core Systems Overview

### A\. Dual Movement &amp; Stances

- **Quiet Walk \(Default — `100%` Speed / `4\.5 m/s`\):** Low footstep radius \(`3\.0 m`\); safe approach to closed doors without auto\-opening them\.
- **Loud Sprint \(`Hold Shift` — `150%` Speed / `6\.8 m/s`\):** Heavy footsteps audible `14\.0 m` away; **automatically bashes closed doors open** on contact\.
- **Silent Crouch \(`Hold Ctrl` — `75%` Speed / `3\.4 m/s`\):** Completely silent \(`0\.0 m` audio\) brisk sneak for closing distance behind unaware rivals and inspecting/disarming shin\-level floor Tripwires\.
- **Encumbrance Modifiers:**
    - Holding **Compact Briefcase** in Left Hand: `90%` speed \(can still sprint and crouch\)\.
    - Holding **Two\-Handed Club** in Right Hand: `100%` speed while drawn idle; **`35%` speed** while actively holding `Left\-Click` to charge the overhead swing\.

### B\. Two\-Slot Physical Hands &amp; Wearable Spy Device

- **Left Hand \(Objective Slot\):** Holds **1 loose Objective Item** OR the **Compact Attaché Briefcase** \(capacity: 4 items\)\.
- **Right Hand \(Action Slot\):** Holds **1 tool/weapon** — Two\-Handed Club, 1 Trap \(Bucket, Spring, Time Bomb, Tripwire\), or the 1\-Shot DVD Dart Gun\.
- **Briefcase Charge\-Drop Rule:** Simply equipping the Two\-Handed Club does **not** drop your Left Hand item\. However, **actively starting the overhead charge \(`Hold Left\-Click`\)** immediately drops the **Briefcase** onto the floor at your feet \(loose single objective items in your Left Hand are **not** dropped when charging\)\.
- **Knockout Full\-Drop Rule:** Getting knocked out by **any** trap, dart, or club hit immediately drops **everything** held in **both** your Left Hand and Right Hand onto the floor\.
- **Wearable Spy Comms &amp; Bluff Device \(`Hold V` Voice / `B` or `Tab` Bluffs\):** Permanent non\-droppable **Spy Wristwatch / Smart Glasses** \(never occupies Left or Right hand slots\)\.

### C\. The 5\-Trap &amp; Special Gadget Roster \(All Owner\-Triggerable\)

Matches start with **`0` pre\-armed traps** \(`starting\_prearmed\_traps = 0`\)\. All traps trigger identically on **both** the rival and the trap's owner\. **4 Objective Items**, **1 Compact Briefcase**, and **4 Drawer Gadgets** \(*Spring, Time Bomb, Tripwire Coil, DVD Dart Gun*\) spawn randomly inside drawers; **Water Buckets** spawn out in the open on floors/corners\.

*[Table view](https://miro.com/app/board/uXjVESmWDpA=/?moveToWidget=3458764690545409172&cot=14)*

| Trap / Gadget | Where Found &amp; Placed | Trigger Condition | Optimal Counter &amp; "Hot Potato" Rule |
| --- | --- | --- | --- |
| 1\. Water Bucket | Found on floors/corners \-&gt; placed on top edge of a closed Door \(0\.8 s\) | Door swings past 25° \(drops on anyone within 1\.2 m doorway zone; falls &amp; spills harmlessly if opened from 1\.8 m max reach\) | Look up at doorframe \-&gt; aim at bucket \-&gt; Hold E \(1\.0 s\) to steal |
| 2\. Tripwire | Found in drawers \-&gt; stretched across floor/doorway at 0\.35 m shin height | Walking or sprinting through the wire | Jump \(Space\) over it, or Silent Crouch \(Ctrl\) \+ Hold E \(1\.0 s\) to steal |
| 3\. Spring | Found in drawers \-&gt; hooked to front inner lip of a Drawer | Fast Slam \(Tap E\) | Slow Peek \(Hold E\) \-&gt; Left\-Click Spring to unlatch \-&gt; drag to Right Hand or re\-arm |
| 4\. Time Bomb | Found in drawers \-&gt; planted inside a Drawer \(under clutter\) or inside a dropped Briefcase | Any open ignites a randomized 2\.5 s–4\.0 s fuse \(5\.0 m blast blocked by walls &amp; closed doors\) | Left\-Click lit Bomb in Top\-Down View to auto\-close &amp; equip in FPS \-&gt; Left\-Click throw \(9\.0 m\); direct body hit forces rival to catch &amp; equip \("Hot Potato"\) |
| 5\. DVD Dart Gun | Found in drawers \-&gt; fired 1\-handed from Right Hand \(1\-shot disposable gadget\) | Direct dart hit with a bouncing DVD\-screensaver crosshair | Erratic movement / cover \(single shot only\) |

### D\. Slapstick Melee Combat \(Charge\-Only Club\) &amp; Knockout State

- **Two\-Handed Club \(Zero Button\-Mashing\):**
    - *No Quick\-Tap Damage:* Tapping `Left\-Click` \(`under 0\.20 s`\) only performs a harmless low\-range **shove/feint** \(`0` damage, preventing click\-spam duels\)\.
    - *Hold `Left\-Click` \(Overhead Ambush Charge\):* Drops Briefcase if held, slows player to `35%` speed, and displays a randomized **RPG quick\-time sweet\-spot bar**\. Releasing inside the green zone delivers an **instant KO overhead slam**\. Over\-charging past `100%` causes the attacker to lose balance and **ragdoll backward for `2\.0 s`**\.
- **Knockout \(KO\) State:** Victim turns into a **`15\-second`** in\-place `PhysicalBone3D` ragdoll, drops **all** items from both Left and Right hands onto the floor, and stands back up in place with **`2\.0 s`** of wake\-up blink immunity\.

### E\. Audio, Wearable Spy Device, CRT Trap\-Cam Replay &amp; Anti\-Camping

- **Proximity Voice Chat:** Real\-time spatial voice attenuated and muffled by walls/closed doors via the team's existing physically based spatial audio pipeline\.
- **Wearable Spy Watch / Smart Glasses \(`Hold V` Global Comms / `B` or `Tab` Bluffs\):** Enables long\-range radio voice and projects directional audio bluffs \(*trap arming, drawer slam, sprint steps, door bash*\) through the physical audio engine\.
- **3\.0\-Second CRT Trap\-Cam Replay:** Each client captures a continuous `3\.0 s` \(`36\-frame` @ `12 FPS`\) low\-res `SubViewport` image ring buffer from the rival's head camera\. When your trap hits your rival, the buffered `3\.0 s` replay plays back on your corner HUD CRT screen\.
- **Anti\-Camping Sneeze:** Staying inside the same `RoomZone` \(`Area3D`\) for **`20\.0 seconds`** `\[TUNABLE\]` without interacting with any prop triggers a loud, echoing cartoon **Sneeze** \(`"ACHOO\!"`, `22\.0 m` radius\)\.

## 5\. Miro Board Documentation Index

1. **Master GDD \(v3\.2 — Synced Playtest Baseline\)** *\(This Document\)*
2. **Doc 2: Player Controller, Dual Movement &amp; Two\-Handed Hand Inventory**
3. **Doc 3: Unified Bidirectional Doors &amp; Top\-Down Drawer Search System**
4. **Doc 4: The 5\-Trap &amp; Gadget Ecosystem \(Bucket, Tripwire, Spring, Hot\-Potato Bomb, DVD Dart Gun\)**
5. **Doc 5: Slapstick Melee Combat, Charge\-Only Club QTE &amp; 15s Ragdoll KO Loop**
6. **Doc 6: Audio Architecture, Wearable Comms &amp; Bluff Device, 3\.0s CRT Replay &amp; Anti\-Camping**
7. **Doc 7: Modular Greybox Level Blueprint &amp; Remaining 2\-Week Sprint Plan**

