"""Generate geometry-only expectations with the frozen complete backend."""
import json
import math
from pathlib import Path
import random
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/reference/backend'))
from services.grouping import group_dots_detailed, GridConfig

rng = random.Random(19)
cases = []


def page(columns=16, lines=9, curve=0, independent=False):
    rows = []
    for line in range(lines):
        for cell in range(columns):
            code = '111111' if cell % 3 == 0 else rng.choice(['101000','111010','110110','100100','010100','001110'])
            for bit, value in enumerate(code):
                if value != '1': continue
                x, y = 70 + cell * 24 + (bit // 3) * 10, 70 + line * 40 + bit % 3 * 10
                xx = x + curve * .00012 * (x - 250) * (y - 240)
                yy = y + curve * .0004 * (x - 250)**2 + curve * .00012 * (y - 240)**2
                if independent: yy += 1.6 * math.sin((x - 70) / 70 + line * .7)
                rows.append([2, xx/700, yy/700, 6/700, 6/700, .94 + (len(rows)%5)*.001])
    return rows


def add(name, rows, settings=None):
    start = time.perf_counter()
    config = GridConfig(**(settings or {}))
    item = {'name':name, 'width':700, 'height':700, 'detections':rows, 'config':settings or {}}
    try:
        result = group_dots_detailed(rows, 700, 700, config=config)
        item['expected'] = result
        print(f"{name}: {result['grid']['fit_type'] if result['grid'] else 'empty'}, {time.perf_counter()-start:.2f}s", flush=True)
    except ValueError as error:
        item['error'] = str(error)
        print(f'{name}: expected rejection: {error}', flush=True)
    cases.append(item)


regular = page()
add('regular-default', regular)
add('calibrated', regular, {'column_spacing':10, 'row_spacing':10, 'cell_pitch':24,
    'line_pitch':40, 'x_origin':70, 'y_origin':70, 'angle_degrees':0})
add('regular-line-refinement', page(independent=True), {'refine_lines':True})
add('regular-segment-refinement', page(independent=True), {'refine_lines':True, 'refine_segments':True})
curved = page(curve=1)
add('curved-auto', curved)
add('curved-forced', curved, {'fit_mode':'warped'})
add('curved-line-refinement', curved, {'fit_mode':'warped','refine_lines':True})
add('curved-segment-refinement', curved, {'fit_mode':'warped','refine_lines':True,'refine_segments':True})
recovery = [list(r) for r in regular]
recovery[50][0] = 1
add('back-label-recovery', recovery, {'recover_back_dots':True})
add('same-class-duplicate', regular + [regular[3][:]])
add('other-class-conflict', regular + [[1,*regular[3][1:]]])
add('no-front-dots', [[1,.2,.2,.01,.01,.9]])
add('sparse-warp-rejected', regular[:60], {'fit_mode':'warped'})
add('invalid-calibration', regular, {'column_spacing':-1})
target = ROOT / 'test/fixtures/grouping_full.json'
target.write_text(json.dumps(cases, ensure_ascii=False), encoding='utf-8')
print(f'Wrote {len(cases)} full-backend geometry cases: {target}', flush=True)
