// Pure date math and dataset lookup for the Almanax widget and its panel.
// Qt-free on purpose, same as the clock's Model.js, so the QML owns all
// locale and theming concerns.

// The Dofus calendar runs twelve months alongside the Gregorian one, in
// step with it: 31 August is 31 Fraouctor. So a real calendar grid is also
// an Almanax grid, and the only mapping needed is the month name.
var DOFUS_MONTHS = ['Javian', 'Flovor', 'Martalo', 'Aperirel', 'Maisial', 'Juinssidor',
                    'Joullier', 'Fraouctor', 'Septange', 'Octolliard', 'Novamaire', 'Descendre']

function dofusMonth(month) {
  return DOFUS_MONTHS[((month % 12) + 12) % 12]
}

// The dataset key. No year: the Almanax repeats on the same yearly cycle,
// which is what lets the panel step to any date without fetching anything.
function almanaxKey(month, day) {
  return day + " " + dofusMonth(month)
}

function keyForDate(date) {
  return almanaxKey(date.getMonth(), date.getDate())
}

// Identity for a specific calendar cell, where the year does matter.
function dateKey(year, month, day) {
  return year + "-" + month + "-" + day
}

function normalizedWeekStart(value, fallback) {
  var n = parseInt(value, 10)
  if (isNaN(n) || n < 0 || n > 6) {
    var f = parseInt(fallback, 10)
    return isNaN(f) || f < 0 || f > 6 ? 1 : f
  }
  return n
}

function weekdayOrder(weekStart) {
  var order = []
  for (var i = 0; i < 7; i++) order.push((weekStart + i) % 7)
  return order
}

// Six rows always, so the panel's height does not jump between months.
function monthGrid(year, month, weekStart, todayKey, selectedKey) {
  var start = normalizedWeekStart(weekStart, 1)
  var leading = (new Date(year, month, 1).getDay() - start + 7) % 7
  var cursor = new Date(year, month, 1 - leading)
  var today = String(todayKey || "")
  var selected = String(selectedKey || "")
  var weeks = []

  for (var w = 0; w < 6; w++) {
    var days = []
    for (var d = 0; d < 7; d++) {
      var cellYear = cursor.getFullYear()
      var cellMonth = cursor.getMonth()
      var cellDay = cursor.getDate()
      var weekday = cursor.getDay()
      var key = dateKey(cellYear, cellMonth, cellDay)
      days.push({
        key: key,
        year: cellYear,
        month: cellMonth,
        day: cellDay,
        weekday: weekday,
        inMonth: cellMonth === month && cellYear === year,
        weekend: weekday === 0 || weekday === 6,
        today: key === today,
        selected: key === selected,
        almanax: almanaxKey(cellMonth, cellDay)
      })
      cursor.setDate(cursor.getDate() + 1)
    }
    weeks.push({ days: days })
  }
  return weeks
}

// Parse "YYYY-MM-DD" as a local calendar date. Used for the Paris-clock
// handoff: the shell asks `date` for the day in Europe/Paris and this turns
// the answer back into a Date without dragging a timezone through QML.
function parseIsoDate(text, fallback) {
  var m = /^\s*(\d{4})-(\d{2})-(\d{2})\s*$/.exec(String(text || ""))
  if (!m) return fallback
  return new Date(parseInt(m[1], 10), parseInt(m[2], 10) - 1, parseInt(m[3], 10))
}

function sameDay(a, b) {
  return a && b
    && a.getFullYear() === b.getFullYear()
    && a.getMonth() === b.getMonth()
    && a.getDate() === b.getDate()
}

// Relative wording for the detail header, so a browsed day says how far it
// is from today instead of leaving you to count squares.
function relativeLabel(selected, today) {
  if (!selected || !today) return ""
  var a = new Date(selected.getFullYear(), selected.getMonth(), selected.getDate())
  var b = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  var days = Math.round((a - b) / 86400000)
  if (days === 0) return "Aujourd'hui"
  if (days === 1) return "Demain"
  if (days === -1) return "Hier"
  if (days > 0) return "Dans " + days + " jours"
  return "Il y a " + (-days) + " jours"
}

