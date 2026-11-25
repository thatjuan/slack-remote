import Foundation

public enum Poll {
    /// Allow the main queue to deliver signal handlers while waiting between attempts.
    public static func wait(until deadline: Date) {
        let nextAttempt = min(deadline, Date().addingTimeInterval(0.1))
        guard nextAttempt > Date() else { return }

        // A run loop with no sources or timers returns immediately, including during lock acquisition.
        let timer = Timer(fire: nextAttempt, interval: 0, repeats: false) { _ in }
        RunLoop.main.add(timer, forMode: .default)
        RunLoop.main.run(until: nextAttempt)
        timer.invalidate()
    }

    public static func until<T>(_ deadline: Date, _ attempt: () throws -> T?) rethrows -> T? {
        while Date() < deadline {
            if let result = try attempt(), Date() < deadline { return result }
            wait(until: deadline)
        }
        return nil
    }
}
