import Foundation

/// Where a newly opened window lands.
public enum InsertPosition: String, Codable, CaseIterable {
    case afterFocused, end
}

/// Editing operations on a strip. All of them keep focus and indices valid.
extension Strip {

    // MARK: Insert / remove

    /// Adds a window in its own column. Returns the column index it went to.
    @discardableResult
    public mutating func insert(_ w: WinID, width: Double, position: InsertPosition = .afterFocused,
                                slot: Int? = nil, focus: Bool) -> Int {
        if case .column(let existing, _)? = locate(w) { return existing }
        guard !contains(w) else { return focusedColumn }
        let col = Column(windows: [w], width: width)
        let idx: Int
        if let slot = slot {
            idx = min(max(slot, 0), columns.count)
        } else if columns.isEmpty || position == .end {
            idx = columns.count
        } else {
            idx = min(focusedColumn + 1, columns.count)
        }
        columns.insert(col, at: idx)
        if focus {
            focusedColumn = idx
            focusedPin = nil
        } else if idx <= focusedColumn && columns.count > 1 {
            // Keep the same column focused when something is inserted before it.
            focusedColumn += 1
        }
        clampFocus()
        return idx
    }

    /// Removes a window wherever it is. Returns true if it was on this strip.
    @discardableResult
    public mutating func remove(_ w: WinID) -> Bool {
        guard let loc = locate(w) else { return false }
        switch loc {
        case .column(let ci, let wi):
            columns[ci].windows.remove(at: wi)
            columns[ci].heightWeights[w] = nil
            if columns[ci].windows.isEmpty {
                columns.remove(at: ci)
                if ci < focusedColumn || (ci == focusedColumn && focusedColumn == columns.count) {
                    focusedColumn -= 1
                }
            } else if wi < columns[ci].activeIndex || columns[ci].activeIndex >= columns[ci].windows.count {
                columns[ci].activeIndex -= 1
            }
            if ci < columns.count { columns[ci].clampActive() }
        case .pinned(let side, let wi):
            var p = pinned(side)!
            p.windows.remove(at: wi)
            p.clampActive()
            setPinned(side, p.windows.isEmpty ? nil : p)
        }
        clampFocus()
        return true
    }

    /// Swaps one window for another in place (native tab switches).
    @discardableResult
    public mutating func replace(_ old: WinID, with new: WinID) -> Bool {
        guard !contains(new), let loc = locate(old) else { return false }
        switch loc {
        case .column(let ci, let wi):
            columns[ci].windows[wi] = new
            columns[ci].heightWeights[new] = columns[ci].heightWeights.removeValue(forKey: old)
        case .pinned(let side, let wi):
            var p = pinned(side)!
            p.windows[wi] = new
            setPinned(side, p)
        }
        return true
    }

    mutating func setPinned(_ side: PinSide, _ c: Column?) {
        if side == .left { pinnedLeft = c } else { pinnedRight = c }
    }

    // MARK: Focus

    /// Makes `w` the focused window. Returns false if it is not on this strip.
    @discardableResult
    public mutating func focusWindow(_ w: WinID) -> Bool {
        guard let loc = locate(w) else { return false }
        switch loc {
        case .column(let ci, let wi):
            focusedColumn = ci
            focusedPin = nil
            columns[ci].activeIndex = wi
        case .pinned(let side, let wi):
            focusedPin = side
            var p = pinned(side)!
            p.activeIndex = wi
            setPinned(side, p)
        }
        return true
    }

    public mutating func focusLeft() {
        switch focus {
        case .pinned(.right):
            focusedPin = nil
            focusedColumn = max(columns.count - 1, 0)
        case .pinned(.left):
            break
        case .column(let i):
            if i > 0 { focusedColumn = i - 1 } else if pinnedLeft != nil { focusedPin = .left }
        }
        clampFocus()
    }

    public mutating func focusRight() {
        switch focus {
        case .pinned(.left):
            focusedPin = nil
            focusedColumn = 0
        case .pinned(.right):
            break
        case .column(let i):
            if i < columns.count - 1 { focusedColumn = i + 1 } else if pinnedRight != nil { focusedPin = .right }
        }
        clampFocus()
    }

    public mutating func focusColumn(_ i: Int) {
        guard columns.indices.contains(i) else { return }
        focusedPin = nil
        focusedColumn = i
    }

    /// Moves focus up (-1) or down (+1) inside the focused column.
    public mutating func focusVertical(_ delta: Int) {
        mutateFocusedColumn { c in
            guard !c.windows.isEmpty else { return }
            c.activeIndex = min(max(c.activeIndex + delta, 0), c.windows.count - 1)
        }
    }

    // MARK: Move

    public mutating func moveColumn(_ delta: Int) {
        guard focusedPin == nil, columns.indices.contains(focusedColumn) else { return }
        let to = focusedColumn + delta
        guard columns.indices.contains(to) else { return }
        columns.swapAt(focusedColumn, to)
        focusedColumn = to
    }

    /// Moves the focused column to an absolute index.
    public mutating func moveColumn(to index: Int) {
        guard focusedPin == nil, columns.indices.contains(focusedColumn) else { return }
        let to = min(max(index, 0), columns.count - 1)
        let c = columns.remove(at: focusedColumn)
        columns.insert(c, at: to)
        focusedColumn = to
    }

