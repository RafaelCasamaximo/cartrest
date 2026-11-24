#!/usr/bin/env python3
"""Exporta as malhas STL e as medidas de corte do Cartrest sem dependências."""

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
CORNER_NAMES = ("superiorEsquerdo", "superiorDireito", "inferiorDireito", "inferiorEsquerdo")

# Cotas em milímetros da face vista de cima, com X para a direita e Y para baixo.
# O mesmo conjunto alimenta a malha e o JSON que o editor carrega.
DIMENSIONS = {
    "unidade": "mm",
    "corpo": {
        "largura": BASE_WIDTH,
        "altura": 106.06,
        "espessura": 6,
        "raios": dict(zip(CORNER_NAMES, (3, 3, 2, 9))),
    },
    "rebaixo": {
        "x": 8.7, "y": 6.2, "largura": 82.6, "altura": 87.2,
        # A diagonal recebe 0,4 mm na sua normal, tal como as bordas retas.
        # Os dois recuos de coordenada dão 7,5 + 0,4 × (2 − √2) = 7,7343 mm.
        "raio": 3.9, "chanfro": 7.7343, "profundidade": 0.6,
    },
    "adesivo": {
        "x": 9.1, "y": 6.6, "largura": 81.8, "altura": 86.4,
        "raio": 3.5, "chanfro": 7.5,
    },
    "seta": {"centroX": 50, "topo": 97.6, "largura": 10, "altura": 4, "profundidade": 0.4},
}


def scaled_dimensions(width):
    """Redimensiona a face em XY e preserva espessura e profundidades em Z."""
    factor = width / BASE_WIDTH

    def scale_value(name, value):
        if name in ("unidade", "espessura", "profundidade"):
            return value
        return round(value * factor, DIMENSION_DECIMALS)

    def scale_xy(values):
        return {
            name: scale_xy(value) if isinstance(value, dict) else scale_value(name, value)
            for name, value in values.items()
        }

    return scale_xy(DIMENSIONS)


def width_suffix(width):
    """Usa as mesmas casas decimais do JSON para identificar a largura no disco."""
    return f"{width:.{DIMENSION_DECIMALS}f}".rstrip("0").rstrip(".")


