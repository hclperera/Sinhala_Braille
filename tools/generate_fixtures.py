"""Create non-photographic regression fixtures using the upstream Python code."""
import json
from pathlib import Path
import random
import sys
import math

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/reference/backend'))
from services.translation import translate_detailed, CONSONANTS, INDEPENDENT_VOWELS, PUNCTUATION
from services.grouping import group_dots_detailed, GridConfig
from sahi.slicing import get_slice_bboxes

rng = random.Random(42)
tokens = list(dict.fromkeys([*CONSONANTS, *INDEPENDENT_VOWELS, *PUNCTUATION,
    '000000', '\n', '001111', '000100', '001000', '000010', '000001', '000011', '011000', 'invalid']))
sequences = [[a, b] for a in tokens for b in tokens]
sequences += [[rng.choice(tokens) for _ in range(rng.randint(3, 30))] for _ in range(250)]
translation = [{'codes': codes, 'text': translate_detailed(codes)['text']} for codes in sequences]
grouping = []
for angle in [0, 4, -7]:
    detections = []
    for line in range(3):
        for cell in range(12):
            # Include complete cells to establish unambiguous geometry.
            code = '111111' if cell % 5 == 0 else rng.choice(list(CONSONANTS))
            for bit, enabled in enumerate(code):
                if enabled == '0': continue
                x = 70 + cell * 30 + (bit // 3) * 12
                y = 70 + line * 50 + (bit % 3) * 12
                radians = math.radians(angle)
                x, y = x * math.cos(radians) - y * math.sin(radians), x * math.sin(radians) + y * math.cos(radians)
                detections.append([2, x / 640, y / 480, 6 / 640, 6 / 480, .95])
    expected = group_dots_detailed(detections, 640, 480, config=GridConfig(fit_mode='regular'))
    grouping.append({'angle':angle, 'width':640, 'height':480, 'detections':detections, 'codes':expected['codes']})
slices = []
for width, height in [(100, 200), (640, 640), (641, 641), (1024, 768), (2000, 3000)]:
    slices.append({'width':width, 'height':height, 'boxes':get_slice_bboxes(height, width,
        slice_height=640, slice_width=640, overlap_height_ratio=.2, overlap_width_ratio=.2)})
target = ROOT / 'test/fixtures'
target.mkdir(parents=True, exist_ok=True)
(target / 'reference.json').write_text(json.dumps({'translation':translation, 'grouping':grouping, 'slices':slices}, ensure_ascii=False), encoding='utf-8')
print(f'Wrote {len(translation)} translation cases, {len(grouping)} grids, {len(slices)} slicing cases')
