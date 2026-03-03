---
name: wda
description: |
  Direct WebDriverAgent (WDA) HTTP API control for iOS devices and simulators.
  Use curl to interact with WDA at localhost:8100 — get DOM/source tree, find elements,
  tap, swipe, type text, take screenshots, manage apps, handle alerts, and more.
  No Appium or Midscene needed — pure HTTP API.

  Triggers: wda, webdriveragent, ios control, ios element, ios dom, ios source tree,
  ios tap, ios swipe, ios type, ios screenshot, ios automation, control iphone,
  get ios page source, find ios element, ios accessibility tree
---

# WDA - WebDriverAgent Direct Control

Control iOS devices/simulators via WDA HTTP API (default `http://localhost:8100`).

## Prerequisites

WDA must be running on the target device. See [references/setup.md](references/setup.md) for installation.

## Quick Reference

All commands use `curl`. Set variables first:

```bash
WDA=http://localhost:8100
H="Content-Type: application/json"
```

### 1. Check Status

```bash
curl $WDA/status
```

### 2. Create Session

```bash
SID=$(curl -s -H "$H" -X POST -d '{"capabilities":{"alwaysMatch":{"bundleId":"com.apple.Preferences"}}}' $WDA/session | python3 -c "import sys,json; print(json.load(sys.stdin)['sessionId'])")
```

Launch any app by changing `bundleId`. Omit it to attach to the current foreground app:

```bash
SID=$(curl -s -H "$H" -X POST -d '{"capabilities":{}}' $WDA/session | python3 -c "import sys,json; print(json.load(sys.stdin)['sessionId'])")
```

### 3. Get Source Tree (DOM)

```bash
# XML format (default)
curl $WDA/session/$SID/source

# JSON format
curl "$WDA/session/$SID/source?format=json"
```

The source tree contains the full accessibility hierarchy: element types, labels, names, values, rects, enabled/visible states.

### 4. Find Elements

Strategies: `class name`, `xpath`, `predicate string`, `class chain`, `link text`, `partial link text`.

```bash
# By class name
curl -s -H "$H" -X POST -d '{"using":"class name","value":"XCUIElementTypeButton"}' $WDA/session/$SID/elements

# By xpath
curl -s -H "$H" -X POST -d '{"using":"xpath","value":"//XCUIElementTypeButton[@name=\"Settings\"]"}' $WDA/session/$SID/elements

# By predicate string (most flexible)
curl -s -H "$H" -X POST -d '{"using":"predicate string","value":"label == \"Settings\" AND visible == true"}' $WDA/session/$SID/elements

# By class chain
curl -s -H "$H" -X POST -d '{"using":"class chain","value":"**/XCUIElementTypeCell[`label CONTAINS \"Wi-Fi\"`]"}' $WDA/session/$SID/elements
```

Response returns element IDs (use as `$EID` below).

### 5. Element Interaction

```bash
# Tap
curl -H "$H" -X POST -d '' $WDA/session/$SID/element/$EID/click

# Type text
curl -H "$H" -X POST -d '{"value":["h","e","l","l","o"]}' $WDA/session/$SID/element/$EID/value

# Clear text
curl -H "$H" -X POST -d '' $WDA/session/$SID/element/$EID/clear

# Get text
curl $WDA/session/$SID/element/$EID/text

# Get attribute
curl $WDA/session/$SID/element/$EID/attribute/label
curl $WDA/session/$SID/element/$EID/attribute/value
curl $WDA/session/$SID/element/$EID/attribute/enabled

# Check displayed
curl $WDA/session/$SID/element/$EID/displayed

# Get element rect (position + size)
curl $WDA/session/$SID/element/$EID/rect
```

### 6. Coordinate Actions

```bash
# Tap at coordinates
curl -H "$H" -X POST -d '{"x":200,"y":400}' $WDA/session/$SID/wda/tap/0

# Double tap at coordinates
curl -H "$H" -X POST -d '{"x":200,"y":400}' $WDA/session/$SID/wda/doubleTap

# Long press
curl -H "$H" -X POST -d '{"x":200,"y":400,"duration":1.5}' $WDA/session/$SID/wda/touchAndHold

