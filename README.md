# bigpicture.sh

A script for CachyOS (or any Arch-based Linux) running **KDE Plasma on Wayland** with **PipeWire** audio. When you run it, it:

1. Saves your current monitor layout and audio output
2. Disables all monitors except your TV
3. Switches audio output to your TV
4. Launches Steam in Big Picture mode
5. When you exit Big Picture — restores all your monitors exactly as they were and switches audio back

---

## Requirements

| Dependency | Purpose |
|---|---|
| `steam` | Obviously |
| `kscreen-doctor` | Monitor control (included with KDE) |
| `pactl` | Audio switching (included with PipeWire/PulseAudio) |
| `bash` | Running the script |

---

## Installation

```bash
# 1. Move the script somewhere permanent
mv bigpicture.sh ~/bigpicture.sh

# 2. Make it executable
chmod +x ~/bigpicture.sh
```

---

## First-Time Setup

Before running, you need to tell the script which output and audio sink belong to your TV.

**Step 1 — Run the setup helper:**
```bash
~/bigpicture.sh --setup
```

This prints your monitors and audio sinks, for example:
```
── Monitors ──────────────────────────────────
  Output: 1 DP-1 ...
  Output: 2 DP-2 ...
  Output: 5 HDMI-A-1 ...   ← your TV

── Audio Sinks ───────────────────────────────
  947  alsa_output.pci-0000_03_00.1.hdmi-stereo-extra3  ...  ← TV audio
  56   alsa_output.usb-Focusrite_Scarlett_2i2 ...            ← your normal audio
```

**Step 2 — Edit the two config lines at the top of the script:**
```bash
nano ~/bigpicture.sh
```

```bash
TV_OUTPUT="HDMI-A-1"                                        # your TV's output name
TV_SINK="alsa_output.pci-0000_03_00.1.hdmi-stereo-extra3"  # your TV's audio sink
```

Your TV output is typically the HDMI port it's plugged into (`HDMI-A-1`, `HDMI-A-2`, etc).  
Your TV audio sink is typically the HDMI entry in the sinks list.

---

## Usage

```bash
~/bigpicture.sh
```

That's it. The script handles everything automatically:

- If Steam is already open, it shuts it down and relaunches in Big Picture mode
- If Steam is not open, it launches directly into Big Picture mode
- When you exit Big Picture, it detects the exit and restores your setup automatically
- If you Ctrl+C the script at any point, it still restores your monitors and audio

### Optional: Desktop Shortcut

To launch from the KDE app menu or taskbar, create a `.desktop` file:

```bash
cat > ~/.local/share/applications/bigpicture.desktop << 'EOF'
[Desktop Entry]
Name=Big Picture Mode
Comment=Switch to TV and launch Steam Big Picture
Exec=/home/YOUR_USERNAME/bigpicture.sh
Icon=steam
Terminal=true
Type=Application
Categories=Game;
EOF
```

Replace `YOUR_USERNAME` with your actual username. The shortcut will appear in your app launcher and can be pinned to the taskbar.

---

## How It Works

### Monitor Management
The script uses `kscreen-doctor` (KDE's native Wayland display tool) to snapshot your full monitor layout — including positions, resolutions, scales, and rotations — before making any changes. On exit it replays this snapshot to restore everything exactly as it was.

### Audio Management
Uses `pactl` to save your current default audio sink, switch to the TV sink on launch, and restore the original sink on exit.

### Big Picture Detection
Steam writes UI mode transitions to `~/.local/share/Steam/logs/gameprocess_log.txt`:
- `UI mode (4->7)` = Big Picture became active
- `UI mode (7->4)` = Big Picture exited

The script records the log file's byte offset before Steam launches, then polls only newly written lines so it never matches events from previous sessions. It also waits 6 seconds after seeing a `(7->4)` before triggering restore, since Steam briefly flickers through that state during startup.

---

## Troubleshooting

**Monitors don't disable / wrong monitor stays on**  
Run `--setup` and verify `TV_OUTPUT` matches exactly what kscreen-doctor shows for your TV.

**Audio doesn't switch**  
Run `--setup` and verify `TV_SINK` matches exactly the sink name shown for your TV's HDMI audio output.

**Steam doesn't launch in Big Picture**  
Make sure `steam` is in your PATH: `which steam`

**Monitors don't restore after exiting**  
The layout is saved to `$XDG_RUNTIME_DIR/bigpicture_layout` (usually `/run/user/1000/bigpicture_layout`). Check if this file exists and looks correct after running the script.

**Script exits too early / too late when leaving Big Picture**  
The 6-second confirmation window can be adjusted by changing `sleep 6` in the exit detection section of the script. Increase it if it triggers too early; the startup flicker on your system may take longer than average.

---

## Configuration Reference

| Variable | Default | Description |
|---|---|---|
| `TV_OUTPUT` | *(your TV Output)* | kscreen-doctor output name for your TV |
| `TV_SINK` | *(your HDMI sink)* | PipeWire sink name for TV audio |
| `LAYOUT_FILE` | `$XDG_RUNTIME_DIR/bigpicture_layout` | Where monitor layout snapshot is saved |
| `STEAM_LOG` | `~/.local/share/Steam/logs/gameprocess_log.txt` | Steam log file watched for Big Picture state changes |
