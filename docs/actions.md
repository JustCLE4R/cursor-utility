# Actions file

The actions file replaces the built-in corner clicks with your own steps. Turn it on in `config.ini`:

```ini
[actions]
file=actions.txt
restore_focus=true
browsers=msedge, chrome, brave, vivaldi, opera, firefox
```

- The path is relative to the config file's folder. An absolute path works too.
- Leave `file=` empty to use the corner clicks (`[click]` settings).
- The shipped [`actions.txt`](../actions.txt) has the full command reference in its comments, and its default steps do the same as the corner clicks.

## Format

- **Lines:** one step per line, run top to bottom each cycle. Commands and words are case-insensitive.
- **Comments:** lines starting with `#` or `;`. Comments after a step aren't supported.
- **Reloading:** the file is reloaded when its size or time stamp changes, so saving it is enough.
- **Mistakes:** any error pauses cycles. The tray turns red and shows the message, e.g. `actions.txt line 4: unknown command 'clik'`, and the log records it once. Cycles resume when the file is fixed. With `-RunOnce`, an error makes the script exit with code 1.

## Commands

| Command | Example | Effect |
|---|---|---|
| `move X Y` | `move center 40%` | Move along a curved, eased path |
| `click` | `click` | Left click where the cursor is |
| `click TYPE` | `click right` | `left`, `right`, `middle` or `double` where the cursor is |
| `click X Y [TYPE]` | `click right-10 bottom-10 right` | Move there, pause 80–250 ms, click |
| `key COMBO` | `key ctrl+shift+f15` | Press the keys in order, hold 50–120 ms, release in reverse. No spaces in the combo. |
| `scroll DIR [N]` | `scroll down 3` | N wheel notches (1–50, default 1), 40–120 ms apart. `up`, `down`, `left`, `right`. |
| `wait MS` | `wait 500` | Pause |
| `wait MIN-MAX` | `wait 700-2200` | Pause for a random time from a bell curve (max 1 hour) |
| `focus NAME` | `focus teams` | Bring a window to the front (see below) |
| `focus tab NAME` | `focus tab whatsapp` | Select a browser tab and bring its window to the front (see below) |

Watch out: `click left` is a left click where the cursor is, not a click on the left edge. To click on the left edge, give both X and Y, e.g. `click left center`.

### X and Y

All of these are relative to the **primary monitor**, whose top-left pixel is (0, 0).

| Form | Example | Meaning |
|---|---|---|
| Pixels | `250`, `-300` | Absolute. Negative values reach monitors left of or above the primary one. |
| Percent | `50%`, `12.5%` | Of the width (X) or height (Y). `0%` is the first pixel, `100%` the last. |
| Words | `left` `center` `right` (X), `top` `center` `bottom` (Y) | Edges and middle. `middle` is the same as `center`. |
| Word ± pixels | `right-20`, `top+15` | Offset from the word |

Targets outside the desktop are pulled to its edge before moving.

### Keys

`a`–`z`, `0`–`9`, `f1`–`f24`, `shift`, `ctrl`, `alt`, `win`, `apps`, `esc`, `enter`, `tab`, `space`, `backspace`, `insert`, `delete`, `home`, `end`, `pageup`, `pagedown`, `up`, `down`, `left`, `right`, `capslock`, `numlock`, `scrolllock`, `pause`, `printscreen`, `volumeup`, `volumedown`, `volumemute`, `playpause`.

Aliases: `control`, `escape`, `return`, `del`, `ins`, `pgup`, `pgdn`, `scroll`, `caps`, `prtsc`, `menu`, `windows`, `mute`.

`f13`–`f24` are handy because almost no program reacts to them. `scrolllock`, `capslock` and `numlock` toggle a state, so press them twice if you want them back where they were.

### Focus

`focus NAME` looks for a visible window in this order:
1. One whose **process name** is exactly `NAME` (`notepad`, `chrome`, `teams`, `code`).
2. Otherwise, the first whose **title contains** `NAME`, case-insensitive. Spaces are allowed, e.g. `focus Microsoft Teams`.

What happens next:
- **Minimized windows** are restored first.
- **Timing:** after focusing, there's a 150–400 ms pause before the next step.
- **No match:** if no window matches, or Windows refuses to switch, the cycle is cancelled and logged as `Focus failed: ...`.
- **Switching back:** with `restore_focus=true`, the window that was in front before the first `focus` comes back at the end of the cycle, including when the cycle is cancelled.
- **The Alt tap:** Windows only lets the program that sent the latest input switch windows. If the first try fails, the script taps Alt and tries again. In some programs, that tap can briefly underline menu letters.

### Focus tab

Windows only sees a browser window's **active** tab, through the window title. So `focus whatsapp` stops finding WhatsApp Web as soon as you switch that window to another tab. `focus tab NAME` looks at the tabs themselves.

How it works:
1. **Find the tab:** it reads the tab strips of every window belonging to the programs in `browsers=` (default: Edge, Chrome, Brave, Vivaldi, Opera, Firefox), using Windows **UI Automation**. Nothing extra needs installing.
2. **Match:** it picks the tab whose title **contains** `NAME`, case-insensitive, so `whatsapp` matches `(3) WhatsApp`. A matching tab that's already selected wins; otherwise the first match is used.
3. **Bring its window to the front,** as `focus` does.
4. **Select the tab** without any input, if the browser supports that. If it doesn't, or the tab didn't switch, the tab is **clicked** instead: the cursor moves there like any other click, and moving the mouse still cancels the cycle.
5. **Switch back:** with `restore_focus=true`, the tab that was showing before comes back at the end of the cycle (using selection only, never a click), then the previous window.

Things to know:
- **Speed:** finding tabs takes roughly 50–250 ms. The first use in a run also loads UI Automation.
- **No match:** if no tab matches, or the browser isn't running, the cycle is cancelled with `Focus failed: no open tab matches '...' in msedge, chrome, ...`.
- **Dry run:** the tab is looked up and logged as `would select` or `already selected`. Nothing switches.
- **Other browsers:** add their process names to `browsers=` (comma-separated, `.exe` optional).
- **Not covered:** web page content isn't searched, so tab-like widgets inside a page aren't found.
- **Tested so far:** with a standard Windows tab control standing in for a browser (find, select, switch back, no match). **Not yet tested against Edge or Chrome themselves.**

## How a cycle runs

- **Before the first step:** the cursor position, the display layout and the foreground window are recorded.
- **Cancelling:** moving the mouse, turning the utility off or changing the display cancels the cycle, as with the corner clicks.
- **After the last step:** if `return_after_move=true`, the cursor goes back to where it was.
- **Logging:** each click, key, scroll and focus is logged. Waits and moves aren't.
- **Dry run:** nothing moves, clicks, types, scrolls or switches windows or tabs. `focus` and `focus tab` still look the window or tab up, so a wrong name shows up as `Focus failed`. Click positions are logged as if the cursor had moved.
- **Overlay:** `-Overlay` marks every `move` and `click` point for the whole cycle.

## Examples

```
# Nudge something harmless, then the corners
key f15
wait 300-800
click left top
wait 700-2200
click left bottom
```

```
# Keep a chat app looking active
focus teams
wait 500-1200
scroll down 2
wait 400-900
scroll up 2
```
