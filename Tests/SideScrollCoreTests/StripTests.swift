import XCTest
import CoreGraphics
@testable import SideScrollCore

final class StripTests: XCTestCase {

    func makeStrip(_ n: Int, width: Double = 0.5) -> Strip {
        var s = Strip()
        for i in 1...n { s.insert(WinID(i), width: width, position: .end, focus: true) }
        return s
    }

    func testInsertAfterFocused() {
        var s = makeStrip(3)
        s.focusColumn(0)
        s.insert(10, width: 0.5, focus: true)
        XCTAssertEqual(s.columns.map { $0.windows[0] }, [1, 10, 2, 3])
        XCTAssertEqual(s.focusedWindow, 10)
    }

    func testInsertWithoutFocusKeepsFocus() {
        var s = makeStrip(3)
        s.focusColumn(1)
        s.insert(10, width: 0.5, slot: 0, focus: false)
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testRemoveFocusedMovesToNeighbour() {
        var s = makeStrip(3)
        s.focusColumn(2)
        s.remove(3)
        XCTAssertEqual(s.focusedWindow, 2)
        s.focusColumn(0)
        s.remove(1)
        XCTAssertEqual(s.focusedWindow, 2)
        s.remove(2)
        XCTAssertTrue(s.isEmpty)
        XCTAssertNil(s.focusedWindow)
    }

    func testMoveColumn() {
        var s = makeStrip(3)
        s.focusColumn(0)
        s.moveColumn(1)
        XCTAssertEqual(s.columns.map { $0.windows[0] }, [2, 1, 3])
        XCTAssertEqual(s.focusedWindow, 1)
        s.moveColumn(to: 2)
        XCTAssertEqual(s.columns.map { $0.windows[0] }, [2, 3, 1])
    }

    func testStackAndPop() {
        var s = makeStrip(3)
        s.focusColumn(1)
        s.stackInto(-1)
        XCTAssertEqual(s.columns.count, 2)
        XCTAssertEqual(s.columns[0].windows, [1, 2])
        XCTAssertEqual(s.focusedWindow, 2)
        s.popOut(1, width: 0.5)
        XCTAssertEqual(s.columns.map { $0.windows }, [[1], [2], [3]])
        XCTAssertEqual(s.focusedWindow, 2)
    }

    func testCycleWidth() {
        var s = makeStrip(1)
        let presets = [0.25, 0.5, 0.75]
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.75)
        s.cycleWidth(presets: presets)
        XCTAssertEqual(s.columns[0].width, 0.25)
        s.cycleWidth(presets: presets, backwards: true)
        XCTAssertEqual(s.columns[0].width, 0.75)
    }

