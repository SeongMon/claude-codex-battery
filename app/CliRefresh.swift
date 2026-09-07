// Manual-refresh CLI warm-up — the dropdown's "Refresh" runs the claude / codex CLIs once
// before the snapshot is re-collected, so the numbers come from freshly re-checked logins.
//
// Only non-consuming commands are used (`claude auth status`, `codex login status`): they burn
// no tokens, but each one walks its CLI's auth path, which renews an expired OAuth token and
// rewrites the local credential/session state the app reads. The automatic 2-minute timer never
// does this — it stays a pure API poll, so the Keychain isn't touched behind the user's back.
import Foundation

// Warm-up outcome (surfaced only through CCB_DEBUG logging)
struct CliRefreshResult {
  let claudeRan: Bool
  let codexRan: Bool
  var any: Bool { claudeRan || codexRan }
}

private func warm(_ name: String, _ args: [String], timeout: TimeInterval) -> Bool {
  guard let bin = findBin(name) else {
    cliLog("\(name): not installed")
    return false
  }
  let ok = runCmd(bin, args, timeout: timeout) != nil
  cliLog("\(name) \(args.joined(separator: " ")): \(ok ? "ok" : "failed")")
  return ok
}

private func cliLog(_ msg: String) {
  guard ProcessInfo.processInfo.environment["CCB_DEBUG"] != nil else { return }
  FileHandle.standardError.write(Data("[cli-refresh] \(msg)\n".utf8))
}

// Runs both CLIs back to back. Call from a background thread — this blocks for up to ~15s.
func runCliRefresh() -> CliRefreshResult {
#if MAS_BUILD
  // Sandbox forbids launching external binaries (same reason ccusage is disabled there)
  return CliRefreshResult(claudeRan: false, codexRan: false)
#else
  if liveDisabled() {
    cliLog("skipped — live queries disabled (.no-live)")
    return CliRefreshResult(claudeRan: false, codexRan: false)
  }
  // Side by side — the two CLIs are unrelated, and the click is waiting on the slower of them
  var claudeOK = false, codexOK = false
  let g = DispatchGroup()
  let q = DispatchQueue.global(qos: .userInitiated)
  q.async(group: g) { claudeOK = warm("claude", ["auth", "status"], timeout: 10) }
  q.async(group: g) { codexOK = warm("codex", ["login", "status"], timeout: 10) }
  g.wait()
  // The CLI may have rotated the Keychain token — drop the copy cached for this process so the
  // usage query below re-reads it (and clear any denial backoff, since this refresh is user-initiated).
  if claudeOK { invalidateClaudeToken() }
  resetClaudeTokenBackoff()
  return CliRefreshResult(claudeRan: claudeOK, codexRan: codexOK)
#endif
}
