#!/usr/bin/env python3
"""Export the Cartrest STL meshes and label dimensions using the Python standard library."""

import argparse
import json
import math
import re
import struct
from collections import defaultdict
from pathlib import Path
from tempfile import TemporaryDirectory


ROOT = Path(__file__).resolve().parent
PROFILES = ROOT.parent / "consoles"
DIMENSION_DECIMALS = 4
CORNER_NAMES = ("topLeft", "topRight", "bottomRight", "bottomLeft")


def scaled_dimensions(nominal, factor):
    """Scale the measured geometry, preserving discrete fields and metadata."""
    def scale(value, name=None):
        if isinstance(value, dict):
            return {key: scale(item, key) for key, item in value.items()}
        if isinstance(value, list):
            return [scale(item, name) for item in value]
        if name in ("unit", "count") or (factor == 1 and name in ("depth", "thickness")):
            return value
        if factor == 1:
            return float(value)
        return round(value * factor, DIMENSION_DECIMALS)

    return scale(nominal)


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
        if not radius:
            points.append((corner_x, corner_y))
            continue
        center_x = corner_x + (-radius if index < 2 else radius)
        center_y = corner_y + (radius if index in (0, 3) else -radius)
        for step in range(13):
            angle = math.radians(-90 + 90 * index + step * 7.5)
            points.append((center_x + radius * math.cos(angle), center_y + radius * math.sin(angle)))
    snapped = []
    for px, py in points:
        point = (round(px, 7), round(py, 7))
        if not snapped or snapped[-1] != point:
            snapped.append(point)
    return snapped[:-1] if snapped and snapped[0] == snapped[-1] else snapped


def body_outline(body):
    vertices = body.get("vertices")
    if vertices is not None:
        return [(round(vertex["x"], 7), round(vertex["y"], 7)) for vertex in vertices]
    radii = tuple(body["cornerRadii"][name] for name in CORNER_NAMES)
    return footprint(0, 0, body["width"], body["height"], radii)


def x_bounds(outline, y):
    """Find both endpoints of a horizontal slice through a single span."""
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
        if outer_top is None or outer_bottom is None:
            raise ValueError("A cut extends beyond the cartridge outline.")
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
            if not (left_top <= inside_top[0] <= inside_top[1] <= outer_top[1]
                    and left_bottom <= inside_bottom[0] <= inside_bottom[1] <= outer_bottom[1]):
                raise ValueError("Cuts on the same face must stay inside the outline and avoid overlap.")
            regions.append(((left_top, inside_top[0]), (left_bottom, inside_bottom[0]), flat_z))
            regions.append((inside_top, inside_bottom, z))
            left_top, left_bottom = inside_top[1], inside_bottom[1]
        regions.append(((left_top, outer_top[1]), (left_bottom, outer_bottom[1]), flat_z))

        for (top_left, top_right), (bottom_left, bottom_right), z in regions:
            # A side relief can occupy the whole span up to the outer edge.
            if top_left == top_right and bottom_left == bottom_right:
                continue
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


def write_stl(path, triangles, header=b"Cartrest | millimeters | PLA | label face up"):
    """Validate the serialized coordinates and return a summary of the saved mesh."""

    def pack_point(point):
        # STL stores float32. Checking at that precision detects vertices that
        # are distinct in double precision but coincide after serialization.
        return struct.unpack("<3f", struct.pack("<3f", *point))

    payload = bytearray(header.ljust(80, b" ") + struct.pack("<I", len(triangles)))
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
                     (recess.get("radius", 0),) * 4, recess.get("chamfer", 0))


def contact_recesses(body, channels):
    """Open each channel all the way to the insertion edge in face coordinates."""
    top, edge = channels["y"], body["height"]
    for index in range(channels["count"]):
        left = round(channels["x"] + index * channels["pitch"], 7)
        right = round(channels["x"] + index * channels["pitch"] + channels["width"], 7)
        yield [(left, top), (right, top), (right, edge), (left, edge)], channels["depth"]


def contact_slot(body, slot):
    """Open the square end onto the insertion edge, leaving a rounded upper end."""
    return footprint(slot["x"], slot["y"], slot["width"], body["height"] - slot["y"],
                     (slot["radius"], slot["radius"], 0, 0)), slot["depth"]


