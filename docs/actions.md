# Actions file

The actions file replaces the built-in corner clicks with your own steps: a small macro that runs once per cycle. This page covers everything the file can do.

**Contents:** [Turn it on](#turn-it-on) · [Your first macro](#your-first-macro) · [File format](#file-format) · [Commands](#commands) · [Positions](#positions-x-and-y) · [Keys](#keys) · [How a cycle runs](#how-a-cycle-runs) · [Testing a macro](#testing-a-macro) · [Error messages](#error-messages) · [Not supported](#not-supported) · [Examples](#examples)

## Turn it on

In `config.ini`:

```ini
[actions]
file=actions.txt
```

- **Path:** relative to the config file's folder. An absolute path such as `D:\macros\chat.txt` works too.
- **Corner clicks:** leave `file=` empty to go back to them (the `[click]` settings).
- **Switching files:** change `file=` while it runs, and the new file is used from the next cycle.

Other settings that affect a macro:

| Setting | Default | Effect on the macro |
|---|---|---|
| `[actions] restore_focus` | `false` | `true` = after a cycle with a `focus` step, bring back the window (and browser tab) that was in front before |
| `[actions] browsers` | `msedge, chrome, brave, opera, firefox, vivaldi` | programs searched by `focus tab` |
| `[activity] min_interval_seconds` / `max_interval_seconds` | `15` / `60` | random time between two runs of the macro |
| `[activity] idle_seconds` | `120` | how long you must be away before the macro runs at all |
| `[activity] return_after_move` | `true` | put the cursor back where it was after the last step |
| `[activity] smooth_move` | `true` | `false` = the cursor jumps instead of gliding |
| `[debug] dry_run` / `overlay` | `false` | same as `-DryRun` / `-Overlay`, see [Testing a macro](#testing-a-macro) |

All settings: [configuration.md](configuration.md).

## Your first macro

1. **Write the steps.** Create `actions.txt`, or edit the shipped one, with one step per line:

   ```
   # Bring Notepad to the front, wait a moment, press a harmless key
   focus notepad
   wait 500-1000
   key f15
   ```

2. **Point the config at it:** `file=actions.txt` under `[actions]`.
3. **Test it without real input:** `.\cursor-utility.ps1 -RunOnce -DryRun -Overlay` (or `powershell -ExecutionPolicy Bypass -File .\cursor-utility.ps1 -RunOnce -DryRun -Overlay` if scripts are blocked). Then read `logs\cursor-utility.log`; see [Testing a macro](#testing-a-macro).
4. **Save and leave it.** A copy that's already running picks the file up when you save it. No restart is needed.

## File format

- **One step per line,** run from top to bottom. The whole file runs once per cycle, then the app waits for the next cycle.
- **Case doesn't matter:** `Click Left Top` is the same as `click left top`.
- **Spaces:** separate the parts of a step with one or more spaces or tabs. Leading and trailing spaces are ignored. A key combo or a wait range must not contain spaces: `ctrl+c` and `700-2200`, not `ctrl + c` or `700 - 2200`.
- **Comments:** lines starting with `#` or `;`. Blank lines are ignored.
- **No comments after a step:** `wait 500 # pause` is an error, because `# pause` is read as part of the step.
- **Quotes:** only `focus` uses them, around a name with spaces, e.g. `focus "Microsoft Teams"` or `focus tab 'WhatsApp Business'`. They're optional: `focus Microsoft Teams` works too.
- **Encoding:** if a window or tab name has letters outside English (é, ü, Arabic, Chinese, ...), save the file as **UTF-8 with BOM**. In Notepad, that's **Save as → Encoding: UTF-8 with BOM**. Without the BOM, Windows PowerShell reads those letters wrongly, and the name won't match.
- **Reloading:** the file is re-read whenever its size or time stamp changes, so saving is enough.
- **Mistakes:** a mistake anywhere pauses all cycles. The tray icon turns red and shows the message with its line number, e.g. `actions.txt line 4: unknown command 'clik'`, and the log records it once. Cycles resume as soon as you save a fixed file. All the messages are listed under [Error messages](#error-messages).
- **Empty file:** a file with only comments counts as a mistake (`actions.txt has no steps`). So does a missing one (`actions.txt not found`).

## Commands

| Command | Example | What it does |
|---|---|---|
| `move X Y` | `move center 40%` | Glide the cursor to a point |
| `click` | `click` | Left click where the cursor is |
| `click TYPE` | `click right` | Click where the cursor is: `left`, `right`, `middle` or `double` |
| `click X Y` | `click left top` | Move to a point, then left click |
| `click X Y TYPE` | `click right-10 bottom-10 right` | Move to a point, then click with that button |
| `key COMBO` | `key ctrl+shift+f15` | Press a key or a key combination |
| `scroll DIR` | `scroll down` | Turn the mouse wheel one notch |
| `scroll DIR N` | `scroll up 3` | Turn the mouse wheel N notches |
| `wait MS` | `wait 500` | Pause for exactly MS milliseconds |
| `wait MIN-MAX` | `wait 700-2200` | Pause for a random time between MIN and MAX |
| `focus NAME` | `focus teams` | Bring a window to the front |
| `focus tab NAME` | `focus tab whatsapp` | Select a browser tab and bring its window to the front |

### `move X Y`

Moves the cursor to the point along a gentle curve that speeds up and slows down, like a hand would. X and Y are any [positions](#positions-x-and-y).

- **Speed:** longer distances take longer: about 0.45–0.9 s across 1000 pixels, with some variation each time.
- **`smooth_move=false`:** the cursor jumps there instantly instead.
- **Off-screen targets** are pulled to the nearest edge of the desktop.

### `click`

| Form | Example | Meaning |
|---|---|---|
| `click` | `click` | left click where the cursor is now |
| `click TYPE` | `click double` | click with TYPE where the cursor is now |
| `click X Y` | `click 250 center` | move to X Y (like `move`), pause 80–250 ms, left click |
| `click X Y TYPE` | `click 50% 50% right` | the same with another button |

- **Types:** `left`, `right` (opens context menus), `middle` (e.g. opens a link in a new tab), `double` (two quick left clicks, to open a file or select a word).
- **Hold time:** each click holds the button for 60–140 ms, like a person would. A `double` holds 40–90 ms per click, with 60–120 ms between them, so Windows always sees a double click.
- **Watch out, one word is always a type:** `click left` is a left click *where the cursor is*, not a click on the left edge. `click center` and `click 50%` are errors. To click a point, always give both X and Y: `click left center`.

### `key COMBO`

Presses one key, or several together, joined with `+`:

```
key f15
key enter
key ctrl+s
key ctrl+shift+esc
key alt+tab
key shift+a
```

- **How it's pressed:** the keys go down in the order written, 20–60 ms apart. They're held for 50–120 ms, then released in reverse order. That's the same as a person pressing Ctrl, then Shift, then the key.
- **Where it goes:** to the window that's **in front**. Put a `focus` step before it if the key is meant for a particular program, or it may land in whatever you left open.
- **Capital letters and symbols:** `key a` types a small `a`. Use `key shift+a` for `A`, and `key shift+1` for `!` on a US keyboard layout.
- **One key per step:** there is no command to type text. To type `ok`, write `key o` and then `key k`, as two steps.
- **Toggle keys:** `capslock`, `numlock` and `scrolllock` switch a state on or off, so press them twice to leave it as it was.
- **Harmless keys:** `f13`–`f24` exist to Windows, but almost no program reacts to them. That makes `key f15` a safe way to show activity.

All key names: [Keys](#keys).

### `scroll DIR [N]`

Turns the mouse wheel N notches (1–50; 1 if you leave it out), 40–120 ms apart.

- **Directions:** `up`, `down`, `left`, `right`. Left and right only work in programs that support sideways scrolling.
- **Where it scrolls:** Windows sends the wheel to the window **under the cursor**, not necessarily the one in front. Put a `move` before it, e.g. `move center center`, to choose what scrolls.
- **How far:** one notch moves as far as one notch of your own mouse wheel, usually 3 lines. That's set in Windows under **Settings → Bluetooth & devices → Mouse**.

### `wait MS` / `wait MIN-MAX`

Pauses, in milliseconds (1000 ms = 1 second).

- **Fixed:** `wait 500` waits exactly half a second. `wait 0` is allowed.
- **Random:** `wait 700-2200` picks a different time every cycle. Times near the middle of the range come up most often, which looks more natural than an even spread.
- **Limits:** whole numbers only, at most 3600000 (1 hour). The first number must not be larger than the second.
- **Cancelling:** waits still watch the mouse, so moving it during a long wait cancels the cycle right away.

Between your steps the app adds no pause of its own, apart from the small ones listed under [Built-in pauses](#built-in-pauses). Add `wait` steps wherever a program needs time to react, e.g. after `focus` or after opening a menu.

### `focus NAME`

Brings a window to the front. `NAME` is a program's process name or part of a window title. It looks through the visible windows in this order:

1. **Process name, exact:** a window whose program is called exactly `NAME`, without `.exe`. For example `notepad`, `chrome`, `msedge`, `teams`, `ms-teams`, `code`, `outlook`, `excel`.
2. **Title, partial:** otherwise, the front-most window whose title **contains** `NAME`, case-insensitive. For example `focus Inbox` matches `Inbox - you@example.com - Outlook`.

```
focus notepad
focus "Microsoft Teams"
focus Untitled - Notepad
```

**Finding the right name:** paste this into a PowerShell window. It lists every program with a visible window:

```powershell
Get-Process | Where-Object MainWindowTitle | Format-Table ProcessName, MainWindowTitle -AutoSize
```

Use the `ProcessName` column for an exact match. It's the most reliable choice, because window titles change, e.g. with the open file or the number of unread messages.

What happens next:
- **Minimized windows** are restored first.
- **Timing:** there's a 150–400 ms pause after focusing, before the next step.
- **No match:** if no window matches, or Windows refuses to switch, the cycle is cancelled. The rest of the steps don't run, and the log shows `Focus failed: ...`. Nothing is clicked in the wrong window.
- **Switching back:** with `restore_focus=true` (off by default), the window that was in front before the *first* `focus` comes back at the end of the cycle, including when the cycle is cancelled.
- **The Alt tap:** Windows only lets the program that sent the latest input switch windows. If the first try fails, the script taps Alt and tries again. In some programs that briefly underlines menu letters.
- **Title matches can pick the wrong window:** `focus notepad` matches a VS Code window titled `notepad-notes.md` when Notepad itself isn't running. A process-name match always wins when there is one.

### `focus tab NAME`

Windows only sees a browser window's **active** tab, through the window title. So `focus whatsapp` stops finding WhatsApp Web as soon as you switch that window to another tab. `focus tab NAME` looks at the tabs themselves:

```
focus tab whatsapp
focus tab 'WhatsApp Business'
```

How it works:
1. **Find the tab:** it reads the tab strips of every window belonging to the programs in `browsers=` (Edge, Chrome, Brave, Opera, Firefox and Vivaldi by default), using Windows **UI Automation**. Nothing extra needs installing.
2. **Match:** it picks the tab whose title **contains** `NAME`, case-insensitive, so `whatsapp` matches `(3) WhatsApp`. A matching tab that's already selected wins; otherwise the first match is used. The tab title is what you see when you hover the mouse over the tab.
3. **Bring its window to the front,** as `focus` does.
4. **Select the tab** without any input, if the browser supports that. If it doesn't, or the tab didn't switch, the tab is **clicked** instead: the cursor moves there like any other click, and moving the mouse still cancels the cycle.
5. **Switch back:** with `restore_focus=true`, the tab that was showing before comes back at the end of the cycle (by selecting it, never with a click), then the previous window.

Things to know:
- **Speed:** finding tabs takes roughly 50–250 ms. The first use in a run also loads UI Automation.
- **No match:** if no tab matches, or the browser isn't running, the cycle is cancelled with `Focus failed: no open tab matches '...' in msedge, chrome, ...`.
- **Dry run:** the tab is looked up and logged as `would select` or `already selected`. Nothing switches.
- **Other browsers:** add their process names to `browsers=`, comma-separated, `.exe` optional.
- **Not covered:** web page content isn't searched, so tab-like widgets inside a page aren't found.
- **Tested so far:** with a standard Windows tab control standing in for a browser (find, select, switch back, no match). **Not yet tested against Edge or Chrome themselves.**

## Positions (X and Y)

`move` and `click` take an X (left to right) and a Y (top to bottom). All positions are on the **primary monitor**, whose top-left pixel is (0, 0). They're real screen pixels, even with Windows display scaling set above 100%.

| Form | Examples | Meaning |
|---|---|---|
| Pixels | `250`, `0`, `-300` | Whole pixels from the top-left corner. Negative values reach monitors to the left of or above the primary one. |
| Percent | `50%`, `12.5%`, `100%` | Of the screen width (X) or height (Y). `0%` is the first pixel, `100%` the last. Up to 100%, not negative. |
| Words for X | `left`, `center`, `right` | First column, middle, last column |
| Words for Y | `top`, `center`, `bottom` | First row, middle, last row |
| Word ± pixels | `right-20`, `top+15`, `center+100` | A word moved by some pixels |

- `middle` works as another name for `center`.
- `left`/`right` only work for X, and `top`/`bottom` only for Y. `click top left` is an error; write `click left top`.
- **Words follow the screen:** `bottom` is the bottom row on any resolution, and so are percentages. Plain pixels don't adapt, so prefer words or percentages if the resolution can change, e.g. with a laptop on and off a dock.
- **The bottom row is the taskbar** with a default Windows layout. `click left bottom` hits the Start button. Use `bottom-60` or so to stay above it.
- **Example on a 1920×1080 screen:** `left`/`top` = 0, `center` = 959 (X) and 539 (Y), `right` = 1919, `bottom` = 1079, `50%` = 960 (X), and `right-20` = 1899.

**Finding a point's pixel position:** paste this into a PowerShell window, point at the spot, and read the numbers. Press Ctrl+C to stop.

```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace W -Name Dpi -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
[W.Dpi]::SetProcessDPIAware() | Out-Null
"Screen: " + [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Size
while ($true) { $p = [System.Windows.Forms.Cursor]::Position; Write-Host -NoNewline "`r$($p.X), $($p.Y)      "; Start-Sleep -Milliseconds 200 }
```

The DPI line makes it report real pixels, the same as the actions file uses, even with display scaling on.

## Keys

Names are case-insensitive. Join several with `+` and no spaces.

| Group | Names |
|---|---|
| Letters | `a` – `z` |
| Digits | `0` – `9` (the row above the letters) |
| Function keys | `f1` – `f24` |
| Modifiers | `shift`, `ctrl`, `alt`, `win` |
| Editing | `enter`, `tab`, `space`, `backspace`, `delete`, `insert`, `esc` |
| Navigation | `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown` |
| Toggles | `capslock`, `numlock`, `scrolllock` |
| Other | `apps` (the context-menu key), `pause`, `printscreen` |
| Media | `volumeup`, `volumedown`, `volumemute`, `playpause` |

Other names for the same keys:

| Alias | Same as |
|---|---|
| `control` | `ctrl` |
| `windows` | `win` |
| `escape` | `esc` |
| `return` | `enter` |
| `del` | `delete` |
| `ins` | `insert` |
| `pgup` / `pgdn` | `pageup` / `pagedown` |
| `caps` | `capslock` |
| `scroll` | `scrolllock` |
| `prtsc` | `printscreen` |
| `menu` | `apps` |
| `mute` | `volumemute` |

**Not available:** punctuation keys (`.`, `,`, `-`, `/`, `;`, brackets and so on), the number pad, left/right versions of modifiers, and media next/previous. For punctuation, `shift` plus a digit gives the symbols above the digits.

## How a cycle runs

1. **When:** only while you're idle for `idle_seconds`, inside an active shift, not on a break, and switched on. Then once every `min_interval_seconds`–`max_interval_seconds`.
2. **Before the first step:** the cursor position, the display layout and the window in front are recorded.
3. **The steps run** from top to bottom.
4. **After the last step:** with `return_after_move=true`, the app pauses 150–500 ms and glides the cursor back to where it was.
5. **Clean-up:** with `restore_focus=true`, the earlier tab and window come back.

### Cancelling

These stop the cycle at once, and the rest of the steps don't run:
- you move the mouse (more than 2 pixels away from where the app put it)
- you turn it off or exit from the tray
- the display changes (resolution, monitors)
- a `focus` step fails
- Windows refuses to move the cursor (an admin window in front; see `-Elevated` in the README)

The next cycle starts again from the first step. **Make a half-finished cycle harmless:** if the steps are `scroll down 5` and then `scroll up 5`, a cancel in between leaves the page scrolled down. Typing on the keyboard does *not* cancel a cycle; only the mouse does.

### Built-in pauses

The app adds these on its own, so steps don't fire unnaturally fast:

| Where | Pause |
|---|---|
| `click X Y`: between arriving and clicking | 80–250 ms |
| each click: button held down | 60–140 ms (double: 40–90 ms, 60–120 ms apart) |
| `key`: between pressing keys / held / between releasing | 20–60 / 50–120 / 10–40 ms |
| `scroll N`: between notches | 40–120 ms |
| after `focus` | 150–400 ms |
| `focus tab`: after the window, after selecting, at the end | 150–400 / 100–250 / 150–400 ms |
| before moving back at the end | 150–500 ms |

### What's logged

Each `click`, `key`, `scroll`, `focus` and `focus tab` writes a line to `logs\cursor-utility.log`, e.g. `Click: left at (0,1079)`, `Key: ctrl+s`, `Scroll: down x3`, `Focus: 'Untitled - Notepad'`. `move` and `wait` don't. So do cancels, with the reason, e.g. `User moved the mouse: expected (959,539), cursor at (1021,610) ...`.

## Testing a macro

1. **Dry run with markers:**

   ```powershell
   .\cursor-utility.ps1 -RunOnce -DryRun -Overlay
   ```

   This runs one cycle right now, ignoring idle time and the schedule. It doesn't move, click, type, scroll or switch anything. Red markers show where each `move` and `click` would land. `focus` and `focus tab` still look the window or tab up, so a wrong name shows up as `Focus failed`.
2. **Read the log:** the last lines of `logs\cursor-utility.log` show each step tagged `[dry-run]`, with the real pixel positions, then `Run once: done`. A mistake in the file shows `Run once: not running, the actions file has an error.` and exits with code 1.
3. **One real run, if you want to see it happen:** `.\cursor-utility.ps1 -RunOnce` runs the steps for real, once. Keep your hands off the mouse until it's done.
4. **Leave it running:** `run.bat`. Or, if it's already running, just save the file.

If scripts are blocked on your PC ("running scripts is disabled"), start these as `powershell -ExecutionPolicy Bypass -File .\cursor-utility.ps1 -RunOnce -DryRun -Overlay`.

## Error messages

Mistakes in the file, shown in the tray and the log as `actions.txt line N: ...`:

| Message | Cause and fix |
|---|---|
| `unknown command 'X' (use move, click, key, scroll, wait, focus)` | A typo in the first word, or a comment that doesn't start with `#` or `;` |
| `move needs X and Y, e.g. 'move center center'` | `move` needs exactly two positions |
| `click takes at most X, Y and a type, ...` | Too many words after `click` |
| `unknown click type 'X' (use left, right, middle or double)` | `click center` or `click 50%`: a single word after `click` must be a type. Give X and Y for a position. |
| `invalid X 'X' (use pixels, a percentage, or a word like left/center/right)` | Not a position, e.g. `1.5`, `abc`, `-10%` (same for Y) |
| `'X' is more than 100%` | A percentage above 100 |
| `'top' can't be used for X` | X and Y swapped, e.g. `click top left`. X comes first. |
| `key needs one key or combo without spaces, ...` | Spaces in the combo (`ctrl + c`), or no key |
| `unknown key 'X'` | A key name not in [Keys](#keys) |
| `scroll needs a direction and an optional count, ...` | No direction, or extra words |
| `unknown scroll direction 'X' (use up, down, left or right)` | A typo in the direction |
| `scroll count must be a number from 1 to 50` | A count of 0, above 50, or not a whole number |
| `wait needs milliseconds, e.g. 'wait 500' or 'wait 700-2200'` | Not a whole number or range, e.g. `wait 1.5`, `wait 1s`, `wait 700 - 2200` |
| `wait range '2000-700' is backwards` | The first number is larger than the second |
| `wait can't be longer than 1 hour (3600000 ms)` | Too long |
| `focus needs a process name or part of a window title, ...` | Nothing after `focus` |
| `focus tab needs part of a tab title, ...` | Nothing after `focus tab` |
| `actions.txt not found` | Wrong `file=` path, or the file was moved |
| `actions.txt has no steps` | The file has only comments and blank lines |

Problems while running, in the log only. These cancel that cycle, and the next one tries again:

| Log line | Meaning |
|---|---|
| `Focus failed: no open window matches 'X'` | No visible window has that process name or title. Check with the `Get-Process` command under [`focus`](#focus-name). |
| `Focus failed: no open tab matches 'X' in msedge, ...` | The browser isn't running, or no tab title contains it |
| `Focus failed: Windows did not bring 'X' to the front` | Windows refused the switch, even after the Alt tap |
| `User moved the mouse: ...` | You moved the mouse; it waits until you're idle again |
| `Windows blocked the cursor: ...` | An admin window is in front; see `-Elevated` in the README |
| `Display changed during the cycle (...)` | The resolution or monitors changed |

## Not supported

- **Typing text:** one key per `key` step only.
- **Punctuation keys and the number pad:** see [Keys](#keys).
- **Holding or dragging:** a button or key can't be held across steps, so there's no drag and drop.
- **Mouse side buttons** (back/forward).
- **Loops, conditions or variables:** the file is a fixed list of steps. To repeat something, write it several times.
- **Choosing a monitor:** positions are on the primary monitor. Reach others with raw pixels, e.g. negative X for one on the left.
- **Comments after a step.**
- **Waiting for something on screen,** e.g. until a window or button appears. Use a generous `wait` instead.

## Examples

**Show activity without clicking anything:**

```
key f15
wait 300-800
move 40% 60%
```

**The built-in corner clicks, written as steps** (what the app does with `file=` empty and `order=bottom_first`):

```
click left bottom
wait 700-2200
click left top
```

**Keep a chat app looking active:**

```
focus teams
wait 500-1200
move center center
scroll down 2
wait 400-900
scroll up 2
```

**Browser tab: scroll WhatsApp Web's chat list and come back:**

```
focus tab whatsapp
wait 400-900
move 250 center
scroll down 5
wait 800-2000
scroll up 5
```

Turn on `restore_focus=true` to get your previous window and tab back after each cycle.

**Save a document now and then:**

```
focus notepad
wait 300-600
key ctrl+s
```

**Open a menu, then close it again:**

```
focus notepad
wait 300-600
click center center right
wait 600-1200
key esc
```
