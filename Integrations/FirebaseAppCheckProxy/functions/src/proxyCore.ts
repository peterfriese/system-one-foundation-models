/**
 * SSRF-safe multi-provider router, credential injector, and HTTP execution core
 * for the System One Firebase App Check Reverse Proxy.
 *
 * Pure and dependency-injected so unit tests can exercise every routing, security,
 * and wire-adaptation branch deterministically via `node --test`.
 */

import {
  ProviderId,
  ProxySafetyRefusalError,
  ProxyValidationError,
  adaptGeminiToSystemOneResponse,
  adaptOpenAIToSystemOneResponse,
  adaptSystemOneToGeminiRequest,
  adaptSystemOneToOpenAIRequest,
  isCanonicalSystemOnePayload,
  isPlainObject,
  isSupportedProvider,
  unwrapCloudflareClefResponse,
  validateCanonicalSystemOneRequest,
  validateNativeGeminiRequest,
  validateNativeOpenAIRequest,
} from "./adapters";

export const FORWARDED_UPSTREAM_HEADERS = [
  "Retry-After",
  "server-timing",
  "x-envoy-upstream-service-time",
  "openai-processing-ms",
  "x-goog-processing-ms",
  "x-inference-time-ms",
] as const;

const FUNCTION_MOUNT_PREFIXES = new Set(["systemone", "jevproxy"]);

const ALLOWLISTED_CLEF_WORKERS_MODELS: Readonly<
  Record<string, { workersModelId: string; bodyModelSlug: "clef" | "clef-flash" }>
> = Object.freeze(
  Object.assign(Object.create(null) as Record<
    string,
    { workersModelId: string; bodyModelSlug: "clef" | "clef-flash" }
  >, {
    "clef-flash": { workersModelId: "@cf/cloudflare/clef-flash", bodyModelSlug: "clef-flash" },
    clef: { workersModelId: "@cf/cloudflare/clef", bodyModelSlug: "clef" },
    "@cf/cloudflare/clef-flash": {
      workersModelId: "@cf/cloudflare/clef-flash",
      bodyModelSlug: "clef-flash",
    },
    "@cf/cloudflare/clef": { workersModelId: "@cf/cloudflare/clef", bodyModelSlug: "clef" },
    "@cf/typesafe/clef-flash": {
      workersModelId: "@cf/typesafe/clef-flash",
      bodyModelSlug: "clef-flash",
    },
    "@cf/typesafe/clef": { workersModelId: "@cf/typesafe/clef", bodyModelSlug: "clef" },
  })
);

const BLOCKED_METADATA_HOSTS = new Set([
  "169.254.169.254",
  "metadata.google.internal",
  "metadata",
  "100.100.100.200",
]);

const LOOPBACK_HOSTS = new Set(["localhost", "127.0.0.1", "::1", "[::1]"]);

export interface ProxyHttpRequest {
  method: string;
  path?: string;
  url?: string;
  body?: unknown;
  header(name: string): string | undefined;
}

export interface ProxyHttpResponse {
  status(code: number): ProxyHttpResponse;
  setHeader(name: string, value: string): unknown;
  json(body: unknown): unknown;
  send(body: string): unknown;
}

export interface AppCheckVerificationResult {
  appId?: string;
  alreadyConsumed?: boolean;
}

export interface ProxyDependencies {
  verifyAppCheckToken: (
    token: string,
    options?: { consume?: boolean }
  ) => Promise<AppCheckVerificationResult>;
  fetchImpl?: typeof fetch;
  env?: NodeJS.ProcessEnv;
  timeoutMs?: number;
  logger?: Pick<Console, "warn" | "error" | "info">;
}

export interface ResolvedUpstreamConfig {
  provider: ProviderId;
  url: string;
  headers: Record<string, string>;
  secretsToRedact: string[];
}

class ProxyConfigurationError extends Error {
  public readonly remediation: string;

  constructor(message: string, remediation: string) {
    super(message);
    this.name = "ProxyConfigurationError";
    this.remediation = remediation;
  }
}

function hasHeaderControlChars(value: string): boolean {
  return /[\r\n\0]/.test(value);
}

