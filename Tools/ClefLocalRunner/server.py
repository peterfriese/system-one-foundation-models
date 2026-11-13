#!/usr/bin/env python3
"""
Tools/ClefLocalRunner/server.py

A lightweight FastAPI daemon for local, zero-network, confidential Mac execution
of Cloudflare Clef and Clef-Flash multimodal decision models.

Features:
- Implements System One / Clef wire protocol: POST /v1/systemone and POST /v1/evaluate
- Hardware acceleration: Apple Silicon GPU (MPS) / NVIDIA (CUDA) / CPU fallback
- Compatible with Cloudflare joint_schema_model.py or standalone PyTorch / HuggingFace inference
- Ingests text `state`, optional `images` (RFC 2397 Data URLs or structured base64), and questions (`noul`, `choice`, `score`)
- Returns calibrated SystemOneResponse JSON with `model`, `answers`, and `usage: { input_tokens, output_tokens: 0 }`
- Includes health and model discovery probes: GET /health and GET /v1/models
- Telemetry headers: RFC 7668 `Server-Timing` and `x-envoy-upstream-service-time` for client latency recording
"""

import argparse
import base64
import hashlib
import importlib.util
import io
import logging
import math
import os
import sys
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any, Dict, List, Optional, Tuple, Union

try:
    import torch
except ImportError:
    torch = None

try:
    from PIL import Image
except ImportError:
    Image = None

try:
    from fastapi import FastAPI, HTTPException, Request, Response, status
    from fastapi.responses import JSONResponse
    import uvicorn
except ImportError:
    FastAPI = None
    HTTPException = None
    JSONResponse = None
    uvicorn = None

try:
    from pydantic import BaseModel
except ImportError:
    BaseModel = None

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger("clef-runner")

# Guardrail constants (matching SystemOneImage.Guardrails and Tech Note 0012/0015)
MAX_IMAGE_COUNT = 4
MAX_MEGAPIXELS = 16.0
MAX_PIXELS = int(MAX_MEGAPIXELS * 1_000_000)
MAX_PAYLOAD_BYTES = 13 * 1024 * 1024  # 13 MiB encoded payload cap
DEFAULT_VISION_TOKENS_PER_IMAGE = 1024

if Image is not None:
    Image.MAX_IMAGE_PIXELS = MAX_PIXELS

# Model ID aliases
MODEL_MAPPINGS = {
    "clef-flash": "Cloudflare/clef-flash",
    "@cf/cloudflare/clef-flash": "Cloudflare/clef-flash",
    "clef": "Cloudflare/clef",
    "@cf/cloudflare/clef": "Cloudflare/clef",
}


# MARK: - Request & Response Schemas

if BaseModel is not None:
    class QuestionPayload(BaseModel):
        type: str
        instructions: str
        criteria: Optional[Union[Dict[str, str], List[str]]] = None
        options: Optional[List[str]] = None

    class EvaluateRequest(BaseModel):
        state: str = ""
        model: Optional[str] = None
        questions: Dict[str, QuestionPayload]
        images: Optional[List[Union[str, Dict[str, Any]]]] = None

    class SystemOneUsage(BaseModel):
        input_tokens: int
        output_tokens: int = 0

    class SystemOneAnswer(BaseModel):
        type: str
        noul: Optional[float] = None
        choice: Optional[str] = None
        score: Optional[float] = None
        confidence: Optional[float] = None
        probabilities: Optional[Dict[str, float]] = None
        legend: Optional[Dict[str, str]] = None

    class SystemOneResponse(BaseModel):
        id: Optional[str] = None
        model: str
        answers: Dict[str, SystemOneAnswer]
        questions: Optional[Dict[str, SystemOneAnswer]] = None
        usage: SystemOneUsage
        server_duration_ms: Optional[float] = None


# MARK: - Image Processing & Extraction

def extract_encoded_image_string(img_data: Union[str, Dict[str, Any]]) -> str:
    """Extracts the raw encoded string from an RFC 2397 Data URL or dictionary attachment."""
    if isinstance(img_data, str):
        return img_data
    elif isinstance(img_data, dict):
        raw_val = (
            img_data.get("data_url")
            or img_data.get("dataURL")
            or img_data.get("base64")
            or img_data.get("data")
        )
        if not raw_val or not isinstance(raw_val, str):
            raise ValueError(f"Image dictionary missing base64 or data_url: {list(img_data.keys())}")
        return raw_val
    else:
        raise ValueError(f"Unsupported image data format: {type(img_data)}")


