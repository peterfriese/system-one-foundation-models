/**
 * Wire DTOs, payload validators, and bidirectional Pattern B canonical <-> provider
 * wire adapters for the System One Multi-Provider Firebase App Check Proxy.
 *
 * Matches Swift wire contracts 100% field-for-field:
 * - Sources/SystemOneCore/Models/{SystemOneDTOs,SystemOneImage}.swift
 * - Sources/OpenAIFoundationModels/{OpenAIDecisionsPayloadAdapter,OpenAIDecisionsWireDTOs}.swift
 * - Sources/GeminiFoundationModels/{GeminiDecisionsPayloadAdapter,GeminiDecisionsWireDTOs}.swift
 * - Sources/ClefFoundationModels/{ClefModel,ClefEndpoint,ClefHTTPBackend}.swift
 */

export const SUPPORTED_PROVIDERS = ["jev", "laya", "clef", "openai", "gemini"] as const;
export type ProviderId = (typeof SUPPORTED_PROVIDERS)[number];

export function isSupportedProvider(value: string): value is ProviderId {
  return (SUPPORTED_PROVIDERS as readonly string[]).includes(value);
}

// ============================================================================
// Errors
// ============================================================================

export class ProxyValidationError extends Error {
  public readonly statusCode: number;

  constructor(message: string, statusCode = 400) {
    super(message);
    this.name = "ProxyValidationError";
    this.statusCode = statusCode;
  }
}

export class ProxySafetyRefusalError extends Error {
  public readonly questionName: string;
  public readonly reason: string;

  constructor(questionName: string, reason: string) {
    super(`Safety refusal on question '${questionName}': ${reason}`);
    this.name = "ProxySafetyRefusalError";
    this.questionName = questionName;
    this.reason = reason;
  }
}

// ============================================================================
// Canonical System One Wire Types
// ============================================================================

export type SystemOneQuestion =
  | { type: "noul"; instructions: string }
  | { type: "choice"; instructions: string; criteria: Record<string, string> }
  | { type: "score"; instructions: string; criteria: string[] };

export interface NormalizedImageAttachment {
  mimeType: "image/png" | "image/jpeg" | "image/webp";
  base64Data: string;
  decodedByteLength: number;
  dataURL: string;
}

export interface SystemOneRequest {
  state: string;
  model: string;
  questions: Record<string, SystemOneQuestion>;
  images?: string[];
}

export interface SystemOneUsage {
  input_tokens: number;
  output_tokens: number;
}

export interface SystemOneAnswer {
  type: "noul" | "choice" | "score";
  noul?: number;
  choice?: string;
  score?: number;
  confidence?: number;
  probabilities?: Record<string, number>;
  legend?: Record<string, string>;
}

export interface SystemOneResponse {
  model: string;
  answers: Record<string, SystemOneAnswer>;
  usage?: SystemOneUsage;
}

// ============================================================================
// OpenAI Decisions Wire Types (`POST /v1/decisions`)
// ============================================================================

export type OpenAIContentBlock =
  | { type: "input_text"; text: string }
  | { type: "input_image"; image_url: string };

export interface OpenAIMessage {
  role: string;
  content: OpenAIContentBlock[];
}

export interface OpenAIChoiceItem {
  value: string;
  description: string;
}

export interface OpenAILevelItem {
  label: string;
  description: string;
}

export interface OpenAIDecisionsQuestion {
  type: "predicate" | "choice" | "score";
  name: string;
  instructions: string;
  choices?: OpenAIChoiceItem[];
  levels?: OpenAILevelItem[];
}

export interface OpenAIDecisionsRequest {
  model: string;
  input: string | OpenAIMessage[];
  questions: OpenAIDecisionsQuestion[];
}

// ============================================================================
// Google Gemini Decisions Wire Types (`POST /v1beta/decisions`)
// ============================================================================

export type GeminiContentItem =
  | { type: "text"; text: string }
  | { type: "image"; mime_type: string; data: string }
  | { text: string }
  | { inline_data: { mime_type: string; data: string } };

export interface GeminiDecisionsQuestion {
  type: "noul" | "choice" | "score";
  instructions: string;
  criteria?: Record<string, string> | string[];
}

export interface GeminiDecisionsRequest {
  model: string;
  input: string | GeminiContentItem[];
  questions: Record<string, GeminiDecisionsQuestion>;
}

// ============================================================================
// Helpers & Validators
// ============================================================================

const SUPPORTED_IMAGE_MIMES = new Set(["image/png", "image/jpeg", "image/webp"]);
const MAX_IMAGE_ATTACHMENTS = 4;
const MAX_IMAGE_PAYLOAD_BYTES = 13 * 1024 * 1024; // 13 MiB
const UNIT_INTERVAL_TOLERANCE = 1e-6;
const CANONICAL_BASE64_REGEX = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Distinguishes canonical `SystemOneRequest` (`{ state, questions, ... }`) from native
 * OpenAI/Gemini wire requests (`{ input, questions, ... }`).
 */
export function isCanonicalSystemOnePayload(body: unknown): boolean {
  if (!isPlainObject(body)) {
    return false;
  }
  return typeof body.state === "string" && body.input === undefined;
}

/**
 * Validates an inline base64 image payload, enforcing supported MIME types
 * (`image/png`, `image/jpeg`, `image/webp`), strict RFC 4648 base64 syntax, and
 * returning exact decoded byte length.
 */
