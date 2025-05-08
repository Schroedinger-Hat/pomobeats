# PomōBeats 🍅

A simple Pomodoro timer with music playback for your work and break sessions. Keep your focus with customized work music and relax during breaks with soothing tunes.

## Features

- Customizable work and break durations
- Different music for work and break sessions
- Chime sound notifications between sessions
- Silent mode option (only chimes, no music)
- Graceful process handling and cleanup

## Prerequisites

- macOS (uses `afplay` for audio playback)
- Bash shell
- MP3 audio files for music (not included)

## Installation

### Quick Start (Local Usage)

1. Clone this repository:

```bash
git clone https://github.com/yourusername/pomobeats.git
cd pomobeats
```

2. Make the script executable:

```bash
chmod +x script.sh
```

### System-wide Installation

To use `pomobeats` from anywhere in your system:

1. Create a bin directory in your home folder if it doesn't exist:

```bash
mkdir -p ~/bin
```

2. Copy the script to your bin directory:

```bash
cp script.sh ~/bin/pomobeats
```

3. Make it executable:

```bash
chmod +x ~/bin/pomobeats
```

4. Add the following line to your `~/.zshrc` or `~/.bash_profile`:

```bash
export PATH="$HOME/bin:$PATH"
```

5. Reload your shell configuration:

```bash
source ~/.zshrc  # or source ~/.bash_profile
```

## Music Setup

1. Create your music directories:

```bash
mkdir -p music/work music/break
```

2. Add your MP3 files:
   - Work music goes in `music/work/`
   - Break music goes in `music/break/`
   - Check the placeholder.md files in each directory for music recommendations

## Usage

### Basic Usage

```bash
pomobeats
```

This will start the timer with default durations (25min work, 5min break)

### Custom Durations

```bash
pomobeats -w 45 -b 15
```

This starts a 45-minute work session followed by a 15-minute break

### Silent Mode

```bash
pomobeats -s
```

Runs the timer with only chime sounds (no music)

### Options

- `-w <minutes>`: Set work duration (default: 25)
- `-b <minutes>`: Set break duration (default: 5)
- `-s`: Silent mode (no music, only chimes)
- `-h`: Show help message

## Controls

- `Ctrl+C`: Gracefully stop the timer and cleanup
- The timer will automatically transition between work and break sessions

## Directory Structure

```
pomobeats/
├── music/
│   ├── work/     # Put your work music here
│   └── break/    # Put your break music here
├── sounds/
│   └── chime.mp3 # Session transition sound
└── script.sh     # Main script
```

## Troubleshooting

If music continues playing after stopping the script:

```bash
pkill afplay
```

## License

This project is licensed under the AGPL License - see the LICENSE file for details.
