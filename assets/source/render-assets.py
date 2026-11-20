"""Render all sword SVG variants from one editable pixel map. No image dependency."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent.parent
data = json.loads((ROOT / 'source/sword-pixels.json').read_text())
grid = data['grid']
def rectangles(foreground):
    return ''.join(f'<rect x="{x}" y="{y}" width="{w}" height="1" fill="{data["palette"][index]}"/>' for x,y,w,index,flag in data['runs'] if flag == foreground)
rects = rectangles(1)
glyph = f'<g id="enchant-sword" shape-rendering="crispEdges">{rects}</g>'
background = '<g id="approved-background" shape-rendering="crispEdges">' + rectangles(0) + '</g>'
for name, backdrop in [('app-icon', background), ('enchanted-sword', '')]:
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {grid} {grid}" width="1024" height="1024">{backdrop}{glyph}</svg>'
    (ROOT / 'images' / f'{name}.svg').write_text(svg)
print('Rendered two SVGs with identical sword geometry and colors.')
