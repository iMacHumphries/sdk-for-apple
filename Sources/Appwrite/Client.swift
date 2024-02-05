import NIO
import NIOCore
import NIOFoundationCompat
import NIOSSL
import Foundation
import AsyncHTTPClient
@_exported import AppwriteModels

typealias CookieListener = (_ existing: [String], _ new: [String]) -> Void

let DASHDASH = "--"
let CRLF = "\r\n"

open class Client {

    // MARK: Properties
    public static var chunkSize = 5 * 1024 * 1024 // 5MB

    open var endPoint = "https://HOSTNAME/v1"

    open var endPointRealtime: String? = nil

    open var headers: [String: String] = [
        "content-type": "application/json",
        "x-sdk-name": "Apple",
        "x-sdk-platform": "client",
        "x-sdk-language": "apple",
        "x-sdk-version": "5.0.0-rc.1",
        "x-appwrite-response-format": "1.4.0"
    ]

    internal var config: [String: String] = [:]

    internal var selfSigned: Bool = false

    internal var http: HTTPClient

    internal static var cookieListener: CookieListener? = nil

    private static let boundaryChars = "abcdefghijklmnopqrstuvwxyz1234567890"

    private static let boundary = randomBoundary()

    private static var eventLoopGroupProvider = HTTPClient.EventLoopGroupProvider.singleton

    // MARK: Methods

    public init() {
        http = Client.createHTTP()
        addUserAgentHeader()
        addOriginHeader()
        NotificationHandler.shared.client = self
    }

    private static func createHTTP(
        selfSigned: Bool = false,
        maxRedirects: Int = 5,
        alloweRedirectCycles: Bool = false,
        connectTimeout: TimeAmount = .seconds(30),
        readTimeout: TimeAmount = .seconds(30)
    ) -> HTTPClient {
        let timeout = HTTPClient.Configuration.Timeout(
            connect: connectTimeout,
            read: readTimeout
        )
        let redirect = HTTPClient.Configuration.RedirectConfiguration.follow(
            max: 5,
            allowCycles: false
        )
        var tls = TLSConfiguration
            .makeClientConfiguration()

        if selfSigned {
            tls.certificateVerification = .none
        }

        return HTTPClient(
            eventLoopGroupProvider: eventLoopGroupProvider,
            configuration: HTTPClient.Configuration(
                tlsConfiguration: tls,
                redirectConfiguration: redirect,
                timeout: timeout,
                decompression: .enabled(limit: .none)
            )
        )

    }

    deinit {
        do {
            try http.syncShutdown()
        } catch {
            print(error)
        }
    }

    ///
    /// Set Project
    ///
    /// Your project ID
    ///
    /// @param String value
    ///
    /// @return Client
    ///
    open func setProject(_ value: String) -> Client {
        config["project"] = value
        _ = addHeader(key: "X-Appwrite-Project", value: value)
        return self
    }

    ///
    /// Set JWT
    ///
    /// Your secret JSON Web Token
    ///
    /// @param String value
    ///
    /// @return Client
    ///
    open func setJWT(_ value: String) -> Client {
        config["jwt"] = value
        _ = addHeader(key: "X-Appwrite-JWT", value: value)
        return self
    }

    ///
    /// Set Locale
    ///
    /// @param String value
    ///
    /// @return Client
    ///
    open func setLocale(_ value: String) -> Client {
        config["locale"] = value
        _ = addHeader(key: "X-Appwrite-Locale", value: value)
        return self
    }

    ///
    /// Set Session
    ///
    /// The user session to authenticate with
    ///
    /// @param String value
    ///
    /// @return Client
    ///
    open func setSession(_ value: String) -> Client {
        config["session"] = value
        _ = addHeader(key: "X-Appwrite-Session", value: value)
        return self
    }


    ///
    /// Set self signed
    ///
    /// @param Bool status
    ///
    /// @return Client
    ///
    open func setSelfSigned(_ status: Bool = true) -> Client {
        self.selfSigned = status
        try! http.syncShutdown()
        http = Client.createHTTP(selfSigned: status)
        return self
    }

    ///
    /// Set endpoint
    ///
    /// @param String endPoint
    ///
    /// @return Client
    ///
    open func setEndpoint(_ endPoint: String) -> Client {
        self.endPoint = endPoint

        if (self.endPointRealtime == nil && endPoint.starts(with: "http")) {
            self.endPointRealtime = endPoint
                .replacingOccurrences(of: "http://", with: "ws://")
                .replacingOccurrences(of: "https://", with: "wss://")
        }

        return self
    }

