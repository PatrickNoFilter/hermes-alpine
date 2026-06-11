# Terminal UI Patterns (no AndroidX)

## Copy Output to Clipboard

Add a copy button to the terminal output area. Uses stock `android.content.ClipboardManager` — no AndroidX needed.

### Layout (add ImageButton in input bar)

```xml
<ImageButton
    android:id="@+id/btnCopy"
    android:layout_width="40dp"
    android:layout_height="40dp"
    android:src="@android:drawable/ic_menu_set_as"
    android:background="@null"
    android:tint="#FF8B949E"
    android:contentDescription="Copy output" />
```

### Java Implementation

```java
import android.content.ClipData;
import android.content.ClipboardManager;

// In onCreate:
btnCopy = findViewById(R.id.btnCopy);
btnCopy.setOnClickListener(v -> copyOutput());

private void copyOutput() {
    String text = tvOutput.getText().toString();
    if (text.isEmpty()) return;
    ClipboardManager clip = (ClipboardManager) getSystemService(CLIPBOARD_SERVICE);
    clip.setPrimaryClip(ClipData.newPlainText("Terminal Output", text));
    appendOutput("[Copied " + text.length() + " chars to clipboard]");
}
```

### Make Output Selectable (long-press copy)

Add to the output `TextView` in XML:
```xml
android:textIsSelectable="true"
```

And programmatically:
```java
tvOutput.setMovementMethod(new ScrollingMovementMethod());
```

Note: `textIsSelectable="true"` in a ScrollView can sometimes interfere with scrolling. The `ScrollingMovementMethod` helps. If selecting text feels finicky, the dedicated copy button is more reliable.

## Command History (Up/Down arrows)

```java
private final List<String> commandHistory = new ArrayList<>();
private int historyIndex = -1;

// In onCreate:
etInput.setOnKeyListener((v, keyCode, event) -> {
    if (event.getAction() == KeyEvent.ACTION_DOWN) {
        if (keyCode == KeyEvent.KEYCODE_DPAD_UP) {
            navigateHistory(-1);
            return true;
        } else if (keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            navigateHistory(1);
            return true;
        }
    }
    return false;
});

private void navigateHistory(int direction) {
    if (commandHistory.isEmpty()) return;
    historyIndex += direction;
    if (historyIndex < 0) historyIndex = 0;
    if (historyIndex >= commandHistory.size()) {
        historyIndex = commandHistory.size();
        etInput.setText("");
        return;
    }
    etInput.setText(commandHistory.get(historyIndex));
    etInput.setSelection(etInput.getText().length());
}
```

## UI: Android-only Constraints

- **No bash**: Android devices don't ship with bash. Use `sh` or `/system/bin/sh` for all shell commands.
- **Run `which` before install**: Check if a binary exists before attempting install, to give clear feedback.
- **Foreground service**: Must use `startForegroundService()` (API 26+) with a notification channel. For API 24-25, the `Notification.Builder(this, CHANNEL_ID)` constructor doesn't exist — fall back to the deprecated single-arg constructor.
- **Boot receiver**: Register `android.permission.RECEIVE_BOOT_COMPLETED` and use `<action android:name="android.intent.action.BOOT_COMPLETED"/>` in the manifest.
