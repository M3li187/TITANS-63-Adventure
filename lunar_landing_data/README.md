# Integrated-game update

The updated game includes a measured lunar crop in `assets/moon/`. Follow the root
README for the playable mission. The guide below describes the earlier standalone
starter pack and optional full-source downloads; full original rasters remain
omitted from the game ZIP.

# Lunar landing data starter pack

This pack supplies curated NASA reference facts, a lunar dataset catalog, and your
three scenarios as JSON. The large source terrain/imagery rasters are NOT included.
Download them from the verified product pages below. No API key is needed for the
local JSON or the linked public pages.

## 1. Start with the right files

| File | Kind | Purpose |
|---|---|---|
| `data/nasa_reference.json` | Curated historical reference | Mission identity, site coordinates, abort-switch and radar incidents |
| `data/terrain_sources.json` | Catalog, not raster measurements | Which terrain, imagery and slope products to download |
| `data/sources.json` | Source links | URLs and attribution for each reference/product |
| `data/scenarios.json` | Your simulated game data | Choices, costs, effects and ending thresholds |
| `data/choice_costs.csv` | Your simulated game data | Same resource costs in a spreadsheet-readable table |
| `godot/LandingData.gd` | Starter loader/helper | Load the JSON and subtract a selected choice's costs |

NASA records support the general malfunction narrative. The resource costs,
backup sensor, placed rocks, choices and endings are educational game content;
they are not NASA telemetry or an operational landing procedure.

## 2. Use the historical facts for Scenarios 1 and 2

Read these NASA sources:

- [Apollo 14 mission summary](https://www.nasa.gov/wp-content/uploads/static/history/SP-4029/Apollo_14a_Summary.htm)
- [Reprogramming in Flight, Chapter 7.4](https://www.nasa.gov/wp-content/uploads/static/history/SP-350/ch-7-4.html)

The NASA summary reports Fra Mauro at 3.64530 degrees south, 17.47136 degrees west.
The equivalent east-positive longitude is 342.52864 degrees. These are reported
historical coordinates; modern cartographic landing positions may differ.

Use the reference JSON in a mission briefing or post-choice explanation. The
historical incidents were a faulty abort-switch signal and a landing-radar data
problem. Mission Control helped resolve both. The radar recovery involved cycling
its circuit breaker; your choice wording is a simplified interpretation.

Suggested attribution in your game: “Historical background: NASA Apollo 14 mission
records. Branching outcomes and resource costs are simulated.”

## 3. Download actual terrain for Scenario 3

Open the [LROC Apollo 14 terrain product group](https://data.lroc.im-ldi.com/lroc/view_rdr/NAC_DTM_APOLLO14).
Download the product README and labels as well as the data files. If a file link
redirects or fails, return to the product page and use its current download link.
The pages were available when checked; large raster transfers were not completed
in this environment.

| Download | File to choose | How to use it |
|---|---|---|
| [Elevation product](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO14) | `NAC_DTM_APOLLO14.TIF` — 32-bit GeoTIFF, catalog size about 118.54 MB | Numerical heights for terrain geometry |
| [Matching 2 m orthophoto](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO14_M150633128_2M) | `NAC_DTM_APOLLO14_M150633128_2M.TIF` — about 29.65 MB | Aligned surface imagery |
| [Slope visualization](https://data.lroc.im-ldi.com/lroc/view_rdr_product/NAC_DTM_APOLLO14_SLOPE) | `NAC_DTM_APOLLO14_SLOPE.TIF` and its slope legend | Visual comparison of steep and flatter ground |

The terrain product is sampled at 2 metres per pixel. A 2 m grid is not a reliable
catalog of individual small boulders. Add your scenario's rocks as separate game
objects and describe their placement as simulated. Colors in a slope map are not
raw numeric heights or slope angles.

Use [Moon Trek](https://trek.nasa.gov/moon/) to inspect the region. For the distant
Moon seen during approach, the [NASA CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/)
has whole-Moon color and displacement maps. Those global maps do not replace the
local DTM for landing-site detail.

## 4. Turn the terrain into a Godot asset

A practical offline workflow is **GIS crop -> Blender mesh -> GLB -> Godot**.

1. Open the DTM in a GIS application such as QGIS. Inspect its native lunar
   projection, pixel scale, NoData mask, scale/offset and elevation units using
   the accompanying label/README. Do not assign Earth WGS84 to lunar data.
2. Locate the Apollo 14 region using the product's lunar coordinate system.
   If converting the supplied geographic location, use the dataset's own lunar
   geographic/projected CRS definitions, not an Earth CRS.
3. Crop a fully valid patch around the chosen gameplay site. Start with roughly
   1 km square. Keep the crop bounds, projection, pixel size and valid elevation
   minimum/maximum. Crop/resample the orthophoto to the same bounds and grid.
4. Export a normalized floating-point height image: valid minimum -> 0,
   valid maximum -> 1. Fill/handle NoData first so it cannot create giant spikes.
   If GDAL is installed, the command pattern is:

   ```sh
   gdal_translate -of GTiff -ot Float32 -scale MIN MAX 0 1 cropped_dem.tif normalized_height.tif
   ```

   Replace `MIN` and `MAX` with your crop's valid numerical elevation range.
   If the source has nontrivial scale/offset, decode it before normalization.
5. In Blender create a plane with UVs, sized to the crop's physical width and
   height in metres. Apply object scale. Subdivide sufficiently for the desired
   terrain detail (start with about 256 segments per side for a small prototype).
6. Add a Displace modifier using `normalized_height.tif`, UV coordinates and
   non-color data. Use Midlevel 0 and Strength equal to the elevation range
   converted to metres. This puts the crop's minimum at local height zero.
   Record that vertical offset if comparing with source elevations.
7. If desired, apply the matching orthophoto through the same UVs. Satellite
   images already contain shadows; use them as reference or a prototype texture,
   rather than claiming they are shadow-free physical albedo. Check north/south
   orientation against landmarks to avoid a flipped texture.
8. Apply the displacement and export the mesh as `fra_mauro_terrain.glb`.
9. Import the GLB into Godot, instance it in a lunar scene, and generate static
   trimesh collision for the terrain mesh. Use 1 Godot unit = 1 metre. Spawn the
   astronaut above valid ground. Keep terrain separate from the ship interior.
10. Place simulated rocks and your clear landing zone on this terrain. Use game
    logic for collision clearance; do not infer that every visually flat patch
    is an operationally safe lunar landing site.

Technical references:
- [GDAL scale/output type options](https://gdal.org/en/stable/programs/gdal_translate.html)
- [Blender displacement settings](https://docs.blender.org/manual/en/5.0/modeling/modifiers/deform/displace.html)
- [Godot static collision import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/advanced_import_settings.html)

## 5. Load your game data in Godot

1. Copy this entire `lunar_landing_data` folder into the folder containing your
   game's `project.godot`. In Godot it should appear as `res://lunar_landing_data/`.
2. Add a Node named **LandingData** under your gameplay scene's root.
3. Attach `godot/LandingData.gd` from this pack to that Node. Run the scene;
   `_ready()` loads the local JSON and starting resources.
4. On a scenario choice, call `apply_choice()` once. Disable that choice UI after
   selection so double-clicking cannot charge twice. The helper intentionally
   does not enforce story order, create a UI, or mark a landing safe for you.

Example calls from a sibling controller, after LandingData is ready:

```gdscript
var landing_data = $LandingData
landing_data.apply_choice("landing_warning", "A")
landing_data.apply_choice("radar_problem", "B")
landing_data.apply_choice("final_landing", "C")
print(landing_data.fuel_percent)            # 70
print(landing_data.power_percent)           # 75
print(landing_data.time_remaining_minutes)  # 11
```

`apply_choice()` returns the chosen dictionary, including `outcome` and `effect`.
Use those to update your cockpit warnings, display messages and HUD. For example,
`radar_restored` can clear a radar warning and restore the height display. Your
controller decides when each scenario appears and when the mission ends.

A cost of 5 means subtract **5 percentage points**, not 5% of the remaining value.
The CSV stores positive costs; the script subtracts them. No real-time resource
consumption is added by this helper. Scenario 1 C sets `landing_aborted = true`
and blocks subsequent helper choices until `reset_resources()`.

## 6. Complete the ending rules in your gameplay controller

The pack preserves your thresholds: safe landing, fuel >= 70, power >= 75,
remaining time >= 7 minutes, and safe decisions for the secret ending.

Explicitly define `safe_landing`, `safe_decisions` and `unsafe_attempt` in your
gameplay logic. Do not treat adequate resources alone as a safe landing.
Scenario 1 B also continues after its delayed fix. Scenario 3 A only improves
visibility; it still needs a landing-site decision. Enabling lights should not
repeatedly charge the same cost.

With these one-time costs, the minimum possible remaining resources are 65% fuel,
70% power and 4 minutes (these minima occur on different paths). Depletion requires
additional ongoing consumption or changed costs. No such balancing changes were
silently added to your data.

All reference/source URLs were checked on 2026-11-15. The GDScript helper and the
A/B/C calculation were tested with Godot 4.6.3. Terrain conversion instructions
are a workflow guide; raw rasters and a generated terrain mesh are not included.