function validateInlineBase64Image(
  rawMimeType: string,
  rawBase64: string
): NormalizedImageAttachment {
  const mimeType = rawMimeType.trim().toLowerCase();
  if (!SUPPORTED_IMAGE_MIMES.has(mimeType)) {
    throw new ProxyValidationError(
      `Unsupported image MIME type '${rawMimeType}'. Allowed MIME types: image/png, image/jpeg, image/webp.`
    );
  }

  const cleanBase64 = rawBase64.replace(/\s+/g, "");
  if (cleanBase64.length === 0 || !CANONICAL_BASE64_REGEX.test(cleanBase64)) {
    throw new ProxyValidationError("Invalid or corrupted inline base64 image data.");
  }

  const decodedBuffer = Buffer.from(cleanBase64, "base64");
  if (decodedBuffer.byteLength === 0) {
    throw new ProxyValidationError("Image attachment contains empty base64 data.");
  }

  const typedMime = mimeType as NormalizedImageAttachment["mimeType"];
  return {
    mimeType: typedMime,
    base64Data: cleanBase64,
    decodedByteLength: decodedBuffer.byteLength,
    dataURL: `data:${typedMime};base64,${cleanBase64}`,
  };
}

function parseDataUrlImage(dataURL: string): NormalizedImageAttachment {
  if (/^https?:\/\//i.test(dataURL.trim())) {
    throw new ProxyValidationError(
      "Remote http/https image URLs are prohibited; pass inline RFC 2397 data:image/(png|jpeg|webp);base64,... URLs."
    );
  }
  const match = /^data:([^;]+);base64,(.*)$/is.exec(dataURL);
  if (!match) {
    throw new ProxyValidationError(
      "Image attachments must be inline RFC 2397 base64 data URLs with MIME image/png, image/jpeg, or image/webp."
    );
  }
  return validateInlineBase64Image(match[1], match[2]);
}

/**
 * Parses and validates `images` from a canonical `SystemOneRequest`.
 * Supports both single-string RFC 2397 Data URLs (standard `SystemOneImage.encode`)
 * and keyed `{ format | content_type, data_url | base64 }` representations.
 */
export function parseNormalizedImages(imagesRaw: unknown): NormalizedImageAttachment[] {
  if (imagesRaw === undefined || imagesRaw === null) {
    return [];
  }
  if (!Array.isArray(imagesRaw)) {
    throw new ProxyValidationError("Invalid 'images' field: expected an array of base64 data URLs.");
  }
  if (imagesRaw.length > MAX_IMAGE_ATTACHMENTS) {
    throw new ProxyValidationError(
      `Image count (${imagesRaw.length}) exceeds maximum allowed (${MAX_IMAGE_ATTACHMENTS}).`
    );
  }

  let totalDecodedBytes = 0;
  const result: NormalizedImageAttachment[] = [];

  for (const item of imagesRaw) {
    let normalized: NormalizedImageAttachment;
    if (typeof item === "string") {
      normalized = parseDataUrlImage(item);
    } else if (isPlainObject(item)) {
      const format =
        typeof item.format === "string"
          ? item.format
          : typeof item.content_type === "string"
            ? item.content_type
            : "image/jpeg";
      if (typeof item.data_url === "string") {
        normalized = parseDataUrlImage(item.data_url);
      } else if (typeof item.base64 === "string") {
        normalized = validateInlineBase64Image(format, item.base64);
      } else {
        throw new ProxyValidationError("Invalid image object: expected 'data_url' or 'base64'.");
      }
    } else {
      throw new ProxyValidationError("Invalid image entry: expected RFC 2397 data URL string.");
    }

    totalDecodedBytes += normalized.decodedByteLength;
    if (totalDecodedBytes > MAX_IMAGE_PAYLOAD_BYTES) {
      throw new ProxyValidationError(
        `Total decoded image payload size (${totalDecodedBytes} bytes) exceeds maximum allowed ${MAX_IMAGE_PAYLOAD_BYTES} bytes (13 MiB).`
      );
    }

    result.push(normalized);
  }

  return result;
}

/**
 * Validates and normalizes a canonical `SystemOneRequest` payload.
 */