    ///
    /// Set realtime endpoint.
    ///
    /// @param String endPoint
    ///
    /// @return Client
    ///
    open func setEndpointRealtime(_ endPoint: String) -> Client {
        self.endPointRealtime = endPoint

        return self
    }

    ///
    /// Set push provider ID.
    ///
    /// @param String endpoint
    ///
    /// @return this
    ///
    open func setPushProviderId(_ providerId: String) -> Client {
        NotificationHandler.shared.providerId = providerId

        return self
    }

    ///
    /// Add header
    ///
    /// @param String key
    /// @param String value
    ///
    /// @return Client
    ///
    open func addHeader(key: String, value: String) -> Client {
        self.headers[key] = value
        return self
    }

   ///
   /// Builds a query string from parameters
   ///
   /// @param Dictionary<String, Any?> params
   /// @param String prefix
   ///
   /// @return String
   ///
   open func parametersToQueryString(params: [String: Any?]) -> String {
       var output: String = ""

       func appendWhenNotLast(_ index: Int, ofTotal count: Int, outerIndex: Int? = nil, outerCount: Int? = nil) {
           if (index != count - 1 || (outerIndex != nil
               && outerCount != nil
               && index == count - 1
               && outerIndex! != outerCount! - 1)) {
               output += "&"
           }
       }

       for (parameterIndex, element) in params.enumerated() {
           switch element.value {
           case nil:
               break
           case is Array<Any?>:
               let list = element.value as! Array<Any?>
               for (nestedIndex, item) in list.enumerated() {
                   output += "\(element.key)[]=\(item!)"
                   appendWhenNotLast(nestedIndex, ofTotal: list.count, outerIndex: parameterIndex, outerCount: params.count)
               }
               appendWhenNotLast(parameterIndex, ofTotal: params.count)
           default:
               output += "\(element.key)=\(element.value!)"
               appendWhenNotLast(parameterIndex, ofTotal: params.count)
           }
       }

       return output.addingPercentEncoding(
           withAllowedCharacters: .urlHostAllowed
       ) ?? ""
   }

    ///
    /// Make an API call
    ///
    /// @param String method
    /// @param String path
    /// @param Dictionary<String, Any?> params
    /// @param Dictionary<String, String> headers
    /// @return Response
    /// @throws Exception
    ///
    open func call<T>(
        method: String,
        path: String = "",
        headers: [String: String] = [:],
        params: [String: Any?] = [:],
        sink: ((ByteBuffer) -> Void)? = nil,
        converter: ((Any) -> T)? = nil
    ) async throws -> T {
        let validParams = params.filter { $0.value != nil }

        let queryParameters = method == "GET" && !validParams.isEmpty
            ? "?" + parametersToQueryString(params: validParams)
            : ""

        var request = HTTPClientRequest(url: endPoint + path + queryParameters)
        request.method = .RAW(value: method)


        for (key, value) in self.headers.merging(headers, uniquingKeysWith: { $1 }) {
            request.headers.add(name: key, value: value)
        }

        request.addDomainCookies()

        if "GET" == method {
            return try await execute(request, converter: converter)
        }

        try buildBody(for: &request, with: validParams)

        return try await execute(request, withSink: sink, converter: converter)
    }

    private func buildBody(
        for request: inout HTTPClientRequest,
        with params: [String: Any?]
    ) throws {
        if request.headers["content-type"][0] == "multipart/form-data" {
            buildMultipart(&request, with: params, chunked: !request.headers["content-range"].isEmpty)
        } else {
            try buildJSON(&request, with: params)
        }
    }

