import { describe, it } from "node:test";
import * as assert from "node:assert/strict";
import {
  ProxyHttpRequest,
  ProxyHttpResponse,
  handleSystemOneProxyRequest,
  validateSafeUpstreamUrl,
} from "../proxyCore";

interface CapturedResponse {
  statusCode: number;
  headers: Record<string, string>;
  rawBody: string;
  jsonBody: unknown;
}

function createMockReqRes(options: {
  method?: string;
  path?: string;
  headers?: Record<string, string>;
  body?: unknown;
}): { req: ProxyHttpRequest; res: ProxyHttpResponse; captured: CapturedResponse } {
  const normalizedHeaders: Record<string, string> = {};
  for (const [k, v] of Object.entries(options.headers ?? {})) {
    normalizedHeaders[k.toLowerCase()] = v;
  }

  const req: ProxyHttpRequest = {
    method: options.method ?? "POST",
    path: options.path ?? "/",
    body: options.body,
    header(name: string): string | undefined {
      return normalizedHeaders[name.toLowerCase()];
    },
  };

  const captured: CapturedResponse = {
    statusCode: 200,
    headers: {},
    rawBody: "",
    jsonBody: undefined,
  };

  const res: ProxyHttpResponse = {
    status(code: number) {
      captured.statusCode = code;
      return res;
    },
    setHeader(name: string, value: string) {
      captured.headers[name.toLowerCase()] = value;
    },
    json(body: unknown) {
      captured.headers["content-type"] = "application/json";
      captured.jsonBody = body;
      captured.rawBody = JSON.stringify(body);
    },
    send(body: string) {
      captured.rawBody = body;
      try {
        captured.jsonBody = JSON.parse(body);
      } catch {
        captured.jsonBody = undefined;
      }
    },
  };

  return { req, res, captured };
}

const VALID_CANONICAL_REQUEST = {
  state: "Database credentials leaked on public paste site.",
  model: "systemone-default",
  questions: {
    isUrgent: {
      type: "noul",
      instructions: "Is this incident urgent?",
    },
    category: {
      type: "choice",
      instructions: "Classify the incident.",
      criteria: {
        security: "Security breach or credential leak",
        billing: "Billing question",
      },
    },
    severity: {
      type: "score",
      instructions: "Rate severity from 1 to 3.",
      criteria: ["Low", "Medium", "High"],
    },
  },
};

const TINY_PNG_DATA_URL =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

