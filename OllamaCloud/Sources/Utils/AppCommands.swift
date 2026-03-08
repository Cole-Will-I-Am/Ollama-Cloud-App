import Foundation

enum AppCommand {
    static let newChat = Notification.Name("seer.command.newChat")
    static let closeChat = Notification.Name("seer.command.closeChat")
    static let openSettings = Notification.Name("seer.command.openSettings")
    static let sendMessage = Notification.Name("seer.command.sendMessage")
    static let quickModelSwitch = Notification.Name("seer.command.quickModelSwitch")
    static let exportConversation = Notification.Name("seer.command.exportConversation")
    static let previousBranch = Notification.Name("seer.command.previousBranch")
    static let nextBranch = Notification.Name("seer.command.nextBranch")
    static let newProject = Notification.Name("seer.command.newProject")
    static let selectConversationIndex = Notification.Name("seer.command.selectConversationIndex")

    static let conversationIndexUserInfoKey = "conversationIndex"

    static func post(_ name: Notification.Name, userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
    }

    static func postSelectConversation(index: Int) {
        post(selectConversationIndex, userInfo: [conversationIndexUserInfoKey: index])
    }

    static func conversationIndex(from notification: Notification) -> Int? {
        notification.userInfo?[conversationIndexUserInfoKey] as? Int
    }
}
