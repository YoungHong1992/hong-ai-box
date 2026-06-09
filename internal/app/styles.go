package app

import "github.com/charmbracelet/lipgloss"

// Theme colors inspired by a tech-cool palette.
var (
	Primary   = lipgloss.Color("#00D4AA") // teal/cyan accent
	Secondary = lipgloss.Color("#5B8DEF") // soft blue
	Accent    = lipgloss.Color("#F59E0B") // amber highlight
	Danger    = lipgloss.Color("#EF4444") // red error
	Success   = lipgloss.Color("#10B981") // green success
	Dim       = lipgloss.Color("#6B7280") // gray
	Fg        = lipgloss.Color("#E5E7EB") // light gray text
	Bg        = lipgloss.Color("#111827") // dark background
)

var (
	// Title is the big bold header style.
	Title = lipgloss.NewStyle().
		Bold(true).
		Foreground(Primary).
		MarginTop(1).
		MarginBottom(1).
		PaddingLeft(2).
		PaddingRight(2)

	// Subtitle is a secondary header.
	Subtitle = lipgloss.NewStyle().
			Foreground(Secondary).
			MarginBottom(1)

	// Normal text.
	Normal = lipgloss.NewStyle().
		Foreground(Fg)

	// Dimmed text.
	Dimmed = lipgloss.NewStyle().
		Foreground(Dim)

	// Box creates a bordered container.
	Box = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(Secondary).
		Padding(1, 2).
		Margin(1, 2)

	// FocusedBox is a highlighted container.
	FocusedBox = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(Primary).
			Padding(1, 2).
			Margin(1, 2)

	// SuccessText for green highlights.
	SuccessText = lipgloss.NewStyle().
			Foreground(Success).
			Bold(true)

	// DangerText for red highlights.
	DangerText = lipgloss.NewStyle().
			Foreground(Danger).
			Bold(true)

	// AccentText for amber highlights.
	AccentText = lipgloss.NewStyle().
			Foreground(Accent).
			Bold(true)

	// Help text at the bottom.
	Help = lipgloss.NewStyle().
		Foreground(Dim).
		MarginTop(1)
)
