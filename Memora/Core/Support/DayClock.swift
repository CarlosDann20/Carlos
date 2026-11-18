//
//  DayClock.swift
//  Memora
//
//  Converts between wall-clock time and "study day" numbers. A study day
//  starts at `rolloverHour` local time (default 4 AM, as in Anki), so a card
//  reviewed at 1 AM still belongs to the previous day.
//

import Foundation

public struct DayClock: Sendable {
    public let creationEpoch: Int64
    public let rolloverHour: Int
    public let calendar: Calendar

    public init(creationEpoch: Int64, rolloverHour: Int, timeZone: TimeZone = .current) {
        self.creationEpoch = creationEpoch
        self.rolloverHour = max(0, min(23, rolloverHour))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        self.calendar = cal
    }

    /// Day number for a given instant: number of rollover boundaries since the
    /// collection's creation day.
    public func dayNumber(for epochSeconds: Int64) -> Int {
        let date = Date(timeIntervalSince1970: TimeInterval(epochSeconds))
        let start = startOfStudyDay(containing: date)
        let creationStart = startOfStudyDay(containing: Date(timeIntervalSince1970: TimeInterval(creationEpoch)))
        let seconds = start.timeIntervalSince(creationStart)
        return Int((seconds / 86_400).rounded())
    }

    public func today(now: Int64 = Int64(Date().timeIntervalSince1970)) -> Int {
        dayNumber(for: now)
    }

    /// The instant a given study day begins (epoch seconds).
    public func startEpoch(ofDay day: Int) -> Int64 {
        let creationStart = startOfStudyDay(containing: Date(timeIntervalSince1970: TimeInterval(creationEpoch)))
        let target = calendar.date(byAdding: .day, value: day, to: creationStart) ?? creationStart
        return Int64(target.timeIntervalSince1970)
    }

    /// Epoch seconds marking the end of today's study day (start of tomorrow).
    public func endOfTodayEpoch(now: Int64 = Int64(Date().timeIntervalSince1970)) -> Int64 {
        startEpoch(ofDay: today(now: now) + 1)
    }

    private func startOfStudyDay(containing date: Date) -> Date {
        // Shift back by rolloverHour, take midnight, then shift forward.
        let shifted = date.addingTimeInterval(TimeInterval(-rolloverHour * 3600))
        let midnight = calendar.startOfDay(for: shifted)
        return midnight.addingTimeInterval(TimeInterval(rolloverHour * 3600))
    }
}
