# Android Build Plan — CreatorAI

Scope: RevenueCat + AppsFlyer integration (matching iOS implementation)

---

## Stack

- **Language**: Kotlin
- **UI**: Jetpack Compose
- **Architecture**: MVVM (ViewModel + StateFlow)
- **Min SDK**: 26 (Android 8.0)
- **Target SDK**: 35

---

## Dependencies (build.gradle)

```kotlin
// RevenueCat
implementation("com.revenuecat.purchases:purchases:7.+")
implementation("com.revenuecat.purchases:purchases-ui:7.+")  // Paywall UI

// AppsFlyer
implementation("com.appsflyer:af-android-sdk:6.+")
implementation("com.android.installreferrer:installreferrer:2.2")

// Supabase (auth)
implementation(platform("io.github.jan-tennert.supabase:bom:2.+"))
implementation("io.github.jan-tennert.supabase:gotrue-kt")
implementation("io.ktor:ktor-client-okhttp:2.+")

// Google Sign-In (replaces Apple Sign-In)
implementation("com.google.android.gms:play-services-auth:21.+")

// Security (replaces Keychain)
implementation("androidx.security:security-crypto:1.1.0-alpha06")
```

---

## Project Structure

```
app/src/main/java/com/holylabs/creatorai/
├── CreatorAIApp.kt              // Application class (configure SDKs)
├── MainActivity.kt              // Single activity
├── AppState.kt                  // Global state (ViewModel)
├── services/
│   ├── PurchaseService.kt       // RevenueCat wrapper
│   ├── AppsFlyerService.kt      // AppsFlyer wrapper
│   ├── AuthService.kt           // Google Sign-In + Supabase
│   └── CreditsService.kt        // /api/credits/get + /api/credits/add
└── ui/
    ├── settings/
    │   ├── SettingsScreen.kt
    │   └── BuyCreditsScreen.kt  // RevenueCat paywall
    └── auth/
        └── LoginScreen.kt       // Google Sign-In
```

---

## Phase 1 — Project Setup (Day 1)

- [ ] Create Android project in `/android/` subfolder
- [ ] Configure `build.gradle` with all dependencies
- [ ] Set up `google-services.json` (Firebase project for Google Sign-In)
- [ ] Add `AndroidManifest.xml` permissions: `INTERNET`, `ACCESS_NETWORK_STATE`
- [ ] Set up `local.properties` for API keys (not committed)
- [ ] Configure ProGuard rules for RevenueCat + AppsFlyer

---

## Phase 2 — AppsFlyer (Day 1–2)

iOS reference: `CreatorAI/Services/AppsFlyerService.swift`

**Android equivalent** (`AppsFlyerService.kt`):
```kotlin
object AppsFlyerService : AppsFlyerConversionListener {
    private const val DEV_KEY = "GbYoDDZzgatShWKfu2nwiJ"

    fun configure(context: Context) {
        AppsFlyerLib.getInstance().apply {
            init(DEV_KEY, this@AppsFlyerService, context)
            setDebugLog(BuildConfig.DEBUG)
        }
    }

    fun start(context: Context) {
        AppsFlyerLib.getInstance().start(context)
    }

    // No ATT on Android — uses standard permissions model
    override fun onConversionDataSuccess(data: Map<String, Any>) {}
    override fun onConversionDataFail(error: String) {}
    override fun onAppOpenAttribution(data: Map<String, String>) {}
    override fun onAttributionFailure(error: String) {}
}
```

Called from `Application.onCreate()` (replaces iOS `AppDelegate.didFinishLaunching`).

**Key difference from iOS**: No ATT dialog on Android. AppsFlyer uses install referrer instead.

---

## Phase 3 — Auth (Day 2–3)

iOS uses Apple Sign-In → Android uses Google Sign-In, same Supabase backend.

```kotlin
class AuthService(private val context: Context) {
    private val supabase = createSupabaseClient(
        supabaseUrl = "YOUR_SUPABASE_URL",
        supabaseKey = "YOUR_SUPABASE_ANON_KEY"
    ) { install(GoTrue) }

    suspend fun signInWithGoogle(): AuthResult {
        // 1. Google Sign-In → get idToken
        // 2. supabase.gotrue.signInWith(IDToken) { provider = Google; idToken = ... }
        // 3. Store JWT in EncryptedSharedPreferences (replaces Keychain)
    }
}
```

Token storage (replaces `KeychainHelper`):
```kotlin
val prefs = EncryptedSharedPreferences.create(
    context, "secure_prefs",
    MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)
```

---

## Phase 4 — RevenueCat (Day 3–4)

iOS reference: `CreatorAI/Services/PurchaseService.swift`

**Android API key**: Create new Android app in RevenueCat dashboard → get `goog_` prefixed key.