def footprint(x, y, width, height, radii, lower_left_chamfer=0):
    """Aproxima o contorno convexo horário com 12 segmentos por canto curvo.

    A ordem dos raios começa no canto superior esquerdo. Quando há chanfro,
    os dois pontos da diagonal substituem o arco do canto inferior esquerdo.
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
    """Retorna os dois extremos horizontais de um corte na forma convexa."""
    hits = []
    for (ax, ay), (bx, by) in zip(outline, outline[1:] + outline[:1]):
        if not min(ay, by) <= y <= max(ay, by):
            continue
        if ay == by:
            # A reta de corte pode coincidir com a aresta inteira.
            hits.extend((ax, bx))
        else:
            hits.append(round(ax + (y - ay) * (bx - ax) / (by - ay), 7))
    return (min(hits), max(hits)) if hits else None


def planar_cells(outer, height, recesses):
    """Particiona a face em células planas, com um rebaixo possível por faixa.

    Entre dois níveis consecutivos de Y, as bordas seguem retas. Todo ponto de
    divisão de uma linha entra nas duas faixas vizinhas, mantendo as arestas
    coincidentes quando a altura muda ou quando começa ou termina um rebaixo.
    """
    outlines = [outer, *(outline for outline, _ in recesses)]
    rows = sorted({y for outline in outlines for _, y in outline})
    row_marks = {}
    for y in rows:
        bounds = (x_bounds(outline, y) for outline in outlines)
        row_marks[y] = sorted({x for limit in bounds if limit for x in limit})

    for top, bottom in zip(rows, rows[1:]):
        outer_top, outer_bottom = x_bounds(outer, top), x_bounds(outer, bottom)
        middle = (top + bottom) / 2
        active = next(((outline, depth) for outline, depth in recesses if x_bounds(outline, middle)), None)
        regions = [(outer_top, outer_bottom, height)]
        if active:
            outline, depth = active
            inside_top, inside_bottom = x_bounds(outline, top), x_bounds(outline, bottom)
            regions = [
                ((outer_top[0], inside_top[0]), (outer_bottom[0], inside_bottom[0]), height),
                (inside_top, inside_bottom, height - depth),
                ((inside_top[1], outer_top[1]), (inside_bottom[1], outer_bottom[1]), height),
            ]
        for (top_left, top_right), (bottom_left, bottom_right), z in regions:
            top_edge = [(x, top) for x in row_marks[top] if top_left <= x <= top_right]
            bottom_edge = [(x, bottom) for x in reversed(row_marks[bottom]) if bottom_left <= x <= bottom_right]
            yield list(reversed(top_edge + bottom_edge)), z


def build_mesh(outer, height, recesses):
    """Cria as faces superior e inferior e fecha cada desnível com duas facetas."""
    y_max = max(y for _, y in outer)
    planar_edges = defaultdict(list)
    triangles = []
    for cell, z in planar_cells(outer, height, recesses):
        # O STL usa Y crescente para cima. A origem do editor fica no canto superior esquerdo.
        polygon = [(x, round(y_max - y, 7)) for x, y in cell]
        center = tuple(sum(point[i] for point in polygon) / len(polygon) for i in range(2))
        # O leque preserva todos os segmentos da borda, inclusive os colineares
        # compartilhados com a célula vizinha.
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            planar_edges[tuple(sorted((a, b)))].append((a, b, z))
            triangles.extend((((*center, z), (*a, z), (*b, z)), ((*center, 0), (*b, 0), (*a, 0))))

    for sides in planar_edges.values():
        if len(sides) > 2:
            raise ValueError("Faixas planas sobrepostas.")
        highest, *neighbors = sorted(sides, key=lambda side: side[2], reverse=True)
        a, b, top = highest
        # Uma borda externa desce até a base. Em um rebaixo, a parede termina
        # no nível inferior compartilhado pelas duas células.
        bottom = neighbors[0][2] if neighbors else 0
        if top == bottom:
            continue
        triangles.extend((((*a, bottom), (*b, bottom), (*b, top)), ((*a, bottom), (*b, top), (*a, top))))
    return triangles


def write_stl(path, triangles):
    """Valida as coordenadas serializadas e retorna o resumo da malha gravada."""

    def pack_point(point):
        # O STL grava float32. Validar nessa precisão detecta a fusão de
        # vértices que ainda eram distintos nos cálculos em dupla precisão.
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
            raise ValueError("Triângulo degenerado no STL.")
        payload.extend(struct.pack("<12fH", *(value / length for value in normal), *a, *b, *c, 0))
        # Soma dos volumes assinados dos tetraedros formados com a origem.
        volume += sum(ai * ni for ai, ni in zip(a, normal)) / 6
        for u, v in ((a, b), (b, c), (c, a)):
            edges[tuple(sorted((u, v)))].append((triangle_index, u < v))

    # Cada aresta precisa ter exatamente duas faces com sentidos opostos.
    neighbors = defaultdict(list)
    for incidents in edges.values():
        if len(incidents) != 2 or incidents[0][1] == incidents[1][1]:
            raise ValueError("Malha aberta ou orientação incoerente.")
        (left, _), (right, _) = incidents
        neighbors[left].append(right)
        neighbors[right].append(left)

    # Percorrer os vizinhos verifica se todas as faces pertencem ao mesmo sólido.
    pending, visited = [0], {0}
    while pending:
        for index in neighbors[pending.pop()]:
            if index not in visited:
                visited.add(index)
                pending.append(index)
    if len(visited) != len(triangles) or volume <= 0:
        raise ValueError("A malha precisa formar um sólido único orientado para fora.")

    path.write_bytes(payload)
    bounds = [max(p[i] for p in vertices) - min(p[i] for p in vertices) for i in range(3)]
    size = " × ".join(f"{axis:.2f}" for axis in bounds)
    return f"{path.name} · {size} mm · {len(triangles)} triângulos · volume {volume / 1000:.2f} cm³"


def pocket_outline(pocket):
    return footprint(pocket["x"], pocket["y"], pocket["largura"], pocket["altura"],
                     (pocket["raio"],) * 4, pocket["chanfro"])


def generate(output, width):
    width = round(width, DIMENSION_DECIMALS)
    dimensions = scaled_dimensions(width)
    body, pocket, arrow = (dimensions[name] for name in ("corpo", "rebaixo", "seta"))
    radii = tuple(body["raios"][name] for name in CORNER_NAMES)
    outer = footprint(0, 0, body["largura"], body["altura"], radii)
    center, top = arrow["centroX"], arrow["topo"]
    half_width = arrow["largura"] / 2
    triangle = [(center - half_width, top), (center + half_width, top), (center, top + arrow["altura"])]
    recesses = [(pocket_outline(pocket), pocket["profundidade"]), (triangle, arrow["profundidade"])]
    coaster = build_mesh(outer, body["espessura"], recesses)

    # O cupom replica perfil, profundidade e chanfro do rebaixo em uma área menor.
    factor = width / BASE_WIDTH
    coupon_outer = footprint(0, 0, 36 * factor, 28 * factor, (2 * factor,) * 4)
    coupon_pocket = {**pocket, "x": 5 * factor, "y": 4 * factor,
                     "largura": 26 * factor, "altura": 20 * factor}
    coupon = build_mesh(coupon_outer, body["espessura"], [(pocket_outline(coupon_pocket), pocket["profundidade"])])
    stls = ((f"cartrest-ds-{width_suffix(width)}mm.stl", coaster),
            ("cartrest-cupom-encaixe.stl", coupon))

    # Valida os dois sólidos e prepara o JSON antes de substituir qualquer
    # saída. A pasta temporária usa o mesmo volume para a troca de cada arquivo.
    output.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(prefix=".cartrest-modelo-", dir=output) as staging_dir:
        staging = Path(staging_dir)
        summaries = [write_stl(staging / name, mesh) for name, mesh in stls]
        data = json.dumps(dimensions, ensure_ascii=False, indent=2)
        (staging / "dimensoes.json").write_bytes((data + "\n").encode("utf-8"))
        for name, _ in stls:
            (staging / name).replace(output / name)
        (staging / "dimensoes.json").replace(output / "dimensoes.json")

    for summary in summaries:
        print(summary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--largura", type=float, default=BASE_WIDTH,
                        help=f"largura final em mm, entre {MIN_WIDTH} e {MAX_WIDTH}")
    parser.add_argument("--saida", type=Path, help="pasta para os STLs e as medidas de corte")
    options = parser.parse_args()
    if not MIN_WIDTH <= options.largura <= MAX_WIDTH:
        parser.error(f"a largura precisa estar entre {MIN_WIDTH} e {MAX_WIDTH} mm")
    default_output = ROOT if options.largura == BASE_WIDTH else ROOT / f"{width_suffix(options.largura)}mm"
    output = options.saida or default_output
    if options.largura != BASE_WIDTH and output.resolve() == ROOT:
        parser.error(f"escolha outra pasta para preservar as medidas padrão de {BASE_WIDTH} mm")
    generate(output, options.largura)


if __name__ == "__main__":
    main()