function isNonPlaceholderSecret(value: string | undefined): value is string {
  if (!value) {
    return false;
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return false;
  }
  const lower = trimmed.toLowerCase();
  return lower !== "mock" && lower !== "mock-key" && !hasHeaderControlChars(trimmed);
}

/**
 * Validates server-configured upstream URLs to eliminate SSRF and cleartext leakage:
 * - Remote endpoints MUST use `https:`.
 * - `http:` is permitted strictly for loopback (`localhost`, `127.0.0.1`, `::1`, `[::1]`)
 *   during local emulator / unit test execution.
 * - Cloud metadata hosts (`169.254.169.254`, `metadata.google.internal`) and URLs with
 *   embedded credentials are unconditionally rejected.
 */
export function validateSafeUpstreamUrl(rawUrl: string, label: string): string {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new ProxyConfigurationError(
      `Invalid upstream URL configured for ${label}.`,
      `Configure a valid HTTPS URL for ${label}.`
    );
  }

  if (parsed.username !== "" || parsed.password !== "") {
    throw new ProxyConfigurationError(
      `Upstream URL for ${label} must not embed credentials.`,
      `Pass credentials via environment secrets rather than URL userinfo.`
    );
  }

  const host = parsed.hostname.toLowerCase();
  if (!host || BLOCKED_METADATA_HOSTS.has(host)) {
    throw new ProxyConfigurationError(
      `Blocked or empty upstream host configured for ${label}.`,
      `Configure an allowlisted HTTPS provider endpoint for ${label}.`
    );
  }

  if (parsed.protocol === "https:") {
    return parsed.toString();
  }

  if (parsed.protocol === "http:" && LOOPBACK_HOSTS.has(host)) {
    return parsed.toString();
  }

  throw new ProxyConfigurationError(
    `Insecure upstream scheme '${parsed.protocol}' for ${label}: remote upstreams require HTTPS.`,
    `Use https:// for remote upstreams (http:// is permitted only on localhost/127.0.0.1 for local emulators).`
  );
}

function validateSafeCloudflareSlug(value: string, label: string): string {
  const trimmed = value.trim();
  if (!/^[a-zA-Z0-9_-]+$/.test(trimmed)) {
    throw new ProxyConfigurationError(
      `Invalid ${label} configuration.`,
      `Set ${label} to an alphanumeric Cloudflare identifier without slashes or query characters.`
    );
  }
  return trimmed;
}

/**
 * Resolves and validates Clef's decoupled identifiers (see tech-notes/0014-cloudflare-workers-ai-model-schema-nuance.md):
 * - `workersModelId` (`@cf/cloudflare/clef` or `@cf/cloudflare/clef-flash`) for Cloudflare edge URL paths.
 * - `bodyModelSlug` (`clef` or `clef-flash`) for `/model` in the outbound JSON body (`^\s*(clef|clef-flash)\s*$`).
 * Uses `Object.hasOwn` on a prototype-less lookup table so prototype keys (`constructor`, `toString`) cannot bypass the allowlist.
 */
export function resolveClefModelIdentifiers(
  requestedModel: string | undefined,
  envModel: string | undefined
): { workersModelId: string; bodyModelSlug: "clef" | "clef-flash" } {
  const candidate = (
    requestedModel && requestedModel !== "systemone-default"
      ? requestedModel
      : envModel || "clef-flash"
  )
    .trim()
    .toLowerCase();

  if (!Object.hasOwn(ALLOWLISTED_CLEF_WORKERS_MODELS, candidate)) {
    throw new ProxyValidationError(
      `Unsupported Clef model '${requestedModel ?? envModel}'. Allowed models: clef-flash, clef, @cf/cloudflare/clef-flash, @cf/cloudflare/clef.`
    );
  }
  return ALLOWLISTED_CLEF_WORKERS_MODELS[candidate];
}

/**
 * Resolves the target System One provider in strict priority order:
 * 1. Path segment suffix on `req.path` (`/jev`, `/laya`, `/clef`, `/openai`, `/gemini`).
 *    Rejects unknown or multi-segment path suffixes with `400`.
 * 2. `X-SystemOne-Provider` header. Rejects unknown header values with `400`.
 * 3. Payload shape / `model` prefix auto-detection.
 * 4. `env.DEFAULT_PROVIDER` (defaulting to `"jev"`).
 */
