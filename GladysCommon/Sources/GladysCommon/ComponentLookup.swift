import Foundation

public final class ComponentLookup {
    public static let shared = ComponentLookup()
    
    private let queue = DispatchQueue(label: "build.bru.gladys.componentLookup", attributes: .concurrent)
    
    private struct WeakComponent {
        weak var component: Component?
    }
    
    private var componentLookup = [UUID: WeakComponent]()
    
    public func cleanup() {
        queue.async(flags: .barrier) { [self] in
            componentLookup = componentLookup.filter { $0.value.component != nil }
        }
    }
    
    public func register(_ component: Component) {
        queue.async(flags: .barrier) { [self] in
            componentLookup[component.uuid] = WeakComponent(component: component)
        }
    }
    
    public func component(uuid: UUID) -> Component? {
        queue.sync {
            componentLookup[uuid]?.component
        }
    }
    
    public func component(uuid: String) -> Component? {
        if let uuidData = UUID(uuidString: uuid) {
            component(uuid: uuidData)
        } else {
            nil
        }
    }
}
