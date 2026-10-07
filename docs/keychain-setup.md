# macOS & iOS Keychain Sharing Setup Guide 🔐

This guide details how to configure **Keychain Sharing** and the **Data Protection Keychain** for `MailTriageApp` on macOS and iOS, how the credential storage layer works in Swift, and how to troubleshoot common code-signing and entitlement issues.

---

## 1. Overview: Data Protection Keychain vs. Legacy Keychain

On Apple platforms, credentials such as API tokens (`TYPESAFE_API_KEY`, `CLOUDFLARE_API_TOKEN`) and account IDs must be securely persisted without exposing them in unencrypted storage (`UserDefaults`, plist files, or plaintext caches).

### The macOS Keychain Dilemma

Historically, macOS and iOS handled keychain operations differently:

| Feature | iOS Keychain | macOS Legacy Keychain (`login.keychain-db`) | macOS Data Protection Keychain |
| :--- | :--- | :--- | :--- |
| **Backend** | Secure Enclave & Data Protection | File-based SQLite database | Modern Data Protection subsystem |
| **Prompt Behavior** | Transparent to owning app | Prompts user with OS dialog to allow access | Transparent to entitled app |
| **Hardware Binding** | `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | Not supported (file password) | Supported (tied to hardware keys) |
| **Entitlement Requirement** | Implicit sandboxed app container | None | **Strictly required** (`keychain-access-groups`) |
| **Syncing** | iCloud Keychain support | Separate mechanism | Modern synced keychain support |

By default, the macOS Security framework (`SecItemAdd`, `SecItemCopyMatching`) interacts with the legacy file-based keychain. This can trigger disruptive system authorization prompts asking the user to grant access.

### Why MailTriageApp Uses the Data Protection Keychain

In `MailTriageApp`, `KeychainService` explicitly enables the modern Data Protection Keychain across both macOS and iOS:

```swift
private func baseQuery(forKey key: String) -> [String: Any] {
    [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: serviceName,
        kSecAttrAccount as String: key,
        kSecUseDataProtectionKeychain as String: true // Modern Data Protection
    ]
}
```

Setting `kSecUseDataProtectionKeychain = true` on macOS provides:
1. **API Parity**: Identical behavior and access semantics on iOS and macOS.
2. **Seamless UX**: No disruptive system dialogs prompting the user to allow keychain access on every launch or update.
3. **Hardware Protection**: Enables modern accessibility attributes such as `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

> [!IMPORTANT]
> On macOS, setting `kSecUseDataProtectionKeychain = true` **requires** that the application is signed with a valid **Keychain Access Groups** entitlement. Running without this entitlement causes keychain calls to fail with `errSecMissingEntitlement` (`-34018`) or triggers a kernel `SIGKILL`.

---

## 2. Step-by-Step Xcode Setup

Follow these steps to configure Keychain Sharing for `MailTriageApp`:

### Step 1: Open the Project in Xcode

Launch Xcode and open the project file:
```text
Examples/MailTriageApp/apps/apple/MailTriageApp.xcodeproj
```

### Step 2: Navigate to Target Signing & Capabilities

1. In the **Project Navigator** (`Cmd + 1`), select the top-level project `MailTriageApp`.
2. Under **Targets**, select `MailTriageApp`.
3. Select the **Signing & Capabilities** tab.

### Step 3: Select Your Apple Development Team

1. Under the **Signing** section, verify that **Automatically manage signing** is checked.
2. In the **Team** dropdown, select your personal or organization Apple Developer Team (do not leave as "None" or "Sign to Run Locally").
3. Verify that the **Bundle Identifier** is set (for example, `dev.peterfriese.mailtriageapp` or your customized reverse-domain identifier).

### Step 4: Add the Keychain Sharing Capability

1. In the top-left corner of the **Signing & Capabilities** tab, click **+ Capability**.
2. In the capability library search field, type `Keychain Sharing`.
3. Double-click **Keychain Sharing** to add the capability card to your target.

### Step 5: Configure Keychain Groups

