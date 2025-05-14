#!/usr/bin/env bash
# Pomodoro Timer with Music and Analytics
# This script implements a Pomodoro timer that plays music during work and break sessions, logs session data, and provides analytics.
# It is designed to be run in a terminal and can be customized with different work and break durations.
# It also includes error handling, signal trapping, and process management to ensure smooth operation.

# --- Header: setters ---
set -o errexit # Exit immediately if a command exits with a non-zero status
set -o nounset # Treat unset variables as an error
set -o pipefail # Prevent errors in a pipeline from being masked
if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace # Print each command before executing it
fi

# --- Header: Global Variables ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Directory of the script

# --- Header: Environment variables ---
MUSIC_DIR="${MUSIC_DIR:-$HOME/pomobeats/music/work}"
MUSIC_BREAK_DIR="${MUSIC_BREAK_DIR:-$HOME/pomobeats/music/break}"
SOUND_DIR="${SOUND_DIR:-$SCRIPT_DIR/sounds}"
DEFAULT_WORK_DURATION="${DEFAULT_WORK_DURATION:-"25m"}" # Default work duration in minutes
DEFAULT_BREAK_DURATION="${DEFAULT_BREAK_DURATION:-"5m"}" # Default break duration in minutes
ANALYTICS_FILE="${ANALYTICS_FILE:-$HOME/.cache/pomobeats/analytics.json}" # File to store analytics data
SILENT_MODE="${SILENT_MODE:-false}" # Flag for silent mode (no music)

# --- Header: internal variable ---
pid_file="/tmp/pomobeats_$$.pids" # Temporary file to store PIDs

# --- Helpers: Convert to second ---
convert_to_seconds() {
  local time_str="$1"
  local total_seconds=0

  # Check for hours, minutes, and seconds
  if [[ "$time_str" =~ ([0-9]+)h ]]; then
    total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 3600))
  fi
  if [[ "$time_str" =~ ([0-9]+)m ]]; then
    total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 60))
  fi
  if [[ "$time_str" =~ ([0-9]+)s ]]; then
    total_seconds=$((total_seconds + ${BASH_REMATCH[1]}))
  fi

  echo $total_seconds
}

# --- Helpers: Detect Audio Player ---
# Detect OS and set appropriate audio player
detect_audio_player() {
  if [[ "$OSTYPE" == "darwin"* ]]; then # macOS
    if command -v afplay >/dev/null 2>&1; then
      echo "afplay"
      return
    fi
  else # Linux or other Unix-like OS
    if command -v ffplay >/dev/null 2>&1; then
      echo "ffplay"
      return
    fi
    if command -v mpg123 >/dev/null 2>&1; then
      echo "mpg123"
      return
    fi
    if command -v play >/dev/null 2>&1; then
      echo "play"
      return
    fi
  fi

  echo "No suitable audio player found. Please install mpg123 or sox." >&2
  exit 1
}

# --- Helpers: Audio Playback ---
# Function to play audio using the detected player
play_audio() {
  local audio_file="$1"
  local music_player=$(detect_audio_player)
  case "$music_player" in
    "afplay")
      afplay "$audio_file" 2>/dev/null
      ;;
    "ffplay")
      ffplay -v 0 -nodisp -autoexit "$audio_file" 2>/dev/null
      ;;
    "mpg123")
      mpg123 -q "$audio_file" 2>/dev/null
      ;;
    "play")
      play -q "$audio_file" 2>/dev/null
      ;;
  esac
}

# --- Helpers: Init Analytics ---
# Function to initialize analytics file if it doesn't exist
init_analytics() {
  # Create the directory if it doesn't exist
  mkdir -p "$(dirname "$ANALYTICS_FILE")"
  if [ ! -f "$ANALYTICS_FILE" ]; then
    echo '{
    "sessions": [],
    "total_work_time": 0,
    "total_break_time": 0
  }' > "$ANALYTICS_FILE"
  fi
}

