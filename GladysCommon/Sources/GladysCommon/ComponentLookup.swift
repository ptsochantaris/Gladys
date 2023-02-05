import Foundation

public final actor ComponentLookup {
    public static let shared = ComponentLookup()

    private struct WeakComponent {
        weak var component: Component?
    }

    private var componentLookup = [UUID: WeakComponent]()

    public func cleanup() {
        componentLookup = componentLookup.filter { $0.value.component != nil }
    }

    public func register(_ component: Component) {
        componentLookup[component.uuid] = WeakComponent(component: component)
    }

    public func component(uuid: UUID) -> Component? {
        componentLookup[uuid]?.component
    }

    public func component(uuid: String) -> Component? {
        if let uuidData = UUID(uuidString: uuid) {
            return component(uuid: uuidData)
        } else {
            return nil
        }
    }
}
