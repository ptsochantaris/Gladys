import Foundation

@discardableResult
@freestanding(expression)
public macro notifications(for notificationName: Notification.Name, block: (Notification) async -> Bool) -> Task<Void, Never> = #externalMacro(module: "MinionsMacros", type: "NotificationMacro")

@discardableResult
@freestanding(expression)
public macro weakSelf<T>(block: T) -> T = #externalMacro(module: "MinionsMacros", type: "WithWeakSelfMacro")

@discardableResult
@freestanding(expression)
public macro weakSelfTask<T>(block: T) -> Task<Void, Never> = #externalMacro(module: "MinionsMacros", type: "WithWeakSelfTaskMacro")
