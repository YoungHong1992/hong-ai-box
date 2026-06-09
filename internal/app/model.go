package app

import (
	"context"
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"

	"github.com/hongge/hongaibox/internal/backend"
	"github.com/hongge/hongaibox/internal/version"
	"github.com/hongge/hongaibox/internal/wizard"
)

// AppModel is the top-level Bubble Tea model for hongaibox.
type AppModel struct {
	width, height int
	currentPage   page
	config        *wizard.Config

	// Huh forms (one active at a time)
	serviceSelectForm *huh.Form
	globalConfigForm  *huh.Form
	serviceConfigForm *huh.Form

	// Per-page state
	configQueue []wizard.ServiceID
	configIdx   int

	// Install page state
	logs       []string
	vp         viewport.Model
	sp         spinner.Model
	orderedIDs []wizard.ServiceID
	scriptIdx  int
	results    map[string]error
	installing bool
	cancelCtx  context.CancelFunc

	quitting bool
}

// NewAppModel creates the initial model.
func NewAppModel() AppModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(Primary)
	return AppModel{
		config: wizard.NewConfig(),
		sp:     s,
	}
}

// Init implements tea.Model.
func (m AppModel) Init() tea.Cmd {
	return m.sp.Tick
}

// Update implements tea.Model.
func (m AppModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Global key handling
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.vp.Width = msg.Width - 6
		m.vp.Height = msg.Height - 14
		if m.serviceSelectForm != nil {
			m.serviceSelectForm.WithWidth(msg.Width - 4).WithHeight(msg.Height - 4)
		}
		if m.globalConfigForm != nil {
			m.globalConfigForm.WithWidth(msg.Width - 4).WithHeight(msg.Height - 4)
		}
		if m.serviceConfigForm != nil {
			m.serviceConfigForm.WithWidth(msg.Width - 4).WithHeight(msg.Height - 4)
		}
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c":
			if m.currentPage == pageInstall && m.installing && m.cancelCtx != nil {
				m.cancelCtx()
			}
			m.quitting = true
			return m, tea.Quit
		case "q":
			if m.currentPage == pageWelcome || m.currentPage == pageSummary {
				m.quitting = true
				return m, tea.Quit
			}
		}

	case nextPageMsg:
		m.advancePage()
		return m, nil

	case prevPageMsg:
		m.goBack()
		return m, nil

	case globalConfigDoneMsg:
		m.config.AccessMode = msg.Mode
		m.config.Domain = msg.Domain
		for _, id := range m.config.SelectedIDs() {
			sc := m.config.GetOrCreate(id)
			sc.AccessMode = msg.Mode
			sc.Domain = msg.Domain
		}
		m.advancePage()
		return m, nil

	case serviceConfigDoneMsg:
		m.advancePage()
		return m, nil

	case reviewConfirmMsg:
		m.orderedIDs = wizard.ResolveDeps(m.config.SelectedIDs())
		m.advancePage()
		cmd := m.runCurrentScript()
		return m, cmd

	case backend.LogMsg:
		prefix := ""
		if msg.Source == "stderr" {
			prefix = "[stderr] "
		}
		m.logs = append(m.logs, prefix+msg.Line)
		content := strings.Join(m.logs, "\n")
		m.vp.SetContent(content)
		m.vp.GotoBottom()
		return m, nil

	case backend.ScriptDoneMsg:
		m.results[msg.Script] = msg.Err
		if msg.Output != "" {
			m.logs = append(m.logs, msg.Output)
			m.vp.SetContent(strings.Join(m.logs, "\n"))
			m.vp.GotoBottom()
		}
		if msg.Err != nil {
			m.logs = append(m.logs, "[ERROR] "+msg.Err.Error())
			m.vp.SetContent(strings.Join(m.logs, "\n"))
			m.vp.GotoBottom()
		}
		m.scriptIdx++
		if m.scriptIdx >= len(m.orderedIDs) {
			m.installing = false
			m.advancePage()
			return m, nil
		}
		cmd := m.runCurrentScript()
		return m, cmd
	}

	// Page-specific handling
	switch m.currentPage {
	case pageWelcome:
		return m.updateWelcome(msg)
	case pageServiceSelect:
		return m.updateServiceSelect(msg)
	case pageGlobalConfig:
		return m.updateGlobalConfig(msg)
	case pageServiceConfig:
		return m.updateServiceConfig(msg)
	case pageReview:
		return m.updateReview(msg)
	case pageInstall:
		var cmd tea.Cmd
		m.sp, cmd = m.sp.Update(msg)
		return m, cmd
	case pageSummary:
		return m.updateSummary(msg)
	}

	return m, nil
}

