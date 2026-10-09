import Foundation
#if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

public enum InboxData {
    public static let sampleEmails: [Email] = generateSampleEmails()

    private static func generateSampleEmails() -> [Email] {
        let referenceDate = Date(timeIntervalSince1970: 1790294400) // Deterministic reference date in 2026

        struct Template {
            let sender: String
            let senderEmail: String
            let subject: String
            let snippet: String
            let body: String
            let category: EmailCategory
            let isVIP: Bool
            let urgencyScore: Int
            let requiresAction: Bool
            let suggestedAction: TriageAction
            let defaultMailbox: Mailbox
        }

        let templates: [Template] = [
            // CI/CD & Infrastructure alerts
            Template(
                sender: "Bazel Build Bot",
                senderEmail: "build-bot@infra.internal.corp",
                subject: "[BROKEN] //compiler/xla:neural_engine_codegen target failed on darwin_arm64",
                snippet: "Build failed during invocation sponge2.corp/invocation/948274a1. 14 targets failed compilation.",
                body: """
                Build //compiler/xla:neural_engine_codegen failed at commit a94f28e.

                ERROR: /workspace/compiler/xla/service/darwin/ane_compiler.cc:214:12: error: \
                use of undeclared identifier 'ANE_MAX_CORE_FREQUENCY'
                    214 |   uint64_t freq = ANE_MAX_CORE_FREQUENCY;
                        |                   ^

                Target //compiler/xla:pjrt_c_api was canceled due to upstream target failure.
                Invocation URL: https://sponge2.corp/invocation/948274a1-b841-4ce8-b118-8f59a9e921d0

                Affected branches:
                - main
                - release-26.4-ane

                Please revert the offending CL or push a fix immediately to unblock team CI.
                """,
                category: .work,
                isVIP: false,
                urgencyScore: 0,
                requiresAction: true,
                suggestedAction: .scheduleTask,
                defaultMailbox: .inbox
            ),
            Template(
                sender: "PagerDuty P0",
                senderEmail: "alerts@pagerduty.internal",
                subject: "[CRITICAL] P0 Alert: Database connection pool exhausted (timeout 30000ms)",
                snippet: "Incident #94820 assigned to you. Database pool connection timeout on primary cluster. Screenshot attached.",
                body: """
                INCIDENT SUMMARY:
                Incident ID: #94820-P0
                Service: Core Database Cluster (europe-west4-a)
                Severity: CRITICAL (P0)
                Trigger: Connection pool exhausted (timeout 30000ms) on postgres-primary-01

                Attached screenshot: database_pool_timeout_trace.png

                Metrics Snapshot:
                - Cluster: eu-west4-db-primary
                - Active connections: 500 / 500 (pool saturated)
                - Waiting queries: 1,420
                - Impact: 4 active training and inference jobs stalled

                War Room: https://meet.corp.google.com/p0-db-emergency
                Slack Channel: #incident-94820-db-pool

                Reply ACK to acknowledge or ESCALATE to secondary on-call.
                """,
                category: .securityAlerts,
                isVIP: true,
                urgencyScore: 0,
                requiresAction: true,
                suggestedAction: .immediateAlert,
                defaultMailbox: .inbox
            ),
            Template(
                sender: "GitHub Actions",
                senderEmail: "notifications@github.com",
                subject: "Run failed: Swift 6 Strict Concurrency Matrix (#2849)",
                snippet: "Job 'macOS-15-arm64 (swift-6.0)' failed in 3m 42s. 2 concurrency violations found.",
                body: """
                GitHub Actions workflow 'Strict Concurrency Matrix' failed for commit 8fb21e0.

                Job summary:
                - Target: Swift 6.0 Complete Concurrency Checking
                - Failures:
                  - MailStore.swift:14:8: error: mutation of non-Sendable type across isolation boundary
                  - DecisionRouting.swift:45:19: warning: capture of 'session' with non-Sendable type in actor closure

                View full workflow logs: https://github.com/typesafe-ai/system-one-foundation-models/actions/runs/1849204

                Commit message: 'Refactor DecisionSession dispatching'
                Author: Peter Friese <peter@apple.com>
                """,
                category: .work,
                isVIP: false,
                urgencyScore: 2,
                requiresAction: true,
                suggestedAction: .scheduleTask,
                defaultMailbox: .inbox
            ),
            // Code Reviews
            Template(
                sender: "Jeff Dean",
                senderEmail: "jeff@google.com",
                subject: "Review requested: CL/649201948 - Optimize memory layout in TensorBufferAllocator",
                snippet: "Can we avoid this heap allocation in the hot inference loop? Benchmarks look promising overall.",
                body: """
                Hi Peter,

                I looked over CL/649201948:
                "Optimize memory layout in TensorBufferAllocator for ANE hardware alignment."

                Overall the 18% throughput improvement on M4 Max is impressive. One question regarding:
                `Sources/CoreML/TensorBufferAllocator.swift:84`

                Could we use stack allocation or a scratch ring-buffer for intermediate tensor descriptors instead of `UnsafeMutableRawBufferPointer.allocate(byteCount:...)`?
                Under 120Hz continuous dispatch, the allocator churn might induce micro-stutters during GC/malloc passes.

                Let me know what you think, or let's chat in the design doc.

                Best,
                Jeff
                """,
                category: .work,
                isVIP: true,
                urgencyScore: 2,
                requiresAction: true,
                suggestedAction: .draftReply,
                defaultMailbox: .inbox
            ),
            Template(
                sender: "Chris Lattner",
                senderEmail: "clattner@modular.com",
                subject: "Feedback on LanguageModelSession Swift 6 ergonomic proposals",
                snippet: "The call-site first approach with @Generable schemas is spot on. Here are some thoughts on Sendable isolation.",
                body: """
                Peter,

                Really enjoyed reviewing the latest draft of the Foundation Models System One bridge.

                Having:
                ```swift
                let session = LanguageModelSession(model: selectedModel)
                let response = try await session.respond(to: prompt, generating: Decision.self)
                ```
                as the primary call-site is exactly the kind of progressive disclosure Swift needs. It completely avoids the unnecessary abstraction layers that plagued earlier inference SDKs.

                One thought: for offline Core ML model loading, ensure the model compilation step doesn't hop back and forth across actors unnecessarily. Keeping the weights warm in unified memory will give you sub-5ms latencies.

                Let's catch up next week.

                Cheers,
                Chris
                """,
                category: .work,
                isVIP: true,
                urgencyScore: 1,
                requiresAction: false,
                suggestedAction: .scheduleTask,
                defaultMailbox: .inbox
            ),
            Template(
                sender: "Craig Federighi",
                senderEmail: "craig@apple.com",
                subject: "Liquid Glass adoption & ProMotion 120Hz validation in MailTriage",
                snippet: "Great work on keeping Liquid Glass outside of scroll view rows. The 120Hz ProMotion experience is velvety smooth.",
                body: """
                Team,

                I spent some time test driving the latest MailTriage build on macOS 27 and iOS 27.

                Adhering to the rule of keeping glass effects strictly in floating toolbars and navigation bars rather than list rows makes an enormous difference. The ProMotion scroll performance is silky smooth even with 500+ messages in the virtualized list.

                Let's ensure the empty state reader and the bottom triage drawer maintain that same level of visual finesse.

                Keep up the fantastic craftsmanship!

                Craig
                """,
                category: .work,
                isVIP: true,
                urgencyScore: 1,
                requiresAction: false,
                suggestedAction: .moveToInbox,
                defaultMailbox: .inbox
            ),
            // Apple Purchases & Developer Program
            Template(
                sender: "Apple Developer Program",
                senderEmail: "developer@apple.com",
                subject: "Your Apple Developer Program membership has been renewed",
                snippet: "Your annual membership has been successfully renewed. Your certificates, identifiers, and profiles remain active.",
                body: """
                Dear Peter,

                Thank you for renewing your Apple Developer Program membership.

                Order Number: W948102847
                Membership Expiration: September 24, 2027
                Annual Fee: $99.00 USD

                All your app IDs, provisioning profiles, CloudKit databases, and TestFlight distributions will continue uninterrupted.
                You can manage your account and access pre-release SDKs at:
                https://developer.apple.com/account

                Apple Developer Relations
                """,
                category: .billing,
                isVIP: false,
                urgencyScore: 3,
                requiresAction: false,
                suggestedAction: .autoArchive,
                defaultMailbox: .inbox
            ),
            Template(
                sender: "App Store Connect",
                senderEmail: "no_reply@email.apple.com",
                subject: "TestFlight: MailTriage version 2.4 (Build 492) is ready for testing",
                snippet: "Build 492 is now available for internal and external testers. Processing completed in 4 minutes.",
                body: """
                The following build has completed processing and is ready for TestFlight testing:

                App: MailTriage (macOS & iOS)
                Version: 2.4
                Build: 492
                SDK: macOS 27.0 / iOS 27.0
                Commit: 7ab1c9f (feature/liquid-glass-sidebar)

                To notify your testers or configure public test groups, visit App Store Connect:
                https://appstoreconnect.apple.com/apps/mailtriage/testflight

                Apple Worldwide Developer Relations
                """,
                category: .work,
                isVIP: false,
                urgencyScore: 1,
                requiresAction: false,
                suggestedAction: .scheduleTask,
                defaultMailbox: .inbox
            ),
            // Cloud Invoices & Billing
            Template(
                sender: "Google Cloud Billing",
                senderEmail: "billing-noreply@google.com",
                subject: "Monthly Statement: Google Cloud Platform TPU v5e Cluster ($14,892.40)",
                snippet: "Your invoice for billing period Aug 1 - Aug 31, 2026 is now available. Auto-payment will process in 3 days.",
                body: """
                Google Cloud Platform Billing Statement

                Account: TypeSafe AI Enterprise Production (ID: 0184A-94B2C-8812F)
                Billing Period: August 1, 2026 - August 31, 2026
                Total Due: $14,892.40 USD

                Breakdown:
                - Cloud TPU v5e Pod Slices (europe-west4): $11,240.00
                - Google Cloud Storage (Multi-region EU): $1,420.40
                - Inter-region Network Egress (RoCE / VPC): $1,850.00
                - Cloud Logging & Monitoring: $382.00

                Payment Method: Corporate Amex ending in 4092 (Auto-charge scheduled for Sep 27, 2026).
                Download official PDF tax invoice: https://console.cloud.google.com/billing
                """,
                category: .billing,
                isVIP: false,
                urgencyScore: 1,
                requiresAction: true,
                suggestedAction: .scheduleTask,
                defaultMailbox: .billing
            ),
            Template(
                sender: "Stripe Invoicing",
                senderEmail: "invoices@stripe.com",
                subject: "Invoice #INV-2026-8819 from TypeSafe Jev Cloud ($3,420.00)",
                snippet: "Receipt for 85,500,000 System One inference calls. Attached: invoice_INV-2026-8819.png.",
                body: """
                Invoice #INV-2026-8819
                Amount Paid: $3,420.00 USD
                Date: September 22, 2026

                Description:
                - TypeSafe Jev Pro Tier Tier-1 Inferences: 85.5M decisions @ $0.040 per 1k calls
                - Mean Latency: 12ms (p99: 28ms)
                - Uptime SLA: 99.995%

                Card charged: Visa ending in 8831.
                Attachment: invoice_INV-2026-8819.png (official tax invoice scan).
                Questions? Visit https://dashboard.typesafe.ai/billing
                """,
                category: .billing,
                isVIP: false,
                urgencyScore: 0,
                requiresAction: false,
                suggestedAction: .autoArchive,
                defaultMailbox: .billing
            ),
            // Security notices & Phishing
            Template(
                sender: "Okta Security Alerts",
                senderEmail: "security-noreply@okta.com",
                subject: "Security Alert: New login from unrecognized device (Dublin, Ireland)",
                snippet: "A successful login to your Apple Corporate SSO was detected from macOS 14.2 in Dublin, Ireland.",
                body: """
                OKTA IDENTITY THREAT DETECTION

                A new sign-in was verified for user: peter@apple.com
                Time: Today at 04:12 AM UTC
                Location: Dublin, Leinster, Ireland (IP: 185.122.91.44)
                Device: macOS 14.2 / Safari 18.0
                Authentication Method: FastPass Biometrics + FIDO2 YubiKey

                If this was you (e.g. traveling or using corporate VPN), no action is required.
                If you did not authorize this login, immediately click:
                https://identity.apple.internal/revoke-all-sessions?token=948a12
                """,
                category: .securityAlerts,
                isVIP: false,
                urgencyScore: 2,
                requiresAction: true,
                suggestedAction: .immediateAlert,
                defaultMailbox: .securityAlerts
            ),
            Template(
                sender: "Executive Payroll Office",
                senderEmail: "executive-wire-update@sec-notice-payroll-auth.info",
                subject: "URGENT: Confidential Executive Wire Transfer verification needed by 5 PM",
                snippet: "Please verify the urgent wire transfer instructions for the overseas board member immediately. Attached login prompt.",
                body: """
                CONFIDENTIAL & TIME SENSITIVE

                Hello,

                Due to the recent quarterly audit, we need you to review and verify the revised banking wire coordinates for the senior executive board distribution ($185,000.00).

                Please review the attached login prompt (swift_wire_verification.png) and verify your corporate credentials to confirm the SWIFT routing number before banking cutoff at 5:00 PM EST.

                Download Link: http://sec-notice-payroll-auth.info/wire-form-oct26.exe

                Thank you,
                Executive Finance Operations
                """,
                category: .quarantine,
                isVIP: false,
                urgencyScore: 3,
                requiresAction: true,
                suggestedAction: .quarantineThreat,
                defaultMailbox: .quarantine
            ),
            Template(
                sender: "Corporate Compliance",
                senderEmail: "compliance@apple.corp",
                subject: "Action Required: Complete Mandatory Q3 Security & Data Privacy Training",
                snippet: "Annual compliance deadline is approaching in 6 business days. Please complete the 20-minute module.",
                body: """
                Team Member,

                All Apple and affiliate engineers must complete the Q3 2026 Security & Data Privacy refresher before Friday, October 2nd.

                Course highlights:
                - On-device data isolation & Neural Engine safety protocols
                - Phishing defense and hardware security key usage
                - Handling confidential benchmark numbers

                Link to Learning Portal: https://learning.internal.apple.com/course/sec-q3-2026
                Estimated duration: 20 minutes.
                """,
                category: .work,
                isVIP: false,
                urgencyScore: 1,
                requiresAction: true,
                suggestedAction: .scheduleTask,
                defaultMailbox: .inbox
            ),
            // Meetings & Calendar
            Template(
                sender: "Elena Rostova",
                senderEmail: "elena@apple.com",
                subject: "1:1 Sync Agenda: Q4 Engineering OKRs & Staff Promotion Packet",
                snippet: "Looking forward to our sync tomorrow at 10 AM. Here is the draft agenda and packet doc.",
                body: """
                Hi Peter,

                For our 1:1 tomorrow at 10:00 AM, I'd like to cover three topics:

                1. Reviewing the MailTriage Foundation Models launch metrics and community adoption.
                2. Finalizing your Staff Engineer promotion packet blurbs (I added notes to section 3).
                3. On-call coverage rotation for the upcoming Thanksgiving sprint.

                Meeting link: https://meet.apple.com/elena-peter-sync
                Agenda doc: https://quip.apple.com/9482/okr-staff-review

                See you tomorrow!
                Elena
                """,
                category: .meetings,
                isVIP: true,
                urgencyScore: 1,
                requiresAction: false,
                suggestedAction: .scheduleTask,
                defaultMailbox: .meetings
            ),
            Template(
                sender: "Marcus Vance",
                senderEmail: "marcus.v@apple.com",
                subject: "Sprint 26.4 Planning & Retro: Backlog Grooming Notes",
                snippet: "Summary of sprint commitments: 42 story points accepted, focusing on FoundationModels integration.",
                body: """
                Hi team,

                Here is the summary of our Sprint 26.4 Planning:

                Sprint Goals:
                - Implement 3-pane NavigationSplitView for MailTriage macOS & iOS
                - Achieve 100% offline unit testing via MockJevTransport & MockSystemOneBackend
                - Benchmark sub-10ms response times for on-device Core ML decisions

                Total capacity: 48 points. Committed: 42 points.
                Jira Sprint Board: https://jira.internal.apple.com/secure/RapidBoard.jspa?rapidView=819

                Thanks everyone for the focused discussion!
                Marcus
                """,
                category: .meetings,
                isVIP: false,
                urgencyScore: 1,
                requiresAction: false,
                suggestedAction: .scheduleTask,
                defaultMailbox: .meetings
            ),
            Template(
                sender: "David Chen",
                senderEmail: "david.c@apple.com",
                subject: "On-call swap request: Covering primary shift on Tuesday Oct 6",
                snippet: "Can anyone swap primary on-call on Oct 6? Happy to take your weekend shift in exchange.",
                body: """
                Hey folks,

                I have a personal family conflict on Tuesday Oct 6 and won't be able to carry the primary PagerDuty pager from 9 AM to 9 PM PST.

                Would anyone on the rotation be willing to swap with me? I'm happy to cover your shift the following Saturday or Sunday in return.

                Let me know if that works for you and I'll submit the schedule override in PagerDuty.

                Thanks a ton,
                David
                """,
                category: .work,
                isVIP: false,
                urgencyScore: 2,
                requiresAction: true,
                suggestedAction: .draftReply,
                defaultMailbox: .inbox
            ),
            // Newsletters & Technical Digests
            Template(
                sender: "John Sundell",
                senderEmail: "john@swiftbysundell.com",
                subject: "Swift Weekly #418: Swift 6 Strict Concurrency, FlowDeck CLI, & Modern SwiftUI",
                snippet: "This week, we explore building high-performance macOS split views, mastering Swift 6 isolation, and FlowDeck.",
                body: """
                Welcome to Swift Weekly issue #418!

                In this issue:
                - Mastering Swift 6 Strict Concurrency: Why actor hops matter in high-throughput pipelines.
                - Apple's NavigationSplitView in macOS 27: Achieving native 3-column elegance with zero boilerplate.
                - FlowDeck CLI in Action: Revolutionizing Apple platform build automation with structured diagnostics.
                - Tip of the week: Using @Observable with fine-grained view invalidation.

                Read the full issue online at: https://swiftbysundell.com/weekly/418

                Happy Swifting!
                John
                """,
                category: .newsletters,
                isVIP: false,
                urgencyScore: 0,
                requiresAction: false,
                suggestedAction: .autoArchive,
                defaultMailbox: .newsletters
            ),
            Template(
                sender: "Alex Xu",
                senderEmail: "alex@bytebytego.com",
                subject: "ByteByteGo Newsletter: How Large-Scale Decision Engines Handle 10M QPS",
                snippet: "Deep dive into low-latency decision model architectures, single-pass forward propagation vs autoregression.",
                body: """
                Hi engineers,

                In today's deep dive, we explore why modern mobile architectures are shifting from heavy LLMs to lightweight System One decision models:

                1. Autoregressive token generation costs 20-50x more memory and latency than single-pass classification heads.
                2. Calibrated probabilities (Nouls) allow enterprise systems to safely route high-confidence actions while human-escalating ambiguities.
                3. On-device Apple Neural Engine execution eliminates network hops, achieving sub-5ms latency and zero cloud costs.

                Architecture diagram and benchmarks included in the full post:
                https://blog.bytebytego.com/p/decision-engines-architecture-10m-qps

                Until next time,
                Alex Xu
                """,
                category: .newsletters,
                isVIP: false,
                urgencyScore: 0,
                requiresAction: false,
                suggestedAction: .autoArchive,
                defaultMailbox: .newsletters
            ),
            Template(
                sender: "ArXiv Daily Feed",
                senderEmail: "digest@arxiv.org",
                subject: "ArXiv CS.AI: Sparse Attention & Decision Transformer Architectures for On-Device Inference",
                snippet: "4 new papers matching your tracked topics: [cs.AI, cs.LG, Apple Neural Engine, Decision Models].",
                body: """
                arXiv Daily Computer Science Update
                Tracked categories: cs.AI, cs.LG, cs.NE

                1. "Sub-Millisecond System One Decision Modeling on Mobile Silicon"
                   Authors: K. Zhang, M. Hoffman, L. Dupont
                   Abstract: We present an optimization technique mapping multi-head decision models to hardware-accelerated INT8 matrix units on modern mobile SoCs, achieving 450 inferences/sec at under 0.8W power draw.

                2. "Calibrated Epistemic Uncertainty in Foundation Model Agents"
                   Authors: S. Venkatesh, R. Chen
                   Abstract: Proposing dual-signal confidence gating for autonomous workflow dispatch.

                Full papers available at: https://arxiv.org/list/cs.AI/recent
                """,
                category: .newsletters,
                isVIP: false,
                urgencyScore: 0,
                requiresAction: false,
                suggestedAction: .autoArchive,
                defaultMailbox: .newsletters
            ),
            Template(
                sender: "Kelsey Hightower",
                senderEmail: "kelsey@minimalist.dev",
                subject: "Reflecting on Simple Software Architectures in 2026",
                snippet: "The best code is the code that doesn't need to exist. Why native Apple Foundation Models hit the sweet spot.",
                body: """
                Peter,

                Read your technical note on the Foundation Models integration.

                "Simplicity is prerequisite for reliability." When developers don't have to manage custom HTTP connection pools, authentication headers, and proprietary response parsers, the entire application becomes much easier to reason about.

                Keep pushing for minimal abstractions. Software that gets out of the developer's way is the software that lasts.

                Best regards,
                Kelsey
                """,
                category: .work,
                isVIP: true,
                urgencyScore: 0,
                requiresAction: false,
                suggestedAction: .draftReply,
                defaultMailbox: .inbox
            )
        ]

        var emails: [Email] = []
        emails.reserveCapacity(500)

        // Target: exactly 500 emails, with ~180 unread (let's do exactly 180 unread and 320 read)
        // Mailbox distribution:
        // - inbox: 415
        // - drafts: 15
        // - sent: 25
        // - archive: 25
        // - quarantine: 10
        // - securityAlerts: 10

        let totalEmails = 500
        let targetUnread = 180

        // Select exactly targetUnread (180) indices within inbox items (0..<415)
        var unreadIndices = Set<Int>()
        var stepCounter = 0
        while unreadIndices.count < targetUnread && stepCounter < 1000 {
            let index = (stepCounter * 7 + 1) % 415
            unreadIndices.insert(index)
            stepCounter += 1
        }

        // Secondary senders for variety
        let secondarySenders = [
            ("Sarah Connor", "sarah.c@apple.com"),
            ("Priya Patel", "priya.p@corp.net"),
            ("Alexei Romanov", "alexei@security.internal"),
            ("Jordan Lee", "jordan.lee@dev.to"),
            ("Rachel Adams", "radams@cloudops.org"),
            ("Michael Chang", "mchang@systems.internal"),
            ("Hanna Lindberg", "hanna.l@nordic-tech.io"),
            ("Tariq Mansoor", "tariq@neural-inference.org")
        ]

        let invoiceAttachment = EmailAttachment(
            filename: "invoice_INV-2026-8819.png",
            mimeType: "image/png",
            data: generateInvoicePNG()
        )
        let databaseAttachment = EmailAttachment(
            filename: "database_pool_timeout_trace.png",
            mimeType: "image/png",
            data: generateDatabaseCrashPNG()
        )
        let phishingAttachment = EmailAttachment(
            filename: "swift_wire_verification.png",
            mimeType: "image/png",
            data: generatePhishingWirePNG()
        )

        for i in 0..<totalEmails {
            let baseTemplate = templates[i % templates.count]
            let isUnread = unreadIndices.contains(i)

            // Calculate timestamp: item 0 is 2 minutes ago, spread out over ~14 days (1,209,600 seconds)
            // Quadratic distribution so there are more recent emails today/yesterday
            let normalizedRatio = Double(i) / Double(totalEmails)
            let secondsAgo = 120.0 + (normalizedRatio * normalizedRatio * 1_200_000.0) + Double(i * 180)
            let emailDate = referenceDate.addingTimeInterval(-secondsAgo)

            // Flags: roughly 1 in 8 emails flagged
            let isFlagged = (i % 8 == 2)

            // VIP: based on template or specific prominent indices
            let isVIP = baseTemplate.isVIP || (i % 15 == 0)

            // Sender variation: periodically inject secondary senders
            let sender: String
            let senderEmail: String
            if i >= templates.count && i % 4 == 0 {
                let sec = secondarySenders[(i / 4) % secondarySenders.count]
                sender = sec.0
                senderEmail = sec.1
            } else {
                sender = baseTemplate.sender
                senderEmail = baseTemplate.senderEmail
            }

            // Subject with subtle index qualification if repetitive
            let subject: String
            if i < templates.count {
                subject = baseTemplate.subject
            } else {
                let cycle = (i / templates.count) + 1
                switch baseTemplate.category {
                case .work:
                    subject = "\(baseTemplate.subject) [Batch #\(cycle)]"
                case .securityAlerts:
                    subject = "\(baseTemplate.subject) (Ticket #\(8000 + i))"
                case .billing:
                    subject = "\(baseTemplate.subject) (Ref #\(4000 + i))"
                case .meetings:
                    subject = "\(baseTemplate.subject) (Follow-up #\(cycle))"
                case .newsletters:
                    subject = "\(baseTemplate.subject) — Edition \(cycle)"
                case .quarantine:
                    subject = "\(baseTemplate.subject) [Ref \(900 + i)]"
                }
            }

            // Mailbox assignment:
            let mailbox: Mailbox
            if i < 415 {
                mailbox = .inbox
            } else if i < 430 {
                mailbox = .drafts
            } else if i < 455 {
                mailbox = .sent
            } else if i < 480 {
                mailbox = .archive
            } else if i < 490 {
                mailbox = .quarantine
            } else {
                mailbox = .securityAlerts
            }

            var emailAttachments: [EmailAttachment] = []
            if baseTemplate.subject.contains("INV-2026-8819") {
                emailAttachments = [invoiceAttachment]
            } else if baseTemplate.subject.contains("Database connection pool") {
                emailAttachments = [databaseAttachment]
            } else if baseTemplate.subject.contains("Executive Wire Transfer") {
                emailAttachments = [phishingAttachment]
            }

            let email = Email(
                id: UUID(),
                sender: sender,
                senderEmail: senderEmail,
                recipient: (mailbox == .sent) ? "team@apple.com" : "developer@apple.com",
                subject: subject,
                previewSnippet: baseTemplate.snippet,
                body: baseTemplate.body,
                date: emailDate,
                isUnread: (mailbox == .sent || mailbox == .drafts) ? false : isUnread,
                isFlagged: isFlagged,
                isVIP: isVIP,
                mailbox: mailbox,
                category: baseTemplate.category,
                urgencyScore: baseTemplate.urgencyScore,
                requiresAction: baseTemplate.requiresAction,
                suggestedAction: baseTemplate.suggestedAction,
                attachments: emailAttachments
            )

            emails.append(email)
        }

        // Sort descending by date (newest first)
        emails.sort { $0.date > $1.date }

        return emails
    }