# --- Helpers: Analytics Logging ---
# Function to log a completed session
log_session() {
  local session_type=$1
  local duration=$2
  local timestamp=$(date +%s)
  local date=$(date +%Y-%m-%d)

  # Create new session JSON
  local new_session="{\"type\":\"$session_type\",\"duration\":$duration,\"timestamp\":$timestamp,\"date\":\"$date\"}"

  # Create a temporary file
  local temp_file=$(mktemp)

  # Read current content and add new session
  if [ -f "$ANALYTICS_FILE" ]; then
    # Insert the new session at the beginning of the sessions array
    jq --arg session "$new_session" '.sessions = [($session | fromjson)] + .sessions' "$ANALYTICS_FILE" > "$temp_file"

    if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
      mv "$temp_file" "$ANALYTICS_FILE"
    else
      echo "Error: Failed to update analytics file" >&2
      rm -f "$temp_file"
      return 1
    fi
  fi
}

# --- Helpers: Analytics Display ---
# Function to display analytics
show_analytics() {
  if [ ! -f "$ANALYTICS_FILE" ]; then
    echo "No analytics data available yet."
    return
  fi

  local current_date=$(date +%Y-%m-%d)
  local week_ago
  if date -v -1d +%Y-%m-%d >/dev/null 2>&1; then
    week_ago="$(date -v-7d +%Y-%m-%d)"  # BSD/macOS
  else
    week_ago="$(date --date="7 days ago" +%Y-%m-%d)"  # GNU/Linux
  fi

  # Use jq to calculate statistics with a simpler query structure
  local stats=$(jq -r --arg today "$current_date" --arg week_ago "$week_ago" '
  reduce .sessions[] as $session (
  {total_work: 0, total_break: 0, today_work: 0, today_break: 0, week_work: 0, week_break: 0};
  if $session.type == "work" then
  .total_work += $session.duration |
  if $session.date == $today then .today_work += $session.duration else . end |
  if $session.date >= $week_ago then .week_work += $session.duration else . end
  else
  .total_break += $session.duration |
  if $session.date == $today then .today_break += $session.duration else . end |
  if $session.date >= $week_ago then .week_break += $session.duration else . end
  end
  ) | 
  "Total Work Time: \(.total_work / 3600 | floor)h \(.total_work % 3600 / 60 | floor)m\n" +
  "Total Break Time: \(.total_break / 3600 | floor)h \(.total_break % 3600 / 60 | floor)m\n" +
  "Today Work Time: \(.today_work / 3600 | floor)h \(.today_work % 3600 / 60 | floor)m\n" +
  "Today Break Time: \(.today_break / 3600 | floor)h \(.today_break % 3600 / 60 | floor)m\n" +
  "This Week Work Time: \(.week_work / 3600 | floor)h \(.week_work % 3600 / 60 | floor)m\n" +
  "This Week Break Time: \(.week_break / 3600 | floor)h \(.week_break % 3600 / 60 | floor)m"
  ' "$ANALYTICS_FILE")

  echo "📊 Pomodoro Analytics"
  echo "===================="
  echo "$stats"
}

# --- Helpers: Help message ---
# Function to display usage
show_usage() {
  echo "Usage: $0 [-w work_duration] [-b break_duration] [-s] [-h] [analytics]"
  echo "Options:"
  echo "  -w    Work duration in minutes (default: $DEFAULT_WORK_DURATION)"
  echo "  -b    Break duration in minutes (default: $DEFAULT_BREAK_DURATION)"
  echo "  -s    Silent mode (no music)"
  echo "  -h    Show this help message"
  echo "Commands:"
  echo "  analytics    Show pomodoro session statistics"
  exit 1
}

# --- Helpers: Graceful Kill ---
graceful_kill() {
  local pid=$1
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null
    # Give it a chance to terminate gracefully
    for i in {1..5}; do
      if ! kill -0 "$pid" 2>/dev/null; then
        return
      fi
      sleep 0.1
    done
    # If still running, force kill
    kill -9 "$pid" 2>/dev/null
  fi
}

# --- Helpers: Cleanup Orphaned Processes ---
# Clean up any orphaned processes from previous runs
cleanup_orphaned() {
  local orphan_pids=$(pgrep -f "afplay.*music/(work|break)" || true)

  if [ -n "$orphan_pids" ]; then
    echo "Cleaning up orphaned processes..."
    echo "$orphan_pids" | while read -r pid; do
    if [ -n "$pid" ]; then
      graceful_kill "$pid" &
    fi
  done
  wait # wait for all background kills
  fi
}

# --- Helpers: Kill Process Tree ---
# Function to kill processes and their children
kill_process_tree() {
  local pid=$1
  if [ -n "$pid" ]; then
    # Kill children first
    ps -o pid --no-headers --ppid "$pid" 2>/dev/null | while read -r child_pid; do
    kill_process_tree "$child_pid"
  done
  graceful_kill "$pid"
  fi
}

# --- Helpers: Cleanup ---
# Cleanup function
cleanup() {
  echo -e "\nStopping music..."

  # Read and kill all stored PIDs
  if [ -f "$pid_file" ]; then
    while read -r pid; do
      if [ -n "$pid" ]; then
        kill_process_tree "$pid"
      fi
    done < "$pid_file"
    rm -f "$pid_file"
  fi

  # Final sweep for any remaining processes
  cleanup_orphaned

  echo "Done."
  exit 0
}

# --- Helpers: Music Playback ---
# Function to play music
play_music() {
  local music_dir=${1:-}
  local current_pid_var="${2:-}"

  # Kill any existing music process
  if [ -n "${!current_pid_var:-}" ]; then
    kill_process_tree "${!current_pid_var}"
  fi

  # Start new music process
  (
  exec 2>/dev/null  # Redirect stderr for this subshell
  while true; do
    for song in "$music_dir"/*.mp3; do
      if [ -f "$song" ]; then
        play_audio "$song" &
        local player_pid=$!
        echo "$player_pid" >> "$pid_file"
        wait "$player_pid" || exit 0
      fi
    done
  done
  ) &

  eval "$current_pid_var=$!"
  echo "$!" >> "$pid_file"
}

# --- Helpers: Verify Process Termination ---
verify_process_stopped() {
  local pid=$1
  local max_attempts=10
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.2
    attempt=$((attempt + 1))
  done
  return 1
}

# --- Helpers: Stop Music ---
# Function to stop music
stop_music() {
  local pid=$1
  if [ -n "$pid" ]; then
    # Stop all child processes first
    pkill -P "$pid" 2>/dev/null || true
    kill "$pid" 2>/dev/null

        # Verify the process is stopped
        verify_process_stopped "$pid"

        # If process still exists, force kill
        if kill -0 "$pid" 2>/dev/null; then
          kill -9 "$pid" 2>/dev/null
          pkill -9 -P "$pid" 2>/dev/null
        fi

        local orphan_pids=$(pgrep -f "afplay.*music/(work|break)" 2>/dev/null || true)
        if [ -n "$orphan_pids" ]; then
          echo "$orphan_pids" | while read -r orphan_pid; do
          [ -n "$orphan_pid" ] && kill -9 "$orphan_pid" 2>/dev/null || true
        done
        fi
  fi
}

# --- Helpers: Play Chime ---
# Function to play chime
play_chime() {
  if [ -f "$SOUND_DIR/chime.mp3" ]; then
    play_audio "$SOUND_DIR/chime.mp3"
    sleep 1  # Short pause after chime
  fi
}

# --- Helpers: Display Countdown ---
# Function to display remaining time
display_countdown() {
  local end_time=$1
  local session_type=$2

  while [ $(date +%s) -lt $end_time ]; do
    local current_time=$(date +%s)
    local remaining_seconds=$(( end_time - current_time ))
    local minutes=$(( remaining_seconds / 60 ))
    local seconds=$(( remaining_seconds % 60 ))

    # Use carriage return to update the same line
    printf "\r%s remaining: %02d:%02d" "$session_type" $minutes $seconds
    sleep 1
  done
  echo "" # New line after countdown finishes
}

# --- Main: help ---
if [[ "${1-}" =~ ^-*h(elp)?$ ]]; then
  show_usage
  exit 0
fi

# --- Main: checks ---
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is not installed. Please install jq to use this script." >&2
  echo "Visit: https://stedolan.github.io/jq/download/" >&2
  exit 1
fi

# --- Main: main ---
main() {
  touch "$pid_file"

  if [ "${1:-}" = "analytics" ]; then
    init_analytics
    show_analytics
    exit 0
  fi

  # Clean up any orphaned processes before starting
  cleanup_orphaned

  # Initialize analytics
  init_analytics

  # Set up trap for various signals
  trap cleanup SIGINT SIGTERM SIGHUP EXIT
  while getopts "w:b:sh" opt; do
    case $opt in
      w)
        # manage h = hours m = minutes s = seconds
        if [[ "$OPTARG" =~ ^[0-9]+[hms]$ ]]; then
          work_duration=$(convert_to_seconds "$OPTARG")
        else
          echo "Error: Work duration must be a positive number or in the format [0-9]+[hms]"
          show_usage
        fi
        ;;
      b)
        if [[ "$OPTARG" =~ ^[0-9]+[hms]$ ]]; then
          break_duration=$(convert_to_seconds "$OPTARG")
        else
          echo "Error: Break duration must be a positive number or in the format [0-9]+[hms]"
          show_usage
        fi
        ;;
      s)
        SILENT_MODE=true
        ;;
      ?)
        echo "Invalid option: -$OPTARG"
        show_usage
        ;;
    esac
  done

  # if work_duration or break_duration is not set, use default values
  if [ -z "${work_duration:-}" ]; then
    work_duration=$(convert_to_seconds "$DEFAULT_WORK_DURATION")
  fi
  if [ -z "${break_duration:-}" ]; then
    break_duration=$(convert_to_seconds "$DEFAULT_BREAK_DURATION")
  fi

  while true; do
    echo "🍅 Work session started! Playing music for $(($work_duration / 60)) minutes..."

    # Start work music
    if [ "$SILENT_MODE" = true ]; then
      echo "Silent mode is enabled. You will only hear the chime."
    else
      play_music "$MUSIC_DIR" "WORK_MUSIC_PID"
    fi

    session_start_time=$(date +%s)

    # Wait for work duration with countdown
    end_time=$(($(date +%s) + work_duration))
    display_countdown $end_time "Work"

    # Log work session
    actual_duration=$(($(date +%s) - session_start_time))
    log_session "work" $actual_duration

    echo "Work session complete. Stopping work music..."

    if [ "$SILENT_MODE" = false ]; then
      stop_music "$WORK_MUSIC_PID"
      WORK_MUSIC_PID=""  # Clear the PID
    fi

    play_chime

    echo "⏸️ Break time! Playing music for $(($break_duration / 60)) minutes..."

    # Start break music
    if [ "$SILENT_MODE" = true ]; then
      echo "Silent mode is enabled. You will only hear the chime."
    else
      play_music "$MUSIC_BREAK_DIR" "BREAK_MUSIC_PID"
    fi

    session_start_time=$(date +%s)

    # Wait for break duration with countdown
    end_time=$(($(date +%s) + break_duration))
    display_countdown $end_time "Break"

    # Log break session
    actual_duration=$(($(date +%s) - session_start_time))
    log_session "break" $actual_duration

    echo "Break complete. Stopping break music..."
    if [ "$SILENT_MODE" = false ]; then
      stop_music "$BREAK_MUSIC_PID"
      BREAK_MUSIC_PID=""  # Clear the PID
    fi

    play_chime
  done
}

main "$@"
