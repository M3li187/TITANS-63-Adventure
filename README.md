# TITANS-63 Adventure

## Challenge

**Build a Junior Astronaut Mission Trainer**

## Summary

TITANS-63 Adventure is a first-person educational game that lets young explorers train for a lunar landing at Fra Mauro. Players explore an interactive spacecraft bridge while LUNA, a voiced robot guide on the ship's screens, helps them respond to a landing-system warning, a radar failure, and a hazardous landing area. Each decision becomes a practical task, such as contacting Mission Control or activating a backup height sensor, while players manage fuel, power, and a running mission clock. NASA lunar terrain and imagery support the landing environment, and different decisions lead to good, bad, safe, or secret endings. The secret ending unlocks an explorable Moon base with a university flag, while surface-specific footsteps and relaxing space music complete the experience.

## How to Run

1. Install **Godot 4.6 or newer, standard edition**. The project has been tested with Godot 4.6.3.
2. Extract the complete game ZIP into a folder. If using a repository checkout, locate the folder containing `project.godot`.
3. Open Godot, select **Import**, and choose `project.godot` inside the `TITANS-Space-Bridge` folder. Wait for the assets to finish importing.
4. Open the project and press **F5** or **Run Project** to start the game.
5. When a mission alert appears, press **Tab** to read it. Choose a plan, follow LUNA's directions and the cyan marker, then press **E** at the indicated control to carry out the task. Open Tab again to review the result and continue.

The game runs offline with bundled data, narration, music, and sound effects. No API keys, plugins, Python installation, or additional audio downloads are required to play.

### Controls

| Input | Action |
| --- | --- |
| W / A / S / D | Move forward, left, backward, and right |
| Mouse | Look around |
| Hold Shift + W / A / S / D | Run |
| Space | Jump while grounded |
| E / left click | Use the control you are aiming at |
| Tab | Open or close the LUNA mission panel |
| 1 / 2 / 3 | Select A / B / C while the choice panel is open |
| T | Replay LUNA's current instructions |
| N | Toggle background music |
| M | Mute or restore all audio |
| V | Toggle LUNA's voice |
| R | Return the astronaut to the current scene's arrival point |
| Esc | Close the mission panel or release the mouse cursor |

## NASA Datasets Used

| Dataset | How it is used |
| --- | --- |
| [LRO/LROC Apollo 14 Digital Terrain Model — NAC_DTM_APOLLO14](https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_APOLLO14) | Supplies measured elevations for the Fra Mauro landing terrain. The game includes a 513 × 513 crop at 2 m spacing, covering approximately 1.024 km between outer sample centers, and displays a terrain mesh sampled at 4 m spacing. Slopes derived from the elevation data inform the example clear-zone location. |
| [LRO/LROC Apollo 14 Orthophoto — NAC_DTM_APOLLO14_M150633128_2M](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO14_M150633128_2M) | Supplies 2 m/pixel lunar surface imagery, cropped and aligned with the terrain grid to texture the landing environment. |

Data credit: **NASA/GSFC/LRO/LROC team**. Source labels, processing details, and provenance are included in `assets/moon/`, including [terrain_metadata.json](assets/moon/terrain_metadata.json).

### NASA Mission-History References

- [NASA Apollo 14 Mission Summary](https://www.nasa.gov/wp-content/uploads/static/history/SP-4029/Apollo_14a_Summary.htm): provides the mission background, Fra Mauro setting, landing date, and reported landing coordinates.
- [NASA, Apollo Expeditions to the Moon — Reprogramming in Flight](https://www.nasa.gov/wp-content/uploads/static/history/SP-350/ch-7-4.html): informs the landing-system warning and radar-failure scenarios, based on Apollo 14's abort-switch fault and landing-radar recovery.

Fuel, power and time penalties, branching outcomes, individual rocks, and the Moon base are authored game simulations rather than NASA measurements.

## Team Members

- Ahmed Alqahtani
- Ali Almatrook
- Renad Alaa Alhaddad
- Ahmed Zakaria Alhajji
- ALJURI ABDULLAH ALDOSARI
- Salim Nabeel Aboghander

For implementation details, source provenance, and regression commands, see [TECHNICAL_GUIDE.md](TECHNICAL_GUIDE.md).