describe("FirebaseAppCheckProxy multi-provider router & wire adapters", () => {
  it("rejects non-POST methods with 405", async () => {
    const { req, res, captured } = createMockReqRes({ method: "GET" });
    await handleSystemOneProxyRequest(req, res, {
      verifyAppCheckToken: async () => ({ appId: "app-1" }),
      env: {},
      logger: { warn: () => {}, error: () => {}, info: () => {} },
    });
    assert.equal(captured.statusCode, 405);
  });

  it("rejects missing, invalid, and alreadyConsumed App Check tokens with 401", async () => {
    // 1. Missing header
    {
      const { req, res, captured } = createMockReqRes({ body: VALID_CANONICAL_REQUEST });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        env: {},
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 401);
    }

    // 2. Invalid token
    {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "forged-token" },
        body: VALID_CANONICAL_REQUEST,
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => {
          throw new Error("Invalid signature");
        },
        env: {},
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 401);
    }

    // 3. Replayed limited-use token (CONSUME_APP_CHECK="true" & alreadyConsumed)
    {
      let receivedConsumeOption = false;
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "replayed-single-use-token" },
        body: VALID_CANONICAL_REQUEST,
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async (_token, opts) => {
          receivedConsumeOption = opts?.consume === true;
          return { appId: "app-1", alreadyConsumed: true };
        },
        env: { CONSUME_APP_CHECK: "true" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(receivedConsumeOption, true);
      assert.equal(captured.statusCode, 401);
    }
  });

  it("routes by path suffix (/jev, /laya, /clef, /openai, /gemini) and rejects unknown paths with 400", async () => {
    const calledUrls: string[] = [];
    const mockFetch: typeof fetch = async (input) => {
      const url = String(input);
      calledUrls.push(url);
      if (url.includes("openai.com")) {
        return new Response(
          JSON.stringify({
            model: "gpt-6-luna",
            answers: [
              { name: "isUrgent", probability: 0.95 },
              { name: "category", choice: "security" },
              { name: "severity", score: 3 },
            ],
            usage: { input_tokens: 12, output_tokens: 4 },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
      }
      if (url.includes("googleapis.com")) {
        return new Response(
          JSON.stringify({
            model: "gemini-decision-1",
            answers: {
              isUrgent: { noul: 0.92 },
              category: { choice: "security" },
              severity: { score: 3 },
            },
            usageMetadata: { promptTokenCount: 15, candidatesTokenCount: 5 },
          }),
          { status: 200, headers: { "Content-Type": "application/json" } }
        );
      }
      return new Response(
        JSON.stringify({
          model: "jev-latest",
          answers: {
            isUrgent: { type: "noul", noul: 0.9 },
            category: { type: "choice", choice: "security" },
            severity: { type: "score", score: 3 },
          },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    };

    const env = {
      TYPESAFE_API_KEY: "ts-secret-key",
      LAYA_UPSTREAM_URL: "http://127.0.0.1:8080/v1/systemone",
      CLOUDFLARE_ACCOUNT_ID: "cf_acct_123",
      CLOUDFLARE_GATEWAY_ID: "cf_gw_456",
      CLOUDFLARE_API_TOKEN: "cf-secret-token",
      OPENAI_API_KEY: "sk-openai-secret",
      GEMINI_API_KEY: "gm-gemini-secret",
    };

    for (const path of ["/jev", "/laya", "/clef", "/openai", "/systemone/gemini"]) {
      const { req, res, captured } = createMockReqRes({
        path,
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: VALID_CANONICAL_REQUEST,
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: mockFetch,
        env,
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 200, `Expected 200 for path ${path}`);
    }

    assert.deepEqual(calledUrls, [
      "https://api.typesafe.ai/v1/systemone",
      "http://127.0.0.1:8080/v1/systemone",
      "https://gateway.ai.cloudflare.com/v1/cf_acct_123/cf_gw_456/workers-ai/@cf/cloudflare/clef-flash",
      "https://api.openai.com/v1/decisions",
      "https://generativelanguage.googleapis.com/v1beta/decisions",
    ]);

    // Unknown path suffix -> 400
    const { req: badReq, res: badRes, captured: badCap } = createMockReqRes({
      path: "/anthropic",
      headers: { "X-Firebase-AppCheck": "valid-token" },
      body: VALID_CANONICAL_REQUEST,
    });
    await handleSystemOneProxyRequest(badReq, badRes, {
      verifyAppCheckToken: async () => ({ appId: "app-1" }),
      fetchImpl: mockFetch,
      env,
      logger: { warn: () => {}, error: () => {}, info: () => {} },
    });
    assert.equal(badCap.statusCode, 400);
  });

  it("routes by X-SystemOne-Provider header and model auto-detection", async () => {
    const calledUrls: string[] = [];
    const mockFetch: typeof fetch = async (input) => {
      calledUrls.push(String(input));
      return new Response(
        JSON.stringify({
          model: "gemini-decision-1",
          answers: { isUrgent: { noul: 0.88 } },
        }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    };

    // Header routing
    {
      const { req, res, captured } = createMockReqRes({
        headers: {
          "X-Firebase-AppCheck": "valid-token",
          "X-SystemOne-Provider": "gemini",
        },
        body: {
          state: "Alert",
          questions: { isUrgent: { type: "noul", instructions: "Urgent?" } },
        },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: mockFetch,
        env: { GEMINI_API_KEY: "gm-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 200);
      assert.equal(calledUrls.at(-1), "https://generativelanguage.googleapis.com/v1beta/decisions");
    }

    // Invalid header value -> 400
    {
      const { req, res, captured } = createMockReqRes({
        headers: {
          "X-Firebase-AppCheck": "valid-token",
          "X-SystemOne-Provider": "unknown-provider",
        },
        body: VALID_CANONICAL_REQUEST,
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: mockFetch,
        env: { GEMINI_API_KEY: "gm-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 400);
    }

    // Model prefix inference (`gemini-decision-1` without path or header)
    {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: {
          state: "Alert",
          model: "gemini-decision-1",
          questions: { isUrgent: { type: "noul", instructions: "Urgent?" } },
        },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: mockFetch,
        env: { GEMINI_API_KEY: "gm-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 200);
      assert.equal(calledUrls.length, 2);
    }
  });

  it("passes through Pattern A native OpenAI and Gemini wire payloads verbatim and preserves telemetry headers", async () => {
    // OpenAI Pattern A passthrough (auto-detected via Array.isArray(questions))
    let capturedOpenAIAuth = "";
    let capturedOpenAIOrg = "";
    const nativeOpenAIRequest = {
      model: "gpt-6-luna",
      input: "Server CPU at 99% for 20 minutes",
      questions: [
        { type: "predicate", name: "pageOnCall", instructions: "Should on-call be paged?" },
      ],
    };
    const nativeOpenAIResponse = {
      id: "dec_123",
      object: "decision",
      model: "gpt-6-luna",
      answers: [{ name: "pageOnCall", type: "predicate", probability: 0.97, confidence: 0.97 }],
      usage: { input_tokens: 18, output_tokens: 3 },
    };

    {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: nativeOpenAIRequest,
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async (_url, init) => {
          const h = init?.headers as Record<string, string>;
          capturedOpenAIAuth = h.Authorization;
          capturedOpenAIOrg = h["OpenAI-Organization"];
          assert.deepEqual(JSON.parse(String(init?.body)), nativeOpenAIRequest);
          return new Response(JSON.stringify(nativeOpenAIResponse), {
            status: 200,
            headers: {
              "Content-Type": "application/json",
              "openai-processing-ms": "41.5",
              "Retry-After": "2",
            },
          });
        },
        env: {
          OPENAI_API_KEY: "sk-real-key",
          OPENAI_ORGANIZATION: "org_typesafe",
        },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 200);
      assert.equal(capturedOpenAIAuth, "Bearer sk-real-key");
      assert.equal(capturedOpenAIOrg, "org_typesafe");
      assert.equal(captured.headers["openai-processing-ms"], "41.5");
      assert.equal(captured.headers["retry-after"], "2");
      assert.deepEqual(captured.jsonBody, nativeOpenAIResponse);
    }

    // Gemini Pattern A passthrough (auto-detected via body.input + dictionary questions)
    let capturedGeminiApiKey = "";
    const nativeGeminiRequest = {
      model: "gemini-decision-1",
      input: "Suspicious login from unfamiliar ASN",
      questions: {
        requireStepUpAuth: { type: "noul", instructions: "Require WebAuthn step-up?" },
      },
    };
    const nativeGeminiResponse = {
      id: "gem_456",
      model: "gemini-decision-1",
      answers: {
        requireStepUpAuth: { type: "noul", noul: 0.94, confidence: 0.94 },
      },
      usageMetadata: { promptTokenCount: 22, candidatesTokenCount: 4, totalTokenCount: 26 },
    };

    {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: nativeGeminiRequest,
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async (_url, init) => {
          const h = init?.headers as Record<string, string>;
          capturedGeminiApiKey = h["x-goog-api-key"];
          assert.deepEqual(JSON.parse(String(init?.body)), nativeGeminiRequest);
          return new Response(JSON.stringify(nativeGeminiResponse), {
            status: 200,
            headers: {
              "Content-Type": "application/json",
              "x-goog-processing-ms": "28.2",
            },
          });
        },
        env: { GEMINI_API_KEY: "AIza-real-gemini-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 200);
      assert.equal(capturedGeminiApiKey, "AIza-real-gemini-key");
      assert.equal(captured.headers["x-goog-processing-ms"], "28.2");
      assert.deepEqual(captured.jsonBody, nativeGeminiResponse);
    }
  });

  it("adapts Pattern B canonical SystemOneRequest <-> OpenAI & Gemini (including multimodal images, safety refusal, and Cloudflare result unwrapping)", async () => {
    const multimodalCanonical = {
      ...VALID_CANONICAL_REQUEST,
      images: [TINY_PNG_DATA_URL],
    };

    // 1. Canonical -> OpenAI -> Canonical SystemOneResponse
    {
      let sentBody: Record<string, unknown> | undefined;
      const { req, res, captured } = createMockReqRes({
        path: "/openai",
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: multimodalCanonical,
      });

      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async (_url, init) => {
          sentBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
          return new Response(
            JSON.stringify({
              model: "gpt-6-luna",
              answers: [
                { name: "isUrgent", probability: 0.91 },
                {
                  name: "category",
                  choice: "security",
                  probabilities: [
                    { value: "security", probability: 0.95 },
                    { value: "billing", probability: 0.05 },
                  ],
                },
                {
                  name: "severity",
                  score: 3,
                  probabilities: [
                    { value: "0", probability: 0.02, label: "Low" },
                    { value: "1", probability: 0.08, label: "Medium" },
                    { value: "2", probability: 0.9, label: "High" },
                  ],
                },
              ],
              usage: { input_tokens: 40, output_tokens: 8 },
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          );
        },
        env: { OPENAI_API_KEY: "sk-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 200);
      assert.ok(Array.isArray(sentBody?.input), "Expected multimodal OpenAI message array");
      assert.ok(Array.isArray(sentBody?.questions), "Expected OpenAI questions array");
      const adapted = captured.jsonBody as {
        model: string;
        answers: Record<string, Record<string, unknown>>;
        usage: { input_tokens: number; output_tokens: number };
      };
      assert.equal(adapted.model, "gpt-6-luna");
      assert.equal(adapted.answers.isUrgent.type, "noul");
      assert.equal(adapted.answers.isUrgent.noul, 0.91);
      assert.equal(adapted.answers.category.choice, "security");
      assert.equal(adapted.answers.severity.score, 3);
      assert.deepEqual(adapted.answers.severity.legend, {
        "0": "Low",
        "1": "Medium",
        "2": "High",
      });
      assert.deepEqual(adapted.usage, { input_tokens: 40, output_tokens: 8 });
    }

    // 2. Canonical -> Gemini -> Safety Refusal (422)
    {
      const { req, res, captured } = createMockReqRes({
        path: "/gemini",
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: multimodalCanonical,
      });

      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async (_url, init) => {
          const sent = JSON.parse(String(init?.body)) as {
            input: Array<{ type: string; mime_type?: string }>;
          };
          assert.equal(sent.input[0].type, "text");
          assert.equal(sent.input[1].type, "image");
          assert.equal(sent.input[1].mime_type, "image/png");
          return new Response(
            JSON.stringify({
              model: "gemini-decision-1",
              answers: {
                isUrgent: { type: "refusal", refusal: "Blocked by safety filter" },
              },
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          );
        },
        env: { GEMINI_API_KEY: "gm-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 422);
      assert.deepEqual(captured.jsonBody, {
        error: {
          type: "safety_refusal",
          question: "isUrgent",
          message: "Blocked by safety filter",
        },
      });
    }

    // 3. Cloudflare Workers AI `{ success: true, result }` unwrapping on `/clef`
    {
      const innerResult = {
        model: "clef-flash",
        answers: {
          isUrgent: { type: "noul", noul: 0.85, confidence: 0.85 },
          category: { type: "choice", choice: "security", confidence: 0.93 },
          severity: { type: "score", score: 2, confidence: 0.88 },
        },
        usage: { input_tokens: 30, output_tokens: 6 },
      };

      const { req, res, captured } = createMockReqRes({
        path: "/clef",
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: VALID_CANONICAL_REQUEST,
      });

      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async () =>
          new Response(JSON.stringify({ success: true, result: innerResult, errors: [] }), {
            status: 200,
            headers: {
              "Content-Type": "application/json",
              "server-timing": "cfL4;dur=8, inference;dur=34.7",
            },
          }),
        env: {
          CLOUDFLARE_ACCOUNT_ID: "acct_abc",
          CLOUDFLARE_API_TOKEN: "cf-token-xyz",
        },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 200);
      assert.equal(captured.headers["server-timing"], "cfL4;dur=8, inference;dur=34.7");
      assert.deepEqual(captured.jsonBody, innerResult);
    }
  });

  it("enforces SSRF upstream URL validation (blocks cleartext remote HTTP and metadata IPs)", () => {
    assert.equal(
      validateSafeUpstreamUrl("https://api.openai.com/v1/decisions", "OPENAI"),
      "https://api.openai.com/v1/decisions"
    );
    assert.equal(
      validateSafeUpstreamUrl("http://127.0.0.1:8080/v1/systemone", "LAYA"),
      "http://127.0.0.1:8080/v1/systemone"
    );
    assert.throws(() => validateSafeUpstreamUrl("http://10.0.0.5:8080/v1/systemone", "LAYA"));
    assert.throws(() =>
      validateSafeUpstreamUrl("https://169.254.169.254/latest/meta-data", "SSRF")
    );
    assert.throws(() =>
      validateSafeUpstreamUrl("https://user:pass@api.typesafe.ai/v1/systemone", "CRED")
    );
  });

  it("hardens Pattern A multimodal OpenAI & Gemini validation against remote URLs, file_id/file_uri, >4 images, invalid base64, and >13 MiB payloads", async () => {
    const rawPngBase64 = TINY_PNG_DATA_URL.split(",")[1];
    // 4 MiB decoded buffer -> 4 images = 16 MiB (> 13 MiB limit)
    const fourMiBBase64 = Buffer.alloc(4 * 1024 * 1024, 0x41).toString("base64");
    const fourMiBDataUrl = `data:image/png;base64,${fourMiBBase64}`;

    // 1. Valid Pattern A OpenAI multimodal inline data URL succeeds
    {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: {
          model: "gpt-6-luna",
          input: [
            {
              role: "user",
              content: [
                { type: "input_text", text: "Inspect screenshot" },
                { type: "input_image", image_url: TINY_PNG_DATA_URL },
              ],
            },
          ],
          questions: [{ type: "predicate", name: "urgent", instructions: "Urgent?" }],
        },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async () =>
          new Response(
            JSON.stringify({
              model: "gpt-6-luna",
              answers: [{ name: "urgent", probability: 0.8 }],
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          ),
        env: { OPENAI_API_KEY: "sk-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 200);
    }

    // 2. Pattern A OpenAI invalid multimodal cases -> 400
    const badOpenAIMultimodalContents: unknown[][] = [
      [{ type: "input_image", image_url: "http://169.254.169.254/latest/meta-data" }],
      [{ type: "input_image", image_url: "https://evil.example.com/pixel.png" }],
      [{ type: "input_image", file_id: "file-abc123" }],
      [{ type: "input_audio", data: rawPngBase64 }],
      [{ type: "input_image", image_url: "data:image/png;base64,not-valid-base64!!!" }],
      Array.from({ length: 5 }, () => ({ type: "input_image", image_url: TINY_PNG_DATA_URL })),
      Array.from({ length: 4 }, () => ({ type: "input_image", image_url: fourMiBDataUrl })),
    ];

    for (const badContent of badOpenAIMultimodalContents) {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: {
          model: "gpt-6-luna",
          input: [{ role: "user", content: badContent }],
          questions: [{ type: "predicate", name: "urgent", instructions: "Urgent?" }],
        },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        env: { OPENAI_API_KEY: "sk-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 400);
    }

    // 3. Valid Pattern A Gemini multimodal inline items succeed (both `{ type: "image" }` and `{ inline_data }`)
    {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: {
          model: "gemini-decision-1",
          input: [
            { type: "text", text: "Inspect screenshot" },
            { type: "image", mime_type: "image/png", data: rawPngBase64 },
            { inline_data: { mime_type: "image/jpeg", data: rawPngBase64 } },
          ],
          questions: { urgent: { type: "noul", instructions: "Urgent?" } },
        },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async () =>
          new Response(
            JSON.stringify({
              model: "gemini-decision-1",
              answers: { urgent: { noul: 0.9 } },
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          ),
        env: { GEMINI_API_KEY: "gm-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 200);
    }

    // 4. Pattern A Gemini invalid multimodal cases -> 400
    const badGeminiInputs: unknown[][] = [
      [{ file_data: { mime_type: "image/png", file_uri: "gs://bucket/img.png" } }],
      [{ type: "image", file_uri: "https://evil.example.com/img.png" }],
      [{ type: "image", mime_type: "image/png", data: "***invalid-base64***" }],
      Array.from({ length: 5 }, () => ({
        type: "image",
        mime_type: "image/png",
        data: rawPngBase64,
      })),
      Array.from({ length: 4 }, () => ({
        type: "image",
        mime_type: "image/png",
        data: fourMiBBase64,
      })),
    ];

    for (const badInput of badGeminiInputs) {
      const { req, res, captured } = createMockReqRes({
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: {
          model: "gemini-decision-1",
          input: badInput,
          questions: { urgent: { type: "noul", instructions: "Urgent?" } },
        },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        env: { GEMINI_API_KEY: "gm-key" },
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 400);
    }
  });

  it("blocks prototype-key Clef models, passes redirect:'error', normalizes Clef body model (Tech Note 0014), and redacts Clef HTTP 200 errors", async () => {
    const cfEnv = {
      CLOUDFLARE_ACCOUNT_ID: "acct_abc",
      CLOUDFLARE_API_TOKEN: "cf-super-secret-token",
    };

    // 1. Prototype keys ("constructor", "toString") rejected with 400 via Object.hasOwn
    for (const protoModel of ["constructor", "toString", "__proto__"]) {
      const { req, res, captured } = createMockReqRes({
        path: "/clef",
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: { ...VALID_CANONICAL_REQUEST, model: protoModel },
      });
      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        env: cfEnv,
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });
      assert.equal(captured.statusCode, 400, `Expected 400 for model=${protoModel}`);
    }

    // 2. Tech Note 0014: `@cf/cloudflare/clef-flash` and `@cf/cloudflare/clef` stay in URL path,
    //    while outbound JSON body `model` is normalized to `"clef-flash"` / `"clef"`,
    //    and `init.redirect === "error"` is enforced on fetch!
    for (const [inputModel, expectedPathModel, expectedBodySlug] of [
      ["@cf/cloudflare/clef-flash", "@cf/cloudflare/clef-flash", "clef-flash"],
      ["@cf/cloudflare/clef", "@cf/cloudflare/clef", "clef"],
    ] as const) {
      let calledUrl = "";
      let calledRedirect: RequestRedirect | undefined;
      let sentJsonModel: unknown;

      const { req, res, captured } = createMockReqRes({
        path: "/clef",
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: { ...VALID_CANONICAL_REQUEST, model: inputModel },
      });

      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async (url, init) => {
          calledUrl = String(url);
          calledRedirect = init?.redirect;
          sentJsonModel = (JSON.parse(String(init?.body)) as { model: unknown }).model;
          return new Response(
            JSON.stringify({
              success: true,
              result: {
                model: expectedBodySlug,
                answers: {
                  isUrgent: { type: "noul", noul: 0.9 },
                  category: { type: "choice", choice: "security" },
                  severity: { type: "score", score: 3 },
                },
              },
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          );
        },
        env: cfEnv,
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 200);
      assert.equal(calledRedirect, "error");
      assert.equal(
        calledUrl,
        `https://api.cloudflare.com/client/v4/accounts/acct_abc/ai/run/${expectedPathModel}`
      );
      assert.equal(sentJsonModel, expectedBodySlug);
    }

    // 3. Cloudflare HTTP 200 `{ success: false, errors: [...] }` returns 502 with secret redaction
    {
      const { req, res, captured } = createMockReqRes({
        path: "/clef",
        headers: { "X-Firebase-AppCheck": "valid-token" },
        body: VALID_CANONICAL_REQUEST,
      });

      await handleSystemOneProxyRequest(req, res, {
        verifyAppCheckToken: async () => ({ appId: "app-1" }),
        fetchImpl: async () =>
          new Response(
            JSON.stringify({
              success: false,
              errors: [{ code: 7000, message: "Auth failed for token cf-super-secret-token" }],
            }),
            { status: 200, headers: { "Content-Type": "application/json" } }
          ),
        env: cfEnv,
        logger: { warn: () => {}, error: () => {}, info: () => {} },
      });

      assert.equal(captured.statusCode, 502);
      assert.equal(captured.rawBody.includes("cf-super-secret-token"), false);
      assert.equal(captured.rawBody.includes("[REDACTED]"), true);
    }
  });
});