# Swipe (from → to)
curl -H "$H" -X POST -d '{"fromX":200,"fromY":500,"toX":200,"toY":200,"duration":0.5}' $WDA/session/$SID/wda/dragfromtoforduration
```

### 7. Screenshot

```bash
# Base64 PNG
curl $WDA/session/$SID/screenshot

# Save to file
curl -s $WDA/session/$SID/screenshot | python3 -c "import sys,json,base64; open('/tmp/screen.png','wb').write(base64.b64decode(json.load(sys.stdin)['value']))"
```

### 8. App Management

```bash
# Go home
curl -H "$H" -X POST -d '' $WDA/wda/homescreen

# Launch app
curl -H "$H" -X POST -d '{"bundleId":"com.apple.mobilesafari"}' $WDA/session/$SID/wda/apps/launch

# Activate app (bring to foreground)
curl -H "$H" -X POST -d '{"bundleId":"com.apple.mobilesafari"}' $WDA/session/$SID/wda/apps/activate

# Terminate app
curl -H "$H" -X POST -d '{"bundleId":"com.apple.mobilesafari"}' $WDA/session/$SID/wda/apps/terminate

# Get app state (1=not running, 2=background, 4=foreground)
curl -H "$H" -X POST -d '{"bundleId":"com.apple.mobilesafari"}' $WDA/session/$SID/wda/apps/state
```

### 9. Alerts

```bash
# Get alert text
curl $WDA/session/$SID/alert/text

# Accept alert
curl -H "$H" -X POST -d '' $WDA/session/$SID/alert/accept

# Dismiss alert
curl -H "$H" -X POST -d '' $WDA/session/$SID/alert/dismiss
```

### 10. Device Control

```bash
# Lock / unlock
curl -H "$H" -X POST -d '' $WDA/session/$SID/wda/lock
curl -H "$H" -X POST -d '' $WDA/session/$SID/wda/unlock

# Get orientation
curl $WDA/session/$SID/orientation

# Set orientation
curl -H "$H" -X POST -d '{"orientation":"LANDSCAPE"}' $WDA/session/$SID/orientation

# Get window size
curl $WDA/session/$SID/window/size

# Device info
curl $WDA/session/$SID/wda/device/info

# Battery info
curl $WDA/session/$SID/wda/batteryInfo

# Touch ID (simulator only, 1=match 0=mismatch)
curl -H "$H" -X POST -d '{"match":1}' $WDA/session/$SID/wda/touch_id

# Clipboard get/set
curl $WDA/session/$SID/wda/clipboard
curl -H "$H" -X POST -d '{"content":"aGVsbG8=","contentType":"plaintext"}' $WDA/session/$SID/wda/clipboard

# Siri
curl -H "$H" -X POST -d '{"text":"What time is it"}' $WDA/session/$SID/wda/siri/activate

# Press hardware keys (home/volumeUp/volumeDown)
curl -H "$H" -X POST -d '{"name":"home"}' $WDA/session/$SID/wda/pressButton
```

### 11. Settings

```bash
# Get settings
curl $WDA/session/$SID/appium/settings

# Optimize for speed
curl -H "$H" -X POST -d '{"settings":{"snapshotMaxDepth":50,"elementResponseAttributes":"type,label,name,value,rect,enabled,visible"}}' $WDA/session/$SID/appium/settings
```

### 12. Delete Session

```bash
curl -X DELETE $WDA/session/$SID
```

## Workflow

1. **Check status** → confirm WDA is running
2. **Create session** → get `$SID`
3. **Get source** → understand current UI
4. **Find elements** → locate targets by predicate/xpath
5. **Interact** → tap, type, swipe
6. **Verify** → get source or screenshot to confirm
7. **Delete session** → cleanup

## Tips

- Parse element IDs from JSON response: `... | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['value'][0]['ELEMENT'])"`
- Predicate string is the fastest search strategy; xpath is the slowest
- Get source tree first to understand the UI hierarchy before finding elements
- Use `snapshotMaxDepth` setting to limit tree depth if source is too slow
- For complete API reference, see [references/api.md](references/api.md)
