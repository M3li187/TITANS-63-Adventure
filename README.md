# TITANS · Space Bridge

The TITANS astronaut's first-person controller and floating walk animation,
integrated into the supplied Sci-Fi Cockpit Bridge 6 project.

## Open and play

1. Extract the entire ZIP into a new folder.
2. In **Godot 4.6 or newer** (standard edition), import `project.godot`.
3. Let Godot import the astronaut assets, then press **F5**.

You start standing in the bridge's central aisle, looking toward the pilot seats
and the planet outside. The active camera is the astronaut's eye camera.
The original flying/orbit camera is no longer connected to the main scene.

## Controls

| Input | Action |
|---|---|
| W / S | Walk forward / backward relative to where you face |
| A / D | Strafe left / right |
| Mouse | Look around |
| E or left click | Operate the control under the crosshair within 2.4 metres |
| Esc | Release the cursor and stop walking |
| Left click after Esc | Resume mouse look; this first click does not operate a control |
| R | Return safely to the entry position |
| H | Show or hide help |

Look down or up to aim at lower console buttons or the overhead panel. A yellow
prompt names the focused control and its current state. Solid walls and closed
doors block interactions. Activations also appear in the event log.

## Interactions

- Screens cycle through their existing live display pages.
- Switches and throttle levers toggle their states and animate.
- CABIN LIGHTS changes the cabin illumination; RED ALERT pulses the warning lights.
- Warning annunciators can be acknowledged.
- BRIDGE DOOR opens/closes the sliding door. Walk through to the corridor.
- The illuminated BRIDGE ACCESS switch inside the corridor operates the same door
  so you can return. The door holds/reopens if the astronaut occupies its opening.
- The original oxygen-alert training scenario remains enabled. After 25 seconds,
  switch LIFE SUPPORT BACKUP at the rear-left wall panel, then acknowledge MASTER
  CAUTION on the main dashboard. Progress appears in the event log.

The cockpit remains a systems-interaction scene: controls retain the original
project's state changes, display logic and mission hooks.

## Character and camera effects

The supplied astronaut GLB, Moon_Walk animation, eye-level camera, mouse look,
smoothed head-animation bob and subtle directional lean are retained. The local
camera hides the astronaut mesh so the helmet cannot obstruct the view.

Select **Astronaut** in `Main.tscn` to adjust:

- **Move Speed** (default 1.5 m/s).
- **Moon Gravity** (default 1.62 m/s²).
- **Camera Motion Strength** (default 0.35; use 0 for a steady camera).
- **Camera Smoothing** and **Mouse Sensitivity**.

The reusable player is `Player.tscn`. The interaction reach is on its
**Interaction** child's **Reach** property.

## Main files

| File | Purpose |
|---|---|
| `Main.tscn` | Cockpit, astronaut, HUD and existing mission scenario |
| `Player.tscn` | Capsule, imported astronaut and first-person eye rig |
| `scripts/Astronaut.gd` | Movement, animation, mouse look and camera effects |
| `scripts/PlayerInteraction.gd` | Short-range, occluded physics-ray interactions |
| `scripts/BridgeCollision.gd` | Solid interior, canopy, level decks and sliding doors |
| `Cockpit.gd` | Original procedural bridge and systems, with walking integration |
| `scripts/CockpitControl.gd` | Existing switch/button/screen/door behavior |
| `scripts/MissionDemo.gd` | Existing O2-pressure training scenario |
| `assets/astronaut/` | Supplied astronaut model and texture sources |

`CameraController.gd` and `scripts/ScreenshotTool.gd` are retained as original
source references only; they are not attached to the integrated main scene.
The images in `screenshots/` show the supplied cockpit, not new integrated captures.

## Validation

Tested in **Godot 4.6.3**, using the headless engine:

- Fresh import and loading of the integrated main scene.
- WASD, view-relative walking, animation start/pause and safe respawn.
- Floor, console, pilot-seat and wall collision.
- Nearby ray-picking of buttons, screens, levers and both door switches.
- E activation, left-click activation, and click-to-recapture behavior.
- Solid closed doors, walk-through open doors, and door-occupancy protection.
- The original life-support and master-caution mission sequence.
- All 72 interior controls reachable from a connected grid of standing positions.
- First-person head tracking, bounded camera motion and settling while idle.

Interactive rendering and the visual feel of the camera were not tested in this
execution environment. The included cockpit artwork, materials, lighting and
space backdrop are preserved from the supplied project.

Optional regression commands, run from this folder:

```sh
godot --headless --editor --import --quit
godot --headless --fixed-fps 60 --path . --script res://tests/bridge_integration_test.gd
godot --headless --fixed-fps 60 --path . --script res://tests/control_accessibility_test.gd
```

The ZIP includes source assets; Godot rebuilds its editor cache on import.
