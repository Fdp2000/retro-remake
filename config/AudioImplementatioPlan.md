# ARCHITECT DIRECTIVE: Phase 4 — Environmental Acoustics & Spatial Audio Engine

### Role & Objective
You are the Lead Systems Architect. Generate a comprehensive, production-ready implementation prompt for the Worker/Coder Agent to build **Phase 4: Environmental Acoustics & Spatial Audio Engine** for our Godot 4.7.2 project.

---

### Critical Guardrails & Performance Constraints

1. **Zero Network Overhead (100% Client-Side):**
   - Acoustics, occlusion, and reverb MUST be calculated purely on the local listener's machine.
   - Do NOT serialize, sync, or transmit acoustic parameters across ENet or EOS. Remote player positions and incoming proximity voice streams are already present locally.
2. **Strict Scope Exclusion (No Third-Party / Heavy Simulators):**
   - **FORBIDDEN:** Do NOT implement or import third-party acoustic plugins (e.g., Steam Audio, Resonance Audio, FMOD, Wwise).
   - **FORBIDDEN:** Do NOT build real-time wave-based raytracing, acoustic diffraction pathfinding (sound bending around doors), or networked RigidBody impact physics.
3. **Native Godot 4.7.2 Architecture Only:**
   - Rely strictly on native Godot primitives: `AudioEffectLowPassFilter`, `Area3D` audio bus overrides, `AudioEffectReverb`, `PhysicsDirectSpaceState3D` raycasting, and `AudioStreamPlayer3D`.
---

### Core Systems to Specify for the Worker Prompt

The implementation prompt you generate must instruct the Worker Agent to implement three distinct subsystems:

#### 1. Dynamic Raycast Occlusion (Wall & Closed-Door Muffling)
- **Target Emitters:** Must apply to remote player proximity voice (`AudioStreamPlayer3D` on head bone/node), footsteps, and interactive container sounds.
- **Occlusion Detection:**
  - Dedicated listener-to-emitter raycast running on a throttled timer (e.g., every 0.05–0.1s or physics tick) rather than heavy per-frame raycasts.
  - Query collision masks for static level geometry (walls) and door colliders.
- **Digital Signal Processing (DSP):**
  - Route emitters through an Audio Bus with an `AudioEffectLowPassFilter`.
  - When line-of-sight is unobstructed: smoothly lerp cutoff frequency to `20,000 Hz` and attenuation to `0 dB`.
  - When obstructed by a wall or closed door: smoothly lerp cutoff frequency down to `600–800 Hz` and apply a `-6 dB` to `-10 dB` volume drop to simulate drywall/wood muffling.
  - Implement smoothing/lerping in `_process` to prevent abrupt audio popping or clicking when crossing thresholds.

#### 2. Environmental Reverb Zones (`Area3D`)
- **Audio Bus Configuration:**
  - Create dedicated aux audio buses in `default_bus_layout.tres`:
    - `Reverb_SmallRoom` (e.g., tiled bathroom, metallic safe: high wet/dry ratio, short decay, prominent early reflections).
    - `Reverb_LargeHall` (e.g., long hallway, lobby: moderate decay, spacious stereo spread).
- **Acoustic Volumes:**
  - Implement reusable `AcousticZone3D` (extending `Area3D`).
  - Configure `audio_bus_override = true` and assign the target reverb bus.
  - Ensure entering and leaving zones transitions the listener and active emitters cleanly using Godot’s built-in area audio bus routing.

#### 3. Surface-Based Footstep & Impact System
- **Surface Detection:**
  - Downward raycast from the player character’s feet detecting the surface beneath.
  - Identify surface type via `PhysicsMaterial` or metadata on colliders (e.g., `"surface": "wood" | "tile" | "carpet" | "metal"`).
- **Audio Modulation:**
  - Map surfaces to sound banks (varied footstep samples).
  - Apply slight randomized pitch shifting ($0.95\times$ to $1.05\times$) on each step to eliminate repetitive audio fatigue.
  - Hook into local character movement and replicated remote player movement state.

---

### Required Deliverables in the Output Prompt

Instruct the Worker Agent to provide:
1. Exact file manifests (`res://core/audio/occlusion_emitter.gd`, `res://core/audio/surface_detector.gd`, bus layout updates).
2. Code for smooth DSP lerping that prevents audio pop artifacts.
3. Test harness integration in `test_gym.tscn` (three test surface patches and a test walled room with an openable door and a looping dummy emitter).
4. Step-by-step single-machine verification steps.