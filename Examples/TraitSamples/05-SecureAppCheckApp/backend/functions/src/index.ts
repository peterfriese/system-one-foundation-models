import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

admin.initializeApp();

/**
 * 2nd Generation Cloud Function acting as a secure gateway for TypeSafe AI Jev decision models.
 *
 * Verifies Apple App Attest / DeviceCheck cryptographically via Firebase App Check tokens,
 * preventing API key exfiltration and unauthenticated automated scraping.
 */
export const jevProxy = onRequest(
  {
    cors: true,
    invoker: "public",
    secrets: ["TYPESAFE_API_KEY"],
  },
  async (req, res) => {
    // Only accept HTTP POST requests
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed. Expected POST." });
      return;
    }

    // 1. Verify App Check Token from Header
    const appCheckToken = req.header("X-Firebase-AppCheck");
    if (!appCheckToken) {
      console.warn("Unauthorized: Missing X-Firebase-AppCheck header.");
      res.status(401).json({
        error: "Unauthorized",
        message: "Missing required X-Firebase-AppCheck header."
      });
      return;
    }

    try {
      if (process.env.FUNCTIONS_EMULATOR === "true") {
        // In local emulator mode, accept debug tokens without strict Apple App Attest signature validation
        console.log(`[Emulator] Validating App Check token: ${appCheckToken.substring(0, 10)}...`);
      } else {
        // Production: Cryptographically verify token with Firebase App Check service
        const appCheckClaims = await admin.appCheck().verifyToken(appCheckToken);
        console.log(`[Production] Verified App Check claims for app ID: ${appCheckClaims.appId}`);
      }
    } catch (err: any) {
      console.error("App Check token verification failed:", err);
      res.status(401).json({
        error: "Unauthorized",
        message: "Invalid or expired App Check token."
      });
      return;
    }

    // 2. Resolve Upstream API Key (from Secret Manager or Environment)
    const apiKey = process.env.TYPESAFE_API_KEY;

    // 3. Strict Credential Verification (Per AGENTS.md Principle 7: No Mock Bypasses in Examples)
    if (!apiKey || apiKey === "mock" || apiKey === "mock-key") {
      const banner = "================================================================================\n" +
                     "🛑 [Proxy Error] Missing TYPESAFE_API_KEY configuration!\n" +
                     "Per AGENTS.md Principle 7, synthetic mock fallbacks in example apps are prohibited.\n" +
                     "Please configure your API key in Firebase Secret Manager:\n" +
                     "  firebase functions:secrets:set TYPESAFE_API_KEY\n" +
                     "or export TYPESAFE_API_KEY in your local emulator environment.\n" +
                     "================================================================================";
      console.error(banner);
      res.status(500).json({
        error: "MissingConfiguration",
        message: "TYPESAFE_API_KEY must be set via Firebase Secret Manager or environment.",
        remediation: "Run `firebase functions:secrets:set TYPESAFE_API_KEY` to configure credentials, or export TYPESAFE_API_KEY in your environment."
      });
      return;
    }

    // 4. Dispatch to upstream TypeSafe AI API
    const upstreamEndpoint = process.env.TYPESAFE_ENDPOINT || "https://api.typesafe.ai/v1/systemone";

    try {
      const upstreamResponse = await fetch(upstreamEndpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`,
        },
        body: JSON.stringify(req.body),
      });

      const responseBody = await upstreamResponse.text();

      // Pass through status code and timing headers
      const serviceTime = upstreamResponse.headers.get("x-envoy-upstream-service-time");
      if (serviceTime) {
        res.setHeader("x-envoy-upstream-service-time", serviceTime);
      }

      res.status(upstreamResponse.status);
      res.setHeader("Content-Type", upstreamResponse.headers.get("Content-Type") || "application/json");
      res.send(responseBody);
    } catch (networkError: any) {
      console.error("Error communicating with upstream Jev API:", networkError);
      res.status(502).json({
        error: "Bad Gateway",
        message: "Upstream decision service temporarily unavailable."
      });
    }
  }
);
