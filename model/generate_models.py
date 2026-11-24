#!/usr/bin/env python3
"""Export the Cartrest STL meshes and label dimensions using the Python standard library."""

import argparse
import json
import math
import struct
from collections import defaultdict
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parent
BASE_WIDTH = 100
MIN_WIDTH = 60
MAX_WIDTH = 180
DIMENSION_DECIMALS = 4
CORNER_NAMES = ("topLeft", "topRight", "bottomRight", "bottomLeft")

# Face dimensions in millimeters, with X increasing rightward and Y downward.
# Both the meshes and the editor's JSON resource use this set of dimensions.
DIMENSIONS = {
    "unit": "mm",
    "body": {
        "width": BASE_WIDTH,
        "height": 106.06,
        "thickness": 6,
        "cornerRadii": dict(zip(CORNER_NAMES, (3, 3, 2, 9))),
    },
    "recess": {
        "x": 8.7, "y": 6.2, "width": 82.6, "height": 87.2,
        # The chamfer has the same 0.4 mm perpendicular clearance as the straight edges.
        # Accounting for the setback on both axes gives 7.5 + 0.4 × (2 − √2) = 7.7343 mm.
        "radius": 3.9, "chamfer": 7.7343, "depth": 0.6,
    },
    "label": {
        "x": 9.1, "y": 6.6, "width": 81.8, "height": 86.4,
        "radius": 3.5, "chamfer": 7.5,
    },
    "arrow": {"centerX": 50, "top": 97.6, "width": 10, "height": 4, "depth": 0.4},
    # Raised ribs separate the rear contact channels. Their mouths meet the
    # insertion edge, while the rest of the rear face stays on the build plate.
    "contactChannels": {
        "x": 16.5, "y": 93.56, "count": 17, "width": 3, "pitch": 4,
        "length": 12.5, "depth": 0.9,
    },
}


def scaled_dimensions(width):
    """Scale the face in XY while keeping the thickness and recess depths in Z."""
    factor = width / BASE_WIDTH

    def scale_value(name, value):
        if name in ("unit", "thickness", "depth", "count"):
            return value
        return round(value * factor, DIMENSION_DECIMALS)

    def scale_xy(values):
        return {
            name: scale_xy(value) if isinstance(value, dict) else scale_value(name, value)
            for name, value in values.items()
        }

    return scale_xy(DIMENSIONS)


def width_suffix(width):
    """Use the precision of the JSON dimensions to name the files."""
    return f"{width:.{DIMENSION_DECIMALS}f}".rstrip("0").rstrip(".")


def footprint(x, y, width, height, radii, lower_left_chamfer=0):
    """Approximate the clockwise convex outline with 12 segments per rounded corner.

    Corner radii are ordered clockwise from the top left. When a chamfer is set,
    its two endpoints replace the bottom-left arc.
    """
    points = []
    corners = ((x + width, y), (x + width, y + height), (x, y + height), (x, y))
    for index, (corner_x, corner_y) in enumerate(corners):
        if index == 2 and lower_left_chamfer:
            points.extend(((x + lower_left_chamfer, y + height), (x, y + height - lower_left_chamfer)))
            continue
        radius = radii[(index + 1) % 4]
        center_x = corner_x + (-radius if index < 2 else radius)
        center_y = corner_y + (radius if index in (0, 3) else -radius)
        for step in range(13):
            angle = math.radians(-90 + 90 * index + step * 7.5)
            points.append((center_x + radius * math.cos(angle), center_y + radius * math.sin(angle)))
    return [(round(px, 7), round(py, 7)) for px, py in points]


def x_bounds(outline, y):
    """Find both horizontal endpoints of a scanline through the convex outline."""
    hits = []
    for (ax, ay), (bx, by) in zip(outline, outline[1:] + outline[:1]):
        if not min(ay, by) <= y <= max(ay, by):
            continue
        if ay == by:
            # The scanline can coincide with an entire edge.
            hits.extend((ax, bx))
        else:
            hits.append(round(ax + (y - ay) * (bx - ax) / (by - ay), 7))
    return (min(hits), max(hits)) if hits else None


