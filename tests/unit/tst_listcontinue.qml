import QtQuick
import QtTest

import "../../plugins/ompom.engine/ListContinue.js" as ListContinue

// Return in a markdown list, as the journal and the break's notes both do
// it. `|` marks the caret in each case's text.
TestCase {
  name: "ListContinue"

  // The text after Return, caret marked, or null when Return is left alone.
  function afterReturn(marked) {
    var pos = marked.indexOf("|")
    var text = marked.replace("|", "")
    var e = ListContinue.edit(text, pos, pos, pos)
    if (e === null) return null
    var out = String(text.substring(0, e.from) + e.text + text.substring(e.to))
    return out.substring(0, e.cursor) + "|" + out.substring(e.cursor)
  }

  function test_return_data() {
    return [
      { tag: "a bullet repeats", text: "- one|", want: "- one\n- |" },
      { tag: "* and + too", text: "* a|\n+ b", want: "* a\n* |\n+ b" },
      { tag: "+", text: "+ b|", want: "+ b\n+ |" },
      { tag: "a number counts on", text: "1. one|", want: "1. one\n2. |" },
      { tag: "keeping its )", text: "9) nine|", want: "9) nine\n10) |" },
      { tag: "the indent carries over", text: "  - deep|", want: "  - deep\n  - |" },
      { tag: "mid-item splits it", text: "- on|e", want: "- on\n- |e" },
      { tag: "an empty item ends the list", text: "- one\n- |", want: "- one\n|" },
      { tag: "an empty number too", text: "1. a\n2. |", want: "1. a\n|" },
      { tag: "not a list", text: "plain|", want: null },
      { tag: "a dash with no space isn't a marker", text: "-x|", want: null },
      { tag: "caret in the marker", text: "-| one", want: null },
      { tag: "caret in the indent", text: " | - one", want: null }
    ]
  }
  function test_return(row) {
    compare(afterReturn(row.text), row.want)
  }

  function test_a_selection_is_left_to_the_field() {
    compare(ListContinue.edit("- one", 2, 2, 5), null)
  }
}
