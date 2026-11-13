import { onRequest } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getAppCheck } from "firebase-admin/app-check";
import { handleSystemOneProxyRequest } from "./proxyCore";

initializeApp();

const SUPPORTED_SECRET_NAMES = [
  "TYPESAFE_API_KEY",
  "LAYA_API_KEY",
  "CLOUDFLARE_API_TOKEN",
  "OPENAI_API_KEY",
  "GEMINI_API_KEY",
] as const;

/**
 * Bind only the Google Cloud Secret Manager secrets explicitly listed in `ENABLED_SECRETS`
 * (comma-separated in `functions/.env`, e.g. `ENABLED_SECRETS="GEMINI_API_KEY,OPENAI_API_KEY"`).
 *
 * By not hardcoding `TYPESAFE_API_KEY`, teams deploying exclusively for Gemini, OpenAI, Clef,
 * or Laya never have to create unused secrets in Google Secret Manager. Runtime credentials
 * are read from `process.env` (populated by bound Secret Manager secrets, Cloud Run env vars,
 * `.env`, or `.secret.local` in the Firebase Local Emulator).
 */
const enabledSecrets = (process.env.ENABLED_SECRETS ?? "")
  .split(",")
  .map((name) => name.trim())
  .filter((name): name is (typeof SUPPORTED_SECRET_NAMES)[number] =>
    (SUPPORTED_SECRET_NAMES as readonly string[]).includes(name)
  );

/**
 * Multi-provider Firebase Cloud Function (2nd Gen) reverse proxy for System One decision models
 * (`jev`, `laya`, `clef`, `openai`, `gemini`) supporting both:
 * - Pattern A: Provider-native wire passthrough (`<Provider>LanguageModel(proxyEndpoint:credential:)`)
 * - Pattern B: Provider-agnostic canonical gateway (`SystemOneLanguageModel(proxyEndpoint:credential:)`)
 */
export const systemone = onRequest(
  {
    cors: false,
    invoker: "public",
    minInstances: 1,
    concurrency: 80,
    preserveExternalChanges: true,
    ...(enabledSecrets.length > 0 ? { secrets: enabledSecrets } : {}),
  },
  async (req, res) => {
    await handleSystemOneProxyRequest(req, res, {
      verifyAppCheckToken: async (token, options) => {
        if (
          process.env.FUNCTIONS_EMULATOR === "true" &&
          process.env.STRICT_EMULATOR_APP_CHECK !== "true"
        ) {
          return { appId: "emulator-debug-app", alreadyConsumed: false };
        }
        return getAppCheck().verifyToken(token, options);
      },
      env: process.env,
    });
  }
);

/** Backward-compatible Cloud Function alias for existing `jevProxy` client URLs. */
export const jevProxy = systemone;

export * from "./adapters";
export * from "./proxyCore";
