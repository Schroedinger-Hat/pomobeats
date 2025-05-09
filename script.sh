#!/bin/bash

# Default values (in minutes)
DEFAULT_WORK_DURATION=25
DEFAULT_BREAK_DURATION=5

# Check for required commands
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed. Please install jq to use this script." >&2
    echo "Visit: https://stedolan.github.io/jq/download/" >&2
    exit 1
fi

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

# Set the audio player
MUSIC_PLAYER=$(detect_audio_player)

# Function to play audio with the correct player
play_audio() {
    local audio_file="$1"
    case "$MUSIC_PLAYER" in
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

# Analytics file path
ANALYTICS_FILE="$HOME/.pomobeats_analytics.json"

# Function to initialize analytics file if it doesn't exist
init_analytics() {
    if [ ! -f "$ANALYTICS_FILE" ]; then
        echo '{
            "sessions": [],
            "total_work_time": 0,
            "total_break_time": 0
        }' > "$ANALYTICS_FILE"
    fi
}

# Function to log a completed session
log_session() {
    local session_type=$1
    local duration=$2
    local timestamp=$(date +%s)
    local date=$(date +%Y-%m-%d)
    
    # Create new session JSON
    local new_session="{\"type\":\"$session_type\",\"duration\":$duration,\"timestamp\":$timestamp,\"date\":\"$date\"}"
    
    # Initialize file if it doesn't exist
    if [ ! -f "$ANALYTICS_FILE" ]; then
        echo '{"sessions":[]}' > "$ANALYTICS_FILE"
    fi
    
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

# Function to display analytics
show_analytics() {
    if [ ! -f "$ANALYTICS_FILE" ]; then
        echo "No analytics data available yet."
        return
    fi
    
    local current_date=$(date +%Y-%m-%d)
    local week_ago=$(date -v-7d +%Y-%m-%d)
    
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

# Parse command line arguments
WORK_DURATION=$DEFAULT_WORK_DURATION
BREAK_DURATION=$DEFAULT_BREAK_DURATION
SILENT_MODE=false

if [ "$1" = "analytics" ]; then
    init_analytics
    show_analytics
    exit 0
fi

while getopts "w:b:sh" opt; do
    case $opt in
        w)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: Work duration must be a positive number"
                show_usage
            fi
            WORK_DURATION=$OPTARG
        ;;
        b)
            if ! [[ "$OPTARG" =~ ^[0-9]+$ ]]; then
                echo "Error: Break duration must be a positive number"
                show_usage
            fi
            BREAK_DURATION=$OPTARG
        ;;
        s)
            SILENT_MODE=true
        ;;
        h)
            show_usage
        ;;
        ?)
            echo "Invalid option: -$OPTARG"
            show_usage
        ;;
    esac
done

# Convert minutes to seconds
WORK_DURATION=$((WORK_DURATION * 60))
BREAK_DURATION=$((BREAK_DURATION * 60))

# Directory settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSIC_DIR="$SCRIPT_DIR/music/work"
MUSIC_BREAK_DIR="$SCRIPT_DIR/music/break"
SOUND_DIR="$SCRIPT_DIR/sounds"

# Create a temporary file to store PIDs
PID_FILE="/tmp/pomobeats_$$.pids"
touch "$PID_FILE"

# Function to gracefully kill a process
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

# Clean up any orphaned processes from previous runs
cleanup_orphaned() {
    pgrep -f "afplay.*music/(work|break)" | while read -r pid; do
        graceful_kill "$pid"
    done
}

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

# Cleanup function
cleanup() {
    echo -e "\nStopping music..."
    
    # Read and kill all stored PIDs
    if [ -f "$PID_FILE" ]; then
        while read -r pid; do
            if [ -n "$pid" ]; then
                kill_process_tree "$pid"
            fi
        done < "$PID_FILE"
        rm -f "$PID_FILE"
    fi
    
    # Final sweep for any remaining processes
    cleanup_orphaned
    
    echo "Done."
    exit 0
}

# Set up trap for various signals
trap cleanup SIGINT SIGTERM SIGHUP EXIT

# Function to play music
play_music() {
    local music_dir=$1
    local current_pid_var=$2
    
    # Kill any existing music process
    if [ -n "${!current_pid_var}" ]; then
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
                    echo "$player_pid" >> "$PID_FILE"
                    wait "$player_pid" || exit 0
                fi
            done
        done
    ) &
    
    eval "$current_pid_var=$!"
    echo "$!" >> "$PID_FILE"
}

# Function to verify process termination
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

# Function to stop music
stop_music() {
    local pid=$1
    if [ -n "$pid" ]; then
        # Stop all child processes first
        pkill -P "$pid" 2>/dev/null
        kill "$pid" 2>/dev/null
        
        # Verify the process is stopped
        verify_process_stopped "$pid"
        
        # If process still exists, force kill
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            pkill -9 -P "$pid" 2>/dev/null
        fi
        
        # Clean up any remaining afplay processes
        pgrep -f "afplay.*music/(work|break)" | while read -r orphan_pid; do
            kill -9 "$orphan_pid" 2>/dev/null
        done
    fi
}

# Function to play chime
play_chime() {
    if [ -f "$SOUND_DIR/chime.mp3" ]; then
        play_audio "$SOUND_DIR/chime.mp3"
        sleep 1  # Short pause after chime
    fi
}

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

# Clean up any orphaned processes before starting
cleanup_orphaned

# Initialize analytics
init_analytics

# Main loop
while true; do
    echo "🍅 Work session started! Playing music for $(($WORK_DURATION / 60)) minutes..."
    
    # Start work music
    if [ "$SILENT_MODE" = true ]; then
        echo "Silent mode is enabled. You will only hear the chime."
    else
        play_music "$MUSIC_DIR" "WORK_MUSIC_PID"
    fi
    
    session_start_time=$(date +%s)
    
    # Wait for work duration with countdown
    end_time=$(($(date +%s) + WORK_DURATION))
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
    
    echo "⏸️ Break time! Playing music for $(($BREAK_DURATION / 60)) minutes..."
    
    # Start break music
    if [ "$SILENT_MODE" = true ]; then
        echo "Silent mode is enabled. You will only hear the chime."
    else
        play_music "$MUSIC_BREAK_DIR" "BREAK_MUSIC_PID"
    fi
    
    session_start_time=$(date +%s)
    
    # Wait for break duration with countdown
    end_time=$(($(date +%s) + BREAK_DURATION))
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
