"""Export local YOLOv8 checkpoints without modifying the originals.

The generated probe checks runtime compatibility only, not Braille accuracy.
Run from the project root:
  python tools/prepare_models.py --page path/to/page.pt --dots path/to/dots.pt
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import time

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.tooling'
WORK.mkdir(exist_ok=True)
os.environ.setdefault('YOLO_CONFIG_DIR', str(WORK))
os.environ.setdefault('YOLO_AUTOINSTALL', 'false')


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--page', required=True, type=Path,
                        help='Path to the YOLO page detection checkpoint')
    parser.add_argument('--dots', required=True, type=Path,
                        help='Path to the YOLO Braille dot detection checkpoint')
    args = parser.parse_args()
    import cv2
    import numpy as np
    import onnx
    import torch
    import ultralytics
    from ultralytics import YOLO

    target = ROOT / 'assets' / 'models'
    target.mkdir(parents=True, exist_ok=True)
    manifest = {'input_size': 640, 'runtime': 'OpenCV DNN CPU',
                'export': {'opset': 12, 'dynamic': False, 'nms': False, 'simplify': False},
                'versions': {'ultralytics': ultralytics.__version__, 'opencv': cv2.__version__,
                             'torch': torch.__version__, 'onnx': onnx.__version__}, 'models': {}}
    # Deterministic synthetic probe; never presented as a real accuracy test.
    rng = np.random.default_rng(42)
    probe = rng.random((1, 3, 640, 640), dtype=np.float32)
    for name, filename in [('page', args.page), ('dots', args.dots)]:
        source = Path(filename)
        checkpoint = WORK / f'{name}.pt'
        if source.resolve() != checkpoint.resolve():
            shutil.copyfile(source, checkpoint)
        model = YOLO(str(checkpoint))
        classes = {str(k): v for k, v in model.names.items()}
        exported = Path(model.export(format='onnx', imgsz=640, opset=12,
                                     dynamic=False, simplify=False, nms=False,
                                     half=False, device='cpu', batch=1))
        destination = target / f'{name}.onnx'
        shutil.copyfile(exported, destination)
        onnx.checker.check_model(str(destination))
        net = cv2.dnn.readNetFromONNX(str(destination))
        net.setInput(probe)
        started = time.perf_counter()
        actual = net.forward()
        elapsed = time.perf_counter() - started
        # Reload because export changes the detection head's execution flags.
        reference = YOLO(str(checkpoint)).model.float().eval()
        with torch.inference_mode():
            expected = reference(torch.from_numpy(probe))[0].numpy()
        if actual.shape != expected.shape or not np.isfinite(actual).all():
            raise RuntimeError(f'{name}: invalid runtime output {actual.shape}')
        delta = np.abs(actual - expected)
        if float(delta.max()) > .05:
            raise RuntimeError(f'{name}: exported output differs from PyTorch: {delta.max()}')
        manifest['models'][name] = {
            'asset': f'assets/models/{name}.onnx', 'classes': classes,
            'source_sha256': digest(source), 'sha256': digest(destination),
            'bytes': destination.stat().st_size, 'output_shape': list(actual.shape),
            'synthetic_probe': {'max_absolute_error': float(delta.max()),
                                'mean_absolute_error': float(delta.mean()),
                                'desktop_cpu_seconds': elapsed,
                                'recognition_accuracy_validated': False}}
        print(f'{name}: {actual.shape}, max delta={delta.max():.6f}, {elapsed:.3f}s', flush=True)
    fronts = [int(k) for k, v in manifest['models']['dots']['classes'].items() if v.lower() == 'front']
    if len(fronts) != 1:
        raise RuntimeError('Dot model must have one identifiable front class')
    manifest['front_class_id'] = fronts[0]
    (target / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
