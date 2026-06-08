package backend

import (
	"bytes"
	"context"
	"os"
	"os/exec"

	tea "github.com/charmbracelet/bubbletea"
)

// RunScript executes a bash script with the given environment variables
// and returns a tea.Cmd. The script runs to completion and its combined
// stdout+stderr is returned inside ScriptDoneMsg.Output.
func RunScript(ctx context.Context, scriptPath string, env []string) tea.Cmd {
	return func() tea.Msg {
		cmd := exec.CommandContext(ctx, "bash", scriptPath)
		cmd.Env = append(os.Environ(), env...)

		var out bytes.Buffer
		cmd.Stdout = &out
		cmd.Stderr = &out

		err := cmd.Run()
		return ScriptDoneMsg{
			Script: scriptPath,
			Output: out.String(),
			Err:    err,
		}
	}
}

// ScriptDoneMsg signals a script finished execution.
type ScriptDoneMsg struct {
	Script string
	Output string
	Err    error
}

// LogMsg carries a single line of output from a script.
type LogMsg struct {
	Line   string
	Source string // "stdout" or "stderr"
}
