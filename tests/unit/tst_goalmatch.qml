import QtQuick
import QtTest

import "../../GoalMatch.js" as GoalMatch

// The journal's `@` goal list: which goals a half-typed query finds, and in
// what order (docs/ui-spec.md, "Goal tags"). Each case here is one of the
// rules GoalMatch.js's comments give, so a change to the scoring that breaks
// one shows up as that rule.
TestCase {
  name: "GoalMatch"

  readonly property var goals: [
    { slug: "wall-squat", title: "Wall Squat", status: "active" },
    { slug: "study-software-architecture", title: "Study Software Architecture", status: "active" },
    { slug: "diat", title: "Diät", status: "active" },
    { slug: "learn-rust", title: "Learn Rust", status: "done" }
  ]

  function slugs(list) { return list.map(function(g) { return g.slug }) }

  function test_empty_query_keeps_the_list() {
    compare(slugs(GoalMatch.filterGoals(goals, "")), slugs(goals))
  }

  function test_foldForMatch_data() {
    return [
      { tag: "case", s: "Wall Squat", want: "wall-squat" },
      { tag: "accents", s: "Diät", want: "diat" },
      { tag: "runs of spaces and hyphens", s: "a  - b", want: "a-b" }
    ]
  }
  function test_foldForMatch(row) { compare(GoalMatch.foldForMatch(row.s), row.want) }

  function test_scattered_letters_in_order() {
    compare(slugs(GoalMatch.filterGoals(goals, "wsq")), ["wall-squat"])
    compare(slugs(GoalMatch.filterGoals(goals, "WallSq")), ["wall-squat"], "case-blind")
    compare(GoalMatch.filterGoals(goals, "qsw").length, 0, "out of order is no match")
  }

  function test_accents_and_hyphens() {
    compare(slugs(GoalMatch.filterGoals(goals, "dia")), ["diat"])
    compare(slugs(GoalMatch.filterGoals(goals, "wall-sq")), ["wall-squat"], "a hyphen matches a space")
  }

  function test_tiers() {
    // The start of the text, then a word start, then anywhere, then
    // scattered: lower is better.
    var start = GoalMatch.matchScore("learn-rust", "lea")
    var word = GoalMatch.matchScore("learn-rust", "rus")
    var inside = GoalMatch.matchScore("learn-rust", "ear")
    var scattered = GoalMatch.matchScore("learn-rust", "lrt")
    verify(start < word && word < inside && inside < scattered,
           [start, word, inside, scattered].join(" < "))
    compare(GoalMatch.matchScore("learn-rust", "xyz"), Infinity)
  }

  // `sa` is Study Software Architecture's initials, and Wall Squat holds it
  // scattered too (squ-a-t). Taking each letter where it first appears would
  // read the `a` inside "software" and rank Wall Squat above it.
  function test_initials_beat_letters_inside_words() {
    var list = slugs(GoalMatch.filterGoals(goals, "sa"))
    compare(list[0], "study-software-architecture")
  }

  function test_ties_keep_the_list_order() {
    var two = [{ slug: "b-x", title: "B x" }, { slug: "a-x", title: "A x" }]
    compare(slugs(GoalMatch.filterGoals(two, "x")), ["b-x", "a-x"])
  }
}
