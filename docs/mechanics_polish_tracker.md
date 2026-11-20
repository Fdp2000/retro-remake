# Mechanics Polish Tracker — Spy vs. Spy 3D

One mechanic at a time. For each one we: **review the design → you test it → list what's off → fix → you sign off ✅**.

**Status key**
| | Meaning |
|---|---|
| ✅ | Signed off by you |
| 🔵 | Iterated on with your feedback, but not signed off yet |
| 🟡 | Built and unit-tested, **you haven't played it yet** |
| 🟠 | Partly built / known deviation from the design |
| ❌ | Not built |

> [!IMPORTANT]
> Order matters. Each group depends on the ones above it. Group F (KO) sits in the middle on purpose: **every trap ends in a KO**, so the KO has to feel right before trap testing means anything.

---

## A. Foundation (moving around)
| # | Mechanic | Status | Notes |
|---|---|---|---|
| A1 | FPS movement + mouse look (DPI / sensitivity, `[`/`]` nudge) | ✅ | |
| A2 | Stances: Walk / Sprint / Crouch (speeds, capsule 1.8m → 1.0m, camera height) | ✅ | |
| A3 | Jump | ✅ | |
| A4 | Footstep sounds (walk 3m, sprint 14m, crouch silent) + landing thud | ✅ | Placeholder synth sounds (swapped in I7) |
| A5 | 2-player connect, lobby, spawn (ENet) | ✅ | EOS path not re-verified |
| A6 | HUD: status bar, prompts, private clock | ✅ | Text-heavy greybox HUD |

## B. Hands & Inventory
| # | Mechanic | Status | Notes |
|---|---|---|---|
| B1 | World pickups (`Tap E`) + floor drops land safely | ✅ | |
| B2 | Left Hand: carry 1 Objective, `Q` drop | ✅ | |
| B3 | Briefcase: carry (0.90 speed), packs up to 4 Objectives | ✅ | Pressing `E` on a floor Objective auto-drops carried Briefcase (or swaps held loose Objectives); slot-free freeform X/Y layered interior with shove/throw momentum & wall bounce; two-stage open with 3-zone search UI, simultaneous Drawer+Briefcase open, and Spring/Bomb trapping (Future visual polish: replace 2D side panels with physical 3D inner-coat pockets & 3D Left-Hand/Briefcase models) |
| B4 | 3-Slot Jacket: fills first empty slot, `1/2/3` + scroll select, `G` drop, swap when full | ✅ | |
| B5 | Personal Club `4`/`R` (tucks gadget back into coat, never drops it) | ✅ | |
| B6 | Held-item visuals (hand sockets, Club on back, Watch) | ✅ | Primitive meshes |

## C. Doors
| # | Mechanic | Status | Notes |
|---|---|---|---|
| C1 | `Tap E` fast open/close, swings away from you | ✅ | |
| C2 | `Hold E` slow push (door opens only as far as you hold) | ✅ | |
| C3 | Sprint auto-bash | ✅ | |
| C4 | Door collision (no walking through the leaf) | ✅ | |

## D. Drawers & Search
| # | Mechanic | Status | Notes |
|---|---|---|---|
| D1 | `E` to focus → slow camera move to top-down | ✅ | |
| D2 | Fast open vs slow open (3.8s, extra slow 0–40%) | ✅ | Committed, non-cancellable 0%→100% Slow Open with exponential ease-in curve (`3.8s`, `drawer_slow_open_exp_steepness = 7.0`) across Drawers, 3D Briefcase, and simultaneous Left Carried Briefcase; clutter/loot drags stay locked until 100%, while armed Springs can be clicked & unlatched mid-animation before reaching `0.42` |
| D3 | Clutter layers: click-drag junk, layers never swap | ✅ | Seeded deterministic placement keeping randomized important items covered by 1–2 overlapping junk pieces across max 3 disjoint vertical layers (~0.70x mesh scale), with shove/throw drag momentum & wall bounce |
| D4 | Looting Objectives / gadgets into hand / jacket | ✅ | |
| D5 | Objective glint particles | ✅ | |
| D6 | Single-user lock `[IN USE]` | ✅ | |
| D7 | Dropped Briefcase opens as a container | ✅ | Unified 3D hinged Briefcase rig (no 4-slot dividers), slot-free freeform X/Y drag with shove/throw momentum & wall bounce, front-angled search camera (~21°), disjoint vertical layering, two-stage Fast/Slow open, and Spring/Bomb trapping (Future visual polish: physical 3D left/right search visuals) |
| D8 | First-search +10s clock bonus | ✅ | |