export function validateCanonicalSystemOneRequest(
  body: unknown,
  defaultModel = "systemone-default"
): { request: SystemOneRequest; normalizedImages: NormalizedImageAttachment[] } {
  if (!isPlainObject(body)) {
    throw new ProxyValidationError("Request body must be a JSON object.");
  }

  const { state, model, questions, images } = body;
  if (typeof state !== "string" || state.trim().length === 0) {
    throw new ProxyValidationError(
      "Bad Request: Payload must include a non-empty 'state' string."
    );
  }
  if (!isPlainObject(questions) || Object.keys(questions).length === 0) {
    throw new ProxyValidationError(
      "Bad Request: Payload must include a non-empty 'questions' object."
    );
  }

  const sanitizedQuestions: Record<string, SystemOneQuestion> = {};
  for (const [name, rawQ] of Object.entries(questions)) {
    if (!name || !isPlainObject(rawQ)) {
      throw new ProxyValidationError(`Invalid question definition for '${name}'.`);
    }
    const qType = rawQ.type;
    const instructions = rawQ.instructions;
    if (typeof instructions !== "string" || instructions.trim().length === 0) {
      throw new ProxyValidationError(
        `Question '${name}' must include non-empty 'instructions'.`
      );
    }

    if (qType === "noul") {
      sanitizedQuestions[name] = { type: "noul", instructions };
    } else if (qType === "choice") {
      if (!isPlainObject(rawQ.criteria) || Object.keys(rawQ.criteria).length === 0) {
        throw new ProxyValidationError(
          `Choice question '${name}' must include a non-empty 'criteria' object.`
        );
      }
      const criteria: Record<string, string> = {};
      for (const [optKey, optDesc] of Object.entries(rawQ.criteria)) {
        if (typeof optDesc !== "string") {
          throw new ProxyValidationError(
            `Choice question '${name}' option '${optKey}' description must be a string.`
          );
        }
        criteria[optKey] = optDesc;
      }
      sanitizedQuestions[name] = { type: "choice", instructions, criteria };
    } else if (qType === "score") {
      if (!Array.isArray(rawQ.criteria) || !rawQ.criteria.every((c) => typeof c === "string")) {
        throw new ProxyValidationError(
          `Score question '${name}' must include a 'criteria' string array.`
        );
      }
      sanitizedQuestions[name] = {
        type: "score",
        instructions,
        criteria: rawQ.criteria as string[],
      };
    } else {
      throw new ProxyValidationError(
        `Question '${name}' has unsupported primitive type '${String(qType)}' (expected 'noul', 'choice', or 'score').`
      );
    }
  }

  const normalizedImages = parseNormalizedImages(images);
  const resolvedModel =
    typeof model === "string" && model.trim().length > 0 ? model.trim() : defaultModel;

  const canonicalRequest: SystemOneRequest = {
    state,
    model: resolvedModel,
    questions: sanitizedQuestions,
    ...(normalizedImages.length > 0 ? { images: normalizedImages.map((img) => img.dataURL) } : {}),
  };

  return { request: canonicalRequest, normalizedImages };
}

/**
 * Validates and sanitizes a native `OpenAIDecisionsRequest` (Pattern A passthrough).
 * Inspects every multimodal content block to forbid remote `http(s)://` `image_url` SSRF,
 * `file_id` references, unknown block types, > 4 images, invalid base64, or > 13 MiB decoded bytes.
 */
export function validateNativeOpenAIRequest(
  body: unknown,
  defaultModel = "gpt-6-luna"
): OpenAIDecisionsRequest {
  if (!isPlainObject(body)) {
    throw new ProxyValidationError("OpenAI Decisions payload must be a JSON object.");
  }

  const { model, input, questions } = body;
  let sanitizedInput: string | OpenAIMessage[];

  if (typeof input === "string") {
    if (input.trim().length === 0) {
      throw new ProxyValidationError(
        "Bad Request: OpenAI Decisions 'input' string must not be empty."
      );
    }
    sanitizedInput = input;
  } else if (Array.isArray(input) && input.length > 0) {
    let totalImages = 0;
    let totalDecodedImageBytes = 0;
    const sanitizedMessages: OpenAIMessage[] = [];

    for (const msg of input) {
      if (
        !isPlainObject(msg) ||
        typeof msg.role !== "string" ||
        msg.role.trim().length === 0 ||
        !Array.isArray(msg.content) ||
        msg.content.length === 0
      ) {
        throw new ProxyValidationError(
          "Bad Request: Each OpenAI multimodal message must include a non-empty 'role' and non-empty 'content' array."
        );
      }

      const sanitizedBlocks: OpenAIContentBlock[] = [];
      for (const block of msg.content) {
        if (!isPlainObject(block)) {
          throw new ProxyValidationError("OpenAI message content block must be a JSON object.");
        }
        if ("file_id" in block) {
          throw new ProxyValidationError(
            "OpenAI 'file_id' attachments are prohibited; pass inline base64 data URLs."
          );
        }

        if (block.type === "input_text") {
          if (typeof block.text !== "string" || block.text.trim().length === 0) {
            throw new ProxyValidationError(
              "OpenAI 'input_text' block requires a non-empty 'text' string."
            );
          }
          sanitizedBlocks.push({ type: "input_text", text: block.text });
        } else if (block.type === "input_image") {
          if (typeof block.image_url !== "string" || block.image_url.trim().length === 0) {
            throw new ProxyValidationError(
              "OpenAI 'input_image' block requires an inline base64 'image_url' data URL string."
            );
          }
          const img = parseDataUrlImage(block.image_url);
          totalImages += 1;
          if (totalImages > MAX_IMAGE_ATTACHMENTS) {
            throw new ProxyValidationError(
              `OpenAI multimodal input exceeds maximum allowed ${MAX_IMAGE_ATTACHMENTS} images.`
            );
          }
          totalDecodedImageBytes += img.decodedByteLength;
          if (totalDecodedImageBytes > MAX_IMAGE_PAYLOAD_BYTES) {
            throw new ProxyValidationError(
              `OpenAI multimodal image bytes exceed maximum allowed ${MAX_IMAGE_PAYLOAD_BYTES} bytes (13 MiB).`
            );
          }
          sanitizedBlocks.push({ type: "input_image", image_url: img.dataURL });
        } else {
          throw new ProxyValidationError(
            `Unsupported OpenAI content block type '${String(block.type)}' (expected 'input_text' or 'input_image').`
          );
        }
      }

      sanitizedMessages.push({
        role: msg.role.trim(),
        content: sanitizedBlocks,
      });
    }

    sanitizedInput = sanitizedMessages;
  } else {
    throw new ProxyValidationError(
      "Bad Request: OpenAI Decisions payload must include a non-empty 'input' string or message array."
    );
  }

  if (!Array.isArray(questions) || questions.length === 0) {
    throw new ProxyValidationError(
      "Bad Request: OpenAI Decisions payload must include a non-empty 'questions' array."
    );
  }

  const sanitizedQuestions: OpenAIDecisionsQuestion[] = [];
  for (const q of questions) {
    if (!isPlainObject(q)) {
      throw new ProxyValidationError("Each OpenAI question must be a JSON object.");
    }
    if (typeof q.name !== "string" || q.name.trim().length === 0) {
      throw new ProxyValidationError("Each OpenAI question must have a non-empty 'name'.");
    }
    if (q.type !== "predicate" && q.type !== "choice" && q.type !== "score") {
      throw new ProxyValidationError(
        `OpenAI question '${q.name}' has invalid type '${String(q.type)}' (expected 'predicate', 'choice', or 'score').`
      );
    }
    if (typeof q.instructions !== "string" || q.instructions.trim().length === 0) {
      throw new ProxyValidationError(
        `OpenAI question '${q.name}' must have non-empty 'instructions'.`
      );
    }
    const cleanQ: OpenAIDecisionsQuestion = {
      type: q.type,
      name: q.name,
      instructions: q.instructions,
      ...(Array.isArray(q.choices) ? { choices: q.choices as OpenAIChoiceItem[] } : {}),
      ...(Array.isArray(q.levels) ? { levels: q.levels as OpenAILevelItem[] } : {}),
    };
    sanitizedQuestions.push(cleanQ);
  }

  const resolvedModel =
    typeof model === "string" && model.trim().length > 0 ? model.trim() : defaultModel;

  return {
    model: resolvedModel,
    input: sanitizedInput,
    questions: sanitizedQuestions,
  };
}

