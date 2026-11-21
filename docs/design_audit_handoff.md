# PotionCrafter — Design Audit & Claude Implementation Handoff

## 0. Codebase Context & Guardrails for Claude
- **Engine & Tech:** Godot 4.7, Jolt Physics, Forward+ renderer, typed GDScript ($\sim 20,500$ LoC), custom analytical liquid shaders, procedural audio synthesis.
- **Core Constraint:** Preserve the continuous property simulation ($60\text{ Hz}$ mass/energy conservation) and analytical liquid performance (dozens of vessels active without SPH particle lag).
- **Safety Gate:** Before completing any phase, run the existing **94 unit tests**, **smoke tests**, and **reaction fuzzer** to verify no regressions in mass/energy balance or temperature clamping ($0.1\text{ K}$ to $10,000\text{ K}$).

---

## 1. Visual & UX Audit Summary (What Needs Fixing & Why)

### A. Fun & Ease of Play (Friction Points)
1. **Blind Sandbox Paralysis ("Brown Sludge Syndrome"):** With $200$ substances, $118$ hidden signature recipes, and zero recipe checklists, casual players lack immediate feedback when they are *close* to discovering something cool versus making inert mud.
2. **Hotkey Overload:** Essential actions currently rely on memorized keyboard shortcuts (`B` to bottle, `E` to store in Satchel, `C`/`X` for chalk, `R` to load rock, `Alt` for info, `M` for stirrer). In a mouse-driven tactile game, every core action should have an obvious, clickable physical prop on the bench.
3. **Repetitive Chores in Mineral Lab:** Manually pressing `R`, swinging the hammer multiple times, dragging the crusher crank in circles, and shaking the sifter creates repetitive mouse strain without skill expression.
4. **UI Collision Bugs:** Top-center stacked notification banners (*"Welcome to the lab"*, *"Recipe learned"*) directly overlap hover tooltips (e.g., *"Empty vial"* card overlaps the toast stack at top-center) and obscure top-shelf glassware.

### B. Graphics & Readability Clutter
1. **Muddy Midtones & Washed-Out Contrast:** Brown wood benches + brown stone walls + brown book spines + parchment riddles + heavy volumetric god-rays create a hazy, low-contrast brown soup. Transparent glass silhouettes disappear into the background.
2. **Floating Raw 3D Text:** In the Mineral Lab and Science Bench, unbacked white text (*"Sand Sifter"*, *"Volatility Tester..."*) floats directly over bright volumetric light shafts and brick mortar lines, making it difficult to read.
3. **Art Style Clashes:** The Gem Polisher looks like a sterile modern white plastic appliance sitting next to medieval stone bricks, and floating mineral specimens look flat-shaded/low-poly compared to the 4K PBR wood and wax seals.

### C. Water & Pouring Physics
1. **Rigid "Plastic Rod" Pour Streams:** Currently, pouring renders a uniform-width cylinder from bottle lip to target. Real fluids accelerate under gravity ($v = \sqrt{v_0^2 + 2gy}$), causing the stream cross-section to **taper**, ripple, and break into droplets (Rayleigh–Plateau instability) for thin liquids or **coil like a rope** for viscous syrups.
2. **Flat Impact & Stiff Sloshing:** Pour streams clip straight into the flat liquid plane without creating an impact cavity, surface ripple rings, crown micro-splashes, or entrained air bubbles rising back to the meniscus.

### D. Typography
1. **Illegible Bottle Labels:** Reagent labels on the bench have tiny, low-contrast serif text on beige paper—unreadable without hovering every single flask.
2. **Weak UI & World Fonts:** UI panels use thin, small sans-serif body text in dark purple boxes with poor hierarchy; the Science Bench chalkboard (`$PV = nRT$`) uses plain Times New Roman rather than authentic chalk lettering; Safety Data Sheets look like unstyled system Arial.

---

## 2. Actionable Implementation Specs for Claude

### Phase 1: Typography & UI Clean-Up (Quickest High-Impact Win)

#### 1.1 Font Pairing & Godot 4.7 Resource Setup
Locate the global Godot `Theme` resource (`.tres`) and all `FontFile` / `FontVariation` assets, and replace them with a curated 4-font system:
- **Display & Grimoire Headers:** **Fraunces** (SemiBold/Bold, optical size enabled) or **Cinzel** — warm parchment tint (`#F5ECD7`), subtle drop shadow, generous tracking.
- **UI Body, Tooltips & Meters:** **Plus Jakarta Sans** or **Atkinson Hyperlegible** (Medium `500` for body, Bold `700` for labels; minimum `15px` at `1080p`). Enable OpenType **Tabular Figures (`tnum = 1`)** so live numbers on the Science Bench don't jitter horizontally as values update at $60\text{ Hz}$.
- **Formulas & Chemical Notation:** **JetBrains Mono** — crisp subscript/superscript rendering for formulas like $\text{H}_2\text{O}$ or $\text{CH}_3\text{COOH}$ in the Ethereal Satchel.
- **Diegetic World Text (Chalkboard & Notes):** **Caveat** or **Architects Daughter** paired with a subtle chalk-dust alpha mask shader on the Science Bench chalkboard (`$PV = nRT$`, `$\text{pH} = -\log[\text{H}^+]$`).