def load_profile(path):
    def invalid_constant(value):
        raise ValueError(f"{value} is not a JSON number.")

    with path.open("rb") as file:
        data = file.read(256 * 1024 + 1)
    if len(data) > 256 * 1024:
        raise ValueError("Use a JSON profile smaller than 256 KiB.")
    profile = json.loads(data, parse_constant=invalid_constant)
    if type(profile["schemaVersion"]) is not int or profile["schemaVersion"] != 1:
        raise ValueError("Use schemaVersion 1.")
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", profile["id"]) or len(profile["id"]) > 64:
        raise ValueError("Use 1–64 lowercase letters, digits, or single hyphens for the ID.")
    width = profile["geometry"]["body"]["width"]
    limit = profile["widthRange"]
    if not 10 <= limit["min"] <= width <= limit["max"] <= 500:
        raise ValueError("The width range must be within 10–500 mm and include the nominal width.")
    if profile["geometry"]["unit"] != "mm":
        raise ValueError("Use millimeters for the profile geometry.")
    return profile


def interpret_recipe(profile):
    """Build front and rear cuts and derive the dimensions report from the recipe."""
    dimensions = dict(profile["geometry"])
    body = dimensions["body"]
    instructions = profile["instructions"]
    if not 2 <= len(instructions) <= 67 or instructions[0]["op"] != "extrudeBody":
        raise ValueError("Start with extrudeBody and use 2–67 instructions.")
    face = (body["width"], body["height"])
    thickness = body["thickness"]
    if not (0.01 <= face[1] <= 1000 and 0.01 <= thickness <= 100):
        raise ValueError("Use positive body dimensions within the profile limits.")

    front, rear = [], []
    channel_rows, slots, reliefs = [], [], []
    counts = {"recessLabel": 0, "engraveArrow": 0, "recessGrip": 0}
    for instruction in instructions[1:]:
        op = instruction["op"]
        settings = {key: value for key, value in instruction.items() if key != "op"}
        if op in counts:
            counts[op] += 1

        if op == "recessLabel":
            recess = dimensions["recess"]
            front.append((recess_outline(recess), recess["depth"]))
        elif op == "engraveArrow":
            arrow = dimensions["arrow"]
            center, top = arrow["centerX"], arrow["top"]
            half_width = arrow["width"] / 2
            triangle = [(center - half_width, top), (center + half_width, top), (center, top + arrow["height"])]
            front.append(([(round(x, 7), round(y, 7)) for x, y in triangle], arrow["depth"]))
        elif op == "recessGrip":
            grip = dimensions["grip"]
            front.append((recess_outline(grip), grip["depth"]))
        elif op == "rearChannels":
            count = settings["count"]
            if type(count) is not int or not 1 <= count <= 64 or count + len(rear) > 64:
                raise ValueError("Use at most 64 individual rear cuts.")
            if not (0 < settings["width"] < settings["pitch"] and 0 <= settings["y"] < face[1]):
                raise ValueError("Rear channels must be separated and open at the insertion edge.")
            rear.extend(contact_recesses(body, settings))
            channel_rows.append({**settings, "length": round(face[1] - settings["y"], DIMENSION_DECIMALS)})
        elif op == "rearSlot":
            if not (0 < settings["width"] and 0 <= settings["y"] < face[1]
                    and 0 <= settings["radius"] <= min(settings["width"] / 2, face[1] - settings["y"])):
                raise ValueError("The rear slot must fit between its upper end and the insertion edge.")
            rear.append(contact_slot(body, settings))
            slots.append(settings)
        elif op == "rearRecess":
            rear.append((recess_outline(settings), settings["depth"]))
            reliefs.append(settings)
        else:
            raise ValueError(f"Unknown instruction {op!r} after extrudeBody.")

    expected = {"recessLabel": 1, "engraveArrow": int("arrow" in dimensions), "recessGrip": int("grip" in dimensions)}
    if counts != expected:
        raise ValueError("Use recessLabel and a matching instruction for each optional front feature.")
    if len(rear) > 64:
        raise ValueError("Use at most 64 individual rear cuts.")
    for outline, depth in [*front, *rear]:
        if len(set(outline)) < 3 or not (0 < depth < thickness):
            raise ValueError("Each cut needs a distinct outline and a positive depth inside the body.")
    if max(depth for _, depth in front) + max((depth for _, depth in rear), default=0) >= thickness:
        raise ValueError("Leave solid material between the deepest front and rear cuts.")

    label = recess_outline(dimensions["label"])
    recess = recess_outline(dimensions["recess"])
    for y in {y for _, y in [*label, *recess]}:
        cut, boundary = x_bounds(label, y), x_bounds(recess, y)
        if cut and (not boundary or not boundary[0] <= cut[0] <= cut[1] <= boundary[1]):
            raise ValueError("The label outline must fit inside the recess, including its corners.")

    if len(channel_rows) == 1:
        row = channel_rows[0]
        dimensions["contactChannels"] = {field: row[field] for field in
                                          ("x", "y", "count", "width", "pitch", "length", "depth")}
    elif channel_rows:
        dimensions["contactChannelRows"] = channel_rows
    if slots:
        dimensions["contactSlots"] = slots
    if reliefs:
        dimensions["rearReliefs"] = reliefs
    return dimensions, front, rear


