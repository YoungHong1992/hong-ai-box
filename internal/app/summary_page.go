package app

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/hongge/hongaibox/internal/wizard"
)

func (m AppModel) updateSummary(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "q", "esc":
			m.quitting = true
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m AppModel) viewSummary() string {
	b := strings.Builder{}
	b.WriteString(m.header())
	b.WriteString("\n\n")

	// Title based on overall result
	allOK := true
	for _, err := range m.results {
		if err != nil {
			allOK = false
			break
		}
	}

	if allOK {
		b.WriteString(SuccessText.Render("🎉 部署完成！"))
	} else {
		b.WriteString(DangerText.Render("⚠️ 部分服务部署失败"))
	}
	b.WriteString("\n\n")

	// Per-service result
	for _, id := range m.orderedIDs {
		svc, _ := wizard.ServiceByID(id)
		script := svc.ScriptPath
		if err := m.results[script]; err != nil {
			b.WriteString(fmt.Sprintf("  %s %s  %s\n",
				lipgloss.NewStyle().Foreground(Danger).Render("✗"),
				svc.Name,
				lipgloss.NewStyle().Foreground(Danger).Render(err.Error()),
			))
		} else {
			b.WriteString(fmt.Sprintf("  %s %s\n",
				lipgloss.NewStyle().Foreground(Success).Render("✓"),
				svc.Name,
			))
		}
	}

	b.WriteString("\n")
	b.WriteString(Subtle.Render("常用管理命令"))
	b.WriteString("\n")
	for _, id := range m.orderedIDs {
		switch id {
		case wizard.ServiceNginx:
			b.WriteString("  systemctl status nginx  |  nginx -t  |  systemctl reload nginx\n")
		case wizard.ServiceDocker:
			b.WriteString("  docker info  |  docker compose version\n")
		case wizard.ServiceNewAPI:
			b.WriteString("  cd /opt/docker-services/new-api && docker compose ps\n")
			b.WriteString("  docker compose logs -f new-api\n")
		case wizard.ServiceCliproxyAPI:
			b.WriteString("  systemctl status cliproxyapi\n")
			b.WriteString("  journalctl -u cliproxyapi -f\n")
		case wizard.ServicePi:
			b.WriteString("  pi --help  |  pi -p \"你的问题\"\n")
		}
	}

	b.WriteString("\n")
	b.WriteString(Dimmed.Render("按 q 退出"))
	b.WriteString("\n")
	b.WriteString(m.footer())

	return b.String()
}