## E. Drawer Traps
| # | Mechanic | Status | Notes |
|---|---|---|---|
| E1 | Spring Trap: arm in drawer, fast open = KO, slow open = see & unlatch < 42% (else KO) | ✅ | Armed Springs trigger KO if still un-disarmed at `SPRING_TRIGGER_VISUAL_RATIO` (`0.42`) during Slow Open; clicking the peeking 3D `LipSpringTrap` or carried Briefcase unlatch button between `15%` and `42%` unlatches safely and lets Slow Open continues to `100%` |
| E2 | Time Bomb: arm in drawer/briefcase, fuse lights on open (3.3–4.0s) | ✅ | Removed `step_open_drawer`; fuse lights immediately at `0%` on both Fast Slam and Committed Slow Open |

## F. Knockout (the payoff for everything)
| # | Mechanic | Status | Notes |
|---|---|---|---|
| F1 | 15s KO state: real 13-bone `PhysicalBoneSimulator3D` ragdoll on `AgentGreen` / `AgentPurple` (Layer 4, no body-blocking) + secondary hits launch KO'd bodies | ✅ | Continuous 13-bone chain on `metarig/Skeleton3D`, Spy Green vs Purple sync, Dart Gun kick & ~5 Hz pelvis sync |
| F2 | KO camera: locked 100% onto `spine.006` head bone | ✅ | Permanent bone-local anchor + unculled `SkeletonKeepAlive` |
| F3 | Full scatter: Left Hand + all 3 jacket slots, Club re-holsters | ✅ | |
| F4 | Wake-up at pelvis position snapped to floor + pushed clear of walls/props | ✅ | Physics floor & 8-way radial clearance snap |
| F5 | 2s blink immunity after wake-up | ✅ | Blinks the 3D Agent model |

## G. World Traps & Gadgets
| # | Mechanic | Status | Notes |
|---|---|---|---|
| G1 | Water Bucket: `Hold LMB` 0.8s rig on closed door, 10° ajar tell | ✅ | |
| G2 | Water Bucket: drops past 28° (4° same-side), KO within 1.2m vs harmless spill | ✅ | |
| G3 | Water Bucket: look at bucket + `Hold E` 1.0s steal (stays ajar) | ✅ | |
| G4 | Tripwire: two-point pole-and-wire placement (`Hold LMB` 0.4s per pole, 0.4m–2.5m span) | ✅ | |
| G5 | Tripwire: walk/sprint = KO, jump / crouch = safe, crouch + `Hold E` steal | ✅ | |
| G6 | Lit Bomb: click in drawer → auto-close → live bomb in FPS hand | ✅ | |
| G7 | Lit Bomb: `LMB` throw (9m arc), mid-air catch by rival, floor re-grab | ✅ | |
| G8 | Lit Bomb: 5m blast, blocked by walls / closed doors, self-detonates if held | ✅ | Fixed in-hand detonation launching ragdoll straight up into roof (now horizontal/backward `12.0` + `4.5` up) |
| G9 | DVD Dart Gun: bouncing reticle 320 px/s | ✅ | |
| G10 | DVD Dart Gun: 1 shot → KO → gun breaks | ✅ | Test no longer checks the KO |
| G11 | Owner-trigger parity (your own traps hit you too) | ✅ | Cross-cutting, check per trap |

## H. Club Melee
| # | Mechanic | Status | Notes |
|---|---|---|---|
| H1 | Charge bar: 3.2s, random 9% green zone (55–75%), speed lerps to 0.35x by halfway to green_start (floored at walk*0.35), 0.4s exp exit lerp, drops Briefcase | ✅ | |
| H2 | Outcomes: feint (<0.2s), whiff (0.6s recovery), green = KO slam, 100% = 2.5s minor backward ragdoll | ✅ | |
| H3 | Slam hit detection: 2m forward, blocked by walls | 🟡 | |
| H4 | Club animation / readable wind-up | 🟠 | Just rotates the held mesh |