// View implements tea.Model.
func (m AppModel) View() string {
	if m.quitting {
		return ""
	}
	switch m.currentPage {
	case pageWelcome:
		return m.viewWelcome()
	case pageServiceSelect:
		return m.viewServiceSelect()
	case pageGlobalConfig:
		return m.viewGlobalConfig()
	case pageServiceConfig:
		return m.viewServiceConfig()
	case pageReview:
		return m.viewReview()
	case pageInstall:
		return m.viewInstall()
	case pageSummary:
		return m.viewSummary()
	}
	return ""
}

// advancePage moves to the next page and initializes its state.
func (m *AppModel) advancePage() {
	switch m.currentPage {
	case pageWelcome:
		m.currentPage = pageServiceSelect
		m.initServiceSelectForm()
	case pageServiceSelect:
		m.currentPage = pageGlobalConfig
		m.initGlobalConfigForm()
	case pageGlobalConfig:
		m.configQueue = m.buildConfigQueue()
		m.configIdx = 0
		if len(m.configQueue) > 0 {
			m.currentPage = pageServiceConfig
			m.initServiceConfigForm()
		} else {
			m.currentPage = pageReview
		}
	case pageServiceConfig:
		m.configIdx++
		if m.configIdx >= len(m.configQueue) {
			m.currentPage = pageReview
		} else {
			m.initServiceConfigForm()
		}
	case pageReview:
		m.currentPage = pageInstall
		m.startInstall()
	case pageInstall:
		m.currentPage = pageSummary
	}
}

// goBack returns to the previous page.
func (m *AppModel) goBack() {
	switch m.currentPage {
	case pageServiceSelect:
		m.currentPage = pageWelcome
	case pageGlobalConfig:
		m.currentPage = pageServiceSelect
		m.initServiceSelectForm()
	case pageServiceConfig:
		if m.configIdx > 0 {
			m.configIdx--
			m.initServiceConfigForm()
		} else {
			m.currentPage = pageGlobalConfig
			m.initGlobalConfigForm()
		}
	case pageReview:
		m.configIdx = len(m.configQueue) - 1
		if m.configIdx >= 0 {
			m.currentPage = pageServiceConfig
			m.initServiceConfigForm()
		} else {
			m.currentPage = pageGlobalConfig
			m.initGlobalConfigForm()
		}
	}
}

// buildConfigQueue returns services that need extra per-service configuration.
func (m *AppModel) buildConfigQueue() []wizard.ServiceID {
	var queue []wizard.ServiceID
	for _, id := range m.config.SelectedIDs() {
		switch id {
		case wizard.ServiceCliproxyAPI, wizard.ServiceNewAPI, wizard.ServiceScience:
			queue = append(queue, id)
		}
	}
	return queue
}

// startInstall initializes the install page state.
func (m *AppModel) startInstall() {
	m.orderedIDs = wizard.ResolveDeps(m.config.SelectedIDs())
	m.scriptIdx = 0
	m.results = make(map[string]error)
	m.installing = true
	m.logs = []string{
		fmt.Sprintf("[%s] 开始部署，共 %d 个服务", version.Name, len(m.orderedIDs)),
		"────────────────────────────────────────",
	}
	m.vp.SetContent(strings.Join(m.logs, "\n"))
}

// runCurrentScript returns a tea.Cmd that runs the current script.
func (m *AppModel) runCurrentScript() tea.Cmd {
	if m.scriptIdx >= len(m.orderedIDs) {
		return nil
	}
	id := m.orderedIDs[m.scriptIdx]
	svc, ok := wizard.ServiceByID(id)
	if !ok {
		m.scriptIdx++
		if m.scriptIdx >= len(m.orderedIDs) {
			m.installing = false
			m.advancePage()
			return nil
		}
		return m.runCurrentScript()
	}

	m.logs = append(m.logs, fmt.Sprintf("\n▶ 正在安装: %s", svc.Name))
	m.vp.SetContent(strings.Join(m.logs, "\n"))
	m.vp.GotoBottom()

	env := backend.BuildEnv(m.config, id)
	ctx, cancel := context.WithCancel(context.Background())
	m.cancelCtx = cancel

	return backend.RunScript(ctx, svc.ScriptPath, env)
}

// header returns the top banner.
func (m AppModel) header() string {
	return Title.Render(version.FullName) + "\n" +
		Dimmed.Render(fmt.Sprintf("  版本 v%s · 按 q 退出 · 按 ← 返回", version.Version))
}

// footer returns the bottom help line.
func (m AppModel) footer() string {
	return Help.Render("ctrl+c 退出")
}