    private func execute<T>(
        _ request: HTTPClientRequest,
        withSink bufferSink: ((ByteBuffer) -> Void)? = nil,
        converter: ((Any) -> T)? = nil
    ) async throws -> T {
        let response = try await http.execute(
            request,
            timeout: .seconds(30)
        )

        switch response.status.code {
        case 0..<400:
            if response.headers["Set-Cookie"].count > 0 {
                let domain = URL(string: request.url)!.host!
                let existing = UserDefaults.standard.stringArray(forKey: domain)
                let new = response.headers["Set-Cookie"]

                Client.cookieListener?(existing ?? [], new)

                UserDefaults.standard.set(new, forKey: domain)
            }
            switch T.self {
            case is Bool.Type:
                return true as! T
            case is ByteBuffer.Type:
                return try await response.body.collect(upTo: Int.max) as! T
            default:
                let data = try await response.body.collect(upTo: Int.max)
                if data.readableBytes == 0 {
                    return true as! T
                }
                let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                return converter?(dict!) ?? dict! as! T
            }
        default:
            var message = ""
            var data = try await response.body.collect(upTo: Int.max)
            var type = ""

            do {
                let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                message = dict?["message"] as? String ?? response.status.reasonPhrase
                type = dict?["type"] as? String ?? ""
            } catch {
                message =  data.readString(length: data.readableBytes)!
            }

            throw AppwriteError(
                message: message,
                code: Int(response.status.code),
                type: type
            )
        }
    }

    func chunkedUpload<T>(
        path: String,
        headers: inout [String: String],
        params: inout [String: Any?],
        paramName: String,
        idParamName: String? = nil,
        converter: ((Any) -> T)? = nil,
        onProgress: ((UploadProgress) -> Void)? = nil
    ) async throws -> T {
        let input = params[paramName] as! InputFile

        switch(input.sourceType) {
        case "path":
            input.data = ByteBuffer(data: try! Data(contentsOf: URL(fileURLWithPath: input.path)))
        case "data":
            input.data = ByteBuffer(data: input.data as! Data)
        default:
            break
        }

        let size = (input.data as! ByteBuffer).readableBytes

        if size < Client.chunkSize {
            params[paramName] = input
            return try await call(
                method: "POST",
                path: path,
                headers: headers,
                params: params,
                converter: converter
            )
        }

        var offset = 0
        var result = [String:Any]()

        if idParamName != nil && params[idParamName!] as! String != "unique()" {
            // Make a request to check if a file already exists
            do {
                let map = try await call(
                    method: "GET",
                    path: path + "/" + (params[idParamName!] as! String),
                    headers: headers,
                    params: [:],
                    converter: { return $0 as! [String: Any] }
                )
                let chunksUploaded = map["chunksUploaded"] as! Int
                offset = chunksUploaded * Client.chunkSize
            } catch {
                // File does not exist yet, swallow exception
            }
        }

        while offset < size {
            let slice = (input.data as! ByteBuffer).getSlice(at: offset, length: Client.chunkSize)
                ?? (input.data as! ByteBuffer).getSlice(at: offset, length: Int(size - offset))

            params[paramName] = InputFile.fromBuffer(slice!, filename: input.filename, mimeType: input.mimeType)
            headers["content-range"] = "bytes \(offset)-\(min((offset + Client.chunkSize) - 1, size - 1))/\(size)"

            result = try await call(
                method: "POST",
                path: path,
                headers: headers,
                params: params,
                converter: { return $0 as! [String: Any] }
            )

            offset += Client.chunkSize
            headers["x-appwrite-id"] = result["$id"] as? String
            onProgress?(UploadProgress(
                id: result["$id"] as? String ?? "",
                progress: Double(min(offset, size))/Double(size) * 100.0,
                sizeUploaded: min(offset, size),
                chunksTotal: result["chunksTotal"] as? Int ?? -1,
                chunksUploaded: result["chunksUploaded"] as? Int ?? -1
            ))
        }

        return converter!(result)
    }

    private static func randomBoundary() -> String {
        var string = ""
        for _ in 0..<16 {
            string.append(Client.boundaryChars.randomElement()!)
        }
        return string
    }

    private func buildJSON(
        _ request: inout HTTPClientRequest,
        with params: [String: Any?] = [:]
    ) throws {
        var encodedParams = [String:Any]()

        for (key, param) in params {
            if param is String
                || param is Int
                || param is Float
                || param is Bool
                || param is [String]
                || param is [Int]
                || param is [Float]
                || param is [Bool]
                || param is [String: Any]
                || param is [Int: Any]
                || param is [Float: Any]
                || param is [Bool: Any] {
                encodedParams[key] = param
            } else {
                let value = try! (param as! Encodable).toJson()

                let range = value.index(value.startIndex, offsetBy: 1)..<value.index(value.endIndex, offsetBy: -1)
                let substring = value[range]

                encodedParams[key] = substring
            }
        }

        let json = try JSONSerialization.data(withJSONObject: encodedParams, options: [])

        request.body = .bytes(json)
    }

