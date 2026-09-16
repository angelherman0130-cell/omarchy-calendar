import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The clock's calendar popup: a month grid with ISO week numbers, built to
// sit beside the weather panel — same hero-over-detail composition, same
// spacing scale, same small-caps labels.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen —
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  property var anchorItem: null

  // The bar tracks the widget mounted in its slot — BarWidget.qml — not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  property int viewMonth: today.getMonth()

  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed — stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // ---- Cronos task creation. Clicking a day turns the popup into a quick-add
  //      form backed by Cronos' own service, so tasks get the same ids, tags,
  //      reminder rules and atomic writes as if they were added there. Zero
  //      files are touched from here: Cronos does the persistence.
  readonly property var cronosService: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("angelherman.cronos")
    : null
  readonly property bool cronosAvailable: root.cronosService !== null && root.cronosService !== undefined

  property string selectedKey: ""
  readonly property date selectedDate: {
    var m = String(root.selectedKey).match(/^(\d{4})-(\d{2})-(\d{2})$/)
    if (!m) return new Date()
    var d = new Date(+m[1], +m[2] - 1, +m[3])
    return isNaN(d.getTime()) ? new Date() : d
  }

  property string titleText: ""
  property string notesText: ""
  property string tagsText: ""
  property string taskTime: ""
  property string leadValue: "0"
  property string leadMode: "exact"
  property string customLeadValue: ""
  property string customLeadUnit: "h"
  property string taskCard: ""
  property string taskNotice: ""

  readonly property var taskTimePresets: [
    "07:00", "09:00", "12:00", "15:00", "18:00", "21:00", "23:59"
  ]

  readonly property var taskLeadPresets: [
    { value: "0",   label: "At deadline", mode: "exact" },
    { value: "1",   label: "1 h",         mode: "exact" },
    { value: "3",   label: "3 h",         mode: "exact" },
    { value: "6",   label: "6 h",         mode: "exact" },
    { value: "12",  label: "12 h",        mode: "exact" },
    { value: "24",  label: "1 day",       mode: "day" },
    { value: "48",  label: "2 days",      mode: "day" },
    { value: "72",  label: "3 days",      mode: "day" },
    { value: "120", label: "5 days",      mode: "day" },
    { value: "168", label: "1 week",      mode: "day" },
    { value: "336", label: "2 weeks",     mode: "day" }
  ]

  // ---- Cronos integration. The calendar popup reads the task list straight
  //      from the Cronos plugin's store, so any plugin that writes the same
  //      "tasks.json" shape lights these days up without extra plumbing.
  property string cronosJson: ""
  readonly property var cronosTasks: {
    if (root.cronosJson.trim() === "") return []
    try {
      var parsed = JSON.parse(root.cronosJson)
      return Array.isArray(parsed) ? parsed : []
    } catch (e) {
      return []
    }
  }
  readonly property var taskDayMap: Model.taskDayMap(root.cronosTasks)
  readonly property var agendaTasks: Model.upcomingTasks(root.cronosTasks, 8)

  FileView {
    id: cronosStore
    path: Quickshell.env("HOME") + "/.local/state/omarchy/cronos/tasks.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.cronosJson = text()
    onLoadFailed: root.cronosJson = ""
  }

  // FileView stops watching a path that did not exist when it mounted; a
  // periodic re-read keeps the agenda fresh regardless.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: cronosStore.reload()
  }

  // Short relative label for a "yyyy-MM-dd" (or longer) due stamp.
  function dueLabel(due) {
    if (!due) return ""
    var stamp = String(due).length >= 10 ? String(due).slice(0, 10) : String(due)
    if (!/^\d{4}-\d{2}-\d{2}$/.test(stamp)) return ""
    var date = new Date(Number(stamp.slice(0, 4)), Number(stamp.slice(5, 7)) - 1, Number(stamp.slice(8, 10)))
    if (isNaN(date.getTime())) return ""
    var todayStart = new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate())
    var diff = Math.round((date - todayStart) / 86400000)
    if (diff === 0) return "Today"
    if (diff === 1) return "Tomorrow"
    if (diff === -1) return "Yesterday"
    return Qt.formatDate(date, "dddd d MMMM")
  }


  // Guarded so the widget renders before the bar is injected (the bar-widget
  // contract instantiates it bare).
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int cellWidth: Style.space(52)
  readonly property int cellHeight: Style.space(34)
  readonly property int cellSpacing: Style.space(2)
  readonly property int weekColumnWidth: Style.space(32)
  readonly property int gutterWidth: Style.space(14)

  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife) root.cancelEditingLife()
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart) return
    persistSettings({ weekStartDay: Model.weekStartSettingName(next) })
  }

  function startEditingLife() {
    root.editingLife = true
    Qt.callLater(function() {
      bornField.text = root.birthYear > 0 ? String(root.birthYear) : ""
      expectancyField.text = String(root.lifeExpectancy)
      bornField.selectAll()
      bornField.forceActiveFocus()
    })
  }

  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
  }

  // Shared by both fields: Tab hops to the other one, Enter commits the pair,
  // Escape drops the lot.
  function handleLifeKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      root.cancelEditingLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      root.commitLife()
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0) return
    persistSettings({ birthYear: 0 })
  }

  function commitLife() {
    var born = Model.parseBirthYear(bornField.text, today.getFullYear())
    var span = Model.parseLifeExpectancy(expectancyField.text)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({ birthYear: born, lifeExpectancy: span })
    cancelEditingLife()
  }

  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  // ---- quick-add form --------------------------------------------------

  function pickTaskDate(key) {
    root.selectedKey = root.selectedKey === key ? "" : key
    root.taskNotice = ""
    root.taskCard = ""
  }

  function toggleTaskCard(name) {
    root.taskCard = root.taskCard === name ? "" : name
    root.taskNotice = ""
  }

  function applyCustomLead() {
    var n = Number(root.customLeadValue)
    if (!isFinite(n) || n <= 0) {
      root.taskNotice = "Enter a number greater than 0 in the custom reminder"
      return
    }
    root.leadValue = String(root.customLeadUnit === "min" ? n / 60 : n)
    root.leadMode = "exact"
    root.taskCard = ""
    root.taskNotice = ""
  }

  function leadLabelFor(hours) {
    var h = Math.max(0, Number(hours) || 0)
    if (h <= 0.001) return "at the deadline"
    var totalMin = Math.round(h * 60)
    if (totalMin < 60) return totalMin + " min"
    if (totalMin % (24 * 60) === 0) {
      var d = totalMin / (24 * 60)
      return d === 1 ? "1 day" : d + " days"
    }
    var hh = Math.floor(totalMin / 60)
    var mm = totalMin % 60
    return mm === 0 ? (hh === 1 ? "1 h" : hh + " h") : hh + " h " + mm + " min"
  }

  function taskSummary() {
    var s = "Due " + root.dueLabel(root.selectedKey)
    if (root.taskTime) s += " · " + root.taskTime
    s += " · reminder " + root.leadLabelFor(root.leadValue)
    return s
  }

  function resetTaskForm() {
    root.titleText = ""
    root.notesText = ""
    root.tagsText = ""
    root.taskTime = ""
    root.customLeadValue = ""
    root.taskNotice = ""
    root.taskCard = ""
  }

  function submitTask() {
    var s = root.cronosService
    if (!s) return
    if (String(root.titleText).trim() === "" || root.selectedKey === "") {
      root.taskNotice = "Check the title"
      return
    }
    if (s.add(root.titleText, root.selectedKey, root.taskTime, root.leadValue,
        root.notesText, root.leadMode, root.tagsText)) {
      root.resetTaskForm()
      cronosStore.reload()
    } else {
      root.taskNotice = "Could not add the task right now"
    }
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey)) return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday) root.goToToday()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(calendarColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editingLife
        || titleTask.activeFocus || notesTask.activeFocus || tagsTask.activeFocus
        || taskTimeField.activeFocus || customLeadField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveMonth(dx)
        if (dy !== 0) root.moveYear(dy)
      }
      onActivateRequested: root.goToToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "[") root.moveMonth(-1)
        else if (t === "]") root.moveMonth(1)
        else if (t === "{") root.moveYear(-1)
        else if (t === "}") root.moveYear(1)
        else if (t === "t" || t === "T") root.goToToday()
        else if (t === "w" || t === "W") root.toggleWeekStart()
      }

      Flickable {
        id: calendarScroll
        anchors.fill: parent
        contentWidth: calendarColumn.width
        contentHeight: calendarColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height || contentWidth > width

        Column {
          id: calendarColumn
          // Never narrower than the grid. The popup width is capped to what
          // the screen allows, and a fixed seven-column grid would otherwise
          // lose its last days off the edge instead of scrolling.
          width: Math.max(calendarScroll.width, gridColumn.width)
          spacing: Style.space(8)

          // ---- Hero: today, centered. Once the view has stepped back
          //      it is also the way home — clicking the date you are
          //      looking for beats hunting for a reset button.
          Item {
            width: parent.width
            height: heroRow.height

            Row {
              id: heroRow
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(22)

              Text {
                // Baseline-aligned, not center-aligned: "July 26" carries a
                // descender, so centering the two boxes leaves the icon
                // sitting visibly low against the digits.
                anchors.baseline: heroDate.baseline
                text: "󰃭"
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                // Decorative, and deliberately outside the Style.font.*
                // scale. Sized so the glyph reads at the cap height of the
                // date beside it rather than towering over it.
                font.pixelSize: 48
              }

              Text {
                id: heroDate
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(root.today, "MMMM d")
                color: heroMouse.containsMouse
                  ? Style.hoverStateColor(root.contentForeground, Color.accent)
                  : root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: 52
                font.bold: true
              }
            }

            MouseArea {
              id: heroMouse
              x: heroRow.x
              y: heroRow.y
              width: heroRow.width
              height: heroRow.height
              enabled: !root.viewingCurrentMonth
              hoverEnabled: enabled
              cursorShape: Qt.PointingHandCursor
              onClicked: root.goToToday()

              PanelToolTip {
                visible: heroMouse.containsMouse
                text: "Back to today"
                fontFamily: root.contentFontFamily
              }
            }
          }

          // ---- Year progress, doubling as the rule under the hero:
          //      a plain hairline said nothing, and whole days done
          //      over days in the year says the same thing louder.
          Item {
            width: parent.width
            height: yearBlock.y + yearBlock.height

            Item {
              id: yearBlock
              y: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(yearLabel.implicitHeight, Style.space(10))

              TapHandler {
                enabled: !root.editingLife
                onDoubleTapped: root.startEditingLife()
              }

              Row {
                visible: root.editingLife
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "BORN"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: bornField
                  width: Style.space(70)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "year"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, expectancyField) }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.verticalCenterOffset: 0
                  leftPadding: Style.space(6)
                  text: "LIVE TO"
                  color: Qt.darker(root.contentForeground, 1.5)
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.letterSpacing: 1
                }

                TextField {
                  id: expectancyField
                  width: Style.space(60)
                  anchors.verticalCenter: parent.verticalCenter
                  placeholderText: "90"
                  foreground: root.contentForeground
                  font.family: root.contentFontFamily
                  inputMethodHints: Qt.ImhDigitsOnly

                  Keys.onPressed: function(event) { root.handleLifeKey(event, bornField) }
                }
              }

              Text {
                id: yearLabel
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.today.getFullYear()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: yearPercent
                textFormat: Text.PlainText
                visible: !root.editingLife
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.yearDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                id: yearTrack
                visible: !root.editingLife
                anchors.left: yearLabel.right
                anchors.right: yearPercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.yearDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }
            }
          }

          // ---- Memento mori. Only here once someone has gone looking and
          //      given an age; the same rail as the year above it, measured
          //      against a nominal lifetime.
          Item {
            visible: root.birthYear > 0
            width: parent.width
            height: visible ? lifeBlock.height : 0

            Item {
              id: lifeBlock
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: Math.max(lifeLabel.implicitHeight, Style.space(10))

              Text {
                id: lifeLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "LIFE"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
                font.letterSpacing: 1
              }

              Text {
                id: lifePercent
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.lifeDonePercent + "%"
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Rectangle {
                anchors.left: lifeLabel.right
                anchors.right: lifePercent.left
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(6)
                radius: Style.cornerRadius > 0 ? height / 2 : 0
                color: Qt.rgba(root.contentForeground.r, root.contentForeground.g, root.contentForeground.b, 0.12)

                Rectangle {
                  width: Math.round(parent.width * root.lifeDone)
                  height: parent.height
                  radius: parent.radius
                  color: Style.selectedStateColor(root.contentForeground, Color.accent)

                  Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }
              }

              TapHandler {
                onDoubleTapped: root.clearLife()
              }

              MouseArea {
                id: lifeMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                PanelToolTip {
                  visible: lifeMouse.containsMouse
                  text: "Memento Mori"
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }

          // ---- Month grid: week numbers down a gutter on the left, then
          //      the seven day columns. Always six rows, so the popup is
          //      exactly as tall in February as it is in August.
          Item {
            width: parent.width
            height: gridColumn.y + gridColumn.height

            WheelHandler {
              onWheel: function(event) {
                // Horizontal wheels and touchpad side-scrolls report y === 0;
                // without this they would every one read as "next month".
                if (event.angleDelta.y === 0) return
                root.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
              }
            }

            Column {
              id: gridColumn
              // The meter above is a solid rule; the grid needs room to
              // read as its own block rather than hanging off it.
              y: Style.space(18)
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(3)

              Row {
                id: headerRow
                spacing: root.cellSpacing

                // The week-number heading doubles as the week-start toggle.
                // It is the one control in the panel whose meaning is not
                // self-evident, so it carries a tooltip naming the day the
                // click will switch to.
                Rectangle {
                  width: root.weekColumnWidth
                  height: Style.space(16)
                  radius: Style.cornerRadius
                  color: weekStartMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent)
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "W"
                    color: weekStartMouse.containsMouse
                      ? Style.hoverStateColor(root.contentForeground, Color.accent)
                      : Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }

                  MouseArea {
                    id: weekStartMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleWeekStart()
                  }

                  PanelToolTip {
                    visible: weekStartMouse.containsMouse
                    text: "Start weeks on " + root.nextWeekStartLabel
                    fontFamily: root.contentFontFamily
                  }
                }

                Item {
                  width: root.gutterWidth
                  height: Style.space(16)
                }

                Repeater {
                  model: root.weekdays

                  Text {
                    textFormat: Text.PlainText
                    required property var modelData
                    width: root.cellWidth
                    height: Style.space(16)
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.weekdayLabel(modelData)
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    font.letterSpacing: 1
                    font.bold: true
                  }
                }
              }

              Repeater {
                model: root.weeks

                Row {
                  required property var modelData
                  spacing: root.cellSpacing

                  Text {
                    textFormat: Text.PlainText
                    width: root.weekColumnWidth
                    height: root.cellHeight
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: modelData.week
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Item {
                    width: root.gutterWidth
                    height: root.cellHeight
                  }

                  Repeater {
                    model: modelData.days

                    Rectangle {
                      required property var modelData
                      readonly property bool sel: modelData.key === root.selectedKey

                      width: root.cellWidth
                      height: root.cellHeight
                      radius: Style.cornerRadius
                      // Today is outlined, not filled: a lit-up block shouts
                      // over a grid this quiet. A selected day (the quick-add
                      // target) is filled with the same accent family.
                      color: modelData.sel ? Style.selectedAccentFill : "transparent"
                      border.width: modelData.sel ? 1 : (
                        modelData.today ? Style.spacing.hairline : 0)
                      border.color: modelData.sel
                        ? Style.selectedBorderColor
                        : (modelData.today ? Style.normalBorderFor(root.contentForeground, Color.accent) : "transparent")

                      Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        visible: cellMouse.containsMouse && !parent.sel && modelData.inMonth
                        color: Style.hoverFill
                      }

                      Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        text: modelData.day
                        color: modelData.inMonth
                          ? (parent.sel ? Color.accent
                            : (modelData.weekend ? Qt.darker(root.contentForeground, 1.45) : root.contentForeground))
                          : Qt.darker(root.contentForeground, 2.2)
                        font.family: root.contentFontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.today
                      }

                      // Days carrying open Cronos tasks get an accent dot.
                      Rectangle {
                        width: Style.space(3)
                        height: Style.space(3)
                        radius: width / 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Style.space(2)
                        visible: root.taskDayMap.hasOwnProperty(modelData.key)
                        color: Color.accent
                      }

                      MouseArea {
                        id: cellMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (modelData.inMonth) root.pickTaskDate(modelData.key)
                        }
                      }

                      PanelToolTip {
                        visible: cellMouse.containsMouse && modelData.inMonth && root.cronosAvailable
                        text: "Create a task on " + Qt.formatDate(
                          new Date(Number(modelData.key.slice(0, 4)),
                            Number(modelData.key.slice(5, 7)) - 1,
                            Number(modelData.key.slice(8, 10))), "dddd d MMMM")
                        fontFamily: root.contentFontFamily
                      }
                    }
                  }
                }
              }
            }

            // Hairline down the week-number gutter, drawn only beside the
            // day rows so it does not cut through the header band.
            Rectangle {
              x: gridColumn.x + root.weekColumnWidth + root.cellSpacing + Math.round((root.gutterWidth - width) / 2)
              y: gridColumn.y + headerRow.height + gridColumn.spacing
              width: Style.spacing.hairline
              height: gridColumn.height - headerRow.height - gridColumn.spacing
              color: root.contentForeground
              opacity: 0.1
            }
          }

          // ---- Month stepping, spanning the grid it drives. The chevrons
          //      sit on the grid's outer bounds, the same edges the year
          //      rail above uses, so the row reads as the panel's other
          //      full-width rail instead of a cluster floating in space.
          //      The label is centered and fixed-width, so it holds still
          //      from "MAY" to "SEPTEMBER".
          Item {
            width: parent.width
            height: monthNav.height

            Item {
              id: monthNav
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              height: monthLabel.implicitHeight + Style.space(10)

              Text {
                id: monthLabel
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                // Fixed width so the chevrons hold still between a
                // "MAY 2026" and a "SEPTEMBER 2026".
                width: Style.space(130)
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(root.viewDate, "MMMM yyyy").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.4)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.letterSpacing: 1
              }

              PanelActionButton {
                // Pulled out by the button's own padding so the glyph, not
                // its hit box, lines up with the "2026" on the year rail.
                anchors.left: parent.left
                anchors.leftMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅁"
                tooltipText: "Previous month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(-1)
              }

              PanelActionButton {
                anchors.right: parent.right
                anchors.rightMargin: -Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅂"
                tooltipText: "Next month"
                foreground: root.contentForeground
                fontFamily: root.contentFontFamily
                onClicked: root.moveMonth(1)
              }
            }
          }

          // ---- Quick add: clicking a day turns the popup into a task form
          //      with the same options as Cronos (title, notes, tags, time,
          //      presets and custom reminder). Tasks go through Cronos'
          //      service, so they land in the same store with the same rules.
          Item {
            id: taskSection
            visible: root.selectedKey !== "" && root.cronosAvailable
            width: parent.width
            height: visible ? taskColumn.y + taskColumn.height + Style.space(4) : 0

            Column {
              id: taskColumn
              y: Style.space(14)
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(8)

              Text {
                textFormat: Text.PlainText
                text: "NEW TASK · " + Qt.formatDate(root.selectedDate, "dddd d MMMM").toUpperCase()
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              TextField {
                id: titleTask
                width: parent.width
                placeholderText: "Task title"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                text: root.titleText
                onTextChanged: root.titleText = text
                onAccepted: root.submitTask()
              }

              TextField {
                id: notesTask
                width: parent.width
                placeholderText: "Description or notes (optional)"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                text: root.notesText
                onTextChanged: root.notesText = text
              }

              TextField {
                id: tagsTask
                width: parent.width
                placeholderText: "Tags (comma separated, optional)"
                foreground: root.contentForeground
                font.family: root.contentFontFamily
                text: root.tagsText
                onTextChanged: root.tagsText = text
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  width: (parent.width - Style.space(6)) / 2
                  text: "Time"
                  foreground: root.contentForeground
                  accent: Color.accent
                  active: root.taskCard === "time"
                  focusable: true
                  onClicked: root.toggleTaskCard("time")
                }

                Button {
                  width: (parent.width - Style.space(6)) / 2
                  text: "Reminder"
                  foreground: root.contentForeground
                  accent: Color.accent
                  active: root.taskCard === "reminder"
                  focusable: true
                  onClicked: root.toggleTaskCard("reminder")
                }
              }

              Text {
                textFormat: Text.PlainText
                text: root.taskSummary()
                color: Qt.darker(root.contentForeground, 1.45)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width
              }

              Rectangle {
                visible: root.taskCard === "time"
                width: parent.width
                height: timeCardLayout.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: Color.popups.background
                border.color: Qt.alpha(Color.accent, 0.4)
                border.width: 1

                Column {
                  id: timeCardLayout
                  width: parent.width - Style.space(24)
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    TextField {
                      id: taskTimeField
                      width: parent.width - Style.space(100)
                      placeholderText: "13:00"
                      foreground: root.contentForeground
                      font.family: root.contentFontFamily
                      text: root.taskTime
                      onTextChanged: root.taskTime = text
                      onAccepted: root.taskCard = ""
                    }

                    Button {
                      width: Style.space(94)
                      text: "Clear"
                      foreground: root.contentForeground
                      accent: Color.accent
                      onClicked: root.taskTime = ""
                    }
                  }

                  GridLayout {
                    width: parent.width
                    columns: 4
                    columnSpacing: Style.space(6)
                    rowSpacing: Style.space(6)

                    Repeater {
                      model: root.taskTimePresets

                      Button {
                        Layout.fillWidth: true
                        text: modelData
                        foreground: root.contentForeground
                        accent: Color.accent
                        active: root.taskTime === modelData
                        onClicked: root.taskTime = modelData
                      }
                    }
                  }
                }
              }

              Rectangle {
                visible: root.taskCard === "reminder"
                width: parent.width
                height: leadCardLayout.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: Color.popups.background
                border.color: Qt.alpha(Color.accent, 0.4)
                border.width: 1

                Column {
                  id: leadCardLayout
                  width: parent.width - Style.space(24)
                  anchors.centerIn: parent
                  spacing: Style.space(6)

                  GridLayout {
                    width: parent.width
                    columns: 4
                    columnSpacing: Style.space(6)
                    rowSpacing: Style.space(6)

                    Repeater {
                      model: root.taskLeadPresets

                      Button {
                        Layout.fillWidth: true
                        text: modelData.label
                        foreground: root.contentForeground
                        accent: Color.accent
                        active: root.leadValue === modelData.value && root.leadMode === modelData.mode
                        onClicked: {
                          root.leadValue = modelData.value
                          root.leadMode = modelData.mode
                        }
                      }
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "Remind before the deadline"
                    color: Qt.darker(root.contentForeground, 1.5)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }

                  Row {
                    width: parent.width
                    spacing: Style.space(6)

                    TextField {
                      id: customLeadField
                      width: parent.width - Style.space(176)
                      placeholderText: "Number"
                      foreground: root.contentForeground
                      font.family: root.contentFontFamily
                      text: root.customLeadValue
                      onTextChanged: root.customLeadValue = text
                      onAccepted: root.applyCustomLead()
                    }

                    Button {
                      width: Style.space(54)
                      text: "min"
                      foreground: root.contentForeground
                      accent: Color.accent
                      active: root.customLeadUnit === "min"
                      onClicked: root.customLeadUnit = "min"
                    }

                    Button {
                      width: Style.space(54)
                      text: "h"
                      foreground: root.contentForeground
                      accent: Color.accent
                      active: root.customLeadUnit === "h"
                      onClicked: root.customLeadUnit = "h"
                    }

                    Button {
                      width: Style.space(62)
                      text: "Use"
                      foreground: root.contentForeground
                      accent: Color.accent
                      onClicked: root.applyCustomLead()
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: "min = minutes before · h = hours before the deadline"
                    color: Qt.darker(root.contentForeground, 1.9)
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    width: parent.width
                  }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  textFormat: Text.PlainText
                  visible: root.taskNotice !== ""
                  text: root.taskNotice
                  color: Color.urgent
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  width: parent.width - Style.space(112)
                }

                Button {
                  width: Style.space(106)
                  text: "＋ Add"
                  accent: Color.accent
                  foreground: root.contentForeground
                  focusable: true
                  onClicked: root.submitTask()
                }
              }
            }
          }

          // ---- Cronos tasks: the next ones, in the same rail-and-list
          //      language as the navbar above. The dots in the grid get a
          //      plain-text reading here.
          Item {
            width: parent.width
            height: cronosHeading.height + cronosList.implicitHeight + Style.space(8)

            Column {
              id: cronosColumn
              anchors.horizontalCenter: parent.horizontalCenter
              width: gridColumn.width
              spacing: Style.space(7)

              Text {
                id: cronosHeading
                textFormat: Text.PlainText
                text: "CRONOS TASKS"
                color: Qt.darker(root.contentForeground, 1.5)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
              }

              Column {
                id: cronosList
                width: parent.width
                spacing: Style.space(3)

                Repeater {
                  model: root.agendaTasks

                  Row {
                    required property var modelData
                    width: parent.width
                    spacing: Style.space(8)
                    height: taskTitle.implicitHeight

                    Rectangle {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(5)
                      height: Style.space(5)
                      radius: width / 2
                      color: Model.dueKey(modelData) < root.todayKey ? Color.urgent : Color.accent
                    }

                    Text {
                      id: taskTitle
                      textFormat: Text.PlainText
                      text: modelData.title || "(untitled)"
                      color: root.contentForeground
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                      width: Math.max(10, parent.width - dueLabel.implicitWidth - Style.space(8) - Style.space(5))
                    }

                    Text {
                      id: dueLabel
                      textFormat: Text.PlainText
                      text: root.dueLabel(modelData.due)
                      color: Qt.darker(root.contentForeground, 1.45)
                      font.family: root.contentFontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }
                }
              }

              Text {
                visible: root.agendaTasks.length === 0
                textFormat: Text.PlainText
                text: "No pending tasks"
                color: Qt.darker(root.contentForeground, 2)
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }
          }
        }
      }
    }
  }
}
