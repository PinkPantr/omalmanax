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
