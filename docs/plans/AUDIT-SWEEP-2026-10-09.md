# System One Foundation Models — Complete Repository Audit & Adversarial Review

- **Document ID**: `AUDIT-SWEEP-2026-10-09`
- **Date**: 2026-10-09
- **Scope**: Repository-Wide Codebase Sweep (`Sources/`, `Examples/`, `Integrations/`, `tech-notes/`, tooling & build configurations)
- **Status**: Audit Completed — Actionable Findings Documented
- **Canonical Document**: `docs/plans/AUDIT-SWEEP-2026-10-09.md`

---

## 1. Executive Summary

A comprehensive adversarial code audit and static analysis sweep was conducted across the entire `system-one-foundation-models` repository. The evaluation covered core engine sources (`Sources/`), demonstration and reference apps (`Examples/`), enterprise gateway integrations (`Integrations/`), architecture documentation (`tech-notes/`), and CI/automation harnesses.

The audit identified critical bugs, dead code, architectural inconsistencies, performance bottlenecks, and security vulnerabilities spanning four primary categories:
1. **Dead Code, Zombie Stubs & Preprocessor Defects**: Unmatched preprocessor directives causing compilation syntax errors, unreferenced compatibility shims, unused translation and metadata helper methods, and active debug logging left in production frameworks.
2. **"Stupid Code" & Ergonomic Anti-Patterns**: Critical multi-turn conversation context bugs returning Turn 1 metadata, schema translation `$ref` resolution failures inside `anyOf` enums, lossy rubric scoring transformations dropping probability distributions, recursive layout/style crashes, out-of-bounds array indexing panics, unthrottled UI tasks on keystroke events, and strict violations of AGENTS.md Principle 7 (synthetic mock bypasses in production demonstrators).
3. **Adversarial & Security Flaws**: Fail-open image dimension guardrails, sequence boundary token hijacking via unescaped ModernBERT delimiters, cleartext HTTP proxy transmission risks, quadratic prefix-slicing DoS in tokenization, and actor-pool thread starvation from synchronous Core ML inference.
4. **Architectural & Domain Discrepancies**: Inverted urgency priority seeds, domain type mismatches, and raw `simctl` CLI tool invocations violating workspace directives.

This sweep also explicitly refutes and drops previous false claims (such as non-existent force-casts, imaginary error-swallowing catch blocks, or standard Apple Foundation Models protocol conformances flagged as defects).

A prioritized 3-phase remediation plan is established at the end of this document.

---

## 2. Part 1: Dead Code & Preprocessor Hygiene Sweep

### 2.1 Core Library (`Sources/`)

- **`Integrations/FirebaseAppCheckProxy/FirebaseAppCheckTransport.swift:93-95`**
  - **Issue**: Duplicate unmatched `#else` / `#endif` preprocessor directive resulting in a compile-time syntax error.
  ```swift
  // Lines 44-57 already closed the conditional:
  #if canImport(FirebaseAppCheck)
  ...
  #else
  throw JevError.networkError("FirebaseAppCheck is not linked in this application target.")
  #endif
  ...
  // Lines 93-95 re-introduce an orphaned #else / #endif without an opening #if:
  #else
  throw JevError.networkError("FirebaseAppCheck is not linked in this target. To use FirebaseAppCheckTransport, link the FirebaseAppCheck SDK.")
  #endif
  ```
  - **Remediation**: Delete the orphaned `#else` / `#endif` block at lines 93-95.

- **`Sources/JevFoundationModels/JevAliases.swift:11-12`**
  - **Issue**: Redundant public `typealias` declarations (`SchemaTranslator`, `ResponseSynthesizer`) that alias `SystemOneCore` types without deprecation annotations.
  ```swift
  public typealias SchemaTranslator = SystemOneCore.SchemaTranslator
  public typealias ResponseSynthesizer = SystemOneCore.ResponseSynthesizer
  ```
  - **Remediation**: Deprecate with `@available(*, deprecated, message: "Use SystemOneCore types directly")` or remove if not part of the public backward-compatibility contract.