/**
 * Validates and sanitizes a native `GeminiDecisionsRequest` (Pattern A passthrough).
 * Inspects every multimodal item to forbid `file_data` / `file_uri` references, unknown item
 * shapes, > 4 images, invalid base64, or > 13 MiB total decoded image bytes.
 */
export function validateNativeGeminiRequest(
  body: unknown,
  defaultModel = "gemini-decision-1"
): GeminiDecisionsRequest {
  if (!isPlainObject(body)) {
    throw new ProxyValidationError("Gemini Decisions payload must be a JSON object.");
  }

  const { model, input, questions } = body;
  let sanitizedInput: string | GeminiContentItem[];

  if (typeof input === "string") {
    if (input.trim().length === 0) {
      throw new ProxyValidationError(
        "Bad Request: Gemini Decisions 'input' string must not be empty."
      );
    }
    sanitizedInput = input;
  } else if (Array.isArray(input) && input.length > 0) {
    let totalImages = 0;
    let totalDecodedImageBytes = 0;
    const sanitizedItems: GeminiContentItem[] = [];

    for (const item of input) {
      if (!isPlainObject(item)) {
        throw new ProxyValidationError("Gemini multimodal input item must be a JSON object.");
      }
      if (
        "file_data" in item ||
        "file_uri" in item ||
        "fileData" in item ||
        "fileUri" in item ||
        "image_url" in item
      ) {
        throw new ProxyValidationError(
          "Gemini 'file_data' / 'file_uri' / remote image URLs are prohibited; pass inline base64 image data."
        );
      }

      if (item.type === "text") {
        if (typeof item.text !== "string" || item.text.trim().length === 0) {
          throw new ProxyValidationError(
            "Gemini 'text' content item requires a non-empty 'text' string."
          );
        }
        sanitizedItems.push({ type: "text", text: item.text });
      } else if (item.type === "image") {
        let rawMime: unknown;
        let rawData: unknown;
        if (typeof item.data === "string") {
          rawMime = item.mime_type;
          rawData = item.data;
        } else if (isPlainObject(item.inline_data)) {
          rawMime = item.inline_data.mime_type;
          rawData = item.inline_data.data;
        }
        if (typeof rawMime !== "string" || typeof rawData !== "string") {
          throw new ProxyValidationError(
            "Gemini 'image' content item requires 'mime_type' and inline base64 'data'."
          );
        }
        const img = validateInlineBase64Image(rawMime, rawData);
        totalImages += 1;
        if (totalImages > MAX_IMAGE_ATTACHMENTS) {
          throw new ProxyValidationError(
            `Gemini multimodal input exceeds maximum allowed ${MAX_IMAGE_ATTACHMENTS} images.`
          );
        }
        totalDecodedImageBytes += img.decodedByteLength;
        if (totalDecodedImageBytes > MAX_IMAGE_PAYLOAD_BYTES) {
          throw new ProxyValidationError(
            `Gemini multimodal image bytes exceed maximum allowed ${MAX_IMAGE_PAYLOAD_BYTES} bytes (13 MiB).`
          );
        }
        sanitizedItems.push({
          type: "image",
          mime_type: img.mimeType,
          data: img.base64Data,
        });
      } else if (item.type === undefined && typeof item.text === "string" && !("inline_data" in item)) {
        if (item.text.trim().length === 0) {
          throw new ProxyValidationError("Gemini text part must not be empty.");
        }
        sanitizedItems.push({ text: item.text });
      } else if (
        item.type === undefined &&
        isPlainObject(item.inline_data) &&
        !("text" in item)
      ) {
        if (
          typeof item.inline_data.mime_type !== "string" ||
          typeof item.inline_data.data !== "string"
        ) {
          throw new ProxyValidationError(
            "Gemini 'inline_data' part requires 'mime_type' and inline base64 'data'."
          );
        }
        const img = validateInlineBase64Image(item.inline_data.mime_type, item.inline_data.data);
        totalImages += 1;
        if (totalImages > MAX_IMAGE_ATTACHMENTS) {
          throw new ProxyValidationError(
            `Gemini multimodal input exceeds maximum allowed ${MAX_IMAGE_ATTACHMENTS} images.`
          );
        }
        totalDecodedImageBytes += img.decodedByteLength;
        if (totalDecodedImageBytes > MAX_IMAGE_PAYLOAD_BYTES) {
          throw new ProxyValidationError(
            `Gemini multimodal image bytes exceed maximum allowed ${MAX_IMAGE_PAYLOAD_BYTES} bytes (13 MiB).`
          );
        }
        sanitizedItems.push({
          inline_data: {
            mime_type: img.mimeType,
            data: img.base64Data,
          },
        });
      } else {
        throw new ProxyValidationError(
          `Unsupported Gemini multimodal content item (expected 'text' or inline base64 'image').`
        );
      }
    }

    sanitizedInput = sanitizedItems;
  } else {
    throw new ProxyValidationError(
      "Bad Request: Gemini Decisions payload must include a non-empty 'input' string or content item array."
    );
  }

  if (!isPlainObject(questions)) {
    throw new ProxyValidationError(
      "Bad Request: Gemini Decisions payload must include a non-empty 'questions' object."
    );
  }
  const questionCount = Object.keys(questions).length;
  if (questionCount < 1 || questionCount > 1000) {
    throw new ProxyValidationError(
      `Gemini Decisions API requires between 1 and 1,000 questions per request (got ${questionCount}).`
    );
  }

  const sanitizedQuestions: Record<string, GeminiDecisionsQuestion> = {};
  for (const [name, q] of Object.entries(questions)) {
    if (!name || !isPlainObject(q)) {
      throw new ProxyValidationError(`Invalid Gemini question '${name}'.`);
    }
    if (q.type !== "noul" && q.type !== "choice" && q.type !== "score") {
      throw new ProxyValidationError(
        `Gemini question '${name}' has invalid type '${String(q.type)}' (expected 'noul', 'choice', or 'score').`
      );
    }
    if (typeof q.instructions !== "string" || q.instructions.trim().length === 0) {
      throw new ProxyValidationError(
        `Gemini question '${name}' must have non-empty 'instructions'.`
      );
    }

    let criteria: Record<string, string> | string[] | undefined;
    if (Array.isArray(q.criteria)) {
      criteria = q.criteria as string[];
    } else if (isPlainObject(q.criteria)) {
      criteria = q.criteria as Record<string, string>;
    } else if (Array.isArray(q.choices)) {
      criteria = Object.fromEntries((q.choices as string[]).map((c) => [c, c]));
    } else if (isPlainObject(q.choices)) {
      criteria = q.choices as Record<string, string>;
    } else if (Array.isArray(q.levels)) {
      criteria = q.levels as string[];
    }

    sanitizedQuestions[name] = {
      type: q.type,
      instructions: q.instructions,
      ...(criteria !== undefined ? { criteria } : {}),
    };
  }

  const resolvedModel =
    typeof model === "string" && model.trim().length > 0 ? model.trim() : defaultModel;

  return {
    model: resolvedModel,
    input: sanitizedInput,
    questions: sanitizedQuestions,
  };
}

