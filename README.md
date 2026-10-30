# 2D Frame Curve Board

A small Godot 4 editor for a 2D cubic Hermite curve controlled by coordinate frames. The blue curve is an editing guide; the green polyline is the generated profile. The current executable is [build/Frame2DCurveBoard_AnalyticFit.exe](build/Frame2DCurveBoard_AnalyticFit.exe).
<img width="1581" height="988" alt="屏幕截图 2026-10-30 140740" src="https://github.com/user-attachments/assets/061b6f03-6ee6-4177-8a7f-a346ce921a9f" />

## Edit

| Action | Control |
| --- | --- |
| Move frame | Drag its center |
| Change tangent direction and scale | Drag the blue handle; its distance from the frame sets `t` |
| Change direction without changing scale | Right drag near a frame or use Q/E |
| Change normal scale `n` | Drag the green handle; it can reach 0 |
| Set selected normal scale to 0 or restore it to 1 | N |
| Change base offset radius `r` | Alt + drag the green handle |
| Insert a frame on the blue or green curve | Click **Frame**, then click the curve; F or double click also works |
| Add a frame at the end | A |
| Delete selected frame | Delete (at least two remain) |
| Move selected frame precisely | Arrow keys; hold Shift for a larger step |
| Toggle open or closed curve | **Open/Closed** toolbar button or C |
| Pan / zoom | Middle drag / mouse wheel |
| Toggle green offsets / red control polygon | O / P |
| Reset example | R |
| Open export dialog | **Export...** or X |
| Open the current curve directly in Blender | **Blender** toolbar button |
| Fit an analytic curve to the current profile | **Fit** toolbar button |

The frame label shows `t` (tangent scale), `n` (normal scale), `r` (base offset radius), and `w` (reserved weight). Tangent scale changes the Hermite derivative magnitude and therefore the curve shape. The offset width at each frame is `n × r`; it is interpolated along each span. **The default is `n = 0` at every frame**, producing one green profile polyline at the blue guide's position. Drag a green handle outward to create two boundary polylines. The blue centerline is only an editing guide and is never exported. At `n = 0`, the green control stays slightly away from the center point so it remains draggable. Weight is currently metadata; the curve evaluator remains cubic Hermite.

Inserting a frame splits its cubic span at the selected parameter. Its initial position, tangent and radius follow the current curve, and the centerline stays exactly the same until you edit it. Clicking a green offset creates the frame at the corresponding centerline point.

Closing adds a smooth Hermite span from the last frame back to the first. Drag the endpoint tangents and their lengths to shape the closing span. The exported closed curves repeat their starting point.

## Analytic curve fitting

Click **Fit** to identify the closest line, circle, or ellipse for the current green production polyline. If normal scaling creates two boundaries, choose which boundary to fit. The dialog lists available models by fit score and shows each model's root mean square (RMS) geometric error in editor units. A small complexity penalty favors a simpler model when errors are close; the listed RMS remains the actual geometric error. You can choose a different model before applying it.

Confirming the fit projects the key frames onto the selected analytic curve, aligns their tangent directions, and adjusts tangent lengths from the spacing between neighboring frames. When fitting a boundary, the frame centers are offset so that the chosen boundary passes through the projected points. The Hermite curve remains editable: drag frames and tangent handles as before to refine the shape. This is a starting approximation; the sampled Hermite spans do not become exact analytic geometry.

## Export

Click **Export...**, choose a format in the file dialog, then choose a destination and filename:

| Format | Contents | Use |
| --- | --- | --- |
| SVG | Standard `<path>` elements for the production boundaries | In Blender: File → Import → Scalable Vector Graphics (.svg); creates curve objects |
| OBJ | Standard Wavefront vertices and `l` line elements for the boundaries | In Blender: File → Import → Wavefront (.obj); creates mesh edges |
| CSV | Production polyline names and sample coordinates | Numerical analysis and other CAD tools |
| JSON | Production polyline names, sample coordinates and closure flag | Inspect or transfer the generated profile |
| PNG | Clean raster rendering of the production polylines | Preview or illustration |

All formats export two production polylines when the normal offset has nonzero width, or one merged production polyline when every normal scale is zero. The blue centerline is not present in any exported file. The **O** key changes editor visibility only; it does not change exported geometry. SVG and OBJ use sampled polylines, so they preserve the displayed geometry to the current sampling resolution rather than exporting native Hermite control data. SVG uses screen-style Y downward. OBJ flips Y so its coordinates follow the usual 3D Y-up convention. All exported coordinates use editor units; choose the scale you need after import.