- **`Sources/SystemOneCore/Schema/SchemaTranslator.swift:76-78`**
  - **Issue**: Unused convenience method `translateToQuestions(_:)` has 0 internal call sites across all library targets, as executors call `translate(_:)` directly to retrieve the full `SchemaTranslation` descriptor.
  - **Remediation**: Remove `translateToQuestions` to keep the API surface minimal.

- **`Sources/SystemOneCore/Response/ResponseExtensions.swift:82-84`**
  - **Issue**: Unused helper method `probabilityValue(for:)` is unreferenced across the codebase; callers directly access `probability(for:)` or the `probabilities` dictionary.
  - **Remediation**: Remove `probabilityValue(for:)`.

- **`Sources/SystemOneCore/Models/SystemOneImage.swift:206-217` — Clarification on `CodingKeys`**
  - **Status**: **DO NOT DELETE**.
  - **Clarification**: Prior audit drafts erroneously suggested deleting `CodingKeys` because `encode(to:)` uses a single-value container. However, `CodingKeys` is strictly required by `init(from decoder: Decoder)` at line 237 (`let container = try decoder.container(keyedBy: CodingKeys.self)`) to support decoding keyed image dictionary payloads.

- **`Sources/OpenAIFoundationModels/OpenAIDecisionsHTTPBackend.swift:209-211`**
  - **Issue**: Active debug `print()` statements in shipping library code:
  ```swift
  print("⚠️ [OpenAIDecisionsHTTPBackend] JSON decoding error: \(error)")
  if let raw = String(data: data, encoding: .utf8) {
      print("⚠️ [OpenAIDecisionsHTTPBackend] Raw response body:\n\(raw)")
  }
  ```
  - **Remediation**: Replace raw `print` calls with OSLog / unified logging or remove entirely to avoid leaking raw response payloads to console logs.

### 2.2 Examples & Reference Apps (`Examples/`)

- **`Examples/NutritionLabelScannerApp/Sources/Models/FoodProduct.swift:56`**
  - **Issue**: Unused property `public let highlightedOffendingIngredients: [String]`.
  - **Clarification**: **DO NOT delete `FoodProduct.swift`!** It is the core data model of `NutritionLabelScannerApp`. Only the single property `highlightedOffendingIngredients` at line 56 (and its initializer argument default) is unreferenced by the UI and evaluation pipelines.
  - **Remediation**: Remove the unused property or connect it to OCR bounding-box highlighting in the product detail view.

---

## 3. Part 2: "Stupid Code" & Ergonomic Anti-Patterns

### 3.1 Critical Multi-Turn Metadata Context Bug
- **File & Lines**: `Sources/SystemOneCore/Response/ResponseExtensions.swift:8-15`
- **Pattern**: When resolving System One metadata from `LanguageModelSession.Response`, the extension iterates forward over `transcriptEntries`:
  ```swift
  public var metadata: [String: GeneratedContent] {
      for entry in transcriptEntries {
          if case .response(let r) = entry {
              return r.metadata
          }
      }
      return [:]
  }
  ```
- **Consequence**: In any multi-turn conversation (e.g. follow-up questions, interactive triage, chain-of-thought refinement), `for entry in transcriptEntries` matches the **very first turn** in the session transcript. As a result, Turn 2, Turn 3, and subsequent answers return stale Turn 1 metadata (probabilities, confidence scores, and latency metrics).
- **Remediation**: Iterate in reverse (`transcriptEntries.reversed()`) or select the last `.response` entry to retrieve the current turn's metadata:
  ```swift
  public var metadata: [String: GeneratedContent] {
      for entry in transcriptEntries.reversed() {
          if case .response(let r) = entry {
              return r.metadata
          }
      }
      return [:]
  }
  ```

### 3.2 Broken `$ref` Dereferencing for Optional Enums
- **File & Lines**: `Sources/SystemOneCore/Schema/SchemaTranslator.swift:174-197`
- **Pattern**: `resolveProperty(raw:defs:)` checks for top-level `$ref` pointers *before* unwrapping `anyOf` constructs:
  ```swift
  if let ref = dict["$ref"] as? String {
      // dereferences $ref
  }

  // Handle anyOf unwrapping (e.g. nullable [null, targetType] or enum choice variants)
  if let anyOf = dict["anyOf"] as? [[String: Any]] {
      let nonNullVariants = anyOf.filter { ($0["type"] as? String) != "null" }
      if let firstVariant = nonNullVariants.first {
          for (k, v) in firstVariant where dict[k] == nil {
              dict[k] = v
          }
      }
  }
  ```
