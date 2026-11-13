# Local Inference & Model Conversion Tools (`Tools/`) 🔧🧠

`Tools/` provides standalone Python utilities for compiling on-device **Core ML** decision models (`LayaOnDevice`) and running confidential, zero-egress **Cloudflare Clef** multimodal servers on Apple Silicon workstations (`ClefFoundationModels`).

---

## 🗂️ Available Tools

| Tool Directory | Target Swift Module | What It Does |
| :--- | :--- | :--- |
| [**`CoreMLConverter/`**](CoreMLConverter/README.md) | [`LayaOnDevice`](../Sources/LayaOnDevice/README.md) | Converts Hugging Face Laya System One checkpoints (`convaiinnovations/laya` ModernBERT 421M and multilingual mmBERT 322M) via `coremltools` into FP16 or 8-bit quantized `.mlpackage` / `.mlmodelc` bundles optimized for the Apple Neural Engine (ANE). |
| [**`ClefLocalRunner/`**](ClefLocalRunner/README.md) | [`ClefFoundationModels`](../Sources/ClefFoundationModels/README.md) | Zero-egress local HTTP inference server (`server.py` + Docker Model Runner instructions) executing **Clef-Flash (9B)** and **Clef (27B)** multimodal evaluations on Apple Silicon Metal Performance Shaders (`mps`) over `POST /v1/evaluate` and `POST /v1/systemone`. |

---

## ⚡ Quick Commands

### 1. Convert & Compile Laya for On-Device Core ML (`LayaOnDevice`)

```bash
pip install -r Tools/CoreMLConverter/requirements.txt

python3 Tools/CoreMLConverter/convert_laya_to_coreml.py \
    --model convaiinnovations/laya \
    --output LayaDecisionModel.mlpackage \
    --seq-len 512 \
    --max-options 32 \
    --quantize fp16

xcrun coremlcompiler compile LayaDecisionModel.mlpackage .
export LAYA_MODEL_PATH="$PWD/LayaDecisionModel.mlmodelc"
swift run laya-ondevice-quickstart
```

### 2. Run Confidential Local Multimodal Clef (`ClefFoundationModels`)

```bash
pip install -r Tools/ClefLocalRunner/requirements.txt
python3 Tools/ClefLocalRunner/server.py --model clef-flash --port 8000

# In another terminal:
CLEF_LOCAL_PORT=8000 swift run clef-quickstart
```
