#!/data/data/com.termux/files/usr/bin/sh
SESSION="uom"
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x 120 -y 40
tmux rename-window -t "$SESSION:0" "orchestrator"
tmux send-keys -t "$SESSION:0" "cd ~/src/universal-omni-master && sh tools/uom-orch-phone.sh 2>&1 | tee ~/.uom-phone.log" ""
tmux new-window -t "$SESSION" -n "opencode"
tmux send-keys -t "$SESSION:1" "cd ~/src/universal-omni-master" ""
tmux new-window -t "$SESSION" -n "git"
tmux send-keys -t "$SESSION:2" "cd ~/src/universal-omni-master && watch -n 30 'git log --oneline -5; echo; cat .uom-agent/state.json 2>/dev/null'" ""
tmux new-window -t "$SESSION" -n "laptop-ssh"
tmux select-window -t "$SESSION:0"
tmux attach-session -t "$SESSION"