// ============================================================================
// Pattern B: Canonical SystemOneRequest <-> OpenAI Decisions Adaptation
// ============================================================================

export function adaptSystemOneToOpenAIRequest(
  request: SystemOneRequest,
  normalizedImages: NormalizedImageAttachment[],
  defaultModel = "gpt-6-luna"
): OpenAIDecisionsRequest {
  const input: string | OpenAIMessage[] =
    normalizedImages.length > 0
      ? [
          {
            role: "user",
            content: [
              { type: "input_text", text: request.state },
              ...normalizedImages.map(
                (img): OpenAIContentBlock => ({
                  type: "input_image",
                  image_url: img.dataURL,
                })
              ),
            ],
          },
        ]
      : request.state;

  const openAIQuestions: OpenAIDecisionsQuestion[] = [];
  for (const name of Object.keys(request.questions).sort()) {
    const q = request.questions[name];
    if (q.type === "noul") {
      openAIQuestions.push({
        type: "predicate",
        name,
        instructions: q.instructions,
      });
    } else if (q.type === "choice") {
      const choices: OpenAIChoiceItem[] = Object.keys(q.criteria)
        .sort()
        .map((key) => ({
          value: key,
          description: q.criteria[key],
        }));
      openAIQuestions.push({
        type: "choice",
        name,
        instructions: q.instructions,
        choices,
      });
    } else {
      const levels: OpenAILevelItem[] =
        q.criteria.length > 0
          ? q.criteria.map((c) => ({ label: c, description: c }))
          : [1, 2, 3, 4, 5].map((n) => ({
              label: `Level ${n}`,
              description: `Rating score ${n}`,
            }));
      openAIQuestions.push({
        type: "score",
        name,
        instructions: q.instructions,
        levels,
      });
    }
  }

  const model =
    !request.model || request.model === "systemone-default" ? defaultModel : request.model;

  return {
    model,
    input,
    questions: openAIQuestions,
  };
}