def holder_mesh(body, outline, width, slots, clearance):
    """Build the base, rails and beveled dividers as one printable solid."""
    scale = width / body["width"]
    coaster_height = body["height"] * scale
    guide_height = min(44, coaster_height * 0.34)
    cutoff = body["height"] - guide_height / scale
    # Include the cut through any edge crossing the top of the guide.
    lower_x = [x for x, y in outline if y >= cutoff]
    lower_x.extend(x_bounds(outline, cutoff) or ())
    contact_width = (max(lower_x) - min(lower_x)) * scale if lower_x else 0
    if contact_width <= 0:
        raise ValueError("The bottom of the coaster must have a measurable width.")

    wall, divider, base = 3.2, 4.0, 3.2
    slot_width = contact_width + 2 * clearance
    slot_depth = body["thickness"] * scale + 2 * clearance
    fin_reach = min(8, contact_width * 0.08)
    foot = max(10, coaster_height * 0.14)
    depth = 2 * foot + slots * (slot_depth + divider) + divider
    height = base + guide_height

    xs = [0, wall, wall + fin_reach, wall + slot_width - fin_reach,
          wall + slot_width, slot_width + 2 * wall]
    ys = [0, foot]
    for _ in range(slots):
        opening = ys[-1] + divider
        ys.extend((opening, opening + slot_depth))
    ys.extend((depth - foot, depth))

    # The last layer of cells bevels the entry by widening each opening.
    lead = min(0.8, guide_height / 4)
    zs = [0, base, height - min(1.6, guide_height / 2), height]
    top_xs, top_ys = xs.copy(), ys.copy()
    top_xs[1] -= lead
    top_xs[4] += lead
    for y in range(2, len(ys) - 2):
        top_ys[y] += lead if y % 2 else -lead

    columns, rows, layers = len(xs) - 1, len(ys) - 1, len(zs) - 1

    def vertex(x, y, z):
        if z == layers:
            return top_xs[x], top_ys[y], zs[z]
        return xs[x], ys[y], zs[z]

    def solid(x, y, z):
        if not (0 <= x < columns and 0 <= y < rows and 0 <= z < layers):
            return False
        if z == 0:
            return True
        return 0 < y < rows - 1 and (x in (0, columns - 1) or (y % 2 == 1 and x != 2))

    triangles = []

    def face(a, b, c, d):
        triangles.extend(((a, b, c), (a, c, d)))

    # Emit exposed faces on a shared grid so the base, rails and fins form one mesh.
    for z in range(layers):
        for y in range(rows):
            for x in range(columns):
                if not solid(x, y, z):
                    continue
                a = vertex(x, y, z)
                b = vertex(x + 1, y, z)
                c = vertex(x + 1, y + 1, z)
                d = vertex(x, y + 1, z)
                e = vertex(x, y, z + 1)
                f = vertex(x + 1, y, z + 1)
                g = vertex(x + 1, y + 1, z + 1)
                h = vertex(x, y + 1, z + 1)
                if not solid(x, y, z - 1):
                    face(d, c, b, a)
                if not solid(x, y, z + 1):
                    face(e, f, g, h)
                if not solid(x - 1, y, z):
                    face(a, e, h, d)
                if not solid(x + 1, y, z):
                    face(b, c, g, f)
                if not solid(x, y - 1, z):
                    face(a, b, f, e)
                if not solid(x, y + 1, z):
                    face(d, h, g, c)
    return triangles