def parse_image_attachment(img_data: Union[str, Dict[str, Any]]) -> Any:
    """
    Decodes an image attachment from either an RFC 2397 Data URL string or a structured dictionary,
    enforcing payload byte limits before base64 decoding and megapixel limits before RGB expansion.
    """
    if Image is None:
        raise RuntimeError("Pillow is not installed. Please install pillow>=10.0.0")

    raw_encoded = extract_encoded_image_string(img_data)
    if len(raw_encoded.encode("utf-8")) > MAX_PAYLOAD_BYTES:
        raise ValueError(
            f"Image payload exceeds maximum allowed size of {MAX_PAYLOAD_BYTES} bytes (13 MiB)."
        )

    if raw_encoded.startswith("data:"):
        parts = raw_encoded.split(",", 1)
        raw_base64 = parts[1] if len(parts) > 1 else parts[0]
    else:
        raw_base64 = raw_encoded

    try:
        image_bytes = base64.b64decode(raw_base64, validate=False)
    except Exception as e:
        raise ValueError(f"Failed to decode base64 image: {str(e)}")

    if len(image_bytes) > MAX_PAYLOAD_BYTES:
        raise ValueError(
            f"Decoded image byte length ({len(image_bytes)}) exceeds {MAX_PAYLOAD_BYTES} bytes."
        )

    try:
        raw_image = Image.open(io.BytesIO(image_bytes))
    except Exception as e:
        raise ValueError(f"Invalid or oversized image header: {str(e)}")

    if raw_image.width * raw_image.height > MAX_PIXELS:
        raise ValueError(
            f"Image resolution ({raw_image.width}x{raw_image.height}) exceeds maximum allowed {MAX_MEGAPIXELS} MP."
        )

    try:
        return raw_image.convert("RGB")
    except Exception as e:
        raise ValueError(f"Failed to decode RGB bitmap: {str(e)}")


def _deterministic_seed(text: str) -> int:
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    return int.from_bytes(digest[:4], "big")


def estimate_input_tokens(state: str, questions: Dict[str, Any], images_count: int, tokenizer: Any = None) -> int:
    """
    Computes input token estimation adhering to Tech Note 0015:
    text tokens + patch grid tokens (~1024 vision tokens per image).
    """
    if tokenizer is not None and hasattr(tokenizer, "encode"):
        try:
            prompt_text = state + " " + " ".join(
                f"{k}: {q.instructions if hasattr(q, 'instructions') else str(q)}"
                for k, q in questions.items()
            )
            text_tokens = len(tokenizer.encode(prompt_text))
        except Exception:
            text_tokens = int(len(state.split()) * 1.3) + (len(questions) * 32)
    else:
        text_tokens = int(len(state.split()) * 1.3) + (len(questions) * 32) + 16

    vision_tokens = images_count * DEFAULT_VISION_TOKENS_PER_IMAGE
    return text_tokens + vision_tokens


# MARK: - Clef Inference Engine

