package app

import "github.com/hongge/hongaibox/internal/wizard"

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

// globalConfigDoneMsg carries the access mode and domain.
type globalConfigDoneMsg struct {
	Mode   wizard.AccessMode
	Domain string
}

// serviceConfigDoneMsg signals a per-service config form finished.
type serviceConfigDoneMsg struct{}

// reviewConfirmMsg signals the user confirmed on the review page.
type reviewConfirmMsg struct{}
