package app

import (
	"strings"

	"github.com/charmbracelet/lipgloss"
	"github.com/hongge/hongaibox/internal/wizard"
)

func (m AppModel) viewInstall() string {
	b := strings.Builder{}
	b.WriteString(m.header())
	b.WriteString("\n\n")

	b.WriteString(Title.Render("🚀 正在安装"))
	b.WriteString("\n\n")

	// Service progress list
	for i, id := range m.orderedIDs {
		svc, _ := wizard.ServiceByID(id)
		var prefix string
		if i < m.scriptIdx {
			prefix = lipgloss.NewStyle().Foreground(Success).Render("  ✓ ")
		} else if i == m.scriptIdx && m.installing {
			prefix = "  " + m.sp.View() + " "
		} else {
			prefix = "  ○ "
		}
		b.WriteString(prefix + svc.Name)
		if i == m.scriptIdx && m.installing {
			b.WriteString(Dimmed.Render("  installing..."))
		}
		b.WriteString("\n")
	}

	b.WriteString("\n")
	b.WriteString(Box.Render(m.vp.View()))
	b.WriteString("\n")
	b.WriteString(m.footer())

	return b.String()
}