interface NormalizedProbabilityEntry {
  key: string;
  probability: number;
  label?: string;
}

function normalizeProbabilityList(raw: unknown): NormalizedProbabilityEntry[] | undefined {
  if (Array.isArray(raw)) {
    const out: NormalizedProbabilityEntry[] = [];
    for (const entry of raw) {
      if (isPlainObject(entry) && typeof entry.probability === "number" && Number.isFinite(entry.probability)) {
        const rawKey = entry.value ?? entry.choice ?? entry.key;
        if (typeof rawKey === "string" || typeof rawKey === "number" || typeof rawKey === "boolean") {
          out.push({
            key: String(rawKey),
            probability: entry.probability,
            ...(typeof entry.label === "string" ? { label: entry.label } : {}),
          });
        }
      }
    }
    return out;
  }
  if (isPlainObject(raw)) {
    const out: NormalizedProbabilityEntry[] = [];
    for (const key of Object.keys(raw).sort()) {
      const val = raw[key];
      if (typeof val === "number" && Number.isFinite(val)) {
        out.push({ key, probability: val });
      }
    }
    return out;
  }
  return undefined;
}

export function adaptOpenAIToSystemOneResponse(
  rawResponse: unknown,
  expectedQuestionNames?: Iterable<string>
): SystemOneResponse {
  if (!isPlainObject(rawResponse)) {
    throw new ProxyValidationError("Invalid OpenAI Decisions response: expected JSON object.", 502);
  }

  const rawAnswers = rawResponse.answers;
  if (!Array.isArray(rawAnswers) || rawAnswers.length === 0) {
    throw new ProxyValidationError(
      "Missing answers in OpenAI Decisions response: answers array is empty.",
      502
    );
  }

  const answers: Record<string, SystemOneAnswer> = {};

  for (const ans of rawAnswers) {
    if (!isPlainObject(ans) || typeof ans.name !== "string" || ans.name.length === 0) {
      throw new ProxyValidationError("Malformed answer item in OpenAI Decisions response.", 502);
    }

    const name = ans.name;
    if (ans.type === "refusal" || (ans.refusal !== undefined && ans.refusal !== null)) {
      const reason =
        typeof ans.refusal === "string" && ans.refusal.length > 0
          ? ans.refusal
          : "Content blocked by safety policy";
      throw new ProxySafetyRefusalError(name, reason);
    }

    const probEntries = normalizeProbabilityList(ans.probabilities);
    const confidence =
      typeof ans.confidence === "number" && Number.isFinite(ans.confidence)
        ? ans.confidence
        : undefined;

    if (typeof ans.probability === "number" && Number.isFinite(ans.probability)) {
      const prob = ans.probability;
      const conf = confidence ?? Math.max(prob, 1.0 - prob);
      const probsDict: Record<string, number> = {
        true: prob,
        false: Math.max(0.0, 1.0 - prob),
      };
      if (probEntries) {
        for (const entry of probEntries) {
          probsDict[entry.key] = entry.probability;
        }
      }
      answers[name] = {
        type: "noul",
        noul: prob,
        confidence: conf,
        probabilities: probsDict,
      };
    } else if (
      typeof ans.choice === "string" ||
      typeof ans.choice === "number" ||
      typeof ans.choice === "boolean"
    ) {
      const choice = String(ans.choice);
      let probsDict: Record<string, number> | undefined;
      if (probEntries) {
        probsDict = {};
        for (const entry of probEntries) {
          if (!(entry.key in probsDict)) {
            probsDict[entry.key] = entry.probability;
          }
        }
      }
      const conf = confidence ?? probsDict?.[choice] ?? 1.0;
      answers[name] = {
        type: "choice",
        choice,
        confidence: conf,
        ...(probsDict ? { probabilities: probsDict } : {}),
      };
    } else if (typeof ans.score === "number" && Number.isFinite(ans.score)) {
      let probsDict: Record<string, number> | undefined;
      let legendDict: Record<string, string> | undefined;
      if (probEntries) {
        probsDict = {};
        const extractedLegend: Record<string, string> = {};
        for (const entry of probEntries) {
          if (!(entry.key in probsDict)) {
            probsDict[entry.key] = entry.probability;
          }
          if (entry.label !== undefined && !(entry.key in extractedLegend)) {
            extractedLegend[entry.key] = entry.label;
          }
        }
        if (Object.keys(extractedLegend).length > 0) {
          legendDict = extractedLegend;
        }
      }
      answers[name] = {
        type: "score",
        score: ans.score,
        confidence: confidence ?? 1.0,
        ...(probsDict ? { probabilities: probsDict } : {}),
        ...(legendDict ? { legend: legendDict } : {}),
      };
    } else {
      throw new ProxyValidationError(
        `Unrecognized OpenAI Decisions answer shape for question '${name}'.`,
        502
      );
    }
  }

  if (expectedQuestionNames) {
    for (const expected of Array.from(expectedQuestionNames).sort()) {
      if (!(expected in answers)) {
        throw new ProxyValidationError(
          `Missing answer for expected question '${expected}' in OpenAI Decisions response.`,
          502
        );
      }
    }
  }

  const rawUsage = isPlainObject(rawResponse.usage) ? rawResponse.usage : undefined;
  const usage: SystemOneUsage = {
    input_tokens: typeof rawUsage?.input_tokens === "number" ? rawUsage.input_tokens : 0,
    output_tokens: typeof rawUsage?.output_tokens === "number" ? rawUsage.output_tokens : 0,
  };

  const model =
    typeof rawResponse.model === "string" && rawResponse.model.length > 0
      ? rawResponse.model
      : "gpt-6-luna";

  return { model, answers, usage };
}

