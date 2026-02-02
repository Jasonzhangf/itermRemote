# Memory Monitoring

This repo includes a system service (launchd) to continuously monitor memory usage of host processes.

## Quick Start

### Using the system service (recommended)

The memory monitor is installed as a user launchd agent and runs automatically when you log in.

```bash
# Install/update the service
cp scripts/itermremote.memory-monitor.plist ~/Library/LaunchAgents/com.itermremote.memory-monitor.plist
launchctl unload -w ~/Library/LaunchAgents/com.itermremote.memory-monitor.plist 2>/dev/null || true
launchctl load -w ~/Library/LaunchAgents/com.itermremote.memory-monitor.plist

# Check service status
launchctl list | grep itermremote

# View logs
tail -f /tmp/itermremote-memory-monitor/memory_monitor.log
```

### Manual daemon control

```bash
# Start daemon with custom state directory
python3 scripts/monitor_memory.py --state-dir /tmp/itermremote-memory-monitor start

# Stop daemon
python3 scripts/monitor_memory.py --state-dir /tmp/itermremote-memory-monitor stop

# Check status and recent logs
python3 scripts/monitor_memory.py --state-dir /tmp/itermremote-memory-monitor status
```

## Log Location

Logs are written to:
- System service: `/tmp/itermremote-memory-monitor/memory_monitor.log`
- Manual daemon: `build/memory_monitor.log` (or custom via `--state-dir`)

Example log output:

```
[2026-02-01 18:50:25] Started monitoring: target=host_test_app interval=5s threshold=2048MB
[2026-02-01 18:50:25] host_test_app RSS=10.7MB (delta=+0.0MB)
[2026-02-01 18:50:30] host_test_app RSS=10.7MB (delta=+0.0MB)
[2026-02-01 18:50:35] host_test_app RSS=12.1MB (delta=+1.4MB)
```

## Alerting

When RSS exceeds the threshold, alerts are logged with `[ALERT: HIGH MEMORY]` tag. Alerts are throttled to avoid spam (every 3rd sample).

## Parameters

- `--target`: Process name to monitor (default: `host_test_app`)
- `--interval`: Sampling interval in seconds (default: 5)
- `--threshold`: Alert threshold in MB (default: 2048)
- `--state-dir`: Directory for pid/log files (default: env `ITERMREMOTE_MONITOR_STATE_DIR` or `./build`)

## Troubleshooting

### Daemon not responding

```bash
# Check if daemon is running
python3 scripts/monitor_memory.py --state-dir /tmp/itermremote-memory-monitor status

# Force stop if needed
rm -f /tmp/itermremote-memory-monitor/.memory_monitor.pid
```

### Process not found

The daemon will log `host_test_app not found, waiting...` until the target process starts. Make sure the Flutter app is running.

## Requirements

- Python 3.8+
- `psutil` package (install with `pip3 install psutil`)