**CRITICAL Godot Import Settings:**
- Set `multichannel_signed_distance_field = true` (MSDF) on **every** font used in `Label3D`, bottle labels, and scaled UI panels so text stays razor-sharp at any camera zoom or tilt angle.
- Set `subpixel_positioning = 1` (Auto) and `oversampling = 2.0` on project GUI settings.

#### 1.2 Readable Bottle Labels (At-a-Glance Identification)
Update the procedural reagent/potion label generator:
- Increase label font weight to **Bold**, dark espresso ink (`#1E1610`) on warm cream (`#F2E6D0`), max 2 lines, larger font size.
- Add a **bold category icon stamp** (e.g., droplet, crystal, acid hazard, arcane star, berry) + subtle color-coded border strip on every vessel label so players can identify reagents across the bench without hovering.

#### 1.3 Fix HUD Layout & Kill Floating Text
- **Fix Toast Overlap:** Move notification toasts (*"Recipe learned"*, *"Secret recipe unlocked"*) from top-center to a **bottom-right stack** with smooth slide/fade animations, freeing top-center exclusively for context prompts and hover cards.
- **Remove Always-On Floating 3D Text:** Strip persistent `Label3D` walls over the Mineral Lab and Science Bench. Replace with:
  1. Engraved brass nameplates directly on machine bases (`VISCOMETER`, `SIFTER`, `POLISHER`).
  2. Clean, dark translucent glass pill-cards (`rgba(16, 14, 28, 0.88)` with `1px` muted gold border `#C8A45D` and `8px` backdrop blur) that appear **only** when hovering or actively using a station.

---

### Phase 2: Cleaner Graphics, Lighting & Visual Cohesion

#### 2.1 De-Muddy the Lighting & Volumetric Haze
Inspect `WorldEnvironment` and bench lighting scenes:
- **Cut Volumetric Fog Haze:** Reduce volumetric fog density by $50\text{--}65\%$ and raise fog sky/ambient contrast. Keep localized light-shaft meshes or subtle dust motes near windows instead of washing out the entire scene's black levels.
- **Foreground/Background Separation:** Darken and slightly desaturate the background bookshelf and stone wall (`0.75x` albedo multiplier or subtle depth-of-field blur beyond the bench depth) so the active workbench pops forward.
- **Glass Silhouette Rim Light:** Add a subtle cool-blue/moonlight rim `DirectionalLight3D` or area backlight grazing the glassware layer. Clear glass needs bright fresnel rim highlights (`pow(1.0 - dot(N, V), 4.0)`) so empty beakers and vials read crisply against dark wood.

#### 2.2 Art Style Unification
- **Reskin Modern White Appliances:** Replace the sterile white housing on the Mineral Lab **Polisher** with aged cast-iron, dark enameled steel, and brushed brass trim to match the Crusher and Science Bench instruments.
- **Upgrade Mineral Shaders:** Replace flat low-poly shading on uncut/cut minerals with a multi-layer PBR shader: triplanar rock normal map + Voronoi crystal facet normals + refraction/subsurface scattering (`subsurface_scattering_strength`) for translucent gems (Fluorite, Quartz, Sapphire).
- **Declutter Pinned Riddles:** Move the 5 hanging parchment *"a sealed riddle"* sheets off the middle of the Potion Bench shelf (where they visually collide with tall flasks and burner stands) onto a dedicated **Corkboard / Commission Ledger** on the left or right margin.

---

### Phase 3: Better Analytical Water & Pouring Physics

Keep the non-particle analytical solver for performance, and upgrade the two visual pillars: **Pour Stream Geometry/Shader** and **Vessel Surface Dynamics**.

#### 3.1 Physically Tapered & Textured Pour Stream
Locate the pour stream mesh generator / shader and replace the uniform cylinder with a procedural segmented tube ($24\text{--}32$ length segments along the ballistic parabola $\mathbf{p}(t) = \mathbf{p}_0 + \mathbf{v}_0 t + \frac{1}{2}\mathbf{g}t^2$):
1. **Continuity Tapering:** Compute instantaneous speed $v(t) = \|\mathbf{v}_0 + \mathbf{g}t\|$. By conservation of volumetric flow rate $Q = A(t)v(t)$, scale stream radius dynamically along the arc:
   $$r(t) = r_0 \sqrt{\frac{v_0}{v(t)}}$$
   Clamp minimum radius based on surface tension $\gamma$.
