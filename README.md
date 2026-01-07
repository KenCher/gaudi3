🚀 Gaudi3 Diagnostics Wrapper (gaudi3_diag_wrapper.sh)
[
[
[

Overview
gaudi3_diag_wrapper.sh is a production‑ready automation wrapper for executing Gaudi3 Full Diagnostic Tests safely across multiple servers.

It validates required environment variables, manages SSH‑based remote diagnostics, timestamps log output, and automatically archives results while associating each run with a JIRA ticket ID.

🧩 Features
🔒 Strict error handling (set -euo pipefail) for production reliability.

⚙️ Environment validation with helpful usage prompts.

📦 Auto‑archiving of logs as .tgz files for upload to tracking systems.

🖥️ Remote execution helper that combines BMC and OS IPs.

🎨 Color‑coded status UI for better traceability during field runs.

🧹 Exit traps ensuring cleanup and logging on completion or interruption.

📦 Prerequisites
Dependency	Description	Install Command
bash	Bourne Again Shell (v4+)	Usually preinstalled
sshpass	Non‑interactive SSH password login helper	sudo apt install sshpass
g3_full_diagnostics.sh	Core diagnostic runner that this wrapper calls	Must be executable and in the same directory
🌐 Required Environment Variables
Variable	Description	Example
PASSWORD	Root or BMC access password	p@ssword123
REMOTE_HOST	BMC (Baseboard Management Controller) IP	192.168.72.48
SERVER	Hostname or Rack identifier	dal2-qz1-sr3-rk506-s20
JIRA	Related tracking ID	SYS-44278
Optional Variables

Variable	Description	Default
REMOTE_USER	SSH username for OS‑level diagnostics	root
DEBUG	Enable shell debug tracing (true)	unset
⚡ Usage
Quick Start

bash
export PASSWORD=pass REMOTE_HOST=192.168.72.48 \
       SERVER=dal2-qz1-sr3-rk506-s20 JIRA="SYS-44278"
./gaudi3_diag_wrapper.sh
One‑Liner

bash
PASSWORD=pass REMOTE_HOST=192.168.72.48 SERVER=server JIRA=SYS-44278 ./gaudi3_diag_wrapper.sh
🧠 Execution Flow
text
┌────────────────────┐
│ gaudi3_diag_wrapper│
│  (this script)     │
└───────┬────────────┘
        │
        ▼
┌────────────────────┐
│ g3_full_diagnostics│
│   (remote call)    │
└───────┬────────────┘
        │
        ▼
┌──────────────────────────┐
│ Log & Archive Management │
│ ($HOME/gaudi3_diag_logs) │
└──────────────────────────┘
Each run produces a timestamped folder and .tgz archive
for reporting or attachment to the matching JIRA ticket.

📂 Log Output & Archives
Type	Location
Session Logs	$HOME/gaudi3_diag_logs/gaudi3_diag_<timestamp>/wrapper.log
Archive	$HOME/gaudi3_diag_logs/<SERVER>_<timestamp>.tgz
Example entry:

text
[2026-01-07 13:22:54] Starting: SERVER=dal2-qz1-sr3-rk506-s20 JIRA=SYS-44278 OS_IP=192.168.72.49
[2026-01-07 13:23:01] Wrapper cleanup (exit: 0)
🧩 Exit Codes
Code	Meaning
0	All diagnostics completed successfully
1	Missing variable, dependency failure, or diagnostic error
🧰 Troubleshooting
Problem	Cause	Fix
❌ "g3_full_diagnostics.sh missing"	Script not present or not executable	chmod +x g3_full_diagnostics.sh
❌ "sshpass required"	Package not installed	sudo apt install sshpass
🚫 No archive found	Early termination	Check $HOME/gaudi3_diag_logs for timestamped directory
🧾 Example Workflow
bash
# Run diagnostics
./gaudi3_diag_wrapper.sh

# Upload result archive to remote collector
scp ~/gaudi3_diag_logs/dal2-qz1-sr3-rk506-s20_20260107-123411.tgz \
    user@reports-server:/data/gaudi3_archives/