- **Consequence**: In Apple Foundation Models, an optional enum (e.g. `MyEnum?`) emits an `anyOf` schema:
  `{"anyOf": [{"type": "null"}, {"$ref": "#/$defs/MyEnum"}]}`.
  Because the top-level property dictionary does not have a root `$ref`, the `$ref` block does not trigger. Then `anyOf` is unpacked, copying `"$ref": "#/$defs/MyEnum"` into `dict`. Because resolution is not recursive, the pointer is never dereferenced, leaving the property with an unparsed `$ref` and no `enum` cases, causing schema translation to fail or treat the field as a plain string.
- **Remediation**: Perform `$ref` resolution iteratively or recursively after unpacking `anyOf` variants.

### 3.3 Loss of Rubric Score Probability Distributions in OpenAI Decisions Adapter
- **File & Lines**: `Sources/OpenAIFoundationModels/OpenAIDecisionsPayloadAdapter.swift:142`
- **Pattern**: When mapping OpenAI score probabilities to `SystemOneAnswer`:
  ```swift
  if let probsList = ans.probabilities {
      probsDict = Dictionary(
          probsList.map { ($0.label ?? $0.value, $0.probability) },
          uniquingKeysWith: { current, _ in current }
      )
      ...
  }
  ```
  Meanwhile, `SystemOneAnswer.scoreValue(minimum:maximum:isInteger:)` in `Sources/SystemOneCore/Models/SystemOneDTOs.swift:193-197` parses score probabilities using integer level indices:
  ```swift
  var indexedProbs: [Int: Double] = [:]
  if let probabilities {
      for (k, v) in probabilities {
          if let idx = Int(k), v.isFinite { indexedProbs[idx] = v }
      }
  }
  ```
- **Consequence**: When OpenAI Decisions returns labeled levels (e.g. `value: "0"`, `label: "Low"`), the adapter keys `probsDict` by `"Low"`. In `SystemOneDTOs`, `Int("Low")` evaluates to `nil`, completely discarding the probability distribution from `ScoreValue`.
- **Remediation**: Key `probsDict` by `$0.value` (the numeric index string) and preserve labels exclusively in `legendDict`.

### 3.4 Infinite Stack Recursion & Scope Failure in Clef Camera Scanner
- **File & Lines**:
  - `Examples/ClefCameraScanner/Views/InspectionHUDView.swift:814`
  - `Examples/ClefCameraScanner/Views/CameraPreviewView.swift:90`
- **Pattern**: `InspectionHUDView.swift` declares:
  ```swift
  private extension ShapeStyle where Self == Color {
      static var emerald: Color { .emerald }
      static var amber: Color { .amber }
      static var rose: Color { .rose }
  }
  ```
  Inside `static var amber: Color { .amber }`, the expression `.amber` evaluates against `Self`, recursively invoking the exact same getter indefinitely until stack exhaustion.
  Furthermore, because this extension is declared `private` inside `InspectionHUDView.swift`, `CameraPreviewView.swift:90`:
  ```swift
  Image(systemName: "video.slash.fill")
      .symbolRenderingMode(.hierarchical)
      .foregroundStyle(.amber)
  ```
  causes a compilation scope failure (out of scope) or falls back to an ambiguous style.
- **Consequence**: Instantaneous stack overflow crash (`EXC_BAD_ACCESS` / recursion) when evaluated, and module-level scoping inconsistencies across scanner views.
- **Remediation**: Make the semantic color tokens `internal extension Color` in a shared palette file, and define `ShapeStyle` properties by returning the concrete `Color` instance:
  ```swift
  extension ShapeStyle where Self == Color {
      static var emerald: Color { Color.emerald }
      static var amber: Color { Color.amber }
      static var rose: Color { Color.rose }
  }
  ```