export function resolveTargetProvider(
  rawPath: string | undefined,
  providerHeader: string | undefined,
  body: unknown,
  env: NodeJS.ProcessEnv
): ProviderId {
  // 1. Path suffix check
  const pathWithoutQuery = (rawPath ?? "").split("?")[0];
  if (pathWithoutQuery.includes("..")) {
    throw new ProxyValidationError("Invalid request path.");
  }
  const segments = pathWithoutQuery
    .split("/")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

  if (segments.length > 0) {
    let candidateSuffix: string | undefined;
    if (segments.length === 1) {
      const seg = segments[0].toLowerCase();
      if (!FUNCTION_MOUNT_PREFIXES.has(seg)) {
        candidateSuffix = seg;
      }
    } else if (segments.length === 2 && FUNCTION_MOUNT_PREFIXES.has(segments[0].toLowerCase())) {
      candidateSuffix = segments[1].toLowerCase();
    } else {
      throw new ProxyValidationError(
        `Unsupported path '${pathWithoutQuery}'. Expected /<jev|laya|clef|openai|gemini>.`
      );
    }

    if (candidateSuffix !== undefined) {
      if (!isSupportedProvider(candidateSuffix)) {
        throw new ProxyValidationError(
          `Unknown System One provider path '/${candidateSuffix}'. Supported providers: jev, laya, clef, openai, gemini.`
        );
      }
      return candidateSuffix;
    }
  }

  // 2. X-SystemOne-Provider header check
  if (providerHeader !== undefined && providerHeader.trim().length > 0) {
    const normalizedHeader = providerHeader.trim().toLowerCase();
    if (!isSupportedProvider(normalizedHeader)) {
      throw new ProxyValidationError(
        `Unknown X-SystemOne-Provider header '${providerHeader}'. Supported providers: jev, laya, clef, openai, gemini.`
      );
    }
    return normalizedHeader;
  }

  // 3. Payload shape / model auto-detection
  if (isPlainObject(body)) {
    const modelStr = typeof body.model === "string" ? body.model.trim().toLowerCase() : "";

    if (
      Array.isArray(body.questions) ||
      modelStr.startsWith("gpt-") ||
      modelStr.startsWith("openai")
    ) {
      return "openai";
    }
    if (
      (body.input !== undefined && !Array.isArray(body.questions)) ||
      modelStr.startsWith("gemini-")
    ) {
      return "gemini";
    }
    if (modelStr.startsWith("@cf/") || modelStr.startsWith("clef")) {
      return "clef";
    }
    if (modelStr.startsWith("laya")) {
      return "laya";
    }
    if (modelStr.startsWith("jev")) {
      return "jev";
    }
  }

  // 4. Server default provider (defaults to "jev" for 100% backward compatibility)
  const fallback = (env.DEFAULT_PROVIDER || "jev").trim().toLowerCase();
  if (!isSupportedProvider(fallback)) {
    throw new ProxyConfigurationError(
      `Invalid DEFAULT_PROVIDER '${env.DEFAULT_PROVIDER}'.`,
      "Set DEFAULT_PROVIDER to one of: jev, laya, clef, openai, gemini."
    );
  }
  return fallback;
}

/**
 * Resolves the allowlisted upstream endpoint URL and outbound authentication headers
 * for the selected provider using server-side environment variables ONLY.
 */