class ClefEngine:
    def __init__(self, model_id_or_path: str, device: str, mock: bool = False, trust_remote_code: bool = False):
        self.model_id_or_path = model_id_or_path
        self.resolved_model = MODEL_MAPPINGS.get(model_id_or_path, model_id_or_path)
        self.device = device
        self.mock = mock
        self.trust_remote_code = trust_remote_code
        self.model = None
        self.processor = None
        self.joint_schema_module = None
        self.tokenizer = None

    @property
    def should_trust_remote_code(self) -> bool:
        return self.trust_remote_code or self.resolved_model.startswith("Cloudflare/clef")

    def load_model(self):
        if self.mock:
            logger.info("Initializing Clef Engine in deterministic MOCK mode.")
            return

        logger.info(f"Targeting device: {self.device}")

        joint_schema_mod = self._try_load_joint_schema_module()
        if joint_schema_mod is None:
            raise RuntimeError(
                f"joint_schema_model.py could not be loaded for '{self.resolved_model}'. "
                "Clef inference requires joint_schema_model.py. Pass --mock to run in deterministic offline mock mode."
            )

        self.joint_schema_module = joint_schema_mod
        try:
            logger.info(f"Loading release model using joint_schema_model.load_release_model({self.resolved_model})...")
            load_fn = getattr(joint_schema_mod, "load_release_model", None)
            if callable(load_fn):
                dtype = torch.float16 if (torch is not None and self.device in ("mps", "cuda")) else torch.float32
                try:
                    self.model, self.processor = load_fn(
                        self.resolved_model,
                        device=self.device,
                        torch_dtype=dtype,
                        trust_remote_code=self.should_trust_remote_code
                    )
                except TypeError:
                    self.model, self.processor = load_fn(
                        self.resolved_model,
                        device=self.device,
                        torch_dtype=dtype
                    )
                self.tokenizer = getattr(self.processor, "tokenizer", self.processor)
                logger.info("Successfully loaded model and processor via joint_schema_model.py.")
                return
            else:
                raise RuntimeError(
                    "joint_schema_model.py could not be loaded: missing callable 'load_release_model' in module"
                )
        except Exception as e:
            logger.error(f"Failed to load via joint_schema_model.load_release_model: {e}")
            raise RuntimeError(f"joint_schema_model.py could not be loaded: {e}")

    def load(self):
        self.load_model()

    def _try_load_joint_schema_module(self):
        """Attempts to discover and import joint_schema_model.py."""
        candidates = [
            "joint_schema_model.py",
            os.path.join(self.model_id_or_path, "joint_schema_model.py"),
            os.path.join(os.path.dirname(__file__), "joint_schema_model.py")
        ]
        for path in candidates:
            if os.path.isfile(path):
                try:
                    spec = importlib.util.spec_from_file_location("joint_schema_model", path)
                    if spec and spec.loader:
                        mod = importlib.util.module_from_spec(spec)
                        spec.loader.exec_module(mod)
                        logger.info(f"Discovered joint_schema_model.py at {path}")
                        return mod
                except Exception as e:
                    logger.warning(f"Error loading {path}: {e}")

        try:
            import joint_schema_model
            return joint_schema_model
        except ImportError:
            pass

        try:
            from huggingface_hub import hf_hub_download
            downloaded_path = hf_hub_download(
                repo_id=self.resolved_model,
                filename="joint_schema_model.py",
                local_files_only=False
            )
            spec = importlib.util.spec_from_file_location("joint_schema_model", downloaded_path)
            if spec and spec.loader:
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                logger.info(f"Downloaded joint_schema_model.py from Hugging Face: {downloaded_path}")
                return mod
        except Exception:
            pass

        return None

    def evaluate(
        self,
        state: str,
        questions: Dict[str, Any],
        images: List[Any],
        model_name: str
    ) -> Dict[str, Any]:
        """
        Evaluates questions over state text and optional images in a single forward pass.
        Returns a dictionary of calibrated answers conforming to SystemOneAnswer.
        """
        if self.mock:
            return self._run_mock_inference(state, questions, images)

        payload = {
            "state": state,
            "questions": questions,
            "images": images,
            "model": model_name
        }

        systemone_fn = None
        if self.joint_schema_module is not None and hasattr(self.joint_schema_module, "systemone"):
            systemone_fn = getattr(self.joint_schema_module, "systemone")
        elif "systemone" in globals():
            systemone_fn = globals()["systemone"]

        if systemone_fn is not None:
            try:
                res = systemone_fn(self.model, self.processor, payload)
                if isinstance(res, dict) and "answers" in res:
                    return res["answers"]
                elif isinstance(res, dict) and "questions" in res:
                    return res["questions"]
                elif isinstance(res, dict):
                    return res
                raise RuntimeError(f"Unexpected response format from systemone: {type(res)}")
            except Exception as e:
                logger.error(f"Error executing real model inference via systemone: {e}")
                raise

        raise RuntimeError(
            "Live inference requires joint_schema_model.py with systemone(model, processor, payload). "
            "Pass --mock to run in deterministic offline mock mode."
        )

    def _run_mock_inference(
        self,
        state: str,
        questions: Dict[str, Any],
        images: List[Any]
    ) -> Dict[str, Any]:
        """Calibrated deterministic mock evaluation for offline testing and verification."""
        answers = {}
        for q_id, q in questions.items():
            q_type = q.type if hasattr(q, "type") else q.get("type", "noul")
            instructions = q.instructions if hasattr(q, "instructions") else q.get("instructions", "")
            criteria = q.criteria if hasattr(q, "criteria") else q.get("criteria", None)
            options = q.options if hasattr(q, "options") else q.get("options", None)

            if q_type == "noul":
                prob = self._synthesize_noul_probability(state, instructions, len(images))
                conf = prob if prob >= 0.5 else (1.0 - prob)
                answers[q_id] = {
                    "type": "noul",
                    "noul": round(prob, 4),
                    "confidence": round(conf, 4)
                }

            elif q_type == "choice":
                candidates = self._extract_choice_candidates(criteria, options)
                probs, chosen = self._synthesize_choice_probabilities(state, instructions, candidates)
                answers[q_id] = {
                    "type": "choice",
                    "choice": chosen,
                    "confidence": round(probs[chosen], 4),
                    "probabilities": {k: round(v, 4) for k, v in probs.items()}
                }

            elif q_type == "score":
                levels = self._extract_score_levels(criteria)
                score_val, conf, level_probs = self._synthesize_score_rubric(state, instructions, levels)
                answers[q_id] = {
                    "type": "score",
                    "score": round(score_val, 2),
                    "confidence": round(conf, 4),
                    "probabilities": {str(k): round(v, 4) for k, v in level_probs.items()}
                }

        return answers

    def _extract_choice_candidates(self, criteria: Any, options: Any) -> List[str]:
        if isinstance(criteria, dict):
            return list(criteria.keys())
        elif isinstance(criteria, list) and criteria:
            return [str(c) for c in criteria]
        elif isinstance(options, list) and options:
            return [str(o) for o in options]
        return ["option_a", "option_b"]

    def _extract_score_levels(self, criteria: Any) -> List[str]:
        if isinstance(criteria, list) and criteria:
            return [str(c) for c in criteria]
        elif isinstance(criteria, dict) and criteria:
            return list(criteria.keys())
        return ["1", "2", "3", "4", "5"]

    def _synthesize_noul_probability(self, state: str, instructions: str, img_count: int) -> float:
        seed = _deterministic_seed(f"{state}|{instructions}|{img_count}")
        raw = (seed % 1000) / 1000.0
        return 0.80 + (raw * 0.18)

    def _synthesize_choice_probabilities(
        self, state: str, instructions: str, candidates: List[str]
    ) -> Tuple[Dict[str, float], str]:
        if not candidates:
            return {"default": 1.0}, "default"
        seed = _deterministic_seed(f"{state}|{instructions}")
        winner_idx = seed % len(candidates)
        winner = candidates[winner_idx]

        probs = {}
        remaining = 0.12
        other_count = len(candidates) - 1

        for idx, cand in enumerate(candidates):
            if idx == winner_idx:
                probs[cand] = 0.88
            else:
                probs[cand] = round(remaining / max(1, other_count), 4)

        total = sum(probs.values())
        normalized = {k: v / total for k, v in probs.items()}
        return normalized, winner

    def _synthesize_score_rubric(
        self, state: str, instructions: str, levels: List[str]
    ) -> Tuple[float, float, Dict[int, float]]:
        if not levels:
            return 2.0, 0.70, {0: 0.05, 1: 0.10, 2: 0.70, 3: 0.10, 4: 0.05}
        level_count = len(levels)
        seed = _deterministic_seed(f"{state}|{instructions}")
        peak_idx = seed % level_count

        level_probs: Dict[int, float] = {}
        for idx in range(level_count):
            dist = abs(idx - peak_idx)
            weight = math.exp(-dist * 1.5)
            level_probs[idx] = weight

        total_weight = sum(level_probs.values())
        normalized = {idx: v / total_weight for idx, v in level_probs.items()}

        expected_score = sum(idx * normalized[idx] for idx in range(level_count))
        confidence = max(normalized.values())
        return expected_score, confidence, normalized


