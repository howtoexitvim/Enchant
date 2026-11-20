#!/usr/bin/env python3
"""Compile the original rectangle-only SVG icons into the native Canvas renderer."""

from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def read_icon(path):
    root = ET.parse(path).getroot()
    if root.attrib.get("viewBox") != "0 0 16 16":
        raise ValueError(f"{path.name}: expected a 16-unit square canvas")
    layers = []

    def visit(node, inherited):
        fill = node.attrib.get("fill", inherited)
        tag = node.tag.rsplit("}", 1)[-1]
        if tag == "rect":
            rect = [int(node.attrib[key]) for key in ("x", "y", "width", "height")]
            x, y, width, height = rect
            if min(x, y) < 0 or min(width, height) <= 0 or x + width > 16 or y + height > 16:
                raise ValueError(f"{path.name}: pixel rectangle outside the canvas")
            if fill != "currentColor" and not re.fullmatch(r"#[0-9a-fA-F]{6}", fill):
                raise ValueError(f"{path.name}: expected currentColor or an explicit RGB color")
            if layers and layers[-1][0] == fill:
                layers[-1][1].append(rect)
            else:
                layers.append((fill, [rect]))
        elif tag not in ("svg", "g", "title", "desc"):
            raise ValueError(f"{path.name}: unsupported SVG element {tag}")
        for child in node:
            visit(child, fill)

    visit(root, "currentColor")
    return layers


def generate():
    cases = []
    for path in sorted((ROOT / "assets/icons").glob("*.svg")):
        layers = []
        for fill, rects in read_icon(path):
            rgb = "nil" if fill == "currentColor" else f"0x{fill[1:].upper()}"
            cells = ", ".join("[" + ", ".join(map(str, r)) + "]" for r in rects)
            layers.append(f"            PixelLayer(rgb: {rgb}, cells: [{cells}])")
        cases.append(f'        case "{path.stem}": return [\n' + ",\n".join(layers) + "\n        ]")

    output = '''import SwiftUI

// Generated from assets/icons/*.svg by scripts/generate-pixel-icons.py.
// Explicit material colors are shared with the preview; color tints monochrome icons only.
struct PixelIcon: View {
    let name: String
    var color: Color = EnchantTheme.accent
    var size: CGFloat = 20

    private struct PixelLayer {
        let rgb: UInt32?
        let cells: [[CGFloat]]
    }

    private var layers: [PixelLayer] {
        switch name {
''' + "\n".join(cases) + '''
        default: return []
        }
    }

    var body: some View {
        Canvas { context, dimensions in
            for layer in layers {
                let fill: Color
                if let rgb = layer.rgb {
                    fill = Color(.sRGB, red: Double((rgb >> 16) & 255) / 255,
                                 green: Double((rgb >> 8) & 255) / 255,
                                 blue: Double(rgb & 255) / 255, opacity: 1)
                } else {
                    fill = color
                }
                for cell in layer.cells {
                    let rect = CGRect(x: cell[0] * dimensions.width / 16,
                                      y: cell[1] * dimensions.height / 16,
                                      width: cell[2] * dimensions.width / 16,
                                      height: cell[3] * dimensions.height / 16)
                    context.fill(Path(rect), with: .color(fill), style: FillStyle(antialiased: false))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
'''
    (ROOT / "App/Shared/PixelIcon.swift").write_text(output)
    print(f"Compiled {len(cases)} SVG icons into PixelIcon.swift")


if __name__ == "__main__":
    generate()