// ============================================================================
// Pattern B: Canonical SystemOneRequest <-> Gemini Decisions Adaptation
// ============================================================================

export function adaptSystemOneToGeminiRequest(
  request: SystemOneRequest,
  normalizedImages: NormalizedImageAttachment[],
  defaultModel = "gemini-decision-1"
): GeminiDecisionsRequest {
  const questionNames = Object.keys(request.questions);
  if (questionNames.length < 1 || questionNames.length > 1000) {
    throw new ProxyValidationError(
      `Gemini Decisions API requires between 1 and 1,000 questions per request (got ${questionNames.length}).`
    );
  }

  const input: string | GeminiContentItem[] =
    normalizedImages.length > 0
      ? [
          { type: "text", text: request.state },
          ...normalizedImages.map(
            (img): GeminiContentItem => ({
              type: "image",
              mime_type: img.mimeType,
              data: img.base64Data,
            })
          ),
        ]
      : request.state;

  const geminiQuestions: Record<string, GeminiDecisionsQuestion> = {};
  for (const [name, q] of Object.entries(request.questions)) {
    if (q.type === "noul") {
      geminiQuestions[name] = {
        type: "noul",
        instructions: q.instructions,
      };
    } else if (q.type === "choice") {
      geminiQuestions[name] = {
        type: "choice",
        instructions: q.instructions,
        criteria: q.criteria,
      };
    } else {
      const levels =
        q.criteria.length > 0
          ? q.criteria
          : [1, 2, 3, 4, 5].map((n) => `Level ${n}: Rating score ${n}`);
      geminiQuestions[name] = {
        type: "score",
        instructions: q.instructions,
        criteria: levels,
      };
    }
  }

  const model =
    !request.model || request.model === "systemone-default" ? defaultModel : request.model;

  return {
    model,
    input,
    questions: geminiQuestions,
  };
}

function validateUnitInterval(value: number, field: string, questionName: string): number {
  if (
    !Number.isFinite(value) ||
    value < -UNIT_INTERVAL_TOLERANCE ||
    value > 1.0 + UNIT_INTERVAL_TOLERANCE
  ) {
    throw new ProxyValidationError(
      `Invalid ${field} ${value} for question '${questionName}'; expected finite value in 0.0...1.0.`,
      502
    );
  }
  return Math.min(Math.max(value, 0.0), 1.0);
}