def generate(output, width, profile, *, holder_slots=None, holder_clearance=0.5):
    nominal, front, rear = interpret_recipe(profile)
    body, recess = nominal["body"], nominal["recess"]
    outer = body_outline(body)
    if len(set(outer)) != len(outer) or len(outer) < 3:
        raise ValueError("The body outline must use distinct vertices.")
    if any(min(p[i] for p in outer) != 0 or max(p[i] for p in outer) != round(body[axis], 7)
           for i, axis in enumerate(("width", "height"))):
        raise ValueError("The body outline must reach the four declared bounds.")

    if holder_slots is not None:
        triangles = holder_mesh(body, outer, width, holder_slots, holder_clearance)
        filename = f"cartrest-{profile['id']}-holder-{holder_slots}slots-{width_suffix(width)}mm.stl"
        output.mkdir(parents=True, exist_ok=True)
        with TemporaryDirectory(prefix=".cartrest-holder-", dir=output) as staging_dir:
            staged = Path(staging_dir) / filename
            summary = write_stl(staged, triangles, header=b"Cartrest | millimeters | holder base down")
            staged.replace(output / filename)
        print(summary)
        return

    coaster = build_mesh(outer, body["thickness"], front, rear)

    # The coupon preserves the recess depth and corners, even for a larger custom chamfer.
    min_side = max(2 * recess["radius"], recess["chamfer"] + recess["radius"])
    cut_width = min(recess["width"], max(26, min_side))
    cut_height = min(recess["height"], max(20, min_side))
    fit_test_outer = footprint(0, 0, cut_width + 10, cut_height + 8, (2,) * 4)
    fit_test_recess = {**recess, "x": 5, "y": 4, "width": cut_width, "height": cut_height}
    fit_test = build_mesh(fit_test_outer, body["thickness"], [(recess_outline(fit_test_recess), recess["depth"])])

    factor = width / body["width"]
    dimensions = scaled_dimensions(nominal, factor)

    def scale_mesh(mesh):
        if factor == 1:
            return mesh
        return [tuple(tuple(axis * factor for axis in vertex) for vertex in triangle) for triangle in mesh]

    stls = ((f"cartrest-{profile['id']}-{width_suffix(width)}mm.stl", scale_mesh(coaster)),
            ("cartrest-fit-test.stl", scale_mesh(fit_test)))

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
    profiles = {path.stem: path for path in sorted(PROFILES.glob("*.json")) if path.name != "profile.schema.json"}
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group()
    source.add_argument("--console", choices=profiles, default="ds", help="bundled profile ID (default: ds)")
    source.add_argument("--profile", type=Path, help="path to a community profile JSON")
    parser.add_argument("--width", type=float, help="final width in millimeters (defaults to the profile's nominal width)")
    parser.add_argument("--output", type=Path, help="directory for the generated files")
    parser.add_argument("--holder-slots", type=int, metavar="N",
                        help="generate only a holder with 1–24 slots (default output: dist/holders)")
    parser.add_argument("--holder-clearance", type=float, metavar="MM",
                        help="clearance per side for the holder, from 0.2 to 1.5 mm (default: 0.5)")
    options = parser.parse_args()
    defaults = {name: ROOT if name == "ds" else ROOT / name for name in profiles}

    try:
        profile = load_profile(options.profile or profiles[options.console])
        nominal_width = profile["geometry"]["body"]["width"]
        width = nominal_width if options.width is None else round(options.width, DIMENSION_DECIMALS)
        limits = profile["widthRange"]
        if not limits["min"] <= width <= limits["max"]:
            raise ValueError(f"Width must be between {limits['min']} and {limits['max']} mm.")
        if options.profile and not options.output:
            raise ValueError("Choose an --output directory for a community profile.")
        clearance = 0.5 if options.holder_clearance is None else options.holder_clearance
        if options.holder_slots is not None:
            if not 1 <= options.holder_slots <= 24:
                raise ValueError("Choose between 1 and 24 holder slots.")
            if not 0.2 <= clearance <= 1.5:
                raise ValueError("Choose a clearance from 0.2 to 1.5 mm per side.")
            generate((options.output or ROOT.parent / "dist" / "holders").resolve(), width, profile,
                     holder_slots=options.holder_slots, holder_clearance=clearance)
            return
        if options.holder_clearance is not None:
            raise ValueError("Use --holder-clearance with --holder-slots.")

        default_directory = defaults[options.console]
        output = options.output or (default_directory if width == nominal_width
                                    else default_directory / f"{width_suffix(width)}mm")
        destination = output.resolve()
        if destination in defaults.values() and (options.profile or destination != default_directory or width != nominal_width):
            raise ValueError("Choose a separate directory to preserve the default model files.")
        generate(destination, width, profile)
    except (KeyError, ValueError, TypeError, OSError, OverflowError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
