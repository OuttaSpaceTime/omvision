.pragma library

// Small pure helpers for the app's state objects. Nothing here touches files
// or QML; everything returns a new value and leaves its arguments alone.
//
// Why copies at all: a QML `property var` holding an object only notifies
// when the property is *assigned*. Setting one key in place
// (`root.goalsData[slug] = x`) changes the object but no binding that reads
// it ever re-evaluates, so every screen keeps showing the old value. Each of
// these state objects is therefore replaced whole, and the copying used to be
// written out by hand at every place that did it.

// A shallow copy of `obj` with `key` set to `value`.
function withKey(obj, key, value) {
  var d = {}
  for (var k in obj) d[k] = obj[k]
  d[key] = value
  return d
}

// A shallow copy of `obj` keeping only the keys listed in `keys`, for
// dropping the entries of files that have disappeared from a listing.
function pickKeys(obj, keys) {
  var keep = {}
  for (var i = 0; i < keys.length; i++) keep[keys[i]] = true
  var d = {}
  for (var k in obj) if (keep[k]) d[k] = obj[k]
  return d
}

// Whether two lists hold the same items in the same order. `keyOf(item)`,
// if given, is what is compared (e.g. a file's path); otherwise the items
// themselves are, with ===. The directory pollers call this every two seconds
// and only reassign their list when it really changed, because reassigning
// rebuilds every loader and screen bound to it.
function sameList(a, b, keyOf) {
  if (a.length !== b.length) return false
  for (var i = 0; i < a.length; i++) {
    var x = keyOf ? keyOf(a[i]) : a[i]
    var y = keyOf ? keyOf(b[i]) : b[i]
    if (x !== y) return false
  }
  return true
}
