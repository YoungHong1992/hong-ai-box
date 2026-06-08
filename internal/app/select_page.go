package app

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/hongge/hongaibox/internal/wizard"
)

func (m *AppModel) initServiceSelectForm() {
	opts := make([]huh.Option[wizard.ServiceID], 0)
	for _, svc := range wizard.AllServices {
		if svc.Mandatory {
			continue
		}
		opts = append(opts, huh.NewOption[wizard.ServiceID](svc.Name, svc.ID))
	}

	m.serviceSelectForm = huh.NewForm(
		huh.NewGroup(
			huh.NewMultiSelect[wizard.ServiceID]().
				Key("services").
				Title("选择要安装的服务").
				Description("空格切换选中，方向键移动，Enter 确认").
				Options(opts...),
		),
	).
		WithShowHelp(true).
		WithWidth(m.width - 4).
		WithHeight(m.height - 4)
}

func (m AppModel) updateServiceSelect(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.serviceSelectForm == nil {
		return m, nil
	}

	newModel, cmd := m.serviceSelectForm.Update(msg)
	m.serviceSelectForm = newModel.(*huh.Form)

	switch m.serviceSelectForm.State {
	case huh.StateCompleted:
		raw := m.serviceSelectForm.Get("services")
		if raw != nil {
			if ids, ok := raw.([]wizard.ServiceID); ok {
				for _, id := range ids {
					m.config.GetOrCreate(id).Enabled = true
				}
			}
		}
		// Always enable mandatory services
		for _, svc := range wizard.AllServices {
			if svc.Mandatory {
				m.config.GetOrCreate(svc.ID).Enabled = true
			}
		}
		return m, func() tea.Msg { return nextPageMsg{} }
	case huh.StateAborted:
		return m, func() tea.Msg { return prevPageMsg{} }
	}

	return m, cmd
}

func (m AppModel) viewServiceSelect() string {
	if m.serviceSelectForm == nil {
		return "Loading..."
	}
	b := strings.Builder{}
	b.WriteString(m.header())
	b.WriteString("\n\n")
	b.WriteString(m.serviceSelectForm.View())
	b.WriteString("\n")
	b.WriteString(m.footer())
	return b.String()
}