export function resolveProviderUpstream(
  provider: ProviderId,
  requestedModel: string | undefined,
  env: NodeJS.ProcessEnv
): ResolvedUpstreamConfig {
  switch (provider) {
    case "jev": {
      const apiKey = env.TYPESAFE_API_KEY;
      if (!isNonPlaceholderSecret(apiKey)) {
        throw new ProxyConfigurationError(
          "TYPESAFE_API_KEY is not configured on the proxy.",
          "Run `firebase functions:secrets:set TYPESAFE_API_KEY` (and include TYPESAFE_API_KEY in ENABLED_SECRETS) or export TYPESAFE_API_KEY in your local emulator environment."
        );
      }
      const trimmedKey = apiKey.trim();
      const rawUrl = env.TYPESAFE_ENDPOINT || "https://api.typesafe.ai/v1/systemone";
      const url = validateSafeUpstreamUrl(rawUrl, "TYPESAFE_ENDPOINT");
      return {
        provider,
        url,
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${trimmedKey}`,
        },
        secretsToRedact: [trimmedKey],
      };
    }

    case "laya": {
      const rawUrl = env.LAYA_UPSTREAM_URL || env.LAYA_SERVE_URL;
      if (!rawUrl || rawUrl.trim().length === 0) {
        throw new ProxyConfigurationError(
          "LAYA_UPSTREAM_URL is not configured on the proxy.",
          "Set LAYA_UPSTREAM_URL (e.g. https://laya.internal.example.com/v1/systemone or http://127.0.0.1:8080/v1/systemone in local emulator)."
        );
      }
      const url = validateSafeUpstreamUrl(rawUrl.trim(), "LAYA_UPSTREAM_URL");
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      const secretsToRedact: string[] = [];
      if (isNonPlaceholderSecret(env.LAYA_API_KEY)) {
        const key = env.LAYA_API_KEY.trim();
        headers.Authorization = `Bearer ${key}`;
        secretsToRedact.push(key);
      }
      return { provider, url, headers, secretsToRedact };
    }

    case "clef": {
      const { workersModelId } = resolveClefModelIdentifiers(requestedModel, env.CLEF_MODEL);
      let url: string;
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      const secretsToRedact: string[] = [];

      if (env.CLEF_UPSTREAM_URL && env.CLEF_UPSTREAM_URL.trim().length > 0) {
        url = validateSafeUpstreamUrl(env.CLEF_UPSTREAM_URL.trim(), "CLEF_UPSTREAM_URL");
      } else if (env.CLOUDFLARE_ACCOUNT_ID && env.CLOUDFLARE_ACCOUNT_ID.trim().length > 0) {
        const accountId = validateSafeCloudflareSlug(
          env.CLOUDFLARE_ACCOUNT_ID,
          "CLOUDFLARE_ACCOUNT_ID"
        );
        if (env.CLOUDFLARE_GATEWAY_ID && env.CLOUDFLARE_GATEWAY_ID.trim().length > 0) {
          const gatewayId = validateSafeCloudflareSlug(
            env.CLOUDFLARE_GATEWAY_ID,
            "CLOUDFLARE_GATEWAY_ID"
          );
          url = `https://gateway.ai.cloudflare.com/v1/${accountId}/${gatewayId}/workers-ai/${workersModelId}`;
          headers["cf-aig-metadata-app"] = "system-one-foundation-models";
          headers["cf-aig-metadata-tag"] = "clef-multimodal";
        } else {
          url = `https://api.cloudflare.com/client/v4/accounts/${accountId}/ai/run/${workersModelId}`;
        }
      } else {
        throw new ProxyConfigurationError(
          "Clef upstream is not configured on the proxy.",
          "Set CLEF_UPSTREAM_URL or CLOUDFLARE_ACCOUNT_ID (+ CLOUDFLARE_API_TOKEN) in your Cloud Function environment."
        );
      }

      const parsedUrl = new URL(url);
      const isLoopback = LOOPBACK_HOSTS.has(parsedUrl.hostname.toLowerCase());
      if (isNonPlaceholderSecret(env.CLOUDFLARE_API_TOKEN)) {
        const token = env.CLOUDFLARE_API_TOKEN.trim();
        headers.Authorization = `Bearer ${token}`;
        secretsToRedact.push(token);
      } else if (!isLoopback) {
        throw new ProxyConfigurationError(
          "CLOUDFLARE_API_TOKEN is not configured on the proxy.",
          "Run `firebase functions:secrets:set CLOUDFLARE_API_TOKEN` (and include CLOUDFLARE_API_TOKEN in ENABLED_SECRETS) or export CLOUDFLARE_API_TOKEN."
        );
      }

      return { provider, url, headers, secretsToRedact };
    }

    case "openai": {
      const apiKey = env.OPENAI_API_KEY;
      if (!isNonPlaceholderSecret(apiKey)) {
        throw new ProxyConfigurationError(
          "OPENAI_API_KEY is not configured on the proxy.",
          "Run `firebase functions:secrets:set OPENAI_API_KEY` (and include OPENAI_API_KEY in ENABLED_SECRETS) or export OPENAI_API_KEY."
        );
      }
      const trimmedKey = apiKey.trim();
      const rawUrl = env.OPENAI_DECISIONS_URL || "https://api.openai.com/v1/decisions";
      const url = validateSafeUpstreamUrl(rawUrl, "OPENAI_DECISIONS_URL");
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
        Authorization: `Bearer ${trimmedKey}`,
      };
      if (env.OPENAI_ORGANIZATION && !hasHeaderControlChars(env.OPENAI_ORGANIZATION)) {
        const org = env.OPENAI_ORGANIZATION.trim();
        if (org.length > 0) {
          headers["OpenAI-Organization"] = org;
        }
      }
      if (env.OPENAI_PROJECT && !hasHeaderControlChars(env.OPENAI_PROJECT)) {
        const proj = env.OPENAI_PROJECT.trim();
        if (proj.length > 0) {
          headers["OpenAI-Project"] = proj;
        }
      }
      return { provider, url, headers, secretsToRedact: [trimmedKey] };
    }

    case "gemini": {
      const apiKey = isNonPlaceholderSecret(env.GEMINI_API_KEY)
        ? env.GEMINI_API_KEY
        : env.GOOGLE_API_KEY;
      if (!isNonPlaceholderSecret(apiKey)) {
        throw new ProxyConfigurationError(
          "GEMINI_API_KEY is not configured on the proxy.",
          "Run `firebase functions:secrets:set GEMINI_API_KEY` (and include GEMINI_API_KEY in ENABLED_SECRETS) or export GEMINI_API_KEY."
        );
      }
      const trimmedKey = apiKey.trim();
      const rawUrl =
        env.GEMINI_DECISIONS_URL || "https://generativelanguage.googleapis.com/v1beta/decisions";
      const url = validateSafeUpstreamUrl(rawUrl, "GEMINI_DECISIONS_URL");
      return {
        provider,
        url,
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": trimmedKey,
        },
        secretsToRedact: [trimmedKey],
      };
    }
  }
}

