package app

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

func (m AppModel) updateWelcome(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		if key.String() == "enter" {
			return m, func() tea.Msg { return nextPageMsg{} }
		}
	}
	return m, nil
}

func (m AppModel) viewWelcome() string {
	logo := `
    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║          ███╗   ██╗ ██████╗  ██████╗  ██████╗ ║
    ║          ████╗  ██║██╔═══██╗██╔════╝ ██╔═══██╗║
    ║          ██╔██╗ ██║██║   ██║██║  ███╗██║   ██║║
    ║          ██║╚██╗██║██║   ██║██║   ██║██║   ██║║
    ║          ██║ ╚████║╚██████╔╝╚██████╔╝╚██████╔╝║
    ║          ╚═╝  ╚═══╝ ╚═════╝  ╚═════╝  ╚═════╝ ║
    ║                                               ║
    ║           洪哥的 AI 工具箱 (hongaibox)          ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
`
	content := lipgloss.JoinVertical(lipgloss.Center,
		Title.Render(logo),
		"",
		Normal.Render("一套面向云服务器的 AI 工具自动化部署工具"),
		"",
		Dimmed.Render("支持: Nginx · Docker · New-API · CliproxyAPI · Pi · Science"),
		"",
		AccentText.Render("按 Enter 开始部署"),
		"",
		Dimmed.Render("按 q 退出"),
	)

	return lipgloss.Place(m.width, m.height,
		lipgloss.Center, lipgloss.Center,
		content,
	)
}
