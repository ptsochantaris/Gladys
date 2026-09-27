import Foundation

public nonisolated let diskSizeFormat = ByteCountFormatStyle(style: .file, allowedUnits: .all, spellsOutZero: true, includesActualByteCount: false)

public nonisolated let agoFormat = Date.ComponentsFormatStyle(style: .abbreviated, fields: [.year, .month, .week, .day, .hour, .minute, .second])

public nonisolated let shortDateFormat = Date.FormatStyle(date: .abbreviated, time: .shortened, capitalizationContext: .standalone)

public nonisolated let decimalNumberFormat = Decimal.FormatStyle()