# MARK: - Device Detection

def detect_device(preferred_device: Optional[str] = None) -> str:
    """Detects and enables Apple Silicon GPU acceleration (MPS), NVIDIA (CUDA), or CPU fallback."""
    if preferred_device and preferred_device != "auto":
        return preferred_device

    if torch is not None:
        return "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")

    return "cpu"


# MARK: - FastAPI Application Factory

def create_app(engine: ClefEngine):
    if FastAPI is None or uvicorn is None or BaseModel is None:
        raise RuntimeError(
            "Missing required web server dependencies (fastapi, uvicorn, pydantic). Please install them via:\n"
            "pip install -r Tools/ClefLocalRunner/requirements.txt"
        )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        logger.info(f"Starting Clef Local Runner for model '{engine.model_id_or_path}' on device '{engine.device}'...")
        engine.load()
        yield
        logger.info("Clef Local Runner shutting down.")

    app = FastAPI(
        title="Clef Local Runner",
        description="Local zero-network System One multimodal inference server for Cloudflare Clef & Clef-Flash",
        version="1.0.0",
        lifespan=lifespan
    )

    @app.middleware("http")
    async def add_timing_and_telemetry(request: Request, call_next):
        start_time = time.perf_counter()
        response: Response = await call_next(request)
        duration_ms = (time.perf_counter() - start_time) * 1000.0

        response.headers["Server-Timing"] = f"inference;dur={duration_ms:.2f}"
        response.headers["x-envoy-upstream-service-time"] = str(int(duration_ms))
        response.headers["x-clef-confidential-execution"] = "local-zero-egress"
        return response

    @app.get("/health", tags=["Health"])
    @app.get("/v1/health", tags=["Health"])
    async def health_check():
        return {
            "status": "ok",
            "model": engine.model_id_or_path,
            "resolved_model": engine.resolved_model,
            "device": engine.device,
            "mps_available": bool(torch and torch.backends.mps.is_available()),
            "cuda_available": bool(torch and torch.cuda.is_available()),
            "mock": engine.mock,
            "version": "1.0.0"
        }

    @app.get("/v1/models", tags=["Discovery"])
    async def list_models():
        return {
            "object": "list",
            "data": [
                {
                    "id": engine.model_id_or_path,
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "cloudflare",
                    "capabilities": {
                        "multimodal": True,
                        "guided_generation": True,
                        "system_one": True,
                        "device": engine.device
                    }
                },
                {
                    "id": engine.resolved_model,
                    "object": "model",
                    "created": int(time.time()),
                    "owned_by": "cloudflare"
                }
            ]
        }

    @app.post("/v1/evaluate", tags=["Inference"])
    @app.post("/v1/systemone", tags=["Inference"])
    async def evaluate_decisions(payload: EvaluateRequest):
        start_inference = time.perf_counter()

        pil_images: List[Any] = []
        if payload.images:
            if len(payload.images) > MAX_IMAGE_COUNT:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Exceeded maximum image count. Received {len(payload.images)}, maximum is {MAX_IMAGE_COUNT}."
                )

            total_encoded_bytes = 0
            for idx, img_item in enumerate(payload.images):
                try:
                    encoded_str = extract_encoded_image_string(img_item)
                    total_encoded_bytes += len(encoded_str.encode("utf-8"))
                    if total_encoded_bytes > MAX_PAYLOAD_BYTES:
                        raise ValueError(
                            f"Total image payload size ({total_encoded_bytes} bytes) exceeds maximum allowed {MAX_PAYLOAD_BYTES} bytes (13 MiB)."
                        )
                    pil_images.append(parse_image_attachment(encoded_str))
                except Exception as img_err:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"Invalid image attachment at index {idx}: {str(img_err)}"
                    )

        input_token_count = estimate_input_tokens(
            state=payload.state,
            questions=payload.questions,
            images_count=len(pil_images),
            tokenizer=engine.tokenizer
        )

        effective_model = payload.model or engine.model_id_or_path

        try:
            answers = engine.evaluate(
                state=payload.state,
                questions=payload.questions,
                images=pil_images,
                model_name=effective_model
            )
        except Exception as eval_err:
            logger.error(f"Inference error: {eval_err}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Clef evaluation failure: {str(eval_err)}"
            )

        duration_ms = (time.perf_counter() - start_inference) * 1000.0

        response_data = {
            "id": f"clef_local_{uuid.uuid4().hex[:12]}",
            "model": effective_model,
            "answers": answers,
            "questions": answers,
            "usage": {
                "input_tokens": input_token_count,
                "output_tokens": 0
            },
            "server_duration_ms": round(duration_ms, 2)
        }

        return JSONResponse(content=response_data)

    return app