    // MARK: - Synthetic Attachment Image Generation

    public static func generateInvoicePNG() -> Data {
        renderSyntheticPNG(width: 480, height: 320) { ctx in
            // Background: Light warm gray (#F8F9FA)
            ctx.setFillColor(red: 0.97, green: 0.98, blue: 0.98, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 0, width: 480, height: 320))

            // White invoice card
            ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            let cardRect = CGRect(x: 20, y: 16, width: 440, height: 288)
            let cardPath = CGPath(roundedRect: cardRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(cardPath)
            ctx.fillPath()

            // Header banner (Blue #1A73E8)
            ctx.setFillColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1.0)
            let headerRect = CGRect(x: 20, y: 256, width: 440, height: 48)
            let headerPath = CGPath(roundedRect: headerRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(headerPath)
            ctx.fillPath()

            // Header accent rectangles representing company logo & INVOICE #INV-2026-8819
            ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.95)
            ctx.fill(CGRect(x: 36, y: 272, width: 80, height: 16))
            ctx.fill(CGRect(x: 310, y: 274, width: 130, height: 12))

            // Metadata row
            ctx.setFillColor(red: 0.4, green: 0.45, blue: 0.5, alpha: 1.0)
            ctx.fill(CGRect(x: 40, y: 226, width: 100, height: 10))
            ctx.fill(CGRect(x: 40, y: 210, width: 160, height: 8))
            ctx.fill(CGRect(x: 320, y: 226, width: 120, height: 10))
            ctx.fill(CGRect(x: 320, y: 210, width: 90, height: 8))

            // Table header bar
            ctx.setFillColor(red: 0.93, green: 0.94, blue: 0.96, alpha: 1.0)
            ctx.fill(CGRect(x: 36, y: 176, width: 408, height: 22))

            // Table rows & simulated text lines
            let rows: [(itemW: CGFloat, costW: CGFloat, y: CGFloat)] = [
                (180, 48, 148),
                (220, 48, 122),
                (160, 48, 96)
            ]
            for row in rows {
                ctx.setFillColor(red: 0.25, green: 0.28, blue: 0.32, alpha: 1.0)
                ctx.fill(CGRect(x: 44, y: row.y, width: row.itemW, height: 8))
                ctx.setFillColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
                ctx.fill(CGRect(x: 388, y: row.y, width: row.costW, height: 8))

                ctx.setStrokeColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
                ctx.setLineWidth(1)
                ctx.strokeLineSegments(between: [CGPoint(x: 36, y: row.y - 8), CGPoint(x: 444, y: row.y - 8)])
            }

            // Total / Paid stamp box (Green #059669)
            ctx.setFillColor(red: 0.02, green: 0.59, blue: 0.41, alpha: 0.15)
            let paidRect = CGRect(x: 300, y: 40, width: 144, height: 36)
            let paidPath = CGPath(roundedRect: paidRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(paidPath)
            ctx.fillPath()

            ctx.setStrokeColor(red: 0.02, green: 0.59, blue: 0.41, alpha: 0.8)
            ctx.setLineWidth(2)
            ctx.addPath(paidPath)
            ctx.strokePath()

            ctx.setFillColor(red: 0.02, green: 0.59, blue: 0.41, alpha: 1.0)
            ctx.fill(CGRect(x: 316, y: 52, width: 112, height: 12))
        }
    }

