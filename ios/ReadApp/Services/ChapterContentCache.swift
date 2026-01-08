import Foundation

actor ChapterContentCache {
    private var storage: [String: String] = [:]
    private var order: [String] = []
    private let maxEntries: Int

    init(maxEntries: Int) {
        self.maxEntries = maxEntries
    }

    func value(for key: String) -> String? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    func insert(_ value: String, for key: String) {
        if storage[key] != nil {
            removeKeyFromOrder(key)
        }
        storage[key] = value
        order.append(key)
        evictIfNeeded()
    }

    func removeAll() {
        storage.removeAll()
        order.removeAll()
    }

    private func touch(_ key: String) {
        removeKeyFromOrder(key)
        order.append(key)
    }

    private func removeKeyFromOrder(_ key: String) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
    }

    private func evictIfNeeded() {
        while storage.count > maxEntries, let oldestKey = order.first {
            order.removeFirst()
            storage.removeValue(forKey: oldestKey)
        }
    }
}
