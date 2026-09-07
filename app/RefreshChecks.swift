// Verification helpers for the dropdown's Refresh path — the same role --dump / --dump-menu play for
// the collection and the menu tree. Nothing here runs unless one of those flags (or CCB_FAKE_5H) is
// passed, so the shipped app is unaffected.
import Cocoa
import ApplicationServices

// CCB_FAKE_5H=10,90 hands out one forced Claude 5-hour figure per collection (the last value sticks
// once the list runs out), so a check can watch a refresh actually move the numbers instead of
// hoping real usage happens to change between two calls seconds apart.
// Test-only: read from whichever thread collects, never concurrently in these single-shot runs.
private var fakeFive: [Double]? = nil

func applyTestOverrides(_ snap: Snapshot) -> Snapshot {
  guard let raw = ProcessInfo.processInfo.environment["CCB_FAKE_5H"] else { return snap }
  if fakeFive == nil { fakeFive = raw.split(separator: ",").compactMap { Double($0) } }
  guard var q = fakeFive, let pct = q.first else { return snap }
  if q.count > 1 { q.removeFirst(); fakeFive = q }
  guard let u = snap.usage else {
    return Snapshot(now: snap.now,
                    usage: ClaudeUsage(measuredAt: snap.now, live: true,
                                       fiveHour: UsageWindow(pct: pct, resetsAt: snap.now + 3600),
                                       weekly: nil, fable: nil),
                    block: snap.block, models: snap.models, codex: snap.codex, update: snap.update)
  }
  return Snapshot(now: snap.now,
                  usage: ClaudeUsage(measuredAt: u.measuredAt, live: u.live,
                                     fiveHour: UsageWindow(pct: pct, resetsAt: u.fiveHour?.resetsAt),
                                     weekly: u.weekly, fable: u.fable),
                  block: snap.block, models: snap.models, codex: snap.codex, update: snap.update)
}

private func describe(_ tag: String, _ s: Snapshot) {
  let five = s.usage?.fiveHour.map { "\($0.pct)%" } ?? "-"
  let week = s.usage?.weekly.map { "\($0.pct)%" } ?? "-"
  let cx = windowState(s.codex?.primary, now: s.now).map { "\($0.pct)%" } ?? "-"
  print("\(tag): at \(fmtClock(s.now)) · claude live=\(s.usage?.live ?? false) 5h=\(five) week=\(week)"
    + " · codex live=\(s.codex?.live ?? false) 5h=\(cx)")
}

private func cacheStamp() -> String {
  ["\(STATE_DIR)/.claude-usage.json", "\(STATE_DIR)/.codex-usage.json"]
    .map { "\(($0 as NSString).lastPathComponent)=\(fmtClock(fileMtime($0)))" }.joined(separator: " ")
}

// --dump-refresh: runs exactly what the Refresh row runs (CLI warm-up → re-collect) and prints the
// before/after figures plus how long each leg took.
func dumpRefreshCheck() -> Never {
  print("cache before:", cacheStamp())
  let t0 = Date()
  describe("before", collectSnapshot())
  let t1 = Date()
  let r = runCliRefresh()
  let t2 = Date()
  let after = collectSnapshot()
  let t3 = Date()
  describe("after ", after)
  print(String(format: "cli warm-up: claude=%@ codex=%@ (%.2fs) · collect %.2fs / %.2fs",
               r.claudeRan ? "ok" : "no", r.codexRan ? "ok" : "no",
               t2.timeIntervalSince(t1), t1.timeIntervalSince(t0), t3.timeIntervalSince(t2)))
  print("cache after :", cacheStamp())
  exit(0)
}

// Reads the rows back out of the dropdown window that is actually on screen (this process's own
// accessibility tree), rather than the NSMenu objects we just wrote to — the check that an update
// landing on an open menu really reaches the rendered panel.
private func axRows() -> [String] {
  var out: [String] = []
  func attr(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success ? v : nil
  }
  func walk(_ el: AXUIElement, _ depth: Int) {
    guard depth < 8 else { return }
    if (attr(el, kAXRoleAttribute as String) as? String) == "AXMenuItem",
       let t = attr(el, kAXTitleAttribute as String) as? String,
       t.contains("▕") || t.contains(":") {
      out.append(t)
    }
    for k in (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] { walk(k, depth + 1) }
  }
  walk(AXUIElementCreateApplication(getpid()), 0)
  return out
}

extension AppDelegate {
  private func gaugeRows() -> [String] {
    (statusItem.menu?.items ?? []).map { $0.title }.filter { $0.contains("▕") || $0.hasPrefix("updated") || $0.hasPrefix("갱신") }
  }

  // --test-refresh-ui: drives the three ways a refresh can reach the dropdown and prints what the
  // panel on screen holds at each step — (1) Refresh while the menu is open, (2) Refresh with the
  // menu closed, the real click flow, which pops it back open, (3) a stale menu re-collecting as it
  // opens. Pair it with CCB_FAKE_5H so each step's figure is distinguishable.
  func startRefreshUICheck() {
    func at(_ delay: TimeInterval, _ body: @escaping () -> Void) {
      // Common-mode timers keep firing inside the nested run loop that menu tracking spins up
      let t = Timer(timeInterval: delay, repeats: false) { _ in body() }
      RunLoop.main.add(t, forMode: .common)
    }
    func show(_ tag: String) {
      dbg("\(tag) open=\(menuOpen) rows: " + axRows().joined(separator: " | "))
    }
    at(0.5) { show("[0] before any click ") } // baseline: what AX reports with the menu closed
    at(1.0) { dbg("→ click the status item"); self.statusItem.button?.performClick(nil) }
    at(2.0) { show("[1] menu opened      ") }
    at(2.5) { dbg("→ Refresh while open"); self.manualRefresh() }
    at(6.0) { show("[1] after refresh    "); self.statusItem.menu?.cancelTracking() }
    at(7.0) { dbg("→ Refresh while closed (what clicking the row does)"); self.manualRefresh() }
    at(11.0) { show("[2] after refresh    "); self.statusItem.menu?.cancelTracking() }
    at(22.0) { dbg("→ opening a stale menu (last collect >\(MENU_STALE_SECONDS)s ago)")
               self.statusItem.button?.performClick(nil) }
    at(25.0) { show("[3] opened stale     "); self.statusItem.menu?.cancelTracking() }
    at(26.0) { exit(0) }
  }
}
