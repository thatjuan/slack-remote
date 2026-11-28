import AppKit
import WebKit

/// Shows where sign-in is happening, plus native navigation and recovery controls.
@MainActor
final class SignInBrowserView: NSView {
    let webView: WKWebView

    private let host = NSTextField(labelWithString: "")
    private let lock = NSImageView(image: NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "Secure")!)
    private let back = NSButton()
    private let progress = NSProgressIndicator()
    private let layout = NSStackView()
    private var observations: [NSKeyValueObservation] = []
    private var bannerView: NSView?
    private var failureView: NSView?
    private var retryURL: URL

    init(webView: WKWebView, startURL: URL) {
        self.webView = webView
        retryURL = startURL
        super.init(frame: .zero)

        back.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        back.toolTip = "Back"
        back.isBordered = false
        back.target = self
        back.action = #selector(goBack)

        let reload = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")!,
                              target: self, action: #selector(reloadPage))
        reload.toolTip = "Reload"
        reload.isBordered = false
        host.font = .systemFont(ofSize: 12)
        host.lineBreakMode = .byTruncatingMiddle
        lock.contentTintColor = .secondaryLabelColor

        progress.style = .bar
        progress.controlSize = .small
        progress.isIndeterminate = false
        progress.maxValue = 1

        let toolbar = NSStackView(views: [back, reload, lock, host, NSView(), progress])
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        let separator = NSBox()
        separator.boxType = .separator
        let page = NSView()
        page.addSubview(webView)

        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 0
        [toolbar, separator, page].forEach(layout.addArrangedSubview)
        addSubview(layout)
        layout.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.heightAnchor.constraint(equalToConstant: 36),
            progress.widthAnchor.constraint(equalToConstant: 66),
            toolbar.widthAnchor.constraint(equalTo: layout.widthAnchor),
            separator.widthAnchor.constraint(equalTo: layout.widthAnchor),
            page.widthAnchor.constraint(equalTo: layout.widthAnchor),
            layout.leadingAnchor.constraint(equalTo: leadingAnchor),
            layout.trailingAnchor.constraint(equalTo: trailingAnchor),
            layout.topAnchor.constraint(equalTo: topAnchor),
            layout.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            webView.topAnchor.constraint(equalTo: page.topAnchor),
            webView.bottomAnchor.constraint(equalTo: page.bottomAnchor),
        ])
        observeNavigation()
        updateToolbar()
    }

    required init?(coder: NSCoder) { nil }

    func navigate(to url: URL) {
        clearFailure()
        retryURL = url
        webView.load(URLRequest(url: url))
        updateToolbar()
    }

    func showBanner(_ message: String?) {
        bannerView?.removeFromSuperview()
        bannerView = nil
        guard let message else { return }
        let banner = Self.banner(message)
        layout.insertArrangedSubview(banner, at: 2)
        banner.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
        bannerView = banner
    }

    /// Replace the page with a retry control while retaining the WebKit profile and history.
    func showFailure(retryURL: URL?) {
        clearFailure()
        if let retryURL, retryURL.scheme == "https" { self.retryURL = retryURL }
        webView.isHidden = true
        let label = NSTextField(wrappingLabelWithString: "Can't reach Slack. Check your connection.")
        label.alignment = .center
        let retry = NSButton(title: "Try Again", target: self, action: #selector(retryPage))
        let feedback = NSStackView(views: [label, retry])
        feedback.orientation = .vertical
        feedback.alignment = .centerX
        feedback.spacing = 16
        guard let page = webView.superview else { return }
        feedback.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(feedback)
        NSLayoutConstraint.activate([
            feedback.centerXAnchor.constraint(equalTo: page.centerXAnchor),
            feedback.centerYAnchor.constraint(equalTo: page.centerYAnchor),
            feedback.leadingAnchor.constraint(greaterThanOrEqualTo: page.leadingAnchor, constant: 24),
            feedback.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -24),
        ])
        failureView = feedback
        updateToolbar()
    }

    static func banner(_ message: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: message)
        let view = NSStackView(views: [label])
        view.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.13).cgColor
        return view
    }

    private func observeNavigation() {
        observations = [
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateToolbar() } },
            webView.observe(\.isLoading) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateToolbar() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateToolbar() } },
            webView.observe(\.estimatedProgress) { [weak self] _, _ in MainActor.assumeIsolated { self?.updateToolbar() } },
        ]
    }

    private func updateToolbar() {
        let url = webView.url ?? retryURL
        host.stringValue = url.host ?? ""
        lock.isHidden = url.scheme != "https"
        back.isEnabled = webView.canGoBack
        progress.doubleValue = webView.estimatedProgress
        progress.isHidden = !webView.isLoading || failureView != nil
    }

    private func clearFailure() {
        failureView?.removeFromSuperview()
        failureView = nil
        webView.isHidden = false
    }

    @objc private func goBack() {
        clearFailure()
        showBanner(nil)
        webView.goBack()
    }

    @objc private func reloadPage() {
        showBanner(nil)
        if failureView != nil || webView.url == nil { retryPage() }
        else { webView.reload() }
    }

    @objc private func retryPage() {
        navigate(to: retryURL)
    }
}
