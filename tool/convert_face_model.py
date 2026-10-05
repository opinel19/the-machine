"""Convert InsightFace w600k_mbf (MobileFaceNet, ArcFace loss) ONNX -> Core ML.

The exported model takes an aligned 112x112 RGB face as float32 in [0, 255]
(NCHW) and returns an L2-normalised 512-d embedding. Input normalisation,
horizontal-flip test-time augmentation and L2 normalisation are baked in so the
app only has to hand over raw pixels.

Usage (from the project root):
    mkdir -p build/model && cd build/model
    curl -LO https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_sc.zip
    unzip buffalo_sc.zip && cd ../..
    uv venv --python 3.12 build/venv
    VIRTUAL_ENV=build/venv uv pip install torch==2.7.0 torchvision==0.22.0 onnx onnx2torch coremltools onnxruntime
    build/venv/bin/python tool/convert_face_model.py
    xcrun coremlcompiler compile build/model/FaceEmbedder.mlpackage ios/Runner/

Android uses the same wrapped model as ONNX; export it with
    torch.onnx.export(Embedder(base), torch.rand(1, 3, 112, 112) * 255,
                      "android/app/src/main/assets/FaceEmbedder.onnx",
                      input_names=["rgb"], output_names=["embedding"], opset_version=17, dynamo=False)
"""
import os
import sys
import warnings

warnings.filterwarnings("ignore")

import coremltools as ct
import numpy as np
import onnx
import onnx2torch
import onnxruntime as ort
import torch

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ONNX_PATH = os.path.join(ROOT, "build", "model", "w600k_mbf.onnx")
OUT_PATH = os.path.join(ROOT, "build", "model", "FaceEmbedder.mlpackage")


class Embedder(torch.nn.Module):
    def __init__(self, base: torch.nn.Module):
        super().__init__()
        self.base = base

    def forward(self, rgb: torch.Tensor) -> torch.Tensor:
        x = (rgb - 127.5) / 127.5
        both = torch.cat([x, torch.flip(x, dims=[3])], dim=0)
        e = self.base(both)
        e = e[0:1] + e[1:2]
        return e / torch.sqrt((e * e).sum(dim=1, keepdim=True) + 1e-10)


def reference(sess: ort.InferenceSession, rgb: np.ndarray) -> np.ndarray:
    """Same computation using onnxruntime, used to validate the conversion."""
    x = (rgb.astype(np.float32) - 127.5) / 127.5
    name = sess.get_inputs()[0].name
    a = sess.run(None, {name: x})[0]
    b = sess.run(None, {name: x[:, :, :, ::-1].copy()})[0]
    e = a + b
    return e / np.linalg.norm(e, axis=1, keepdims=True)


def main() -> None:
    base = onnx2torch.convert(onnx.load(ONNX_PATH)).eval()
    model = Embedder(base).eval()

    example = torch.rand(1, 3, 112, 112) * 255.0
    with torch.no_grad():
        traced = torch.jit.trace(model, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="rgb", shape=(1, 3, 112, 112), dtype=np.float32)],
        outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.precision.FLOAT16,
    )
    mlmodel.short_description = (
        "MobileFaceNet (InsightFace w600k_mbf) face embedder. "
        "Input: aligned 112x112 RGB face, float32 0-255, NCHW. "
        "Output: L2-normalised 512-d embedding (flip-TTA)."
    )
    mlmodel.save(OUT_PATH)
    print("saved", OUT_PATH)

    # --- validation against onnxruntime -------------------------------------
    sess = ort.InferenceSession(ONNX_PATH, providers=["CPUExecutionProvider"])
    rng = np.random.default_rng(0)
    worst = 1.0
    for _ in range(5):
        rgb = (rng.random((1, 3, 112, 112)) * 255).astype(np.float32)
        ref = reference(sess, rgb)[0]
        with torch.no_grad():
            pt = model(torch.from_numpy(rgb)).numpy()[0]
        cm = mlmodel.predict({"rgb": rgb})["embedding"].reshape(-1)
        worst = min(worst, float(ref @ pt), float(ref @ cm))
    print(f"worst cosine(reference, converted) on random inputs: {worst:.5f}")
    if worst < 0.995:
        sys.exit("conversion mismatch")


if __name__ == "__main__":
    main()