### 3.5 Direct Array Index Out-of-Bounds Panics
- **File & Lines**: `Examples/NutritionLabelScannerApp/Sources/Views/SafetyIndicatorBanner.swift:105, 112`
- **Pattern**: Direct array indexing on 4-element string arrays:
  ```swift
  // Line 105:
  IndicatorBadge(
      label: "Allergen",
      value: ["Clean", "Trace", "Hidden", "Direct"][decision.allergenRisk],
      ...
  )

  // Line 112:
  IndicatorBadge(
      label: "NOVA",
      value: ["Whole (1)", "Culinary (2)", "Processed (3)", "Ultra-UPF (4)"][decision.processingTier],
      ...
  )
  ```
  without clamping `decision.allergenRisk` or `decision.processingTier` to `0...3`.
- **Consequence**: If the model output yields a score outside `0...3` (e.g. negative value, 4, or 5), the app crashes with `Fatal error: Index out of range`.
- **Remediation**: Clamp index values or use safe bounds checking:
  ```swift
  let allergenLabels = ["Clean", "Trace", "Hidden", "Direct"]
  let clampedAllergen = min(max(0, decision.allergenRisk), allergenLabels.count - 1)
  value: allergenLabels[clampedAllergen]
  ```

### 3.6 Unthrottled UI Tasks Spawning on Every Keystroke
- **File & Lines**:
  - `Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Services/MailStore.swift:35`
  - `Examples/MailTriageApp/apps/apple/Packages/AppUI/Sources/AppUI/Views/MailListView.swift:292-300`
- **Pattern**:
  In `MailStore.swift:35`:
  ```swift
  public var selectedBackend: TriageBackend = .onDeviceCoreML {
      didSet {
          Task { @MainActor in
              await probeActiveBackend()
          }
      }
  }
  ```
  In `MailListView.swift:292-300`:
  ```swift
  .onChange(of: configStore.cloudflareAccountId) { _, _ in
      Task { await store.probeActiveBackend() }
  }
  .onChange(of: configStore.cloudflareApiToken) { _, _ in
      Task { await store.probeActiveBackend() }
  }
  .onChange(of: configStore.typesafeApiKey) { _, _ in
      Task { await store.probeActiveBackend() }
  }
  ```
- **Consequence**: When a user types their credentials in Settings, `probeActiveBackend()` fires un-tracked, uncancelled network/backend probe tasks on **every single keystroke** without debouncing or task cancellation. This floods the network, causes out-of-order state updates, and wastes compute.
- **Remediation**: Use `.task(id:)` with debouncing or maintain a cancellable `Task` reference in `MailStore` that cancels previous probe tasks before starting a new one.

### 3.7 Strict Violations of AGENTS.md Principle 7 (Fake Mocks & Synthetic Bypasses in Demos)
AGENTS.md explicitly mandates:
> *"Example applications and CLI demonstrators in `Examples/` and `Examples/TraitSamples/` are production-representative showcases, **NOT unit tests**. **NEVER implement mock fallbacks, fake offline simulators, or synthetic response bypasses in example apps.** If any required credential or background process is missing or unreachable: 1. Issue a clear, formatted warning banner. 2. Provide the exact remediation command. 3. Terminate immediately with `exit(1)`."*

The audit uncovered four flagrant violations of this directive:

1. **`Examples/TraitSamples/05-SecureAppCheckApp/backend/functions/src/index.ts:57-92`**:
   - Implements an offline mock bypass when `TYPESAFE_API_KEY` is missing, `"mock"`, or `"mock-key"`, returning synthetic `noul: 0.96`, `choice`, and `score: 3.0` answers.
   - *Note on Integrations Cleanliness*: In contrast, `Integrations/FirebaseAppCheckProxy/functions/src/index.ts` is clean and correctly requires genuine API keys and returns 400/502 on errors.
2. **`Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Services/TriageEngine.swift:95-133`**:
   - When loading a Core ML model fails, it inspects whether the file looks like `.safetensors` and injects a mock predictor returning synthetic logits (`logits[0] = -1.2, logits[1] = 2.8` for noul, `3.0` for score/choice), bypassing real execution.