    private func buildMultipart(
        _ request: inout HTTPClientRequest,
        with params: [String: Any?] = [:],
        chunked: Bool = false
    ) {
        func addPart(name: String, value: Any) {
            bodyBuffer.writeString(DASHDASH)
            bodyBuffer.writeString(Client.boundary)
            bodyBuffer.writeString(CRLF)
            bodyBuffer.writeString("Content-Disposition: form-data; name=\"\(name)\"")

            if let file = value as? InputFile {
                bodyBuffer.writeString("; filename=\"\(file.filename)\"")
                bodyBuffer.writeString(CRLF)
                bodyBuffer.writeString("Content-Length: \(bodyBuffer.readableBytes)")
                bodyBuffer.writeString(CRLF+CRLF)

                var buffer = file.data! as! ByteBuffer

                bodyBuffer.writeBuffer(&buffer)
                bodyBuffer.writeString(CRLF)
                return
            }

            let string = String(describing: value)
            bodyBuffer.writeString(CRLF)
            bodyBuffer.writeString("Content-Length: \(string.count)")
            bodyBuffer.writeString(CRLF+CRLF)
            bodyBuffer.writeString(string)
            bodyBuffer.writeString(CRLF)
        }

        var bodyBuffer = ByteBuffer()

        for (key, value) in params {
            switch key {
            case "file":
                addPart(name: key, value: value!)
            default:
                if let list = value as? [Any] {
                    for listValue in list {
                        addPart(name: "\(key)[]", value: listValue)
                    }
                    continue
                }
                addPart(name: key, value: value!)
            }
        }

        bodyBuffer.writeString(DASHDASH)
        bodyBuffer.writeString(Client.boundary)
        bodyBuffer.writeString(DASHDASH)
        bodyBuffer.writeString(CRLF)

        request.headers.remove(name: "content-type")
        if !chunked {
            request.headers.add(name: "Content-Length", value: bodyBuffer.readableBytes.description)
        }
        request.headers.add(name: "Content-Type", value: "multipart/form-data;boundary=\"\(Client.boundary)\"")
        request.body = .bytes(bodyBuffer)
    }

    private func addUserAgentHeader() {
        let packageInfo = OSPackageInfo.get()
        let device = Client.getDevice()

        #if !os(Linux) && !os(Windows)
        _ = addHeader(
            key: "user-agent",
            value: "\(packageInfo.packageName)/\(packageInfo.version) \(device)"
        )
        #endif
    }

    private func addOriginHeader() {
        let packageInfo = OSPackageInfo.get()
        let operatingSystem = Client.getOperatingSystem()
        _ = addHeader(
            key: "origin",
            value: "appwrite-\(operatingSystem)://\(packageInfo.packageName)"
        )
    }
}

extension Client {
    private static func getOperatingSystem() -> String {
        #if os(iOS)
        return "ios"
        #elseif os(watchOS)
        return "watchos"
        #elseif os(tvOS)
        return "tvos"
        #elseif os(macOS)
        return "macos"
        #elseif os(Linux)
        return "linux"
        #elseif os(Windows)
        return "windows"
        #endif
    }

    private static func getDevice() -> String {
        let deviceInfo = OSDeviceInfo()
        var device = ""

        #if os(iOS)
        let info = deviceInfo.iOSInfo
        device = "\(info!.modelIdentifier) iOS/\(info!.systemVersion)"
        #elseif os(watchOS)
        let info = deviceInfo.watchOSInfo
        device = "\(info!.modelIdentifier) watchOS/\(info!.systemVersion)"
        #elseif os(tvOS)
        let info = deviceInfo.iOSInfo
        device = "\(info!.modelIdentifier) tvOS/\(info!.systemVersion)"
        #elseif os(macOS)
        let info = deviceInfo.macOSInfo
        device = "(Macintosh; \(info!.model))"
        #elseif os(Linux)
        let info = deviceInfo.linuxInfo
        device = "(Linux; U; \(info!.id) \(info!.version))"
        #elseif os(Windows)
        let info = deviceInfo.windowsInfo
        device = "(Windows NT; \(info!.computerName))"
        #endif

        return device
    }
}