def scanlines(outer, recesses):
    """Collect split points shared by both faces of the solid."""
    outlines = [outer, *(outline for outline, _ in recesses)]
    rows = sorted({y for outline in outlines for _, y in outline})
    row_marks = {}
    for y in rows:
        bounds = (x_bounds(outline, y) for outline in outlines)
        row_marks[y] = sorted({x for limit in bounds if limit for x in limit})
    return rows, row_marks


def planar_cells(outer, flat_z, recesses, seams):
    """Partition a face into planar cells, with disjoint recesses in each band.

    Between consecutive Y levels, the outlines follow straight lines. Both
    neighboring bands include every split point along their shared edge, so
    their edges match at height changes and at the start or end of a recess.
    """
    rows, row_marks = seams
    for top, bottom in zip(rows, rows[1:]):
        outer_top, outer_bottom = x_bounds(outer, top), x_bounds(outer, bottom)
        middle = (top + bottom) / 2
        active = []
        for outline, z in recesses:
            bounds = x_bounds(outline, middle)
            if bounds is not None:
                active.append((bounds[0], outline, z))
        active.sort(key=lambda item: item[0])

        regions = []
        left_top, left_bottom = outer_top[0], outer_bottom[0]
        for _, outline, z in active:
            inside_top, inside_bottom = x_bounds(outline, top), x_bounds(outline, bottom)
            regions.append(((left_top, inside_top[0]), (left_bottom, inside_bottom[0]), flat_z))
            regions.append((inside_top, inside_bottom, z))
            left_top, left_bottom = inside_top[1], inside_bottom[1]
        regions.append(((left_top, outer_top[1]), (left_bottom, outer_bottom[1]), flat_z))

        for (top_left, top_right), (bottom_left, bottom_right), z in regions:
            top_edge = [(x, top) for x in row_marks[top] if top_left <= x <= top_right]
            bottom_edge = [(x, bottom) for x in reversed(row_marks[bottom]) if bottom_left <= x <= bottom_right]
            yield list(reversed(top_edge + bottom_edge)), z


def triangulate_face(cells, y_max, triangles, *, underside=False, mirror_flat_base=False):
    """Write planar faces and return their incident edges for the wall pass."""
    planar_edges = defaultdict(list)
    for cell, z in cells:
        # Flip the top-left editor coordinates to the STL view, where Y increases upward.
        polygon = [(x, round(y_max - y, 7)) for x, y in cell]
        center = tuple(sum(point[i] for point in polygon) / len(polygon) for i in range(2))
        # The fan preserves every boundary segment, including collinear edges
        # shared with the neighboring cell.
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            planar_edges[tuple(sorted((a, b)))].append((a, b, z))
            first, second = (b, a) if underside else (a, b)
            triangles.append(((*center, z), (*first, z), (*second, z)))
            if mirror_flat_base:
                triangles.append(((*center, 0), (*b, 0), (*a, 0)))
    return planar_edges


def collect_walls(front_edges, rear_edges):
    """Match both outlines and add walls along every change of surface height."""
    rear_boundary = {edge: sides[0][2] for edge, sides in rear_edges.items() if len(sides) == 1}
    walls = []
    for edge, sides in front_edges.items():
        if len(sides) > 2:
            raise ValueError("Overlapping planar bands.")
        highest, *neighbors = sorted(sides, key=lambda side: side[2], reverse=True)
        a, b, top = highest
        # At the perimeter, connect to the matching rear edge. Inside the face,
        # connect to the next lower cell at a front recess.
        if neighbors:
            bottom = neighbors[0][2]
        elif rear_edges:
            bottom = rear_boundary.pop(edge, None)
            if bottom is None:
                raise ValueError("Front and rear outlines do not match.")
        else:
            bottom = 0
        if top != bottom:
            walls.append((a, b, bottom, top))
    if rear_boundary:
        raise ValueError("Front and rear outlines do not match.")

    for sides in rear_edges.values():
        if len(sides) > 2:
            raise ValueError("Overlapping planar bands.")
        if len(sides) == 2:
            (a, b, bottom), (_, _, top) = sorted(sides, key=lambda side: side[2])
            if top != bottom:
                walls.append((a, b, bottom, top))
    return walls