export function adaptGeminiToSystemOneResponse(
  rawResponse: unknown,
  expectedQuestionNames?: Iterable<string>
): SystemOneResponse {
  if (!isPlainObject(rawResponse)) {
    throw new ProxyValidationError("Invalid Gemini Decisions response: expected JSON object.", 502);
  }

  const rawAnswers = rawResponse.answers;
  if (!isPlainObject(rawAnswers) || Object.keys(rawAnswers).length === 0) {
    throw new ProxyValidationError(
      "Missing answers in Gemini Decisions response: answers dictionary is empty.",
      502
    );
  }

  const answers: Record<string, SystemOneAnswer> = {};

  for (const [name, ans] of Object.entries(rawAnswers)) {
    if (!isPlainObject(ans)) {
      throw new ProxyValidationError(`Malformed Gemini answer for question '${name}'.`, 502);
    }

    if (ans.type === "refusal" || (ans.refusal !== undefined && ans.refusal !== null)) {
      const reason =
        typeof ans.refusal === "string" && ans.refusal.length > 0
          ? ans.refusal
          : "Content blocked by Google Gemini safety policy";
      throw new ProxySafetyRefusalError(name, reason);
    }

    const explicitConfidence =
      typeof ans.confidence === "number"
        ? validateUnitInterval(ans.confidence, "confidence", name)
        : undefined;

    // Normalize legend from Record<string, string> or string[]
    let legend: Record<string, string> | undefined;
    if (isPlainObject(ans.legend)) {
      legend = {};
      for (const [k, v] of Object.entries(ans.legend)) {
        if (typeof v === "string") {
          legend[k] = v;
        }
      }
    } else if (Array.isArray(ans.legend) && ans.legend.every((item) => typeof item === "string")) {
      legend = Object.fromEntries((ans.legend as string[]).map((val, idx) => [String(idx), val]));
    }

    // Normalize probabilities from Record<string, number>, ProbabilityItem[], or number[]
    let sanitizedProbabilities: Record<string, number> | undefined;
    if (Array.isArray(ans.probabilities) && ans.probabilities.every((n) => typeof n === "number")) {
      sanitizedProbabilities = {};
      for (const [idx, val] of (ans.probabilities as number[]).entries()) {
        sanitizedProbabilities[String(idx)] = validateUnitInterval(
          val,
          `probability[${idx}]`,
          name
        );
      }
    } else {
      const probEntries = normalizeProbabilityList(ans.probabilities);
      if (probEntries) {
        sanitizedProbabilities = {};
        const extractedLegend: Record<string, string> = {};
        for (const entry of probEntries) {
          if (!(entry.key in sanitizedProbabilities)) {
            sanitizedProbabilities[entry.key] = validateUnitInterval(
              entry.probability,
              `probability[${entry.key}]`,
              name
            );
          }
          if (entry.label !== undefined && !(entry.key in extractedLegend)) {
            extractedLegend[entry.key] = entry.label;
          }
        }
        if (!legend && Object.keys(extractedLegend).length > 0) {
          legend = extractedLegend;
        }
      }
    }

    const rawProb = typeof ans.noul === "number" ? ans.noul : ans.probability;
    const rawChoice = ans.choice !== undefined && ans.choice !== null ? ans.choice : ans.selected;

    if (typeof rawProb === "number") {
      const clampedProb = validateUnitInterval(rawProb, "noul probability", name);
      const conf = explicitConfidence ?? Math.max(clampedProb, 1.0 - clampedProb);
      const probsDict: Record<string, number> = {
        true: clampedProb,
        false: Math.max(0.0, 1.0 - clampedProb),
        ...(sanitizedProbabilities ?? {}),
      };
      answers[name] = {
        type: "noul",
        noul: clampedProb,
        confidence: conf,
        probabilities: probsDict,
      };
    } else if (
      typeof rawChoice === "string" ||
      typeof rawChoice === "number" ||
      typeof rawChoice === "boolean"
    ) {
      const choice = String(rawChoice);
      const conf = explicitConfidence ?? sanitizedProbabilities?.[choice] ?? 1.0;
      answers[name] = {
        type: "choice",
        choice,
        confidence: conf,
        ...(sanitizedProbabilities ? { probabilities: sanitizedProbabilities } : {}),
      };
    } else if (typeof ans.score === "number" && Number.isFinite(ans.score)) {
      answers[name] = {
        type: "score",
        score: ans.score,
        confidence: explicitConfidence ?? 1.0,
        ...(sanitizedProbabilities ? { probabilities: sanitizedProbabilities } : {}),
        ...(legend ? { legend } : {}),
      };
    } else {
      throw new ProxyValidationError(
        `Unrecognized Gemini Decisions answer shape for question '${name}'.`,
        502
      );
    }
  }

  if (expectedQuestionNames) {
    for (const expected of Array.from(expectedQuestionNames).sort()) {
      if (!(expected in answers)) {
        throw new ProxyValidationError(
          `Missing answer for expected question '${expected}' in Gemini Decisions response.`,
          502
        );
      }
    }
  }

  let inputTokens = 0;
  let outputTokens = 0;
  if (isPlainObject(rawResponse.usage)) {
    const u = rawResponse.usage;
    inputTokens =
      typeof u.input_tokens === "number"
        ? u.input_tokens
        : typeof u.total_input_tokens === "number"
          ? u.total_input_tokens
          : typeof u.promptTokenCount === "number"
            ? u.promptTokenCount
            : typeof u.total_tokens === "number"
              ? u.total_tokens
              : 0;
    outputTokens =
      typeof u.output_tokens === "number"
        ? u.output_tokens
        : typeof u.total_output_tokens === "number"
          ? u.total_output_tokens
          : typeof u.candidatesTokenCount === "number"
            ? u.candidatesTokenCount
            : 0;
  } else if (isPlainObject(rawResponse.usageMetadata)) {
    const meta = rawResponse.usageMetadata;
    inputTokens = typeof meta.promptTokenCount === "number" ? meta.promptTokenCount : 0;
    outputTokens = typeof meta.candidatesTokenCount === "number" ? meta.candidatesTokenCount : 0;
  }

  const model =
    typeof rawResponse.model === "string" && rawResponse.model.length > 0
      ? rawResponse.model
      : typeof rawResponse.modelVersion === "string" && rawResponse.modelVersion.length > 0
        ? rawResponse.modelVersion
        : "gemini-decision-1";

  return {
    model,
    answers,
    usage: {
      input_tokens: inputTokens,
      output_tokens: outputTokens,
    },
  };
}

// ============================================================================
// Cloudflare Workers AI v4 Envelope Unwrapping (`Clef`)
// ============================================================================

/**
 * Unwraps Cloudflare Workers AI `{ success: true, result: SystemOneResponse }` envelopes
 * into direct `SystemOneResponse` JSON so both `ClefHTTPBackend` (Pattern A) and
 * `SystemOneProxyBackend` (Pattern B) decode responses natively.
 */
export function unwrapCloudflareClefResponse(rawText: string): {
  ok: boolean;
  bodyText: string;
  errorMessage?: string;
} {
  let parsed: unknown;
  try {
    parsed = JSON.parse(rawText);
  } catch {
    return { ok: true, bodyText: rawText };
  }

  if (!isPlainObject(parsed) || typeof parsed.success !== "boolean") {
    return { ok: true, bodyText: rawText };
  }

  if (parsed.success === false) {
    let errorMessage = "Cloudflare Workers AI request failed.";
    if (Array.isArray(parsed.errors) && parsed.errors.length > 0 && isPlainObject(parsed.errors[0])) {
      if (typeof parsed.errors[0].message === "string" && parsed.errors[0].message.length > 0) {
        errorMessage = parsed.errors[0].message;
      }
    }
    return { ok: false, bodyText: JSON.stringify({ error: errorMessage }), errorMessage };
  }

  if (isPlainObject(parsed.result)) {
    return { ok: true, bodyText: JSON.stringify(parsed.result) };
  }

  return { ok: true, bodyText: rawText };
}
