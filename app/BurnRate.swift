// How fast the 5-hour window is being spent — the signal that drives the mascot's mood.
//
// Upstream reads $/hour from ccusage, which is an optional extra: with it absent the burn rate is
// flat zero and the mascot is pinned to its sleeping frame no matter how hard the account is being
// used. The 5-hour utilisation carries the same information for free — sample it on every
// collection and its slope is %/hour, which maps onto the same states.
import Foundation

private let TRACE = "\(STATE_DIR)/.burn-trace.json"
private let TRACE_WINDOW = 45 * 60 // samples older than this say nothing about the current pace
private let MIN_SPAN = 5 * 60 // below this the slope is mostly rounding noise
private let traceLock = NSLock() // collections can overlap (the 2-minute timer and a manual refresh)

private func readTrace(_ now: Int) -> [(t: Int, u: Double)] {
  var samples: [(t: Int, u: Double)] = []
  for s0 in ja(jd(readJSONFile(TRACE))?["samples"]) ?? [] {
    guard let s = jd(s0), let t = jn(s["t"]), let v = jn(s["u"]) else { continue }
    if now - Int(t) <= TRACE_WINDOW { samples.append((Int(t), v)) }
  }
  return samples.sorted { $0.t < $1.t }
}

private func pace(_ samples: [(t: Int, u: Double)]) -> Double? {
  guard let first = samples.first, let last = samples.last, last.t - first.t >= MIN_SPAN else { return nil }
  // A reset drops utilisation back to zero; that is the window turning over, not a negative pace
  return max(0, (last.u - first.u) / (Double(last.t - first.t) / 3600))
}

// Records where the 5-hour window stands. Called once per collection.
func trackBurnRate(now: Int, utilization: Double?) {
  guard let u = utilization else { return }
  traceLock.lock()
  defer { traceLock.unlock() }
  let samples = readTrace(now) + [(now, u)]
  writeJSONFile(TRACE, ["samples": samples.map { ["t": $0.t, "u": $0.u] }])
}

// The current pace in % per hour, or nil while there is not yet enough history to say (a fresh
// install, or the app has been closed for a while). Read-only — safe to call while rendering.
func currentBurnRate(now: Int) -> Double? {
  traceLock.lock()
  defer { traceLock.unlock() }
  return pace(readTrace(now))
}