In the newly added **Keychain Sharing** card:
1. Click the **+** button under **Keychain Groups**.
2. Add the following entry:
   ```text
   $(AppIdentifierPrefix)dev.peterfriese.mailtriageapp
   ```
   *(Alternatively, use `$(AppIdentifierPrefix)$(CFBundleIdentifier)` to match whatever bundle ID you have configured).*
3. Press **Return** to commit the group.

---

## 3. How Xcode Manages Provisioning & Entitlements

When you perform the steps above, Xcode handles configuration behind the scenes:

### 1. Entitlements File Creation

Xcode creates or updates `MailTriageApp/MailTriageApp.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>keychain-access-groups</key>
	<array>
		<string>$(AppIdentifierPrefix)dev.peterfriese.mailtriageapp</string>
	</array>
</dict>
</plist>
```

### 2. Variable Expansion: `$(AppIdentifierPrefix)`

The `$(AppIdentifierPrefix)` macro is resolved during code signing:
- On macOS and iOS, Apple prepends your **Team ID** (e.g., `YGAZHQXHH4.`) to the keychain group string.
- The resulting access group embedded into the binary is `YGAZHQXHH4.dev.peterfriese.mailtriageapp`.
- This ensures your app's keychain items cannot be accessed by other applications from different developer teams.

### 3. Build Settings Configuration

Xcode automatically updates the target's build configuration in `project.pbxproj`:
- `CODE_SIGN_ENTITLEMENTS = MailTriageApp/MailTriageApp.entitlements;`
- `CODE_SIGN_STYLE = Automatic;`

When building, Xcode generates a provisioning profile that authorizes the `keychain-access-groups` capability for your Team ID and embeds it into the application bundle.

---

## 4. Swift Architecture: `@KeychainStorage` and `KeychainKey`

The credential storage architecture in `MailTriageApp` lives in `Packages/AppCore` and `Packages/AppUI`. It provides an Apple-native, SwiftUI-ergonomic API for managing secrets.

### 1. Type-Safe Enum: `KeychainKey`

Credentials are categorized using the strongly typed enum `KeychainKey`:

```swift
public enum KeychainKey: String, Sendable, CaseIterable {
    case cloudflareAccountId = "cloudflareAccountId"
    case cloudflareApiToken = "cloudflareApiToken"
    case typesafeApiKey = "typesafeApiKey"
    case hostedVpcToken = "hostedVpcToken"
    case huggingFaceToken = "huggingFaceToken"
}
```

### 2. Service Layer: `KeychainService`

`KeychainService` implements `KeychainServiceProtocol` and encapsulates all interactions with the Apple Security framework:

- **Data Protection**: Enforces `kSecUseDataProtectionKeychain = true`.
- **Accessibility**: Applies `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
- **Concurrency**: Thread-safe with internal locking (`NSLock`).
- **Clean Deletion**: Setting an empty string or `nil` automatically removes the item from the keychain.

### 3. SwiftUI Property Wrapper: `@KeychainStorage`

Modeled after Apple's `@AppStorage`, `@KeychainStorage` is a `DynamicProperty` that binds keychain values directly to SwiftUI views:

```swift
import SwiftUI
import AppCore

struct CloudflareSettingsCard: View {
    @KeychainStorage(.cloudflareAccountId) private var accountId = ""
    @KeychainStorage(.cloudflareApiToken) private var apiToken = ""

