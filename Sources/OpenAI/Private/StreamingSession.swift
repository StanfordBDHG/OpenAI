//
//  StreamingSession.swift
//  
//
//  Created by Sergii Kryvoblotskyi on 18/04/2023.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Security

final class StreamingSession<ResultType: Codable>: NSObject, Identifiable, URLSessionDelegate, URLSessionDataDelegate {
    
    enum StreamingError: Error {
        case unknownContent
        case emptyContent
    }
    
    var onReceiveContent: ((StreamingSession, ResultType) -> Void)?
    var onProcessingError: ((StreamingSession, Error) -> Void)?
    var onComplete: ((StreamingSession, Error?) -> Void)?
    
    private let streamingCompletionMarker = "[DONE]"
    private let urlRequest: URLRequest
    private lazy var urlSession: URLSession = {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return session
    }()
    
    private var previousChunkBuffer = ""
    private let caCertificate: SecCertificate?
    private let expectedHost: String?

    /// Create an instance of the `StreamingSession`
    ///
    /// - Parameters:
    ///    - urlRequest: Base `URLRequest`
    ///    - caCertificate: The optional, to-be-trusted custom CA certificate.
    ///    - expectedHost: The optional expected hostname to verify the received TLS token against. Useful for network requests to another domain or IP than the host issued the TLS token (e.g. within a local network with non-public hostnames and requests via IPs)
    init(urlRequest: URLRequest, caCertificate: SecCertificate? = nil, expectedHost: String? = nil) {
        self.urlRequest = urlRequest
        self.caCertificate = caCertificate
        self.expectedHost = expectedHost
    }
    
    func perform() {
        self.urlSession
            .dataTask(with: self.urlRequest)
            .resume()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(self, error)
    }
    
    /// Handle HTTP 401 and 403 status codes returned by OpenAI API implementations such as Ollama and completes the current request with an error.
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let httpResponse = response as? HTTPURLResponse {
                // Handle negative HTTP status code returned by various OpenAI API implementations
                if httpResponse.statusCode == 401 {
                    // Propagate the HTTP error up the call stack
                    onComplete?(
                        self,
                        APIErrorResponse(
                            error: .init(
                                message: "HTTP 401: Unauthorized",
                                type: "unauthorized",
                                param: nil,
                                code: "401"
                            )
                        )
                    )
                    completionHandler(.cancel)
                    return
                } else if httpResponse.statusCode == 403 {
                    // Propagate the HTTP error up the call stack
                    onComplete?(
                        self,
                        APIErrorResponse(
                            error: .init(
                                message: "HTTP 403: Forbidden",
                                type: "forbidden",
                                param: nil,
                                code: "403"
                            )
                        )
                    )
                    completionHandler(.cancel)
                    return
                }
            }
            
            completionHandler(.allow)
        }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let stringContent = String(data: data, encoding: .utf8) else {
            onProcessingError?(self, StreamingError.unknownContent)
            return
        }
        processJSON(from: stringContent)
    }
    
    /// Handle custom TLS certificate verification of `StreamingSession` requests.
    ///
    /// Uses the `caCertificate` and `expectedHost` parameters of the `StreamingSession` to verify the server's authenticity and establish a secure SSL connection.
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let caCertificate, let expectedHost else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Set the anchor certificate
        let anchorCertificates: [SecCertificate] = [caCertificate]
        SecTrustSetAnchorCertificates(serverTrust, anchorCertificates as CFArray)
        
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        
        let policy = SecPolicyCreateSSL(true, expectedHost as CFString)
        SecTrustSetPolicies(serverTrust, policy)
        
        var error: CFError?
        if SecTrustEvaluateWithError(serverTrust, &error) {
            // Trust evaluation succeeded, proceed with the connection
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            // Trust evaluation failed, handle the error
            print("OpenAI: Trust evaluation failed with error: \(String(describing: error?.localizedDescription))")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

extension StreamingSession {
    
    private func processJSON(from stringContent: String) {
        if stringContent.isEmpty {
            return
        }
        let jsonObjects = "\(previousChunkBuffer)\(stringContent)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "data:")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        previousChunkBuffer = ""
        
        guard jsonObjects.isEmpty == false, jsonObjects.first != streamingCompletionMarker else {
            return
        }
        jsonObjects.enumerated().forEach { (index, jsonContent)  in
            guard jsonContent != streamingCompletionMarker && !jsonContent.isEmpty else {
                return
            }
            guard let jsonData = jsonContent.data(using: .utf8) else {
                onProcessingError?(self, StreamingError.unknownContent)
                return
            }
            let decoder = JSONDecoder()
            do {
                let object = try decoder.decode(ResultType.self, from: jsonData)
                onReceiveContent?(self, object)
            } catch {
                if let decoded = try? decoder.decode(APIErrorResponse.self, from: jsonData) {
                    onProcessingError?(self, decoded)
                } else if index == jsonObjects.count - 1 {
                    previousChunkBuffer = "data: \(jsonContent)" // Chunk ends in a partial JSON
                } else {
                    onProcessingError?(self, error)
                }
            }
        }
    }
    
}