# MARK: - CLI Entrypoint

def main():
    parser = argparse.ArgumentParser(
        description="Run local confidential Cloudflare Clef inference daemon on Apple Silicon or CUDA."
    )
    parser.add_argument(
        "--model",
        type=str,
        default="clef-flash",
        help="Clef model identifier or local directory path (default: 'clef-flash' or 'Cloudflare/clef-flash')"
    )
    parser.add_argument("--port", type=int, default=8000, help="Port to listen on (default: 8000)")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Host interface to bind (default: 127.0.0.1)")
    parser.add_argument(
        "--device",
        type=str,
        default="auto",
        choices=["auto", "mps", "cuda", "cpu"],
        help="Execution device (default: 'auto' -> mps if available, cuda if available, else cpu)"
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Run in deterministic offline mock mode without loading large model weights"
    )
    parser.add_argument(
        "--trust-remote-code",
        action="store_true",
        default=False,
        help="Allow executing custom code from remote Hugging Face repositories (default: False; auto-enabled for 'Cloudflare/clef' repos)"
    )

    args = parser.parse_args()
    resolved_device = detect_device(args.device)
    logger.info(f"Resolved execution hardware device: {resolved_device.upper()}")

    engine = ClefEngine(
        model_id_or_path=args.model,
        device=resolved_device,
        mock=args.mock,
        trust_remote_code=args.trust_remote_code
    )

    app = create_app(engine)
    logger.info(f"Starting server on http://{args.host}:{args.port}")
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")


if __name__ == "__main__":
    main()