2. **Viscosity-Driven Regimes:**
   - **Low Viscosity ($\mu < 10\text{ mPa}\cdot\text{s}$, e.g., water, spirits):** Add high-frequency scrolling normal ripples, fresnel refraction (`SCREEN_TEXTURE`), and **Rayleigh–Plateau breakup** near the bottom of slow pours (modulate radius with traveling sine waves $\sin(k s - \omega t)$ that pinch into discrete falling droplets when flow rate $Q$ is low).
   - **High Viscosity ($\mu > 500\text{ mPa}\cdot\text{s}$, e.g., honey, glycerin, slime):** Smooth laminar glassy tube that slows fall acceleration slightly near the lip and exhibits **liquid rope coiling** (helical spiral offset at the impact point: $\Delta x = A\cos(\omega_c t)$, $\Delta z = A\sin(\omega_c t)$ fading upward over the bottom $15\%$ of the stream).
3. **Lip Teardrop Cling:** Anchor the stream origin to the lowest world-space point of the tilted vessel rim inner radius, adding a small meniscus bulge at the lip so liquid never looks detached or clipping through glass.

#### 3.2 Dynamic Vessel Surface, Meniscus & Impact Feedback
Upgrade the analytical vessel liquid shader + GDScript controller:
1. **Damped 2nd-Order Slosh & Ripple Modes:** Ensure vessel slosh uses an underdamped spring-damper ($\ddot{\theta} + 2\zeta\omega_n\dot{\theta} + \omega_n^2\theta = \text{accel}_{\text{lateral}}$) where damping $\zeta$ scales directly with fluid viscosity $\mu$ (water sloshes lively for $1.5\text{ s}$; honey settles sluggishly with zero overshoot).
2. **Pour Impact Cavity & Concentric Ripples:** Pass `pour_hit_uv` and `pour_impulse` uniforms into the receiving vessel's liquid shader:
   - Depress the liquid surface downward in a small Gaussian dimple at the impact point.
   - Add outward-traveling radial sine ripples (`sin(dist * 28.0 - TIME * 14.0) * exp(-dist * 5.0) * pour_intensity`).
3. **Entrained Plunge Bubbles & Meniscus Rim:**
   - Spawn lightweight GPU billboard micro-bubbles (`GPUParticles3D`, capped at $24$ per vessel) at the stream impact point that rise buoyantly to the surface and pop into a subtle foam ring (scaled by air-content / surfactant property).
   - Render a crisp **meniscus highlight curve** along the glass wall intersection—concave upward ($+$ height at wall) for wetting fluids like water, convex downward ($-$ height at wall) for non-wetting fluids like quicksilver ($\text{Hg}$).

---

### Phase 4: Making Gameplay Easier & Way More Fun

#### 4.1 100% Mouse-Playable Diegetic Bench (Zero Mandatory Hotkeys)
Keep all existing keyboard shortcuts, and add tactile mouse interactions for every hidden hotkey:
- **Physical Cork & Wax Dish (Replaces mandatory `B`):** Place a small wooden bowl of corks/wax stamp at the corner of the Potion Bench. Dragging a filled flask onto it (or clicking a contextual `[Cork & Seal]` icon badge floating beside a held potion) triggers the bottling & wax-stamp ceremony with juicy audio/haptic crunch.
- **Satchel Drop-Zone (Replaces mandatory `E`):** When holding any item, slide a subtle glowing Satchel pocket tab onto the right screen edge; dropping an item there stows it immediately.
- **Physical Chalk & Eraser Sponge (Replaces mandatory `C` / `X`):** Put a piece of glowing arcane chalk and a damp sponge on the bench ledge—click chalk to draw sigils, wipe with sponge to clear.
- **Auto-Feed Hopper Option (Replaces repetitive `R`):** Clicking the `SPECIMENS` crate in the Mineral Lab directly tosses the next rock onto the anvil with a satisfying arc.

