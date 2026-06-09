package backend

import (
	"bufio"
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sync"

	tea "github.com/charmbracelet/bubbletea"
)

// Program is set by main.go before the TUI starts.
// It is used by RunScript to stream real-time output.
var Program *tea.Program

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

// RunScript executes a bash script with the given environment variables
// and returns a tea.Cmd. Stdout and stderr are streamed line-by-line
// as LogMsg via Program.Send. When the script exits, ScriptDoneMsg is
// returned.
//
// The scriptPath is resolved relative to the directory of the running
// binary at execution time.
func RunScript(ctx context.Context, scriptPath string, env []string) tea.Cmd {
	return func() tea.Msg {
		cmd := exec.CommandContext(ctx, "bash", resolvePath(scriptPath))
		cmd.Env = append(os.Environ(), env...)

		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return ScriptDoneMsg{Script: scriptPath, Err: err}
		}
		stderr, err := cmd.StderrPipe()
		if err != nil {
			return ScriptDoneMsg{Script: scriptPath, Err: err}
		}

		if err := cmd.Start(); err != nil {
			return ScriptDoneMsg{Script: scriptPath, Err: err}
		}

		var wg sync.WaitGroup
		wg.Add(2)

		go func() {
			defer wg.Done()
			scanLines(stdout, "stdout")
		}()
		go func() {
			defer wg.Done()
			scanLines(stderr, "stderr")
		}()

		wg.Wait()
		err = cmd.Wait()

		return ScriptDoneMsg{Script: scriptPath, Err: err}
	}
}

// scanLines reads lines from r and sends each as a LogMsg.
func scanLines(r io.Reader, source string) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		if Program != nil {
			Program.Send(LogMsg{Line: scanner.Text(), Source: source})
		}
	}
	if err := scanner.Err(); err != nil && Program != nil {
		Program.Send(LogMsg{Line: err.Error(), Source: "stderr"})
	}
}

// resolvePath resolves a relative scriptPath using several deployment layouts:
//  1. relative to the running executable directory (source build layout)
//  2. relative to the current working directory (go run / project-root usage)
//  3. relative to /usr/local/share/hongaibox (system install layout)
//
// If no candidate exists, the first candidate is returned to preserve a useful
// error path in the eventual exec failure.
func resolvePath(scriptPath string) string {
	if filepath.IsAbs(scriptPath) {
		return scriptPath
	}

	candidates := make([]string, 0, 3)
	if exe, err := os.Executable(); err == nil {
		candidates = append(candidates, filepath.Join(filepath.Dir(exe), scriptPath))
	}
	if wd, err := os.Getwd(); err == nil {
		candidates = append(candidates, filepath.Join(wd, scriptPath))
	}
	candidates = append(candidates, filepath.Join("/usr/local/share/hongaibox", scriptPath))

	for _, candidate := range candidates {
		if _, err := os.Stat(candidate); err == nil {
			return candidate
		}
	}
	if len(candidates) > 0 {
		return candidates[0]
	}
	return scriptPath
}