// ---- Search --------------------------------------------------------------
//
// The dataset is keyed by Dofus date with no year, so a hit has to be mapped
// back onto a real calendar date before it can be listed. Every result is the
// *next* occurrence of that day, which is the question actually being asked:
// not "where in the year does this sit" but "when can I next go and do it".

// French accents folded by hand rather than through String.normalize(), which
// is not something to lean on in the shell's JS engine. The set is closed —
// the dataset is French — so a table is both exact and cheap.
var FOLD = {
  "à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a",
  "ç": "c",
  "è": "e", "é": "e", "ê": "e", "ë": "e",
  "ì": "i", "í": "i", "î": "i", "ï": "i",
  "ñ": "n",
  "ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o",
  "ù": "u", "ú": "u", "û": "u", "ü": "u",
  "ý": "y", "ÿ": "y",
  "œ": "oe", "æ": "ae"
}

function normalize(text) {
  return String(text === null || text === undefined ? "" : text)
    .toLowerCase()
    .replace(/[àáâäãåçèéêëìíîïñòóôöõùúûüýÿœæ]/g, function (c) { return FOLD[c] || c })
    .replace(/[’‘‚´`]/g, "'")
}

// Whitespace-separated terms, all of which must match, so "sagesse pandawa"
// narrows rather than widens.
function searchTerms(query) {
  var parts = normalize(query).split(/\s+/)
  var terms = []
  for (var i = 0; i < parts.length; i++) if (parts[i] !== "") terms.push(parts[i])
  return terms
}

function matchesAll(haystack, terms) {
  for (var i = 0; i < terms.length; i++) if (haystack.indexOf(terms[i]) === -1) return false
  return true
}

// "31 Fraouctor" -> { month: 7, day: 31 }
function parseAlmanaxKey(key) {
  var m = /^\s*(\d{1,2})\s+(\S+)\s*$/.exec(String(key || ""))
  if (!m) return null
  var month = DOFUS_MONTHS.indexOf(m[2])
  if (month < 0) return null
  return { month: month, day: parseInt(m[1], 10) }
}

// The next time this month/day comes round, on or after `from`. Walking years
// rather than adding one is what keeps 29 Flovor honest: Date rolls an
// impossible 29 February into 1 March, so the guard rejects that year and the
// search carries on to the next leap one.
function nextOccurrence(month, day, from) {
  for (var i = 0; i < 8; i++) {
    var d = new Date(from.getFullYear() + i, month, day)
    if (d.getMonth() === month && d.getDate() === day && d >= from) return d
  }
  return null
}

// Rank 0 = the query hit the offering or the bonus name, rank 1 = it only
// turned up inside the bonus description. Rank sorts first so an incidental
// word in a paragraph never outranks the thing you actually named; within a
// rank the soonest day wins.
function searchDays(days, query, today, limit) {
  var terms = searchTerms(query)
  var empty = { total: 0, capped: false, rows: [] }
  if (terms.length === 0 || !days) return empty

  var from = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  var keys = Object.keys(days)
  var results = []

  for (var i = 0; i < keys.length; i++) {
    var entry = days[keys[i]]
    if (!entry) continue

    var named = normalize(entry.offrande) + " " + normalize(entry.bonusTitle)
    if (!matchesAll(named + " " + normalize(entry.bonus), terms)) continue

    var parsed = parseAlmanaxKey(keys[i])
    if (!parsed) continue
    var when = nextOccurrence(parsed.month, parsed.day, from)
    if (!when) continue

    results.push({
      key: keys[i],
      entry: entry,
      year: when.getFullYear(),
      month: when.getMonth(),
      day: when.getDate(),
      weekday: when.getDay(),
      away: Math.round((when - from) / 86400000),
      rank: matchesAll(named, terms) ? 0 : 1
    })
  }

  results.sort(function (a, b) { return a.rank - b.rank || a.away - b.away })

  var capped = limit > 0 && results.length > limit
  return {
    total: results.length,
    capped: capped,
    rows: capped ? results.slice(0, limit) : results
  }
}