3. **`Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Services/BackendHealthProbeService.swift:568-575`**:
   - In `probeCoreML()`, when `MLModel(contentsOf:configuration:)` throws, lines 571-574 check if the file exists and `size > 0`, returning `.healthy(latencyMs: elapsed)` on broken or uncompilable model weights.
4. **`Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/BenchmarkCLI/main.swift:21, 33-34, 147`**:
   - Contains a `-m, --mock` CLI argument (`var mockMode: Bool = false`) that runs simulated offline benchmark iterations with synthetic timings instead of real model executions.

- **Remediation**: Eradicate all synthetic mock bypasses from `Examples/`. Replace with formatted warning banners, explicit remediation commands, and immediate termination / typed error throwing as required by Rule 7.

---

## 4. Part 3: Adversarial Review & Security Audit

### 4.1 Image Guardrail Bypass (Fail-Open Dimension Parser)
- **File & Lines**: `Sources/SystemOneCore/Models/SystemOneImage.swift:108-114`
- **Vulnerability**:
  ```swift
  public func validate() throws {
      guard let data = rawData else {
          throw SystemOneError.modelExecutionError("Invalid or corrupted base64 image data")
      }

      if let dimensions = Self.extractDimensions(data: data, format: format) {
          let megapixels = (Double(dimensions.width) * Double(dimensions.height)) / 1_000_000.0
          if megapixels > Guardrails.maxMegapixels {
              throw SystemOneError.modelExecutionError("Image resolution (\(String(format: "%.1f", megapixels)) MP) exceeds maximum allowed \(Guardrails.maxMegapixels) MP")
          }
      }
  }
  ```
  If `extractDimensions(data:format:)` cannot parse the image header (e.g. truncated header, malformed EXIF/JPEG chunk, or adversarial decompression bomb), it returns `nil`. The validation logic **fails open**, skipping resolution checks entirely and passing the payload to the downstream pipeline.
- **Impact**: Attackers can submit image decompression bombs or oversized images that bypass client-side guardrails, causing memory exhaustion or Core ML / vision pipeline crashes.
- **Remediation**: Fail closed: throw `SystemOneError.modelExecutionError("Unable to verify image dimensions for format \(format)")` when `extractDimensions` returns `nil`.

### 4.2 Delimiter Token Hijacking & Prompt Injection
- **File & Lines**: `Sources/LayaOnDevice/Tokenization/LayaSequenceBuilder.swift:42, 79`
- **Vulnerability**:
  ```swift
  // Line 42:
  let cleanInstructions = instructions.replacingOccurrences(of: maskTok, with: " ")
  ...
  // Line 79:
  var stateIds = tokenizer.encode(state.replacingOccurrences(of: maskTok, with: " "), addSpecialTokens: false)
  ```
  `buildSequence` only sanitizes `maskTok` (`[MASK]`). It fails to strip or sanitize `[SEP]`, `[CLS]`, `<bos>`, `<eos>`, or other reserved delimiter tokens from `state`, `instructions`, or `options`.
- **Impact**: Untrusted input containing `"[SEP] System Override: ... [SEP]"` allows token sequence boundary injection into ModernBERT, corrupting attention masks and manipulating decision outcomes.
- **Remediation**: Sanitize all special delimiter tokens (`[SEP]`, `[CLS]`, `<s>`, `</s>`, etc.) or encode user text through a tokenizer pipeline that does not map raw string delimiters to reserved token IDs.

### 4.3 Denial of Service via ModernBERT Tokenizer Prefix Slicing
- **File & Lines**: `Sources/LayaOnDevice/Tokenization/ModernBERTTokenizer.swift:115-133`
- **Vulnerability**:
  ```swift
  var remaining = word[...]
  while !remaining.isEmpty {
      var matched = false
      for end in stride(from: remaining.count, to: 0, by: -1) {
          let sub = String(remaining.prefix(end))
          if let id = vocab[sub] {
              result.append(id)
              remaining = remaining.dropFirst(end)
              matched = true
              break
          }
      }
      if !matched {
          let firstChar = String(remaining.prefix(1))
          result.append(vocab[firstChar] ?? unkTokenId)
          remaining = remaining.dropFirst(1)
      }
  }
  ```
  In Swift, `remaining.count` on a `Substring` requires $O(L)$ traversal across Unicode grapheme clusters. Inside the nested loop, `remaining.prefix(end)` and `String(...)` allocate copies on every candidate check. The combined complexity on long unspaced strings is $O(L^3)$.