    public static func generateDatabaseCrashPNG() -> Data {
        renderSyntheticPNG(width: 500, height: 320) { ctx in
            // Terminal background (#1E1E2E)
            ctx.setFillColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 0, width: 500, height: 320))

            // Window titlebar (#181825)
            ctx.setFillColor(red: 0.09, green: 0.09, blue: 0.15, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 288, width: 500, height: 32))

            // macOS window control buttons
            ctx.setFillColor(red: 0.93, green: 0.27, blue: 0.27, alpha: 1.0)
            ctx.fillEllipse(in: CGRect(x: 16, y: 298, width: 12, height: 12))
            ctx.setFillColor(red: 0.95, green: 0.69, blue: 0.22, alpha: 1.0)
            ctx.fillEllipse(in: CGRect(x: 36, y: 298, width: 12, height: 12))
            ctx.setFillColor(red: 0.30, green: 0.76, blue: 0.47, alpha: 1.0)
            ctx.fillEllipse(in: CGRect(x: 56, y: 298, width: 12, height: 12))

            // Title bar simulated text
            ctx.setFillColor(red: 0.5, green: 0.52, blue: 0.62, alpha: 1.0)
            ctx.fill(CGRect(x: 160, y: 300, width: 180, height: 8))

            // Error alert box (Dark crimson #450A0A)
            ctx.setFillColor(red: 0.27, green: 0.04, blue: 0.04, alpha: 1.0)
            let errRect = CGRect(x: 20, y: 226, width: 460, height: 48)
            let errPath = CGPath(roundedRect: errRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(errPath)
            ctx.fillPath()

            // Crimson border
            ctx.setStrokeColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 0.8)
            ctx.setLineWidth(1.5)
            ctx.addPath(errPath)
            ctx.strokePath()

            // Error pill + "FATAL: Connection pool exhausted (timeout 30000ms)"
            ctx.setFillColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1.0)
            ctx.fill(CGRect(x: 32, y: 250, width: 54, height: 14))
            ctx.fill(CGRect(x: 94, y: 252, width: 280, height: 10))
            ctx.setFillColor(red: 0.95, green: 0.6, blue: 0.6, alpha: 0.9)
            ctx.fill(CGRect(x: 32, y: 234, width: 340, height: 8))

            // Stack trace lines
            let traceLines: [(color: (r: CGFloat, g: CGFloat, b: CGFloat), x: CGFloat, w: CGFloat, y: CGFloat)] = [
                ((0.95, 0.65, 0.2), 24, 420, 196),
                ((0.90, 0.25, 0.25), 24, 380, 174),
                ((0.55, 0.70, 0.95), 44, 310, 148),
                ((0.55, 0.70, 0.95), 44, 290, 126),
                ((0.70, 0.72, 0.80), 44, 340, 104),
                ((0.70, 0.72, 0.80), 44, 260, 82),
                ((0.86, 0.15, 0.15), 24, 210, 50)
            ]
            for line in traceLines {
                ctx.setFillColor(red: line.color.r, green: line.color.g, blue: line.color.b, alpha: 0.95)
                ctx.fill(CGRect(x: line.x, y: line.y, width: line.w, height: 7))
            }
        }
    }

    public static func generatePhishingWirePNG() -> Data {
        renderSyntheticPNG(width: 480, height: 320) { ctx in
            // Background (#F1F5F9)
            ctx.setFillColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 0, width: 480, height: 320))

            // Urgent header banner (Red #DC2626)
            ctx.setFillColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1.0)
            ctx.fill(CGRect(x: 0, y: 272, width: 480, height: 48))

            // Warning icon & banner text bars
            ctx.setFillColor(red: 1.0, green: 0.9, blue: 0.2, alpha: 1.0)
            ctx.fill(CGRect(x: 20, y: 288, width: 16, height: 16))
            ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            ctx.fill(CGRect(x: 46, y: 290, width: 280, height: 12))

            // Central fake auth modal card
            ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            let modalRect = CGRect(x: 30, y: 24, width: 420, height: 232)
            let modalPath = CGPath(roundedRect: modalRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
            ctx.addPath(modalPath)
            ctx.fillPath()

            // Card border
            ctx.setStrokeColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1.0)
            ctx.setLineWidth(1)
            ctx.addPath(modalPath)
            ctx.strokePath()

            // Subtitle
            ctx.setFillColor(red: 0.35, green: 0.38, blue: 0.44, alpha: 1.0)
            ctx.fill(CGRect(x: 48, y: 224, width: 290, height: 9))

            // Field 1: SWIFT / Routing Code Box
            ctx.setFillColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1.0)
            ctx.fill(CGRect(x: 48, y: 198, width: 140, height: 8))
            ctx.setFillColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
            let f1 = CGRect(x: 48, y: 164, width: 384, height: 28)
            ctx.fill(f1)
            ctx.setStrokeColor(red: 0.80, green: 0.84, blue: 0.90, alpha: 1.0)
            ctx.stroke(f1)
            ctx.setFillColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            ctx.fill(CGRect(x: 58, y: 174, width: 120, height: 8))

            // Field 2: Token / Signature Box
            ctx.setFillColor(red: 0.45, green: 0.48, blue: 0.54, alpha: 1.0)
            ctx.fill(CGRect(x: 48, y: 142, width: 160, height: 8))
            let f2 = CGRect(x: 48, y: 108, width: 384, height: 28)
            ctx.setFillColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0)
            ctx.fill(f2)
            ctx.stroke(f2)
            ctx.setFillColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
            for d in 0..<8 {
                ctx.fillEllipse(in: CGRect(x: 58 + (d * 14), y: 119, width: 6, height: 6))
            }

            // Big Urgent Authorization Button (Crimson #DC2626)
            ctx.setFillColor(red: 0.86, green: 0.15, blue: 0.15, alpha: 1.0)
            let btnRect = CGRect(x: 48, y: 44, width: 384, height: 36)
            let btnPath = CGPath(roundedRect: btnRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            ctx.addPath(btnPath)
            ctx.fillPath()

            ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            ctx.fill(CGRect(x: 120, y: 56, width: 240, height: 12))
        }
    }

    #if canImport(CoreGraphics) && canImport(ImageIO) && canImport(UniformTypeIdentifiers)
    private static func renderSyntheticPNG(width: Int, height: Int, draw: (CGContext) -> Void) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return fallbackPNGData()
        }

        draw(context)

        guard let image = context.makeImage() else {
            return fallbackPNGData()
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return fallbackPNGData()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return fallbackPNGData()
        }
        return data as Data
    }
    #else
    private static func renderSyntheticPNG(width: Int, height: Int, draw: (Any) -> Void) -> Data {
        fallbackPNGData()
    }
    #endif

    private static func fallbackPNGData() -> Data {
        Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
    }
}
