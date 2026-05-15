import Foundation

/// Completion handler signature shared by the URL session protocol and mock.
typealias MockURLSessionCompletion = @Sendable (Data?, URLResponse?, Error?) -> Void

class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var mockData: Data?
    var mockResponse: URLResponse?
    var mockError: Error?

    func dataTask(with request: URLRequest,
                  completionHandler: @escaping MockURLSessionCompletion) -> MockURLSessionDataTask {
        return MockURLSessionDataTask {
            completionHandler(self.mockData, self.mockResponse, self.mockError)
        }
    }
    
    func setMockResponse(data: Data?, response: URLResponse?, error: Error?) {
        mockData = data
        mockResponse = response
        mockError = error
    }
}

protocol URLSessionProtocol {
    func dataTask(with request: URLRequest,
                  completionHandler: @escaping MockURLSessionCompletion) -> MockURLSessionDataTask
}

class MockURLSessionDataTask: @unchecked Sendable {
    private let closure: () -> Void

    init(closure: @escaping () -> Void) {
        self.closure = closure
    }

    func resume() {
        closure()
    }
}
