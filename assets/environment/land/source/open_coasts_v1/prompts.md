# Open coasts v1 — built-in ImageGen prompts

All ten calls used `transparent_background=true`. Input 1 was the matching `*_layout.png` diagram; input 2 was the previous `land_scattered_islands_16x9_runtime.png`, used for style only. Generated source files and hashes are in manifest.json. The first diagram is retained as explicit coordinates in layout_reference.json.

## Scattered islands

Edit game map sprite. First image is AUTHORITATIVE composition mask: EXACTLY FOUR islands at those exact positions/shapes, 1920x1080 canvas aspect 16:9. Second image is existing art STYLE reference. Remove every island except four corner islands. Render only four provided silhouettes with matching illustrated top-down rocky green islands, low saturated olive grassy rocky plateaus, sandy shores, narrow foam edge. Preserve first image's exact outlines/positions/sizes; no extra tiny rocks or islands anywhere. All empty space including entire central area fully transparent. No water background, no text, no labels, no grid, no frame. Fill each island to its outer silhouette with land; tiny coastal foam allowed inside silhouette, no big turquoise halo. This is production game terrain artwork.

## Other nine maps

Production game terrain sprite {map_id}. Image 1 authoritative exact map silhouette, image 2 STYLE ONLY. Render exactly the green land shapes of image 1, at same coordinates, scale and orientation on same 16:9 transparent canvas. Fill silhouettes with low-saturation olive grassy rocky plateaus, tan sand coast, tiny foam edge, illustrated top down 2D mobile sea battle art matching image2. Preserve exact silhouette, bays and empty space. Do not rearrange, enlarge or recenter. No extra islands, no rocks outside silhouettes, no buildings, no labels/text/grid/frame. Entire water and background must be transparent; no ocean or turquoise ponds. Coast foam must be very narrow. Image1 polygon outlines are physics, precise adherence matters.

For broken_atoll, central_sandbar and crescent_bay the foam sentence was: “Coast foam must be very narrow and inside silhouette.”

Map IDs: broken_atoll, central_sandbar, crescent_bay, offset_large_island, long_archipelago, dual_channel_reef_line, ring_lagoon, harbor_mouth, double_island_long_channel.

## Review and export

Every image inspected individually, then together. Canvas registration normalizes size/position; original alpha is retained. Candidate shore outlines were reviewed on an overlay and one self-intersecting 1-pixel spur on long_archipelago was removed from authored geometry. The approved JSON, not bitmap alpha, is runtime authority. No automatic geometry extraction occurs during regular export or map rebuild.
