import Foundation

/// Maps live platform elements (e.g. AX window references) to stable `WindowID`s.
///
/// Stable ids matter because undo snapshots record window ids and must match
/// the same windows on a later click; if every enumeration minted fresh ids,
/// snapshots could never be matched against the current windows.
///
/// Pruning rule: after each `handles(for:in:)` call, every entry of that group
/// that was not matched by the call is dropped, so ids are retired when a window
/// disappears from an enumeration of its group. Ids come from a monotonically
/// increasing counter shared across groups and are never reused, even after pruning.
///
/// Deliberately NOT `Sendable`: the adapter uses it on the main actor only.
public final class StableHandleRegistry<Element> {
    private struct Entry {
        var id: WindowID
        var element: Element
    }

    private let isSame: (Element, Element) -> Bool
    private var groups: [Int: [Entry]] = [:]
    private var nextID = 1

    public init(isSame: @escaping (Element, Element) -> Bool) {
        self.isSame = isSame
    }

    /// Returns ids for `elements` (in input order), reusing the id of any existing
    /// entry in `group` that is `isSame` as the element and refreshing its stored
    /// element; otherwise minting a new id. Unmatched entries of `group` are pruned.
    /// If two input elements are `isSame` to each other (should not happen with real
    /// AX elements), the second receives the same id as the first.
    public func handles(for elements: [Element], in group: Int) -> [(id: WindowID, element: Element)] {
        let old = groups[group] ?? []
        var matched = Set<Int>()
        var fresh: [Entry] = []
        var result: [(id: WindowID, element: Element)] = []
        for element in elements {
            if let idx = fresh.firstIndex(where: { isSame($0.element, element) }) {
                fresh[idx].element = element
                result.append((fresh[idx].id, element))
                continue
            }
            let id: WindowID
            if let idx = old.indices.first(where: { !matched.contains($0) && isSame(old[$0].element, element) }) {
                matched.insert(idx)
                id = old[idx].id
            } else {
                id = WindowID(nextID)
                nextID += 1
            }
            fresh.append(Entry(id: id, element: element))
            result.append((id, element))
        }
        groups[group] = fresh
        return result
    }

    /// The latest element recorded for `id`, in any group.
    public func element(for id: WindowID) -> Element? {
        for entries in groups.values {
            if let e = entries.first(where: { $0.id == id }) { return e.element }
        }
        return nil
    }

    /// Drops all entries of `group`.
    public func removeGroup(_ group: Int) {
        groups[group] = nil
    }

    /// Total number of entries across all groups.
    public var count: Int {
        groups.values.reduce(0) { $0 + $1.count }
    }
}
