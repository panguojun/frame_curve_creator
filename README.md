
# 3D Frame Curve Board

<img width="1917" height="1078" alt="屏幕截图 2026-11-06 100135" src="https://github.com/user-attachments/assets/b44239bb-1181-49b4-804c-fd0ef6dbd373" />
A Godot 4 editor for spatial cubic Hermite curves. The Windows executable is `Frame3DCurveBoard.exe` in the project root. The scene is `scenes/main_3d.tscn`.

## Workspace

The left rail contains Add, Insert, Delete, Close, Template, Surface, Blender, Export, Open, Reset, and ZEN. The center contains FRONT, TOP, RIGHT and PERSPECTIVE views in a 2 by 2 grid. The right Properties panel edits the selected control frame's position and tangent as XYZ values.

| View | Horizontal axis | Vertical axis | Hidden coordinate |
| --- | --- | --- | --- |
| FRONT | X | Y | Z |
| TOP | X | Z | Y |
| RIGHT | Z | Y | X |
| PERSPECTIVE | Orbit camera | | |

Drag a point to move it; the view's hidden coordinate stays unchanged. Drag a blue handle to change its three dimensional tangent. The single editable curve is blue.

- **Left drag** a point or blue tangent handle; left drag in PERSPECTIVE to orbit.
- **Middle drag** to pan an orthographic view; **wheel** to zoom the hovered view.
- **A** add a frame; **F** then click the blue curve to insert; **Delete** remove a frame.
- **C** close/open the active curve; **R** reset the scene; **X** export; **O** open saved JSON.
- **T** opens Template; **S** toggles the surface without selecting a frame; **B** opens the scene in Blender.
- **F11** or the ZEN button enters full screen focus mode; **F11** or **Esc** exits.

## Templates

Click **Template** and choose Circle, Square, Triangle, Rectangle, or Regular polygon. Choose the FRONT/XY, TOP/XZ, or RIGHT/ZY plane. Set radius, width/height, or side count in the dialog. The shape replaces the current curve. After choosing a template, select Save to write the current editable scene as JSON, Don't Save to replace it immediately, or Cancel to keep the current curve. A failed or canceled save leaves the current curve unchanged. The new shape is a closed curve whose frames and tangents can be edited. Square, triangle, rectangle and polygon templates begin with zero tangents to keep their edges straight. Circle uses cubic Hermite tangent values for a close circular approximation.

## Triangulated surface from a closed 3D curve

Click **Surface** (or press **S**) at any time; no frame selection is needed. An open curve closes automatically before the surface is generated. The editor projects the sampled loop to a stable local plane, rejects degenerate or self intersecting projections, triangulates the interior while keeping the loop as the boundary, splits edges by spatial length, flips interior edges when triangle quality improves, relaxes interior vertices with orientation checks, and solves a smooth harmonic height field with fixed 3D boundary heights. The surface updates when control frames move. The Properties panel offers Detail (0–2) and Smooth (0–60) controls. Choosing another template clears the previous curve and its surface.

This is a boundary interpolating triangle mesh, not an exact rational NURBS surface. A nonplanar closed loop does not determine a unique surface; this tool chooses a deterministic height field over its projection. Curves whose chosen projection self intersects cannot be filled by this method. The construction follows the boundary validation and constrained triangulation principles used in AnalyticSurfaceStudio, adapted here to a spatial loop without a source UV patch.

## Blender and export

The **Blender** button looks for `C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe`. It writes the current scene to Godot's user data `blender_exports` folder and launches Blender with a Python import script. The scene curve becomes a native 3D Blender Curve with a POLY spline and no bevel. Enabled surfaces become Blender Mesh objects with triangle faces. The button opens a new Blender process; it does not change your existing Blender scene.

**Export** writes JSON with the editable frame positions and tangents, closure flag, sampled points, and generated surface vertices/triangles, or OBJ with 3D `v` and `l` records for the curve plus `f` records for the generated surface. Curve export uses 36 samples per Hermite span; surface boundaries use an adaptive rate capped near 512 points for interactive updates. Existing `frame_curve_3d_v1` JSON remains loadable. When an older file contains several layers, only its main curve is opened; old normal offset fields are ignored. Inserting a frame samples the curve position and derivative, but can slightly change adjacent spans because tangents are shared between spans.

The perspective view keeps its grid, axes, camera and curve nodes alive while editing. Only curve mesh data and marker positions are updated, avoiding the repeated node deletion that caused flashing during dragging.
