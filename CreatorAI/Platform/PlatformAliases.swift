import SwiftUI
import AVFoundation

// MARK: - Cross-platform type aliases

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
public typealias PlatformView = UIView
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
public typealias PlatformView = NSView
#endif

// MARK: - PlatformImage convenience extensions (unified API)

extension PlatformImage {
    /// Create image from CGImage (cross-platform).
    static func from(cgImage: CGImage) -> PlatformImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }

    /// Create image from Data (cross-platform).
    static func from(data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #else
        return NSImage(data: data)
        #endif
    }

    /// Get JPEG data (cross-platform).
    func jpegData(quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        return jpegData(compressionQuality: quality)
        #else
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    /// Get CGImage (cross-platform).
    var platformCGImage: CGImage? {
        #if canImport(UIKit)
        return cgImage
        #else
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

// MARK: - SwiftUI Image from PlatformImage

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

// MARK: - Dismiss keyboard (cross-platform)

func dismissKeyboard() {
    #if canImport(UIKit)
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    #else
    NSApp.keyWindow?.makeFirstResponder(nil)
    #endif
}

// MARK: - macOS: remove default button bezel globally

#if os(macOS)
struct PlainButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.plain)
    }
}

extension View {
    /// On macOS, removes the default button bezel/frame from all buttons in this view tree.
    func plainButtonsOnMac() -> some View {
        #if os(macOS)
        self.modifier(PlainButtonStyleModifier())
        #else
        self
        #endif
    }
}
#endif

// MARK: - AVPlayerLayer view (cross-platform)

#if canImport(UIKit)
struct PlatformVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeUIView(context: Context) -> UIView {
        let view = _AVPlayerUIView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let v = uiView as? _AVPlayerUIView {
            v.playerLayer.player = player
            v.playerLayer.videoGravity = videoGravity
        }
    }
}

private final class _AVPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
    }
}

#elseif canImport(AppKit)
struct PlatformVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    var videoGravity: AVLayerVideoGravity = .resizeAspectFill

    func makeNSView(context: Context) -> NSView {
        let view = _AVPlayerNSView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = videoGravity
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? _AVPlayerNSView {
            v.playerLayer.player = player
            v.playerLayer.videoGravity = videoGravity
        }
    }
}

private final class _AVPlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(playerLayer)
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
#endif

// MARK: - Share (cross-platform)

#if canImport(UIKit)
struct PlatformShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#elseif canImport(AppKit)
struct PlatformShareSheet: View {
    let items: [Any]
    var body: some View {
        Button("Share") {
            guard let window = NSApp.keyWindow, let view = window.contentView else { return }
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }
}
#endif

// MARK: - WebView (cross-platform WKWebView wrapper)

import WebKit

#if canImport(UIKit)
struct PlatformWebView: UIViewRepresentable {
    let url: URL
    let onTokenReceived: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> WebViewCoordinator { WebViewCoordinator(onTokenReceived: onTokenReceived) }
}
#elseif canImport(AppKit)
struct PlatformWebView: NSViewRepresentable {
    let url: URL
    let onTokenReceived: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    func makeCoordinator() -> WebViewCoordinator { WebViewCoordinator(onTokenReceived: onTokenReceived) }
}
#endif

/// Shared coordinator for PlatformWebView.
class WebViewCoordinator: NSObject, WKNavigationDelegate {
    let onTokenReceived: (String) -> Void
    init(onTokenReceived: @escaping (String) -> Void) { self.onTokenReceived = onTokenReceived }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let token = components.queryItems?.first(where: { $0.name == "token" })?.value {
            onTokenReceived(token)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

// MARK: - Screen size helper

struct ScreenSize {
    static var width: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.width
        #else
        NSScreen.main?.frame.width ?? 1440
        #endif
    }

    static var height: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.height
        #else
        NSScreen.main?.frame.height ?? 900
        #endif
    }

    static var size: CGSize {
        CGSize(width: width, height: height)
    }
}