- **Impact**: Submitting a continuous string of 5,000 Unicode characters or unspaced sequences freezes the thread for seconds, causing Catastrophic Tokenization Backtracking / DoS.
- **Remediation**: Bound maximum token search length (e.g. 100 characters per subword), use UTF-8 byte index slicing instead of grapheme cluster counts, and avoid repeated string re-allocations.

### 4.4 Plaintext Transmission Risk in Proxy Transport
- **File & Lines**: `Sources/JevFoundationModels/Transport/ProxyTransport.swift:25, 91`
- **Vulnerability**: `ProxyTransport` accepts any `proxyEndpoint: URL` without enforcing TLS (`https://`), allowing unencrypted `http://` endpoints to remote hosts.
- **Impact**: Sensitive prompts, authorization headers, and decisions could be transmitted over cleartext networks in enterprise or cloud proxy environments.
- **Remediation**: Require `https://` for all proxy endpoints, permitting `http://` exclusively for local loopback addresses (`localhost`, `127.0.0.1`).

---

## 5. Part 4: Concurrency, Architecture & Hygiene

### 5.1 Concurrency Deficiencies

- **Data Race on `MockOpenAIDecisionsBackend.handler`**:
  - **File & Lines**: `Sources/OpenAIFoundationModels/MockOpenAIDecisionsBackend.swift:27`
  - **Issue**: `MockOpenAIDecisionsBackend` is marked `@unchecked Sendable`. While `_lastRequest` and `_evaluationCount` are synchronized via `NSLock`, `public var handler: (@Sendable (SystemOneRequest) async throws -> SystemOneResponse)?` is completely unsynchronized, permitting concurrent read/write data races.
  - **Remediation**: Protect `handler` access with `lock.withLock` or migrate the mock class to a Swift actor.

- **Synchronous Core ML Inference on Cooperative Pool**:
  - **File & Lines**: `Sources/LayaOnDevice/CoreML/LayaCoreMLEngine.swift:136`
  - **Issue**: `let output = try model.prediction(from: featureProvider)` is invoked synchronously inside `executeCoreML(...)` directly from an `async` method, blocking the Swift concurrency cooperative thread pool during heavy neural engine/GPU computation.
  - **Remediation**: Offload model inference via `Task.detached` or isolate `LayaCoreMLEngine` to a dedicated background actor/serial queue.

- **Unsafe Caller Configuration Mutation**:
  - **File & Lines**: `Sources/LayaOnDevice/CoreML/LayaCoreMLEngine.swift:41`
  - **Issue**: Directly sets `configuration.computeUnits = .all` on the caller-passed `MLModelConfiguration` instance, mutating the caller's reference.
  - **Remediation**: Clone the configuration via `configuration.copy() as! MLModelConfiguration` before mutating.

- **Repeated State Tokenization in Batch Question Evaluation**:
  - **File & Lines**: `Sources/LayaOnDevice/CoreML/LayaCoreMLEngine.swift:67-70`
  - **Issue**: Inside `for (qid, question) in request.questions`, `buildSequence(state: request.state, question: question)` re-encodes the entire state string for every question in the request rather than caching pre-tokenized state tokens.
  - **Remediation**: Pre-tokenize `request.state` once per `predict` call.

- **Swallowing Task Cancellation**:
  - **File & Lines**: `Sources/LayaFoundationModels/LayaHTTPBackend.swift:46-50`
  - **Issue**: Catches all errors from `session.data(for: urlRequest)` and unconditionally wraps them in `SystemOneError.networkError(...)`, converting `CancellationError` into a network failure and preventing cooperative task cancellation.
  - **Remediation**: Re-throw `CancellationError` and `URLError.cancelled` immediately.

