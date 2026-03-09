import Foundation
import AppsFlyerLib
import AppTrackingTransparency

class AppsFlyerService: NSObject, AppsFlyerLibDelegate {
    static let shared = AppsFlyerService()

    private let devKey = "GbYoDDZzgatShWKfu2nwiJ"
    private let appleAppID = "6757284712"

    func configure() {
        let appsFlyer = AppsFlyerLib.shared()
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = appleAppID
        appsFlyer.delegate = self
        appsFlyer.waitForATTUserAuthorization(timeoutInterval: 60)
        #if DEBUG
        appsFlyer.isDebug = true
        #endif
        print("[AppsFlyer] SDK configured")
    }

    func start() {
        AppsFlyerLib.shared().start()
        print("[AppsFlyer] SDK started")
    }

    func requestTrackingAuthorization() {
        ATTrackingManager.requestTrackingAuthorization { status in
            switch status {
            case .authorized:
                print("[AppsFlyer] Tracking authorized")
            case .denied:
                print("[AppsFlyer] Tracking denied")
            case .restricted:
                print("[AppsFlyer] Tracking restricted")
            case .notDetermined:
                print("[AppsFlyer] Tracking not determined")
            @unknown default:
                break
            }
        }
    }

    // MARK: - AppsFlyerLibDelegate

    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {
        print("[AppsFlyer] Conversion data: \(conversionInfo)")
    }

    func onConversionDataFail(_ error: any Error) {
        print("[AppsFlyer] Conversion data error: \(error.localizedDescription)")
    }
}