    /// Reorders a column after a drag. `from` and `to` are column indices.
    public mutating func reorderColumn(from: Int, to: Int) {
        guard columns.indices.contains(from) else { return }
        let focusedID = columns.indices.contains(focusedColumn) ? columns[focusedColumn].id : nil
        let c = columns.remove(at: from)
        columns.insert(c, at: min(max(to, 0), columns.count))
        if let id = focusedID, let i = columns.firstIndex(where: { $0.id == id }) { focusedColumn = i }
    }

    /// Moves the focused window up (-1) or down (+1) inside its column.
    public mutating func moveVertical(_ delta: Int) {
        mutateFocusedColumn { c in
            let to = c.activeIndex + delta
            guard c.windows.indices.contains(to) else { return }
            c.windows.swapAt(c.activeIndex, to)
            c.activeIndex = to
        }
    }

    // MARK: Stacks

    /// Puts the focused window into the neighbouring column (-1 left, +1 right).
    public mutating func stackInto(_ delta: Int) {
        guard focusedPin == nil, columns.indices.contains(focusedColumn),
              let w = columns[focusedColumn].activeWindow else { return }
        let target = focusedColumn + delta
        guard columns.indices.contains(target) else { return }
        let targetID = columns[target].id
        remove(w)
        guard let ti = columns.firstIndex(where: { $0.id == targetID }) else { return }
        columns[ti].windows.append(w)
        columns[ti].activeIndex = columns[ti].windows.count - 1
        focusedColumn = ti
        focusedPin = nil
    }

    /// Takes the focused window out of its stack into a new column on that side.
    public mutating func popOut(_ delta: Int, width: Double) {
        guard focusedPin == nil, columns.indices.contains(focusedColumn),
              columns[focusedColumn].windows.count > 1,
              let w = columns[focusedColumn].activeWindow else { return }
        let ci = focusedColumn
        remove(w)
        let idx = delta < 0 ? ci : ci + 1
        columns.insert(Column(windows: [w], width: width), at: idx)
        focusedColumn = idx
        focusedPin = nil
    }

    public mutating func toggleTabbed() {
        mutateFocusedColumn { $0.isTabbed.toggle() }
    }

    /// Grows (+) or shrinks (-) the focused window's share of the column height.
    public mutating func adjustHeight(_ delta: Double) {
        mutateFocusedColumn { c in
            guard c.windows.count > 1, let w = c.activeWindow else { return }
            c.heightWeights[w] = min(max(c.weight(w) + delta, 0.2), 5)
        }
    }

    public mutating func resetHeights() {
        mutateFocusedColumn { $0.heightWeights = [:] }
    }

    // MARK: Width

    public mutating func cycleWidth(presets: [Double], backwards: Bool = false) {
        let sorted = presets.sorted()
        guard !sorted.isEmpty else { return }
        mutateFocusedColumn { c in
            c.widthBeforeFull = nil
            if backwards {
                c.width = sorted.last(where: { $0 < c.width - 0.01 }) ?? sorted.last!
            } else {
                c.width = sorted.first(where: { $0 > c.width + 0.01 }) ?? sorted.first!
            }
        }
    }

    public mutating func adjustWidth(_ delta: Double) {
        mutateFocusedColumn { c in
            c.widthBeforeFull = nil
            c.width = min(max(c.width + delta, 0.1), 1.0)
        }
    }

    public mutating func setWidth(_ width: Double) {
        mutateFocusedColumn { c in
            c.widthBeforeFull = nil
            c.width = min(max(width, 0.1), 1.0)
        }
    }

    public mutating func toggleFullWidth() {
        mutateFocusedColumn { c in
            if let prev = c.widthBeforeFull {
                c.width = prev
                c.widthBeforeFull = nil
            } else {
                c.widthBeforeFull = c.width
                c.width = 1.0
            }
        }
    }

    // MARK: Pin

    /// Pins the focused window to a screen edge, or unpins it if it is already
    /// pinned there. Whatever was pinned on that side goes back on the strip.
    public mutating func togglePin(_ side: PinSide, defaultWidth: Double) {
        if case .pinned(let s) = focus, let p = pinned(s) {
            // Unpin: the column returns to the strip at the matching end.
            setPinned(s, nil)
            focusedPin = nil
            var col = p
            col.width = min(col.width, 1)
            let idx = s == .left ? 0 : columns.count
            columns.insert(col, at: idx)
            focusedColumn = idx
            if s != side { togglePinFocused(side) }
            return
        }
        togglePinFocused(side)
    }

    private mutating func togglePinFocused(_ side: PinSide) {
        guard columns.indices.contains(focusedColumn) else { return }
        let col = columns.remove(at: focusedColumn)
        if let old = pinned(side) {
            columns.insert(old, at: side == .left ? 0 : columns.count)
        }
        var pinnedCol = col
        // A pinned column cannot take the whole screen.
        pinnedCol.width = min(col.width, 0.5)
        pinnedCol.widthBeforeFull = nil
        setPinned(side, pinnedCol)
        focusedPin = side
        if focusedColumn >= columns.count { focusedColumn = max(columns.count - 1, 0) }
    }

    // MARK: Helpers

    mutating func mutateFocusedColumn(_ body: (inout Column) -> Void) {
        if let side = focusedPin, var p = pinned(side) {
            body(&p)
            p.clampActive()
            setPinned(side, p)
            return
        }
        guard columns.indices.contains(focusedColumn) else { return }
        body(&columns[focusedColumn])
        columns[focusedColumn].clampActive()
    }
}