- **Main Thread Semaphore Deadlock in App Check Trait Sample**:
  - **File & Lines**: `Examples/TraitSamples/05-SecureAppCheckApp/Sources/App.swift:17`
  - **Issue**: Uses `let semaphore = DispatchSemaphore(value: 0)` and `semaphore.wait()` inside `SecureAppCheckApp.init()` when running in headless CLI mode, risking UI thread deadlock.
  - **Remediation**: Restructure headless execution to use standard Swift concurrency without blocking semaphores.

### 5.2 Domain & Tooling Inconsistencies

- **Inverted Urgency Priority Seed Data**:
  - **File & Lines**: `Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Data/InboxData.swift:54, 86, 226`
  - **Issue**: The seed templates assign `urgencyScore: 3` to critical P0 database outages and broken team builds, while assigning `urgencyScore: 0` to routine Developer Program renewal receipts. This conflicts directly with `EmailTriageDecision.swift:44-51` where `p0Critical = 0` (Critical) and `p3Low = 3` (Low).
  - **Remediation**: Align seed `urgencyScore` values with `UrgencyPriority` enum semantics (`0` for P0 alerts, `3` for informational receipts).

- **Domain Type Misalignment**:
  - **File**: `Examples/MailTriageApp/apps/apple/Packages/AppCore/Sources/AppCore/Models/Email.swift:26` vs `EmailTriageDecision.swift:28`
  - **Issue**: `Email.suggestedAction` is typed as loose `String?`, while `EmailTriageDecision.suggestedAction` is a strongly-typed `TriageAction` enum.
  - **Remediation**: Type `Email.suggestedAction` as `TriageAction?`.

- **DateFormatter Allocation in Hot Paths**:
  - **Files**:
    - `Examples/MailTriageApp/apps/apple/Packages/AppUI/Sources/AppUI/Views/MailRowView.swift:98, 104`
    - `Sources/SystemOneCore/Routing/RetryPolicy.swift:93`
  - **Issue**: Allocates new `DateFormatter()` instances inside row rendering and HTTP date parsing loops.
  - **Remediation**: Use static shared cached formatters or modern `Date.FormatStyle`.

- **Missing `Choosable` Protocol Conformance**:
  - **File & Lines**: `Sources/ClefFoundationModels/VisualInspectionDecision.swift:9-19`
  - **Issue**: `ItemCategory` conforms to `CaseIterable` and `Codable` but omits `Choosable`, preventing its direct use with `session.choice(...)`.
  - **Remediation**: Add `Choosable` conformance to `ItemCategory`.

- **Disallowed Tooling Usage in Justfile**:
  - **File & Lines**: `justfile:29`
  - **Issue**: Invokes `xcrun simctl boot "iPhone 16 Pro"` instead of `flowdeck simulator boot`, violating the AGENTS.md mandate that FlowDeck CLI replaces all raw Apple CLI tools.
  - **Remediation**: Replace `xcrun simctl` with `flowdeck`.

---

## 6. Refutation of False Claims (Dropped Findings)

To maintain rigorous engineering ground truth, the following claims from previous audit drafts have been verified as **false** and are formally dropped:

1. **CLAIM: `TranscriptAttachmentExtractor` force casts `as! ImageAttachment`**:
   - **Ground Truth**: Verified false. `Sources/SystemOneCore/Attachment/TranscriptAttachmentExtractor.swift:43-51` uses safe pattern matching:
     `switch attachmentSegment.content { case .data(...): ... case .image(...): ... default: return nil }`.
     No force cast exists.
2. **CLAIM: `LanguageModelSession+SystemOne.swift` has a catch block swallowing errors into a disabled buffer**:
   - **Ground Truth**: Verified false. `Sources/SystemOneCore/Ergonomics/LanguageModelSession+SystemOne.swift` contains no error-swallowing catch blocks; evaluation methods propagate errors directly via `try await self.respond(...)`.
3. **CLAIM: Empty `prewarm()` implementations in executors are library bugs**:
   - **Ground Truth**: Verified false. `prewarm()` is an optional lifecycle requirement of Apple's Foundation Models protocols. Executors that do not require ahead-of-time pipeline allocation implement an empty `{}` body in full compliance with Apple SDK protocols.