#### 4.2 "Warm/Cold" Discovery Telegraphing (Make Experimentation Fun, Not Blind)
Preserve *"Emergence over scripting"*, while giving players exciting sensory breadcrumbs when their mixture approaches one of the $118$ discoverable recipes:
- **Proximity Resonance System:** In the recipe signature matcher, compute a normalized proximity score $S \in [0, 1]$ to the nearest undiscovered recipe signature.
  - At $S \ge 0.70$ (*"Getting Warm"*): Emit subtle harmonic chime overtones from the audio director + faint arcane shimmer particles rising from the vessel rim.
  - At $S \ge 0.90$ (*"Almost There!"*): Distinct rhythmic pulse glow + tooltip hint in plain language (e.g., *"Needs slightly more heat"*, *"Too acidic — buffer it"*, or *"Swirl counter-clockwise to align chirality"*).
- **Upgraded Magnifying Glass (Bench 1 Quick-Read):** Picking up the physical **Magnifying Glass** on the Potion Bench and holding it over any beaker shows an instant diegetic "Alchemist Lens" overlay with simple visual bars (Temperature, Acidity $\text{pH}$, Viscosity, Primary Arcane Aura) so players don't have to switch to Bench 3 every 10 seconds unless they want exact numerical precision.

#### 4.3 Juicier, Less Grindy Mineral Lab
- **Fracture Weak-Points on Rocks:** Render a glowing hairline mineral seam on rocks placed on the anvil. Clicking the hammer on the seam triggers a **Critical Strike** (brief $40\text{ ms}$ hit-stop, camera micro-shake, crisp chime, instant clean shatter in 1 hit instead of 4–5 repetitive clicks).
- **Flywheel Momentum on Crusher & Sifter:** Give the Rock Crusher crank and Sand Sifter rotational/linear inertia! One brisk flick of the mouse spins the heavy flywheel through $40\text{--}50\%$ of the job instead of forcing continuous circular mouse dragging.

#### 4.4 Onboarding & Guided Commissions ("First 5 Minutes" Hook)
- Replace the passive *"a sealed riddle"* text scraps with **Interactive Alchemist Commissions** (3 starter requests pinned to the Commission Board that teach mechanics organically):
  1. *Tutorial 1 (Fizz & Seal):* **"The Apprentice's Volcano"** — Mix Vinegar + Salt of Soda + Saponified Lather (teaches pouring, foaming reactions, and corking).
  2. *Tutorial 2 (Arcane Gravity):* **"Weightless Dew"** — Purify/concentrate Moonwater until gravity coupling $g_c < 0$ (teaches floating bottle physics & wax grading).
  3. *Tutorial 3 (Heat & Phase):* **"Hot Ice"** — Supersaturate and cool to trigger rapid crystallization (teaches burner control & thermal shock care).

---

## 3. Execution Checklist & File Discovery Plan for Claude

Execute this update in **4 atomic commits**, verifying tests after each step:

1. **Repo Recon:**
   - Glob `**/*.gd`, `**/*.gdshader`, `**/*.tres`, `**/*.tscn` to map:
     - Liquid vessel & pour stream shaders/scripts
     - Global UI `Theme` and `Label3D` configurations
     - `WorldEnvironment` and workstation lighting rigs (`Bench1`, `Bench2`, `Bench3`)
     - Recipe signature evaluator & HUD notification manager
2. **Commit 1 — Fonts, UI Theme & Toast/Label Overhaul:**
   - Bundle open-source OFL fonts (`Fraunces`, `Plus Jakarta Sans`, `JetBrains Mono`, `Caveat`) into `res://assets/fonts/` with MSDF enabled.
   - Refactor HUD toast anchor to bottom-right; convert persistent floating `Label3D` text into hover-only dark pill cards + machine brass plaques; upgrade bottle label legibility + category icons.
3. **Commit 2 — Graphics & Lighting Polish:**
   - Tune `WorldEnvironment` volumetric fog, add glassware fresnel rim light, darken background wall value by $20\%$, reskin Mineral Lab polisher to brass/cast-iron, upgrade gem refraction/SSS shader.
4. **Commit 3 — Analytical Pour Stream & Liquid Surface Physics:**
   - Implement $r(t) = r_0 \sqrt{v_0 / v(t)}$ tapered stream mesh, Rayleigh–Plateau droplet breakup vs. viscous rope coiling, impact dimple + radial ripple ring uniforms, meniscus wall curve, and micro-bubble particle bursts.
5. **Commit 4 — Gameplay Juice, Diegetic Controls & Discovery Hints:**
   - Add clickable Cork/Wax dish, Satchel edge drop-zone, physical Chalk/Sponge, Magnifying Glass quick-lens, recipe proximity shimmer/audio cues, Mineral Lab crit seams + flywheel momentum, and 3 starter Commissions.
6. **Final Verification:**
   - Run full Godot test suite (`94` unit tests + smoke tests + reaction fuzzer) via headless CLI and confirm zero physics/NaN regressions and steady $60+\text{ FPS}$.