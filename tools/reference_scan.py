"""Run the frozen original backend on a local photo for comparison.

Example: python tools/reference_scan.py test_images/page.jpg
No server, accounts, or database are required. Outputs stay in .tooling/.
"""
import argparse
import json
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/reference/backend'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / '.tooling/reference_scan')
    args = parser.parse_args()
    if not args.image.is_file(): parser.error('Image file does not exist')
    args.output.mkdir(parents=True, exist_ok=True)
    os.environ['PAGE_MODEL_PATH'] = str(ROOT / '.tooling/page.pt')
    os.environ['DOT_MODEL_PATH'] = str(ROOT / '.tooling/dots.pt')
    os.environ['YOLO_CONFIG_DIR'] = str(ROOT / '.tooling')
    os.environ['DEVICE'] = 'cpu'
    from services.segmentation import run_vision_stages
    from services.grouping import group_dots_detailed, GridConfig
    from services.translation import translate_detailed
    vision = run_vision_stages(str(args.image.resolve()), debug_dir=args.output)
    (args.output / 'vision.json').write_text(json.dumps(vision, ensure_ascii=False, indent=2), encoding='utf-8')
    grouped = group_dots_detailed(vision['yolo_outputs'], vision['img_width'], vision['img_height'],
                                 config=GridConfig(front_class_id=vision['front_class_id']))
    translated = translate_detailed(grouped['codes'])
    for name, result in [('grouping', grouped), ('translation', translated)]:
        (args.output / f'{name}.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Reference output: {args.output.resolve()}')


if __name__ == '__main__': main()