    func testFullWidthToggle() {
        var s = makeStrip(1, width: 0.5)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].width, 1.0)
        s.toggleFullWidth()
        XCTAssertEqual(s.columns[0].width, 0.5)
    }

    func testPinAndUnpin() {
        var s = makeStrip(3)
        s.focusColumn(1)
        s.togglePin(.left, defaultWidth: 0.5)
        XCTAssertEqual(s.pinnedLeft?.windows, [2])
        XCTAssertEqual(s.columns.map { $0.windows[0] }, [1, 3])
        XCTAssertEqual(s.focusedWindow, 2)
        s.focusRight()
        XCTAssertEqual(s.focusedWindow, 1)
        s.focusLeft()
        XCTAssertEqual(s.focusedWindow, 2)
        s.togglePin(.left, defaultWidth: 0.5)
        XCTAssertNil(s.pinnedLeft)
        XCTAssertEqual(s.columns.map { $0.windows[0] }, [2, 1, 3])
    }

    func testLayoutTwoHalvesFillViewport() {
        let s = makeStrip(2)
        let p = LayoutParams(area: CGRect(x: 0, y: 0, width: 1000, height: 800),
                             screen: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 10)
        let r = Layout.compute(s, p, viewOffset: 0)
        XCTAssertEqual(r.placements[0].frame, CGRect(x: 0, y: 0, width: 495, height: 800))
        XCTAssertEqual(r.placements[1].frame, CGRect(x: 505, y: 0, width: 495, height: 800))
        XCTAssertTrue(r.placements.allSatisfy { $0.visible })
    }

    func testOffscreenColumnsAreParked() {
        let s = makeStrip(4)
        let p = LayoutParams(area: CGRect(x: 0, y: 0, width: 1000, height: 800),
                             screen: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 10)
        let r = Layout.compute(s, p, viewOffset: 0)
        XCTAssertFalse(r.placements[2].visible)
        XCTAssertEqual(r.placements[2].frame.minX, 999)
    }

    func testOffsetShowingScrollsMinimally() {
        let s = makeStrip(4)
        let off = Layout.offsetShowing(2, s, viewportWidth: 1000, gap: 10, mode: .never, current: 0)
        XCTAssertEqual(off, 505)
        let centered = Layout.offsetShowing(2, s, viewportWidth: 1000, gap: 10, mode: .always, current: 0)
        XCTAssertEqual(centered, 1010 + 247.5 - 500)
    }

    func testStackedHeights() {
        var s = makeStrip(2)
        s.focusColumn(1)
        s.stackInto(-1)
        let p = LayoutParams(area: CGRect(x: 0, y: 0, width: 1000, height: 810),
                             screen: CGRect(x: 0, y: 0, width: 1000, height: 810), gap: 10)
        let r = Layout.compute(s, p, viewOffset: 0)
        XCTAssertEqual(r.placements[0].frame.height, 400)
        XCTAssertEqual(r.placements[1].frame.minY, 410)
        XCTAssertEqual(r.placements[1].frame.height, 400)
    }

    func testSnapPicksColumnUnderCenter() {
        let s = makeStrip(5)
        let (col, off) = Layout.snap(s, viewportWidth: 1000, gap: 10, projected: 1300)
        XCTAssertEqual(col, 3)
        XCTAssertTrue(off >= 0)
    }

    func testSessionRestoreMatchesByTitle() {
        let snap = StripSnapshot(display: "d", columns: [
            ColumnSnapshot(windows: [WindowIdentity(windowID: 99, bundleID: "a", title: "Doc")], width: 0.75, isTabbed: false),
            ColumnSnapshot(windows: [WindowIdentity(windowID: 98, bundleID: "b", title: "X")], width: 0.25, isTabbed: false),
        ])
        let live = [
            WindowIdentity(windowID: 5, bundleID: "b", title: "X"),
            WindowIdentity(windowID: 6, bundleID: "c", title: "New"),
            WindowIdentity(windowID: 7, bundleID: "a", title: "Doc"),
        ]
        let s = SessionRestore.rebuild(snap, available: live, defaultWidth: 0.5)
        XCTAssertEqual(s.columns.map { $0.windows }, [[7], [5], [6]])
        XCTAssertEqual(s.columns[0].width, 0.75)
    }

    func testBindingsMergeKeepsUserChoices() {
        var stored = Bindings()
        stored[.focusLeft] = [KeyCombo(Key.r, Mod.control | Mod.option)]
        let merged = stored.mergedWithDefaults()
        XCTAssertEqual(merged[.focusLeft], [KeyCombo(Key.r, Mod.control | Mod.option)])
        // cycleWidth's default (⌃⌥R) is taken, so it stays unbound.
        XCTAssertEqual(merged[.cycleWidth], [])
        XCTAssertEqual(merged[.fullWidth], [KeyCombo(Key.f, Mod.control | Mod.option)])
    }

    func testConfigDecodesOldFiles() throws {
        let json = #"{"gap": 4, "swipeFingers": 3}"#.data(using: .utf8)!
        let c = try JSONDecoder().decode(Config.self, from: json)
        XCTAssertEqual(c.gap, 4)
        XCTAssertEqual(c.swipeFingers, 3)
        XCTAssertEqual(c.defaultWidth, 0.5)
    }

    func testActionSlugs() {
        XCTAssertEqual(Action.focusLeft.slug, "focus-left")
        XCTAssertEqual(Action.focusColumn3.slug, "focus-column-3")
        XCTAssertEqual(Action(slug: "move-to-next-display"), .moveToNextDisplay)
        XCTAssertEqual(Action(slug: "focusRight"), .focusRight)
        XCTAssertNil(Action(slug: "nope"))
        XCTAssertFalse(Action.closeWindow.allowedFromAutomation)
        for a in Action.allCases { XCTAssertEqual(Action(slug: a.slug), a) }
    }

    func testMinWidthWidensColumn() {
        var s = makeStrip(2)
        s.columns[0].minWidth = 700
        let p = LayoutParams(area: CGRect(x: 0, y: 0, width: 1000, height: 800),
                             screen: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 10)
        let r = Layout.compute(s, p, viewOffset: 0)
        XCTAssertEqual(r.placements[0].frame.width, 700)
        XCTAssertEqual(r.placements[1].frame.minX, 710)
    }

    func testSpringSettles() {
        var sp = Spring(value: 0, target: 100, stiffness: 700)
        for _ in 0..<120 { sp.step(1.0 / 60) }
        XCTAssertEqual(sp.value, 100)
    }
}
