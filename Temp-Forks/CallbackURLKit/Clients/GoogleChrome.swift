//
//  GoogleChrome
//  CallbackURLKit
/*
 The MIT License (MIT)
 Copyright (c) 2017 Eric Marchand (phimage)
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */
#if IMPORT
    import CallbackURLKit
#endif
import Foundation

/*
 Google chrome client class
 https://developer.chrome.com/multidevice/ios/links
 */
public class GoogleChrome: Client {

    #if os(macOS)
    public static let DownloadURL = URL(string: "https://www.google.com/chrome/browser/desktop/index.html")
    #else
    public static let DownloadURL = URL(string: "itms-apps://itunes.apple.com/us/app/chrome/id535886823")
    #endif

    public init() {
        super.init(urlScheme: "googlechrome-x-callback")
    }

    /*
     If chrome not installed open itunes.
     */
    public func checkInstalled() {
      if !self.appInstalled, let url = GoogleChrome.DownloadURL {
        Manager.open(url: url)
      }
    }

    public func open(url: String, newTab: Bool = false,
                     onSuccess: SuccessCallback? = nil, onFailure: FailureCallback? = nil, onCancel: CancelCallback? = nil) throws {
        var parameters = ["url": url]
        if newTab {
            parameters = ["create-new-tab": ""]
        }
        try self.perform(action: "open", parameters: parameters,
                         onSuccess: onSuccess, onFailure: onFailure, onCancel: onCancel)
    }

}
