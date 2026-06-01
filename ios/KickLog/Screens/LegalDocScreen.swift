import SwiftUI
import WebKit

// 개인정보 처리방침 / 이용약관 — 번들에 포함된 HTML 을 WKWebView 로 표시.
// 오프라인 동작 + 서식 유지. App Store 제출용 URL 은 동일 내용을 GitHub Pages 로 별도 게시한다.
struct LegalDocScreen: View {

    enum Document {
        case privacy
        case terms

        var title: String {
            switch self {
            case .privacy: "개인정보 처리방침"
            case .terms: "이용약관"
            }
        }

        // 번들 내 HTML 리소스 이름 (privacy.html / terms.html).
        var resourceName: String {
            switch self {
            case .privacy: "privacy"
            case .terms: "terms"
            }
        }
    }

    let document: Document

    var body: some View {
        Group {
            if let url = bundleURL {
                LegalWebView(fileURL: url)
            } else {
                ContentUnavailableView("문서를 불러올 수 없습니다", systemImage: "doc.questionmark")
            }
        }
        .background(KLTokens.bg)
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // 동기화 그룹이 폴더 구조를 유지할 수도/flat 복사할 수도 있어 양쪽을 모두 시도한다.
    private var bundleURL: URL? {
        Bundle.main.url(forResource: document.resourceName, withExtension: "html", subdirectory: "Legal")
            ?? Bundle.main.url(forResource: document.resourceName, withExtension: "html")
    }
}

// WKWebView 를 SwiftUI 로 래핑 — 로컬 HTML 파일 로드.
private struct LegalWebView: UIViewRepresentable {
    let fileURL: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
    }
}
