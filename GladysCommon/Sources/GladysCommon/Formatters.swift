import Foundation

public let diskSizeFormat = ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false)

public let agoFormat = Date.ComponentsFormatStyle(style: .abbreviated, fields: [.year, .month, .week, .day, .hour, .minute, .second])

public let shortDateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened, capitalizationContext: .standalone)

public let decimalNumberFormat = Decimal.FormatStyle()
