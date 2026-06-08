package app

import (
	"context"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/hongge/hongaibox/internal/wizard"
)

// page identifies the current UI page.
type page int

const (
	pageWelcome page = iota
	pageServiceSelect
	pageGlobalConfig
	pageServiceConfig
	pageReview
	pageInstall
	pageSummary
)

// nextPageMsg signals the app to advance to the next page.
type nextPageMsg struct{}

// prevPageMsg signals the app to go back.
type prevPageMsg struct{}

// serviceSelectDoneMsg carries the chosen service IDs.
type serviceSelectDoneMsg struct {
	IDs []wizard.ServiceID
}

// globalConfigDoneMsg carries the access mode and domain.
type globalConfigDoneMsg struct {
	Mode   wizard.AccessMode
	Domain string
}

// serviceConfigDoneMsg signals a per-service config form finished.
type serviceConfigDoneMsg struct{}

// reviewConfirmMsg signals the user confirmed on the review page.
type reviewConfirmMsg struct{}

// installStartMsg begins installation.
type installStartMsg struct {
	Ordered []wizard.ServiceID
}

// logMsg carries a single line of output from a script.
type logMsg struct {
	Line   string
	Source string // "stdout" or "stderr"
}

// scriptDoneMsg signals a script finished execution.
type scriptDoneMsg struct {
	Script string
	Output string
	Err    error
}

// allDoneMsg signals every script completed.
type allDoneMsg struct {
	Results map[string]error
}

// progressMsg updates install progress.
type progressMsg struct {
	Current int
	Total   int
	Label   string
}

// ctxKey is used to store the tea.Program in context for backend runner.
type ctxKey string

const programCtxKey ctxKey = "bubbletea-program"

// ContextWithProgram injects the tea program into a context.
func ContextWithProgram(ctx context.Context, p interface{ Send(tea.Msg) }) context.Context {
	return context.WithValue(ctx, programCtxKey, p)
}