4. **CLAIM: Storing JSON string metadata in `GeneratedContent` is a defect**:
   - **Ground Truth**: Verified false. `GeneratedContent` does not support arbitrary nested Swift dictionary structures; encoding complex metadata dictionaries (such as calibrated probabilities) as JSON strings is the official Apple Foundation Models interop pattern.

---

## 7. Prioritized Remediation Roadmap

### Phase 1: P0 Critical (Security, Panics & Rule 7 Compliance)
1. **Fix Multi-Turn Metadata Bug**: Update `ResponseExtensions.swift:8-15` to reverse search `transcriptEntries` for the active turn's metadata.
2. **Eliminate Crash Panics**:
   - Fix infinite recursion in `InspectionHUDView.swift:814` and resolve scope failure for `.amber` in `CameraPreviewView.swift:90`.
   - Add bounds clamping to array indexing in `SafetyIndicatorBanner.swift:105, 112`.
3. **Fail-Closed Image Validation**: Update `SystemOneImage.swift:108-114` to throw when dimension extraction returns `nil`.
4. **Prevent Delimiter Token Hijacking**: Sanitize `[SEP]`, `[CLS]`, `<bos>`, `<eos>` in `LayaSequenceBuilder.swift:42, 79`.
5. **Eradicate Fake Mocks (Rule 7)**:
   - Remove mock bypass in `Examples/TraitSamples/05-SecureAppCheckApp/backend/functions/src/index.ts:57-92`.
   - Remove synthetic logits fallback in `TriageEngine.swift:95-133`.
   - Remove fake healthy status on broken weights in `BackendHealthProbeService.swift:568-575`.
   - Remove `--mock` CLI flag in `BenchmarkCLI/main.swift:21, 147`.
6. **Fix Preprocessor Syntax Error**: Delete orphaned `#else` / `#endif` in `Integrations/FirebaseAppCheckProxy/FirebaseAppCheckTransport.swift:93-95`.

### Phase 2: P1 High (Concurrency, Performance & Protocol Fidelity)
1. **Fix `$ref` Resolution for Optional Enums**: Make schema dereferencing in `SchemaTranslator.swift:174-197` recursive across `anyOf` variants.
2. **Preserve Rubric Score Distributions**: Key score probabilities by index value in `OpenAIDecisionsPayloadAdapter.swift:142`.
3. **Prevent Tokenizer DoS**: Replace $O(L^3)$ substring slicing in `ModernBERTTokenizer.swift:115-133` with bounded UTF-8 matching.
4. **Eliminate Unthrottled UI Tasks**: Debounce and cancel keystroke probe tasks in `MailListView.swift:292-300` and `MailStore.swift:35`.
5. **Isolate Synchronous Core ML Execution**: Dispatch `model.prediction` in `LayaCoreMLEngine.swift:136` off the cooperative thread pool.
6. **Support Task Cancellation**: Re-throw `CancellationError` in `LayaHTTPBackend.swift:46-50`.
7. **Thread Safety in Mock Backend**: Protect `handler` in `MockOpenAIDecisionsBackend.swift:27` with lock synchronization.
8. **Enforce HTTPS in ProxyTransport**: Restrict `http://` in `ProxyTransport.swift:25, 91` to loopback addresses.

### Phase 3: P2 Polish (Hygiene, Dead Code & Alignment)
1. **Remove Production Print Statements**: Delete debug prints in `OpenAIDecisionsHTTPBackend.swift:209-211`.
2. **Purge Unused Members**: Remove `highlightedOffendingIngredients` in `FoodProduct.swift:56` and dead helpers in `SchemaTranslator.swift` and `ResponseExtensions.swift`.
3. **Align Domain Types**: Update `Email.suggestedAction` to use `TriageAction?`.
4. **Correct Seed Data**: Fix inverted urgency levels in `InboxData.swift:54, 86, 226`.
5. **Cache DateFormatters**: Replace repetitive allocations in `MailRowView.swift` and `RetryPolicy.swift`.
6. **Adopt `Choosable`**: Add conformance to `ItemCategory` in `VisualInspectionDecision.swift`.
7. **Enforce FlowDeck Tooling**: Update `justfile:29` to use `flowdeck`.
