.pragma library

// Matching a half-typed `@` query against the app's goals, for the journal's
// goal list (JournalScreen's `@` goal tags). Pure: nothing here touches QML
// state or files, so it is a shared library rather than functions on the
// screen, and the screen only keeps thin wrappers for its existing callers.

// Fuzzy and case-blind: the query's letters have to appear in the slug or
// the title in order, not side by side, so `wsq` and `WallSq` both find
// Wall Squat. Plain substring matching missed those, and a query is typed
// fast and half-remembered. Tighter matches rank first -- see matchScore
// -- and ties keep the list's own order (active goals first).
//
// `goals` is [{slug, title, status}]; returns the matching ones, best first.
function filterGoals(goals, query) {
  var q = foldForMatch(query)
  if (q === "") return goals
  var scored = []
  for (var i = 0; i < goals.length; i++) {
    var g = goals[i]
    var score = Math.min(matchScore(foldForMatch(g.slug), q),
                         matchScore(foldForMatch(g.title), q))
    if (score < Infinity) scored.push({ g: g, score: score, i: i })
  }
  scored.sort(function(a, b) { return a.score !== b.score ? a.score - b.score : a.i - b.i })
  return scored.map(function(s) { return s.g })
}

// Lower case, accents dropped (a title's `Diät` has to answer to `dia`:
// the query is a would-be slug, so it can only hold ASCII), and every run
// of spaces or hyphens made one hyphen, so a slug and a title compare
// alike and a hyphen typed in the query matches a space in a title.
function foldForMatch(s) {
  var t = String(s).toLowerCase()
  if (typeof t.normalize === "function") t = t.normalize("NFD").replace(/[̀-ͯ]/g, "")
  return t.replace(/[\s-]+/g, "-")
}

// How well the folded query q matches the folded text t, lower is better,
// Infinity for no match. In tiers: the start of the text, then the start
// of a word, then anywhere as one piece, then scattered in order. Hyphens
// in the query are ignored for the scattered tier, so `wall-sq` and
// `wallsq` rank alike there.
//
// A scattered match is scored the way initials are read: a letter that
// follows the previous one costs nothing, one that begins a word costs a
// little, one lost in the middle of a word costs most, and a hair more for
// every letter skipped breaks ties. The best placement is searched for,
// not the first: taking each letter where it first appears reads `sa` in
// Study Software Architecture as the `a` inside "software", and ranks it
// below Wall Squat, when the `a` of "architecture" is plainly meant.
function matchScore(t, q) {
  if (t.indexOf(q) === 0) return 0
  if (("-" + t).indexOf("-" + q) >= 0) return 1
  if (t.indexOf(q) >= 0) return 2
  var letters = q.replace(/-/g, "")
  if (letters === "") return Infinity
  // cost[j]: the cheapest placement of the letters so far, the last at j.
  var cost = []
  for (var k = 0; k < letters.length; k++) {
    var next = []
    for (var j = 0; j < t.length; j++) {
      next.push(Infinity)
      if (t.charAt(j) !== letters.charAt(k)) continue
      var wordStart = j === 0 || t.charAt(j - 1) === "-"
      if (k === 0) { next[j] = wordStart ? 0 : 3; continue }
      if (j > 0 && cost[j - 1] < Infinity) next[j] = cost[j - 1]
      for (var p = 0; p < j - 1; p++)
        if (cost[p] < Infinity)
          next[j] = Math.min(next[j], cost[p] + (wordStart ? 1 : 3) + 0.01 * (j - p - 1))
    }
    cost = next
  }
  var best = Math.min.apply(null, cost)
  return best < Infinity ? 3 + best / (3 * letters.length + t.length + 1) : Infinity
}
