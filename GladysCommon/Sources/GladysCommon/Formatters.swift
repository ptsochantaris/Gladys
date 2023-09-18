import Foundation

public let diskSizeFormatter = ByteCountFormatter()

public let agoFormatter: DateComponentsFormatter = {
    let f = DateComponentsFormatter()
    f.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
    f.unitsStyle = .abbreviated
    f.maximumUnitCount = 2
    return f
}()

public let priceFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    return formatter
}()

public let shortDateFormatter: DateFormatter = {
    let d = DateFormatter()
    d.doesRelativeDateFormatting = true
    d.dateStyle = .short
    d.timeStyle = .short
    return d
}()

public let decimalNumberFormatter: NumberFormatter = {
    let n = NumberFormatter()
    n.numberStyle = .decimal
    return n
}()
