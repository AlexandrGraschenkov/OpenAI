//
//  AIEventStream.swift
//
//
//  Created by Kyrylo Mukha on 29.03.2023.
//

import Combine
import Foundation
#if canImport(FoundationNetworking) && canImport(FoundationXML)
import FoundationNetworking
import FoundationXML
#endif

public struct AIStreamResponse<ResponseType: Decodable> {
	public let stream: AIEventStream<ResponseType>
	public let message: ResponseType?
	public let data: Data?
	public var isFinished: Bool = false
	public var forceEnd: Bool = false
}

public final class AIEventStream<ResponseType: Decodable>: NSObject, URLSessionDataDelegate {
	private let request: URLRequest
	private var session: URLSession?
	private let credentialChecker: URLSessionDelegate?
	private var operationQueue: OperationQueue

	private var onStartCompletion: (() -> Void)?
	private var onCompleteCompletion: ((_ code: Int?, _ forceEnd: Bool, _ error: Error?) throws -> Void)?
	private var onMessageCompletion: ((_ data: Data, _ message: ResponseType?) -> Void)?

	private var isStreamActive: Bool = false

	private var fetchError: Error? = nil


	init(request: URLRequest, credentialChecker: URLSessionDelegate?) {
		self.request = request
		self.operationQueue = OperationQueue()
		operationQueue.maxConcurrentOperationCount = 1
		self.credentialChecker = credentialChecker
	}

	public func startStream() {
		guard session == nil else { return }

		let configurationHeaders = [
			"Accept": "text/event-stream",
			"Cache-Control": "no-cache"
		]

		let sessionConfiguration = URLSessionConfiguration.default
		sessionConfiguration.timeoutIntervalForRequest = TimeInterval(INT_MAX)
		sessionConfiguration.timeoutIntervalForResource = TimeInterval(INT_MAX)
		sessionConfiguration.httpAdditionalHeaders = configurationHeaders

		session = URLSession(configuration: sessionConfiguration, delegate: self, delegateQueue: operationQueue)
		session?.dataTask(with: request).resume()
	}

	public func stopStream() {
		isStreamActive = false
		session?.invalidateAndCancel()
		operationQueue.cancelAllOperations()
		try? onCompleteCompletion?(0, true, nil)
	}

	// MARK: - URLSessionDataDelegate

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
    	if let checker = credentialChecker, 
    		checker.urlSession?(session, didReceive: challenge, completionHandler: completionHandler) != nil {
    			// handled
    	} else {
    		completionHandler(.performDefaultHandling, nil)
    	}
    }

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
		completionHandler(URLSession.ResponseDisposition.allow)

		isStreamActive = true
		onStartCompletion?()
	}

	public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
		guard isStreamActive else { return }

		if let response = (dataTask.response as? HTTPURLResponse), let decodedError = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
			guard 200 ... 299 ~= response.statusCode, decodedError["error"] != nil else {
				let error = NSError(domain: NSURLErrorDomain, code: response.statusCode, userInfo: decodedError)
				fetchError = error
				return
			}
		}

		let decoder = JSONDecoder.aiDecoder

		let dataString = String(data: data, encoding: .utf8) ?? ""
		let lines = dataString.components(separatedBy: "\n")

		for line in lines {
			var message: ResponseType?

			if line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8) {
				message = try? decoder.decode(ResponseType.self, from: data)
			}

			onMessageCompletion?(data, message)
		}
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard let responseStatusCode = (task.response as? HTTPURLResponse)?.statusCode else {
			try? onCompleteCompletion?(nil, false, error ?? fetchError)
			return
		}

		var error = error
		if responseStatusCode >= 400, error == nil {
			var message = "Text generation failed"
            if responseStatusCode == 403 {
                message = "Access denied"
            }
            error = NSError(domain: "", code: responseStatusCode, userInfo: [NSLocalizedDescriptionKey: message]) as Error
		}
        
        try? onCompleteCompletion?(responseStatusCode, false, error ?? fetchError)
	}

	public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
		completionHandler(request)
	}
}

public extension AIEventStream {
	func onStart(_ onStartCompletion: @escaping (() -> Void)) {
		self.onStartCompletion = onStartCompletion
	}

	func onComplete(_ onCompleteCompletion: @escaping ((_ code: Int?, _ forceEnd: Bool, _ error: Error?) throws -> Void)) {
		self.onCompleteCompletion = onCompleteCompletion
	}

	func onMessage(_ onMessageCompletion: @escaping ((_ data: Data, _ message: ResponseType?) -> Void)) {
		self.onMessageCompletion = onMessageCompletion
	}
}