function redactSecrets(text: string, secrets: readonly string[]): string {
  let sanitized = text;
  for (const secret of secrets) {
    if (secret.length >= 4 && sanitized.includes(secret)) {
      sanitized = sanitized.split(secret).join("[REDACTED]");
    }
  }
  return sanitized;
}

/**
 * Core HTTP handler supporting all 5 networked System One providers across both:
 * - Pattern A: Provider-specific native wire format passthrough (`<Provider>LanguageModel(proxyEndpoint:credential:)`)
 * - Pattern B: Provider-agnostic canonical `SystemOneRequest` gateway (`SystemOneLanguageModel(proxyEndpoint:credential:)`)
 */
export async function handleSystemOneProxyRequest(
  req: ProxyHttpRequest,
  res: ProxyHttpResponse,
  deps: ProxyDependencies
): Promise<void> {
  const env = deps.env ?? process.env;
  const fetchFn = deps.fetchImpl ?? fetch;
  const timeoutMs = deps.timeoutMs ?? 25_000;
  const logger = deps.logger ?? console;

  // 1. Enforce HTTP POST
  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed", message: "Expected HTTP POST." });
    return;
  }

  // 2. Verify Firebase App Check Token (+ optional limited-use replay protection)
  const appCheckToken = req.header("X-Firebase-AppCheck");
  if (!appCheckToken || appCheckToken.trim().length === 0) {
    res.status(401).json({
      error: "Unauthorized",
      message: "Missing required X-Firebase-AppCheck header.",
    });
    return;
  }

  const consume = env.CONSUME_APP_CHECK === "true";
  try {
    const claims = await deps.verifyAppCheckToken(
      appCheckToken.trim(),
      consume ? { consume: true } : undefined
    );
    if (consume && claims.alreadyConsumed) {
      res.status(401).json({
        error: "Unauthorized",
        message: "App Check limited-use token has already been consumed.",
      });
      return;
    }
  } catch (err) {
    logger.warn("App Check token verification failed:", err);
    res.status(401).json({
      error: "Unauthorized",
      message: "Invalid or expired App Check token.",
    });
    return;
  }

  // 3. Route to allowlisted System One provider & prepare outbound payload
  let provider: ProviderId;
  let outboundBodyObj: unknown;
  let adaptMode: "passthrough" | "canonical-to-openai" | "canonical-to-gemini" = "passthrough";
  let expectedQuestionNames: string[] | undefined;
  let requestedModel: string | undefined;

  try {
    provider = resolveTargetProvider(
      req.path ?? req.url,
      req.header("X-SystemOne-Provider"),
      req.body,
      env
    );

    if (isPlainObject(req.body) && typeof req.body.model === "string") {
      requestedModel = req.body.model;
    }

    if (provider === "openai") {
      if (isCanonicalSystemOnePayload(req.body)) {
        const { request, normalizedImages } = validateCanonicalSystemOneRequest(req.body);
        expectedQuestionNames = Object.keys(request.questions);
        outboundBodyObj = adaptSystemOneToOpenAIRequest(
          request,
          normalizedImages,
          env.OPENAI_MODEL || "gpt-6-luna"
        );
        adaptMode = "canonical-to-openai";
      } else {
        outboundBodyObj = validateNativeOpenAIRequest(req.body, env.OPENAI_MODEL || "gpt-6-luna");
      }
    } else if (provider === "gemini") {
      if (isCanonicalSystemOnePayload(req.body)) {
        const { request, normalizedImages } = validateCanonicalSystemOneRequest(req.body);
        expectedQuestionNames = Object.keys(request.questions);
        outboundBodyObj = adaptSystemOneToGeminiRequest(
          request,
          normalizedImages,
          env.GEMINI_MODEL || "gemini-decision-1"
        );
        adaptMode = "canonical-to-gemini";
      } else {
        outboundBodyObj = validateNativeGeminiRequest(
          req.body,
          env.GEMINI_MODEL || "gemini-decision-1"
        );
      }
    } else if (provider === "clef") {
      // Per tech-notes/0014-cloudflare-workers-ai-model-schema-nuance.md, Cloudflare Workers AI
      // requires the full @cf/cloudflare/... identifier in the URL path, but strictly enforces
      // ^\s*(clef|clef-flash)\s*$ on `/model` in the JSON body.
      const { request } = validateCanonicalSystemOneRequest(req.body, env.CLEF_MODEL || "clef-flash");
      requestedModel = request.model;
      const { bodyModelSlug } = resolveClefModelIdentifiers(request.model, env.CLEF_MODEL);
      outboundBodyObj = {
        state: request.state,
        model: bodyModelSlug,
        questions: request.questions,
        ...(request.images && request.images.length > 0 ? { images: request.images } : {}),
      };
    } else {
      const defaultModelByProvider: Record<"jev" | "laya", string> = {
        jev: env.JEV_MODEL || "jev-latest",
        laya: env.LAYA_MODEL || "laya-default",
      };
      const { request } = validateCanonicalSystemOneRequest(
        req.body,
        defaultModelByProvider[provider]
      );
      requestedModel = request.model;
      outboundBodyObj = {
        state: request.state,
        model:
          request.model === "systemone-default"
            ? defaultModelByProvider[provider]
            : request.model,
        questions: request.questions,
        ...(request.images && request.images.length > 0 ? { images: request.images } : {}),
      };
    }
  } catch (err) {
    if (err instanceof ProxyValidationError) {
      res.status(err.statusCode).json({ error: "Bad Request", message: err.message });
      return;
    }
    if (err instanceof ProxyConfigurationError) {
      logger.error(`[Proxy Configuration Error] ${err.message} (${err.remediation})`);
      res.status(500).json({
        error: "MissingConfiguration",
        message: err.message,
        remediation: err.remediation,
      });
      return;
    }
    res.status(400).json({ error: "Bad Request", message: "Invalid request payload." });
    return;
  }

  // 4. Resolve server-side upstream URL & credentials (SSRF-safe)
  let upstream: ResolvedUpstreamConfig;
  try {
    upstream = resolveProviderUpstream(provider, requestedModel, env);
  } catch (err) {
    if (err instanceof ProxyValidationError) {
      res.status(err.statusCode).json({ error: "Bad Request", message: err.message });
      return;
    }
    if (err instanceof ProxyConfigurationError) {
      logger.error(`[Proxy Configuration Error] ${err.message} (${err.remediation})`);
      res.status(500).json({
        error: "MissingConfiguration",
        message: err.message,
        remediation: err.remediation,
      });
      return;
    }
    res.status(500).json({ error: "Internal Server Error" });
    return;
  }

  // 5. Execute upstream call (`redirect: "error"` prevents 307/308 credential forwarding SSRF)
  try {
    const upstreamResponse = await fetchFn(upstream.url, {
      method: "POST",
      redirect: "error",
      headers: upstream.headers,
      body: JSON.stringify(outboundBodyObj),
      signal: AbortSignal.timeout(timeoutMs),
    });

    const rawResponseText = await upstreamResponse.text();

    for (const headerName of FORWARDED_UPSTREAM_HEADERS) {
      const headerVal = upstreamResponse.headers.get(headerName);
      if (headerVal && !hasHeaderControlChars(headerVal)) {
        res.setHeader(headerName, headerVal);
      }
    }

    if (!upstreamResponse.ok) {
      const safeErrorBody = redactSecrets(rawResponseText, upstream.secretsToRedact);
      res.setHeader(
        "Content-Type",
        upstreamResponse.headers.get("Content-Type") || "application/json"
      );
      res.status(upstreamResponse.status).send(safeErrorBody);
      return;
    }

    // Pattern B response adaptation (`openai` / `gemini` -> canonical `SystemOneResponse`)
    if (adaptMode === "canonical-to-openai" || adaptMode === "canonical-to-gemini") {
      let parsedJson: unknown;
      try {
        parsedJson = JSON.parse(rawResponseText);
      } catch {
        res.status(502).json({
          error: "Bad Gateway",
          message: `Upstream ${provider} returned non-JSON payload.`,
        });
        return;
      }

      try {
        const canonical =
          adaptMode === "canonical-to-openai"
            ? adaptOpenAIToSystemOneResponse(parsedJson, expectedQuestionNames)
            : adaptGeminiToSystemOneResponse(parsedJson, expectedQuestionNames);
        res.setHeader("Content-Type", "application/json");
        res.status(200).send(JSON.stringify(canonical));
        return;
      } catch (adaptErr) {
        if (adaptErr instanceof ProxySafetyRefusalError) {
          res.status(422).json({
            error: {
              type: "safety_refusal",
              question: adaptErr.questionName,
              message: adaptErr.reason,
            },
          });
          return;
        }
        if (adaptErr instanceof ProxyValidationError) {
          res.status(adaptErr.statusCode).json({
            error: "Bad Gateway",
            message: adaptErr.message,
          });
          return;
        }
        throw adaptErr;
      }
    }

    // Clef Cloudflare Workers AI `{ success, result }` unwrapping
    if (provider === "clef") {
      const unwrapped = unwrapCloudflareClefResponse(rawResponseText);
      res.setHeader("Content-Type", "application/json");
      if (!unwrapped.ok) {
        const safeErrorBody = redactSecrets(unwrapped.bodyText, upstream.secretsToRedact);
        res.status(502).send(safeErrorBody);
        return;
      }
      res.status(upstreamResponse.status).send(unwrapped.bodyText);
      return;
    }

    // Pattern A native passthrough (`jev`, `laya`, `openai`, `gemini`)
    res.setHeader(
      "Content-Type",
      upstreamResponse.headers.get("Content-Type") || "application/json"
    );
    res.status(upstreamResponse.status).send(rawResponseText);
  } catch (networkErr) {
    logger.error(`Upstream System One (${provider}) proxy failure:`, networkErr);
    res.status(502).json({
      error: "Bad Gateway",
      message: `Upstream ${provider} decision evaluation failed.`,
    });
  }
}
