import SwiftUI

// 오픈소스 라이선스 고지 화면 — 설정 > 정보 > 오픈소스 라이선스 진입점.
// SPM 의존성(Kakao iOS SDK, Alamofire)의 라이선스를 고지한다.
// MIT/Apache 2.0 모두 저작권·라이선스 고지 포함 의무가 있어 앱 내 정적 표시로 충족한다.
struct LicenseScreen: View {

    private struct License: Identifiable {
        let id = UUID()
        let name: String
        let url: String
        let summary: String
        let text: String
    }

    private let licenses: [License] = [
        License(
            name: "Kakao iOS SDK",
            url: "https://github.com/kakao/kakao-ios-sdk",
            summary: "Apache License 2.0 · Copyright Kakao Corp.",
            text: """
            Licensed under the Apache License, Version 2.0 (the "License");
            you may not use this file except in compliance with the License.
            You may obtain a copy of the License at

                http://www.apache.org/licenses/LICENSE-2.0

            Unless required by applicable law or agreed to in writing, software
            distributed under the License is distributed on an "AS IS" BASIS,
            WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
            See the License for the specific language governing permissions and
            limitations under the License.
            """
        ),
        License(
            name: "Alamofire",
            url: "https://github.com/Alamofire/Alamofire",
            summary: "MIT License · Copyright (c) Alamofire Software Foundation",
            text: """
            Permission is hereby granted, free of charge, to any person obtaining a copy
            of this software and associated documentation files (the "Software"), to deal
            in the Software without restriction, including without limitation the rights
            to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
            copies of the Software, and to permit persons to whom the Software is
            furnished to do so, subject to the following conditions:

            The above copyright notice and this permission notice shall be included in
            all copies or substantial portions of the Software.

            THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
            IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
            FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
            AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
            LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
            OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
            THE SOFTWARE.
            """
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(licenses) { license in
                    licenseCard(license)
                }
                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(KLTokens.bg)
        .navigationTitle("오픈소스 라이선스")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func licenseCard(_ license: License) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(license.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KLTokens.text)
            if let url = URL(string: license.url) {
                Link(license.url, destination: url)
                    .font(.system(size: 12))
                    .tint(KLTokens.pitch)
            }
            Text(license.summary)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KLTokens.textSec)
            Text(license.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(KLTokens.textTer)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(KLTokens.bgElev)
        .clipShape(RoundedRectangle(cornerRadius: KLTokens.radiusCard))
    }
}