## I. Spy Watch, Deduction & Audio
| # | Mechanic | Status | Notes |
|---|---|---|---|
| I1 | `C` cycle bluff cue, `B` self-bluff (12m) | 🟡 | |
| I2 | `Hold Tab` map → remote room bluff | 🟡 | |
| I3 | `Hold V` radio | 🟠 | Indicator only, no actual voice |
| I4 | Anti-camp: 15s sniffle → 20s sneeze (22m), resets on room change / action | 🟠 | Uses nearest room centre instead of proper room trigger zones |
| I5 | CRT Trap-Cam replay (3s, 12 FPS, on the trap owner's HUD) | 🟡 | Real 240×135 12 FPS remote rival head-camera `SubViewport`, render-layer self-occlusion so trap owner appears in replay, 2.0s pre-impact + 1.0s post-impact ragdoll tail, retro CRT scanline/vignette/static bezel — ready for playtest |
| I6 | Spatial audio: wall muffling, reverb zones, floor surfaces | 🟠 | Basic on/off muffling only; no reverb or surface sounds |
| I7 | Real sound assets (replacing synth beeps) | ❌ | |

## J. Match Loop & Level
| # | Mechanic | Status | Notes |
|---|---|---|---|
| J1 | Airport Exit victory (Briefcase with 4/4) | 🟡 | Plays cleanly in Full Match Mode (Room_2_2 `SharedAirportExit`); requires real 4/4 Briefcase escape — ready for playtest |
| J2 | Clock elimination / mutual-loss draw | 🟡 | Wired `spy_eliminated_by_clock`: scatters eliminated spy's Left Hand + 3 Jacket slots onto floor for survivor & locks KO until rematch — ready for playtest |
| J3 | Seeded match spawner (12 drawers, loot, 3 floor buckets, 0 pre-armed) | 🟡 | Runs live in Full Match Mode (corner room spawns NW/SE, no `TestPickups` row); fixed `FurnitureSpawner` marker skip (`occupied_by_match_drawer`) so furniture never clips into searchable drawers |
| J4 | 3×3 greybox embassy level (6m × 6m rooms) | ❌ | Currently using BuildingComplex2 |
| J5 | Lobby map picker, match-end screen, rematch | 🟡 | Lobby now splits Solo Full Match vs. Sandbox Gym (2P Lobby defaults to Full Match); added [match_end_overlay_ui.gd](file:///C:/Users/fedef/Documents/retro-remake/ui/match_end_overlay_ui.gd) with Victory/Defeat/Draw summary, instant Rematch (new seed), and Mode Switch |

---

## Suggested Order
```mermaid
flowchart LR
    A["A. Foundation ✅"] --> B["B. Inventory (B3)"] --> C["C. Doors ✅"] --> D["D. Drawers ✅"] --> F["F. KO ✅"]
    F --> E["E. Drawer Traps ✅"] --> G["G. World Traps"] --> H["H. Club"] --> I["I. Watch & Audio"] --> J["J. Match & Level"]
```

## Session Log
| Date | Mechanic | Outcome |
|---|---|---|
| 2026-11-19 | A1–A6, B1–B2, B4–B6, F1–F5 | Signed off ✅; B3 (Briefcase) flagged 🟠 as active fix |
| 2026-11-19 | B3, D7 | Reworked Briefcase UX + blocked floor-Objective carry pickup + slot-free layered interior; 38/38 tests passing, ready for playtest 🔵 |
| 2026-11-19 | B2, B3, D3, D7 | Auto-drop Briefcase / swap Objective on floor `E` pickup, ~0.70x drawer interior scale, max 3 clutter layers, shove/throw drag momentum in Drawers & Briefcases; 39/39 tests passing 🔵 |
| 2026-11-19 | B2, B3, D3 | Fixed Objective-to-Objective `E` swap dispatch & restored all 6 drawer junk props across max 3 disjoint vertical layers; 39/39 tests passing 🔵 |
| 2026-11-19 | B3, D3, D7, I5 | Signed off B3, D3, D7 ✅ (future 3D pocket/hand visuals noted); built real rival head-camera `SubViewport` CRT Trap-Cam Replay (`I5` 🟡) with visual-layer self-occlusion & retro CRT shader bezel |
| 2026-11-19 | J1–J3, J5 | Wired Full Match Mode vs. Sandbox Gym Mode, fixed `FurnitureSpawner`/`MatchSpawner` drawer overlap, connected clock elimination item scatter & KO lock, and built `MatchEndOverlayUI` with instant Rematch & Mode Switch 🟡 |
| 2026-11-20 | C1–C4, D1–D8, E1–E2 | Groups C (Doors), D (Drawers & Search), and E (Drawer Traps) signed off ✅ |
| 2026-11-20 | E2, G6–G8 | Signed off Lit Bomb (`G6–G8`) ✅; removed `step_open_drawer`, lit bomb fuse immediately on slow/fast open (`3.3–4.0s`), and fixed self-detonation roof-stuck ragdoll impulse |
