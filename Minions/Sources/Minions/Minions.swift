import Foundation

@discardableResult
@freestanding(expression)
public macro notifications(for notificationName: Notification.Name, block: (Notification) async -> Bool) -> Task<Void, Never> = #externalMacro(module: "MinionsMacros", type: "NotificationMacro")
