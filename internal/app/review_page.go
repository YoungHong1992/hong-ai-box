package app

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/hongge/hongaibox/internal/wizard"
)

func (m AppModel) updateReview(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
		case "enter":
			return m, func() tea.Msg { return reviewConfirmMsg{} }
		case "left", "esc":
			return m, func() tea.Msg { return prevPageMsg{} }
		}
	}
	return m, nil
}

func (m AppModel) viewReview() string {
	b := strings.Builder{}
	b.WriteString(m.header())
	b.WriteString("\n\n")
	b.WriteString(Title.Render("📋 配置总览"))
	b.WriteString("\n\n")

	// Global config
	b.WriteString(Subtle.Render("全局配置"))
	b.WriteString("\n")
	b.WriteString(fmt.Sprintf("  访问模式: %s\n", accessModeLabel(m.config.AccessMode)))
	b.WriteString(fmt.Sprintf("  域名/IP:  %s\n", m.config.Domain))
	b.WriteString("\n")

	// Services
	b.WriteString(Subtle.Render("待安装服务"))
	b.WriteString("\n")
	for _, id := range wizard.ResolveDeps(m.config.SelectedIDs()) {
		svc, _ := wizard.ServiceByID(id)
		sc := m.config.GetOrCreate(id)
		line := fmt.Sprintf("  %s %s", checkedBox, svc.Name)
		b.WriteString(line)
		b.WriteString("\n")

		// Show per-service config
		switch id {
		case wizard.ServiceCliproxyAPI:
			pass := sc.AdminPassword
			if pass == "" {
				pass = "（自动生成）"
			} else {
				pass = "（已设置）"
			}
			b.WriteString(fmt.Sprintf("      密码: %s\n", pass))
		case wizard.ServiceNewAPI:
			b.WriteString(fmt.Sprintf("      数据库: %s\n", dbLabel(sc.DBType)))
		case wizard.ServiceScience:
			b.WriteString(fmt.Sprintf("      SNI: %s  端口: %s\n", sc.DestSNI, sc.RealityPort))
		}
	}

	b.WriteString("\n")
	b.WriteString(AccentText.Render("按 Enter 确认并开始安装"))
	b.WriteString("  ")
	b.WriteString(Dimmed.Render("按 ← 返回修改"))
	b.WriteString("\n")
	b.WriteString(m.footer())

	return b.String()
}

func accessModeLabel(mode wizard.AccessMode) string {
	switch mode {
	case wizard.AccessDomain:
		return "域名（Let's Encrypt）"
	case wizard.AccessIP:
		return "IP（自签名证书）"
	case wizard.AccessHTTP:
		return "HTTP（无 SSL）"
	}
	return string(mode)
}

func dbLabel(db wizard.DBType) string {
	switch db {
	case wizard.DBPostgresql:
		return "PostgreSQL"
	case wizard.DBMySQL:
		return "MySQL"
	}
	return string(db)
}

var (
	checkedBox = lipgloss.NewStyle().Foreground(Success).Render("✓")
	Subtle     = lipgloss.NewStyle().Foreground(Dim).Bold(true)
)