```kotlin
@Singleton
class PurchaseService @Inject constructor() {

    private val creditAmounts = mapOf(
        "credits_100" to 100,
        "credits_200" to 200,
        "credits_300" to 300
    )

    fun configure(context: Context, userId: String) {
        Purchases.configure(
            PurchasesConfiguration.Builder(context, "goog_YOUR_KEY")
                .appUserID(userId)
                .build()
        )
    }

    suspend fun loadOfferings(): List<Package> {
        return withContext(Dispatchers.IO) {
            Purchases.sharedInstance.awaitOfferings().current?.availablePackages ?: emptyList()
        }
    }

    suspend fun purchase(activity: Activity, pkg: Package): Boolean {
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(activity, pkg)
            handlePurchaseCompleted(result.storeTransaction.productIds.first())
            true
        } catch (e: PurchasesException) {
            if (e.code == PurchasesErrorCode.PurchaseCancelledError) false
            else throw e
        }
    }

    suspend fun restorePurchases(): Boolean {
        return try {
            Purchases.sharedInstance.awaitRestore()
            true
        } catch (e: PurchasesException) { false }
    }

    private suspend fun handlePurchaseCompleted(productId: String) {
        val credits = creditAmounts[productId] ?: 100
        addCreditsOnServer(productId, credits)
    }

    private suspend fun addCreditsOnServer(productId: String, amount: Int) {
        // POST http://api.holylabs.net/api/credits/add
        // body: { userId, productId, amount }
    }
}
```

**Key difference from iOS**: `purchase()` requires an `Activity` reference (needed for Google Play billing sheet).

---

## Phase 5 — AppState + Credits (Day 4)

Direct port of `AppState.swift` → `AppState.kt` as `ViewModel`:

```kotlin
class AppState : ViewModel() {
    val isAuthenticated = MutableStateFlow(false)
    val userId = MutableStateFlow<String?>(null)
    val credits = MutableStateFlow(0)
    val isLoadingCredits = MutableStateFlow(false)

    fun setAuth(token: String, userId: String, email: String?) {
        // store in EncryptedSharedPreferences
        // configure PurchaseService
        viewModelScope.launch { fetchCredits() }
    }

    suspend fun fetchCredits() {
        // POST http://api.holylabs.net/api/credits/get
        // body: { userId }
    }
}
```

Anonymous ID fallback (same as iOS):
```kotlin
val anonymousId = prefs.getString("RevenueCatAnonymousId", null)
    ?: UUID.randomUUID().toString().also { prefs.edit().putString("RevenueCatAnonymousId", it).apply() }
```

---

## Phase 6 — UI Screens (Day 4–5)

### BuyCreditsScreen (Jetpack Compose)
- Use RevenueCat's `PaywallDialog` (Compose) — matches iOS `RevenueCatUI` paywall
- Trigger from Settings screen

### SettingsScreen
- Show credits balance
- "Buy Credits" button → opens paywall
- "Restore Purchases" button
- Sign out button

### LoginScreen
- Google Sign-In button
- On success → `appState.setAuth(...)`

---

## RevenueCat Dashboard Setup

1. Add Android app to existing RevenueCat project
2. Link same products (`credits_100`, `credits_200`, `credits_300`) — create as Google Play consumables
3. Get Android API key (`goog_...`)
4. Same entitlements/offerings as iOS

---

## API Endpoints (unchanged from iOS)

| Endpoint | Method | Body |
|----------|--------|------|
| `/api/credits/get` | POST | `{ userId }` |
| `/api/credits/add` | POST | `{ userId, productId, amount }` |

No backend changes needed.

---

## Files to Create

```
android/
├── app/
│   ├── build.gradle
│   ├── google-services.json     # not committed
│   ├── proguard-rules.pro
│   └── src/main/
│       ├── AndroidManifest.xml
│       └── java/com/holylabs/creatorai/
│           ├── CreatorAIApp.kt
│           ├── MainActivity.kt
│           ├── AppState.kt
│           ├── services/
│           │   ├── PurchaseService.kt
│           │   ├── AppsFlyerService.kt
│           │   ├── AuthService.kt
│           │   └── CreditsService.kt
│           └── ui/
│               ├── settings/SettingsScreen.kt
│               ├── settings/BuyCreditsScreen.kt
│               └── auth/LoginScreen.kt
├── build.gradle
└── settings.gradle
```

---

## Timeline

| Day | Work |
|-----|------|
| 1 | Project setup + AppsFlyer |
| 2 | Google Sign-In + Supabase auth |
| 3 | RevenueCat configure + offerings |
| 4 | Purchase flow + credits API + AppState |
| 5 | UI (Settings, BuyCredits, Login) + testing |

**Total: ~5 days** for a working Android app with feature parity on RevenueCat + AppsFlyer.
