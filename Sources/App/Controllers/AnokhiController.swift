import Foundation
import Vapor
import Crypto

struct SlackRequest: Content {
    let token: String
    let team_id: String
    let api_app_id: String
    let event: SlackEvent
    let type: String
    let authed_users: [String]
    let event_id: String
    let event_time: UInt64
}

struct SlackEvent: Content {
    let type: String
    let user: String?
    let text: String?
    let channel: String?
}

final class AnokhiController: RouteCollection {
    
    func boot(router: Router) throws {
        let group = router.grouped("anokhi")
        group.post(SlackRequest.self, at: "/", use: send)
    }
    
    func send(_ request: Request, _ data: SlackRequest) throws -> HTTPStatus {
        if let secrect = request.http.headers.firstValue(name: HTTPHeaderName("X-Slack-Signature")),
            let timestamp = request.http.headers.firstValue(name: HTTPHeaderName("X-Slack-Request-Timestamp")),
            let rawData = request.http.body.data,
            let requestString = String(data: rawData, encoding: .utf8) {
            
            let finalString = "v0:\(timestamp):\(requestString)"
            let hmac = try HMAC.SHA256.authenticate(finalString, key: Environment.get("anokhiKey")!)
            let hash = hmac.map { String(format: "%02x", $0) }.joined()
            
            if "v0=\(hash)" == secrect {
                reply(data.event)
                return .ok
            }
        }
        
        return .unauthorized
    }
    
    private func reply(_ event: SlackEvent) {
        DispatchQueue.global().async {
            if event.type == "app_mention" {
                self.checkForReply(event)
            } else if event.type == "message" {
                if event.text?.lowercased().contains("anokhi") == true {
                    self.checkForReply(event)
                }
            }
        }
    }
    
    private func checkForReply(_ event: SlackEvent) {
        guard let input = event.text else { return }
        
        if let replies = quickReplies.first(where: {input.contains($0.key)})?.value {
            let reply = replies[Int.random(in: 0..<replies.count)]
            let user = event.user ?? ""
            let channel = event.channel ?? ""
            
            let responseText = user.withCString {
                String(format: reply, $0)
            }
            
            let response = """
            { "text": "\(responseText)", "channel": "\(channel)" }
            """
            
            self.sendMessage(data: response)
        }
    }
    
    private func sendMessage(data: String) {
        let token = "Bearer \(Environment.get("anokhiToken")!)"
        
        var urlRequest = URLRequest(url: URL(string: "https://slack.com/api/chat.postMessage")!)
        urlRequest.allHTTPHeaderFields = [
            "Content-type": "application/json",
            "Authorization": token
        ]
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = data.data(using: .utf8)
        
        let configuration = URLSessionConfiguration.default
        URLSession(configuration: configuration).dataTask(with: urlRequest) { _, _, _ in
            print("Msg sent")
        }.resume()
    }
}

let hellos = ["Hello! <@%s>", "Hey! <@%s>", "Hola! <@%s>", "Namaste! <@%s>"]

let quickReplies = [
    "hi": hellos,
    "hello": hellos,
    "": hellos,
    "hey": hellos,
    "namaste": hellos
]
