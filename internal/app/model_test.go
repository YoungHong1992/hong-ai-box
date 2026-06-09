package app

import (
	"strings"
	"testing"

	"github.com/hongge/hongaibox/internal/wizard"
)

func TestAdvancePage_BasicPath(t *testing.T) {
	m := NewAppModel()

	// Welcome → ServiceSelect
	m.advancePage()
	if m.currentPage != pageServiceSelect {
		t.Errorf("after welcome: got page %d, want pageServiceSelect", m.currentPage)
	}

	// ServiceSelect → GlobalConfig (need to init form first)
	m.initServiceSelectForm()
	m.advancePage()
	if m.currentPage != pageGlobalConfig {
		t.Errorf("after serviceSelect: got page %d, want pageGlobalConfig", m.currentPage)
	}

	// GlobalConfig → Review (when no extra config needed → empty queue)
	m.advancePage()
	if m.currentPage != pageReview {
		t.Errorf("after globalConfig (empty queue): got page %d, want pageReview", m.currentPage)
	}

	// Review → Install
	m.advancePage()
	if m.currentPage != pageInstall {
		t.Errorf("after review: got page %d, want pageInstall", m.currentPage)
	}

	// Install → Summary
	m.advancePage()
	if m.currentPage != pageSummary {
		t.Errorf("after install: got page %d, want pageSummary", m.currentPage)
	}
}

func TestAdvancePage_WithServiceConfig(t *testing.T) {
	m := NewAppModel()
	// Enable a service that requires extra config (cliproxyapi)
	m.config.GetOrCreate(wizard.ServiceCliproxyAPI).Enabled = true

	// Walk to GlobalConfig
	m.advancePage() // welcome → serviceSelect
	m.initServiceSelectForm()
	m.advancePage() // serviceSelect → globalConfig
	m.initGlobalConfigForm()

	// GlobalConfig → ServiceConfig (because cliproxyapi is in queue)
	m.advancePage()
	if m.currentPage != pageServiceConfig {
		t.Errorf("after globalConfig (with cliproxyapi): got page %d, want pageServiceConfig", m.currentPage)
	}
	if len(m.configQueue) != 1 {
		t.Errorf("configQueue len = %d, want 1", len(m.configQueue))
	}

	// ServiceConfig → Review (only one service to config)
	m.advancePage()
	if m.currentPage != pageReview {
		t.Errorf("after serviceConfig: got page %d, want pageReview", m.currentPage)
	}
}

func TestGoBack_BasicPath(t *testing.T) {
	m := NewAppModel()

	// Go forward to serviceSelect
	m.advancePage() // welcome → serviceSelect
	m.initServiceSelectForm()

	// Go back to welcome
	m.goBack()
	if m.currentPage != pageWelcome {
		t.Errorf("goBack from serviceSelect: got page %d, want pageWelcome", m.currentPage)
	}

	// Can't go back from welcome — stays
	m.goBack()
	if m.currentPage != pageWelcome {
		t.Errorf("goBack from welcome: should stay, got page %d", m.currentPage)
	}
}

func TestGoBack_FromGlobalConfig(t *testing.T) {
	m := NewAppModel()

	m.advancePage() // welcome → serviceSelect
	m.initServiceSelectForm()
	m.advancePage() // serviceSelect → globalConfig
	m.initGlobalConfigForm()

	// Go back to serviceSelect
	m.goBack()
	if m.currentPage != pageServiceSelect {
		t.Errorf("goBack from globalConfig: got page %d, want pageServiceSelect", m.currentPage)
	}
}

func TestGoBack_FromReview(t *testing.T) {
	m := NewAppModel()

	// Walk to review
	m.advancePage() // welcome → serviceSelect
	m.initServiceSelectForm()
	m.advancePage() // serviceSelect → globalConfig
	m.advancePage() // globalConfig → review (empty queue)

	// Go back from review
	m.goBack()
	if m.currentPage != pageGlobalConfig {
		t.Errorf("goBack from review (empty queue): got page %d, want pageGlobalConfig", m.currentPage)
	}
}

func TestBuildConfigQueue(t *testing.T) {
	m := NewAppModel()

	// No services selected beyond mandatory → empty queue
	queue := m.buildConfigQueue()
	if len(queue) != 0 {
		t.Errorf("empty config: queue len = %d, want 0", len(queue))
	}

	// Enable cliproxyapi, newapi, science
	m.config.GetOrCreate(wizard.ServiceCliproxyAPI).Enabled = true
	m.config.GetOrCreate(wizard.ServiceNewAPI).Enabled = true
	m.config.GetOrCreate(wizard.ServiceScience).Enabled = true

	queue = m.buildConfigQueue()
	if len(queue) != 3 {
		t.Errorf("3 configurable services: queue len = %d, want 3", len(queue))
	}

	// Check that non-configurable services are excluded
	for _, id := range queue {
		switch id {
		case wizard.ServiceNginx, wizard.ServiceDocker, wizard.ServicePi:
			t.Errorf("service %s should not be in config queue", id)
		}
	}
}

func TestStartInstall(t *testing.T) {
	m := NewAppModel()
	m.config.GetOrCreate(wizard.ServiceDocker).Enabled = true
	m.startInstall()

	if !m.installing {
		t.Error("installing should be true after startInstall")
	}
	if m.scriptIdx != 0 {
		t.Errorf("scriptIdx = %d, want 0", m.scriptIdx)
	}
	if len(m.orderedIDs) == 0 {
		t.Error("orderedIDs should not be empty")
	}
	if len(m.results) != 0 {
		t.Errorf("results len = %d, want 0", len(m.results))
	}
	if len(m.logs) < 2 {
		t.Error("logs should be initialized with header lines")
	}
}

func TestReviewConfirmStartsFirstScript(t *testing.T) {
	m := NewAppModel()
	m.currentPage = pageReview

	model, cmd := m.Update(reviewConfirmMsg{})
	if cmd == nil {
		t.Fatal("reviewConfirmMsg should return a command that starts the first script")
	}

	got, ok := model.(AppModel)
	if !ok {
		t.Fatalf("Update returned %T, want AppModel", model)
	}
	if got.currentPage != pageInstall {
		t.Errorf("currentPage = %d, want pageInstall", got.currentPage)
	}
	if !got.installing {
		t.Error("installing should be true after review confirm")
	}
	if got.cancelCtx == nil {
		t.Error("cancelCtx should be set after starting the first script")
	}
	if len(got.logs) < 3 {
		t.Fatalf("logs len = %d, want at least 3", len(got.logs))
	}
	if !strings.Contains(got.logs[len(got.logs)-1], "正在安装") {
		t.Errorf("last log = %q, want installing log", got.logs[len(got.logs)-1])
	}
}
