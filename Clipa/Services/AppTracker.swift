import Foundation

/// Optional startup statistics. Source builds leave the endpoint unset.
final class AppTracker {
    static let shared = AppTracker()

    private init() {}

    func track() {
        guard Self.appInfoURL() != nil else { return }
        attemptTrack(attempt: 1, maxRetries: 5, retryDelay: 2)
    }


    private func attemptTrack(attempt: Int, maxRetries: Int, retryDelay: TimeInterval) {
        guard let url = Self.appInfoURL() else {
            retryOrFail(attempt: attempt, maxRetries: maxRetries, retryDelay: retryDelay)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }
            if let error {
                print("AppTracker 请求失败: \(error.localizedDescription)")
                self.retryOrFail(attempt: attempt, maxRetries: maxRetries, retryDelay: retryDelay)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("AppTracker 响应异常: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                self.retryOrFail(attempt: attempt, maxRetries: maxRetries, retryDelay: retryDelay)
                return
            }

            print("AppTracker 统计成功")
        }.resume()
    }

    private static func appInfoURL() -> URL? {
        guard let endpoint = Bundle.main.object(forInfoDictionaryKey: "ClipaStartupStatsURL") as? String,
              var components = URLComponents(string: endpoint),
              components.scheme == "https", components.host != nil else { return nil }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        components.queryItems = [
            URLQueryItem(name: "platform", value: "ios"),
            URLQueryItem(name: "version", value: version),
            URLQueryItem(name: "build", value: build)
        ]
        return components.url
    }

    private func retryOrFail(attempt: Int, maxRetries: Int, retryDelay: TimeInterval) {
        guard attempt < maxRetries else {
            print("AppTracker 已达最大重试次数")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            self?.attemptTrack(attempt: attempt + 1, maxRetries: maxRetries, retryDelay: retryDelay)
        }
    }
}
