# What to implement next

Ordered by what it closes, not by what it looks like. Each item says what will be true afterwards
and how it is checked; an item with no check is not on this list.

## 1. Non-zero statistics — attempted, no opponent in five minutes

**What was done:** launched with `BIM_AUTOPLAY=1 BIM_AUTOFIGHT=1`, watched for five minutes.
**Result:** the app sat in "Waiting for your opponents…" the whole time (`07_logs/mm-1..13.png`);
the statistics stay in their zero state. Nothing in the app is at fault — the server had nobody
queued at 15:14 UTC.
**What the wait did produce:** the app's own log (`Documents/log.txt`) is readable and full of
signal — see #3 and #9 below. **Cost of retrying:** five minutes, at a busier hour.

## 2. `BIM_NETLOG` — see every request the app makes

**What:** a seam next to the existing audio log that writes `METHOD host/path -> status` per
request, from the one exchange layer (`modules/bim/net/`).
**Why:** three claims in `PARITY_INVENTORY.md` are presence-only or unverified: analytics delivery,
the 403 on `/client/config`, and whether `transfer-legacy-inventory` is ever called. One seam turns
all three into log lines.
**Check:** launch, read `$HOME/net.log`: an `authenticate` 200, a `config` 403 with the app falling
back to defaults, an analytics POST. Then the inventory rows get statuses with evidence.
**Cost:** ~1 hour, one rebuild. **Depends on:** nothing.

## 3. `ic_log` — already correct, drop the caveat

**What the wait showed:** `[2026-11-23 15:14:26][I][new_game_exchange] Got game proposal 3240.` The
log prints timestamp, level, module and text. The `[{}][{}]` claim in `BUILD.md` and `DEVICE_TEST.md`
is stale; this build formats correctly.
**What to do instead:** move the observed severity-`E` lines to the front of the queue — see #9.
**Cost:** 10 minutes, documentation only.

## 9. Two invalid state transitions, found while waiting

**What the log says, twice:**

```
[I][new_game_exchange] Accepting encounter 0.
[E][... state_monitor_m_monitor] idle -> accept_random is not a valid transition.
[I][new_game_exchange] Requesting random game in session 1306.
[E][... state_monitor_m_monitor] accept_random -> start_random is not a valid transition.
```

**Why it matters:** it is the first severity-`E` line this port has produced, and it happens while
matchmaking is trying to work. Either the exchange's state machine is stricter than its callers
assume — an upstream bug that also exists on Android — or the `BIM_AUTOFIGHT` seam fires earlier
than a finger would, and the port is manufacturing its own error.
**How to tell them apart:** run twice, once with `BIM_AUTOFIGHT` unset and one tap-equivalent
delay, and diff the log. If the error survives, it is upstream and belongs in the parity notes,
not in the port.
**Check:** no severity-`E` lines during a matchmaking round, or a note that upstream does it too.
**Cost:** ~1 h, no rebuild needed (the log is enough).

## 4. Animation timings against REA §3.2

**What:** compare `assets/animations.json` (walk 360 ms, flame 330 ms, crate 270 ms per the recon
notes) with what the style data actually declares, and with the upstream constants.
**Why:** these are the only cosmetic numbers in REA that have never been checked on iOS; a wrong
duration is invisible in stills.
**Check:** a table in `01_port/PARITY_INVENTORY.md` with the three durations from both sides, plus
one screenshot pair if they disagree. **Cost:** ~30 min, no rebuild.

## 5. Foreground / background

**What:** background the app by launching another one, wait, bring Bim back.
**Check:** the arena resumes at the right clock, music does not double-start (`BIM_AUDIOLOG` lines
show at most one `music ... id=` per resume), and no crash.
**Cost:** ~30 min. **Depends on:** #2 or the audio log for observation.

## 6. Shop: write down why it cannot be finished, not just that it is not done

**What:** trace the upstream shop call, `POST /client/billing/validate-purchase` with a Google Play
purchase token and a package name; confirm on the server side that it verifies the token against
Play. Then state in `README.md` that iOS cannot be completed here **because the backend has no
Apple path**, which is a different sentence from "not ported".
**Check:** the claim cites the request shape and the server's validation call; the lobby keeps
showing the donation link. **Cost:** ~45 min, no code.

## 7. Cold rebuild from a wiped `build/`

**What:** `rm -rf build && ./01_port/tools/build-all.sh` on this host, x86_64 simulator slice.
**Why:** CI proves the arm64 path from a fresh clone; the local path has never been run end to end
and every "just rebuild" instruction in `BUILD.md` assumes it works.
**Check:** the build completes from zero and the app launches; note the wall time in `BUILD.md`.
**Cost:** ~40-60 min of machine time, `JOBS=4`, supervised. **Risk:** the three kernel panics were
all parallel compiles; do not raise `JOBS`.

## 8. Playbook visibility

**What:** the two repos it documents are public; the playbook is private.
**Check:** decide and do one of them — publish, or say in its README why it stays private.
**Cost:** minutes, needs the owner's decision.

## Not on this list, deliberately

* **StoreKit implementation** — blocked on the backend (#6), not on iOS work.
* **Statistics for a 10,000-game account**, rankings, friends: upstream has none.
* **Landscape/rotation** — upstream is portrait-locked, so parity means staying locked.
* **A signed IPA** — needs the owner's Apple ID and a device registration; nothing here can do it.
