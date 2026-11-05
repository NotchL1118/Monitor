import Foundation
import Network
import MonitorCore

/// This server is deliberately bound to loopback, never Wi-Fi / LAN interfaces.
final class LocalServer {
    private let token: String
    private var listener: NWListener?
    private var clients: [UUID: NWConnection] = [:]
    var onUpdate: ((BrowserUpdate) -> Void)?
    var isRecording: (() -> Bool)?
    var onState: ((String?) -> Void)?

    init(token: String) { self.token = token }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 47821)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.onState?(nil)
            case .failed(let error): self?.onState?("本机连接服务不可用：\(error.localizedDescription)。请检查是否已打开另一个 Monitor，或端口 47821 被占用。")
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: .main)
    }

    func stop() {
        listener?.cancel()
        for connection in clients.values { connection.cancel() }
        clients.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        guard clients.count < 16 else { connection.cancel(); return }
        let id = UUID()
        clients[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish(id) }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.finish(id) }
        receive(connection, id: id, buffer: Data())
    }

    private func finish(_ id: UUID) { clients.removeValue(forKey: id)?.cancel() }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8193) { [weak self] data, _, complete, error in
            guard let self, self.clients[id] != nil else { return }
            var bytes = buffer
            if let data { bytes.append(data) }
            switch HTTPRequest.parse(bytes) {
            case .invalid: self.respond(connection, id: id, code: 400, message: "invalid_request")
            case .incomplete:
                if complete || error != nil { self.finish(id) }
                else { self.receive(connection, id: id, buffer: bytes) }
            case .complete(let request): self.handle(request, connection: connection, id: id)
            }
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection, id: UUID) {
        let origin = request.extensionOrigin
        if request.method == "OPTIONS", origin != nil, request.headers["host"] == "127.0.0.1:47821" {
            respond(connection, id: id, code: 204, message: "ok", origin: origin)
            return
        }
        guard request.isAuthorized(token: token) else {
            respond(connection, id: id, code: 401, message: "pairing_required", origin: origin); return
        }
        if request.method == "GET", request.path == "/v1/status" {
            respond(connection, id: id, code: 200, message: "ok", origin: origin); return
        }
        guard request.method == "POST", request.path == "/v1/activity" else {
            respond(connection, id: id, code: 404, message: "not_found", origin: origin); return
        }
        guard request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
              let update = try? JSONDecoder().decode(BrowserUpdate.self, from: request.body), update.isValid else {
            respond(connection, id: id, code: 400, message: "invalid_activity", origin: origin); return
        }
        onUpdate?(update)
        respond(connection, id: id, code: 200, message: "ok", origin: origin)
    }

    private func respond(_ connection: NWConnection, id: UUID, code: Int, message: String, origin: String? = nil) {
        let body = code == 204 ? Data() : (try? JSONSerialization.data(withJSONObject: [
            "status": message, "recording": isRecording?() ?? false, "version": 1
        ])) ?? Data()
        let reason = [200: "OK", 204: "No Content", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found"][code] ?? "Error"
        var head = "HTTP/1.1 \(code) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\nCache-Control: no-store\r\n"
        if let origin {
            head += "Access-Control-Allow-Origin: \(origin)\r\nVary: Origin\r\nAccess-Control-Allow-Methods: GET, POST, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization, Content-Type\r\n"
        }
        var response = Data((head + "\r\n").utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in self?.finish(id) })
    }
}