def triangulate_walls(walls, triangles):
    """Keep vertical edges aligned where a contact channel opens onto the rim."""
    levels = defaultdict(set)
    for a, b, bottom, top in walls:
        levels[a].update((bottom, top))
        levels[b].update((bottom, top))

    for a, b, bottom, top in walls:
        a_splits = [(*a, z) for z in sorted(levels[a], reverse=True) if bottom < z < top]
        b_splits = [(*b, z) for z in sorted(levels[b]) if bottom < z < top]
        if not a_splits and not b_splits:
            triangles.extend((((*a, bottom), (*b, bottom), (*b, top)), ((*a, bottom), (*b, top), (*a, top))))
            continue

        # A mouth adds a height change at only one end of a wall. The fan
        # includes the resulting split vertex so no edge meets a T-junction.
        polygon = [(*a, bottom), (*b, bottom), *b_splits, (*b, top), (*a, top), *a_splits]
        center = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (top + bottom) / 2)
        triangles.extend((center, first, second) for first, second in zip(polygon, polygon[1:] + polygon[:1]))


def build_mesh(outer, height, recesses, rear_recesses=()):
    """Triangulate both faces and join them into one closed solid."""
    front = [(outline, height - depth) for outline, depth in recesses]
    seams = scanlines(outer, [*front, *rear_recesses])
    y_max = max(y for _, y in outer)
    triangles = []
    front_cells = planar_cells(outer, height, front, seams)
    front_edges = triangulate_face(front_cells, y_max, triangles, mirror_flat_base=not rear_recesses)
    rear_edges = {}
    if rear_recesses:
        rear_cells = planar_cells(outer, 0, rear_recesses, seams)
        rear_edges = triangulate_face(rear_cells, y_max, triangles, underside=True)
    triangulate_walls(collect_walls(front_edges, rear_edges), triangles)
    return triangles


def write_stl(path, triangles):
    """Validate the serialized coordinates and return a summary of the saved mesh."""

    def pack_point(point):
        # STL stores float32. Checking at that precision detects vertices that
        # are distinct in double precision but coincide after serialization.
        return struct.unpack("<3f", struct.pack("<3f", *point))

    header = b"Cartrest | millimeters | PLA | label face up".ljust(80, b" ")
    payload = bytearray(header + struct.pack("<I", len(triangles)))
    edges = defaultdict(list)
    volume = 0
    vertices = set()
    for triangle_index, triangle in enumerate(triangles):
        a, b, c = map(pack_point, triangle)
        vertices.update((a, b, c))
        ab, ac = (tuple(value - a[i] for i, value in enumerate(p)) for p in (b, c))
        normal = tuple(ab[j] * ac[k] - ab[k] * ac[j] for j, k in ((1, 2), (2, 0), (0, 1)))
        length = math.hypot(*normal)
        if length == 0:
            raise ValueError("Degenerate triangle in the STL.")
        payload.extend(struct.pack("<12fH", *(value / length for value in normal), *a, *b, *c, 0))
        # Sum the signed volumes of the tetrahedra formed with the origin.
        volume += sum(ai * ni for ai, ni in zip(a, normal)) / 6
        for u, v in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted((u, v)))].append((triangle_index, u < v))

    # Each edge needs exactly two incident faces with opposite orientations.
    neighbors = defaultdict(list)
    for incidents in edges.values():
        if len(incidents) != 2 or incidents[0][1] == incidents[1][1]:
            raise ValueError("Open mesh or inconsistent winding.")
        (left, _), (right, _) = incidents
        neighbors[left].append(right)
        neighbors[right].append(left)

    # Walking the face adjacency graph checks that the mesh forms a single solid.
    pending, visited = [0], {0}
    while pending:
        for index in neighbors[pending.pop()]:
            if index not in visited:
                visited.add(index)
                pending.append(index)
    if len(visited) != len(triangles) or volume <= 0:
        raise ValueError("The mesh must form one solid with outward-facing triangles.")

    path.write_bytes(payload)
    bounds = [max(p[i] for p in vertices) - min(p[i] for p in vertices) for i in range(3)]
    size = " × ".join(f"{axis:.2f}" for axis in bounds)
    return f"{path.name} · {size} mm · {len(triangles)} triangles · volume {volume / 1000:.2f} cm³"