    var body: some View {
        Form {
            TextField("Account ID", text: $accountId)
                .textFieldStyle(.roundedBorder)

            SecureField("API Token", text: $apiToken)
                .textFieldStyle(.roundedBorder)
        }
    }
}
```

**Features of `@KeychainStorage`:**
- **Two-Way Binding**: Accessing the projected value (`$accountId`) yields a standard SwiftUI `Binding<String>`.
- **Automatic Persistence**: Modifying the property immediately updates or removes the item in the keychain.
- **View Invalidation**: When the stored value changes, the containing SwiftUI view is invalidated and re-rendered.
- **Dependency Injection**: Resolves `KeychainServiceProtocol` via FactoryKit (`Container.shared.keychainService`), allowing seamless substitution of mock implementations during testing and previews.

### 4. Dependency Injection & Canvas Previews

To run SwiftUI Canvas Previews or offline tests without touching the real macOS Keychain, `AppCore` provides `MockKeychainService`:

```swift
// Inject in-memory keychain for previews
Container.shared.keychainService.register {
    MockKeychainService(initialStorage: [
        KeychainKey.cloudflareAccountId.rawValue: "preview-account-id",
        KeychainKey.cloudflareApiToken.rawValue: "preview-token"
    ])
}
```

---

## 5. Troubleshooting & Common Pitfalls

### Issue 1: `errSecMissingEntitlement` (`OSStatus -34018`)

#### Symptoms
When launching the app or attempting to save credentials in Settings, the console outputs:
```text
Keychain operation failed with status -34018 (OSStatus -34018)
SecItemAdd / SecItemCopyMatching failed: -34018
```

#### Causes
1. **Missing Team**: The target is configured with **Sign to Run Locally** (ad-hoc signing) instead of an active Apple Developer team.
2. **Missing Capability**: The `Keychain Sharing` capability has not been added to the target.
3. **Missing Entitlement File**: The `CODE_SIGN_ENTITLEMENTS` build setting does not point to a valid `.entitlements` file containing `keychain-access-groups`.

#### Remediation
1. In Xcode, navigate to `MailTriageApp` target > **Signing & Capabilities**.
2. Select your registered developer team under **Team**.
3. Verify the **Keychain Sharing** capability is present and includes `$(AppIdentifierPrefix)dev.peterfriese.mailtriageapp`.
4. Clean the build folder (`Cmd + Shift + K`) and rebuild (`Cmd + R`).

---

### Issue 2: Process Crash on Launch (`SIGKILL` / `EXC_CRASH`)

#### Symptoms
The app crashes immediately upon launch before `NSApplicationMain` executes:
```text
Command /Applications/Xcode.app/Contents/Developer/usr/bin/actool failed with exit code 1
Process killed with signal 9 (SIGKILL) [Code 0xdead10cc]
kernel: Security entitlement verification failed for process ...
```

#### Causes
The entitlements file requests a keychain access group with a Team ID that does not match the signing certificate's Team ID, or the local provisioning profile is out of date.

#### Remediation
1. Open `MailTriageApp.entitlements` and verify that the group prefix uses `$(AppIdentifierPrefix)` rather than a hardcoded Team ID from another developer account.
2. In Xcode > **Settings** > **Accounts**, select your Apple ID and click **Download Manual Profiles**.
3. Re-run `flowdeck build` or press `Cmd + R` in Xcode.

---

### Issue 3: Works on iOS Simulator but Fails on macOS Native

#### Symptoms
The app runs and saves credentials normally in the iOS Simulator, but fails with `-34018` when run as a native macOS app (**My Mac**).

#### Causes
The iOS Simulator environment simulates keychain operations without enforcing full hardware code-signing verification. In contrast, native macOS execution strictly checks Mach-O code-signing validity, Apple Developer team certificates, and task entitlement blobs.

#### Remediation
Configure code signing for the macOS target as described in [Section 2](#2-step-by-step-xcode-setup). For local development where no Apple Developer Team is available, use `MockKeychainService` via FactoryKit in your test harnesses and previews.

---

## 6. Summary Checklist

- [ ] `MailTriageApp.xcodeproj` opened in Xcode.
- [ ] Valid Apple Developer Team selected in **Signing & Capabilities**.
- [ ] **Keychain Sharing** capability added to `MailTriageApp` target.
- [ ] Keychain group `$(AppIdentifierPrefix)dev.peterfriese.mailtriageapp` configured.
- [ ] `MailTriageApp.entitlements` verified and referenced in `CODE_SIGN_ENTITLEMENTS`.
- [ ] Clean build and verified credential saving in Settings (`Cmd + ,`).
