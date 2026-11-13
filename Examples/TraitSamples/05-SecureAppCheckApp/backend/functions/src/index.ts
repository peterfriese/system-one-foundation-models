import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { handleSystemOneProxyRequest } from "./proxyCore";

admin.initializeApp();

const SUPPORTED_SECRET_NAMES = [
  "TYPESAFE_API_KEY",
  "LAYA_API_KEY",
  "CLOUDFLARE_API_TOKEN",
  "OPENAI_API_KEY",
  "GEMINI_API_KEY",
] as const;

const enabledSecrets = (process.env.ENABLED_SECRETS ?? "")
  .split(",")
  .map((name) => name.trim())
  .filter((name): name is (typeof SUPPORTED_SECRET_NAMES)[number] =>
    (SUPPORTED_SECRET_NAMES as readonly string[]).includes(name)
  );

/**
 * 2nd Generation Cloud Function acting as a multi-provider secure gateway for all 5 networked
 * System One decision model providers (`jev`, `laya`, `clef`, `openai`, `gemini`) across both
 * Pattern A (provider-native wire passthrough) and Pattern B (canonical `SystemOneRequest`).
 *
 * Verifies Apple App Attest / DeviceCheck cryptographically via Firebase App Check tokens,
 * preventing API key exfiltration and unauthenticated automated scraping.
 */
export const systemone = onRequest(
  {
    cors: true,
    invoker: "public",
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
          console.log(`[Emulator] Validating App Check token: ${token.substring(0, 10)}...`);
          return { appId: "emulator-debug-app", alreadyConsumed: false };
        }
        const claims = await admin.appCheck().verifyToken(token, options);
        console.log(`[Production] Verified App Check claims for app ID: ${claims.appId}`);
        return claims;
      },
      env: process.env,
    });
  }
);

/** Backward-compatible Cloud Function alias for existing `jevProxy` client URLs and scripts. */
export const jevProxy = systemone;

export * from "./adapters";
export * from "./proxyCore";