def recess_outline(recess):
    return footprint(recess["x"], recess["y"], recess["width"], recess["height"],
                     (recess["radius"],) * 4, recess["chamfer"])


def contact_recesses(body, channels):
    """Open each channel all the way to the insertion edge in face coordinates."""
    top, edge = channels["y"], body["height"]
    for index in range(channels["count"]):
        left = round(channels["x"] + index * channels["pitch"], DIMENSION_DECIMALS)
        right = round(left + channels["width"], DIMENSION_DECIMALS)
        yield [(left, top), (right, top), (right, edge), (left, edge)], channels["depth"]


def generate(output, width):
    width = round(width, DIMENSION_DECIMALS)
    dimensions = scaled_dimensions(width)
    body, recess, arrow = (dimensions[name] for name in ("body", "recess", "arrow"))
    radii = tuple(body["cornerRadii"][name] for name in CORNER_NAMES)
    outer = footprint(0, 0, body["width"], body["height"], radii)
    center, top = arrow["centerX"], arrow["top"]
    half_width = arrow["width"] / 2
    triangle = [(center - half_width, top), (center + half_width, top), (center, top + arrow["height"])]
    recesses = [(recess_outline(recess), recess["depth"]), (triangle, arrow["depth"])]
    contacts = list(contact_recesses(body, dimensions["contactChannels"]))
    coaster = build_mesh(outer, body["thickness"], recesses, contacts)

    # The fit test reproduces the recess profile, depth, and chamfer on a smaller piece.
    factor = width / BASE_WIDTH
    fit_test_outer = footprint(0, 0, 36 * factor, 28 * factor, (2 * factor,) * 4)
    fit_test_recess = {**recess, "x": 5 * factor, "y": 4 * factor,
                     "width": 26 * factor, "height": 20 * factor}
    fit_test = build_mesh(fit_test_outer, body["thickness"], [(recess_outline(fit_test_recess), recess["depth"])])
    stls = ((f"cartrest-ds-{width_suffix(width)}mm.stl", coaster),
            ("cartrest-fit-test.stl", fit_test))

    # Validate both solids and prepare the JSON before replacing any output.
    # Staging on the same volume allows each file to be replaced atomically.
    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=".cartrest-model-", dir=output) as staging_dir:
        staging = Path(staging_dir)
        summaries = [write_stl(staging / name, mesh) for name, mesh in stls]
        data = json.dumps(dimensions, ensure_ascii=False, indent=2)
        (staging / "dimensions.json").write_bytes((data + "\n").encode("utf-8"))
        for name, _ in stls:
            (staging / name).replace(output / name)
        (staging / "dimensions.json").replace(output / "dimensions.json")

    for summary in summaries:
        print(summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--width", type=float, default=BASE_WIDTH,
                        help=f"final width in mm, between {MIN_WIDTH} and {MAX_WIDTH}")
    parser.add_argument("--output", type=Path, help="directory for the STL meshes and cutting dimensions")
    options = parser.parse_args()
    if not MIN_WIDTH <= options.width <= MAX_WIDTH:
        parser.error(f"width must be between {MIN_WIDTH} and {MAX_WIDTH} mm")
    default_output = ROOT if options.width == BASE_WIDTH else ROOT / f"{width_suffix(options.width)}mm"
    output = options.output or default_output
    if options.width != BASE_WIDTH and output.resolve() == ROOT:
        parser.error(f"choose a different directory to preserve the default {BASE_WIDTH} mm dimensions")
    generate(output, options.width)


if __name__ == "__main__":
    main()
