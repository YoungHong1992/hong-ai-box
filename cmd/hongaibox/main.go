package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/hongge/hongaibox/internal/app"
	"github.com/hongge/hongaibox/internal/version"
)

func main() {
	var (
		showHelp    = flag.Bool("h", false, "显示帮助")
		showVersion = flag.Bool("version", false, "显示版本")
	)
	flag.Parse()

	if *showHelp {
		fmt.Printf("%s v%s\n\n", version.FullName, version.Version)
		fmt.Println("用法:")
		fmt.Println("  hongaibox         启动交互式 TUI 部署向导")
		fmt.Println("  hongaibox -h      显示此帮助")
		fmt.Println("  hongaibox --version 显示版本")
		fmt.Println()
		fmt.Println("说明:")
		fmt.Println("  hongaibox 是一套面向云服务器的 AI 工具自动化部署工具。")
		fmt.Println("  通过交互式 TUI 引导您完成 Nginx、Docker、New-API、CliproxyAPI 等组件的安装。")
		os.Exit(0)
	}

	if *showVersion {
		fmt.Printf("%s v%s\n", version.Name, version.Version)
		os.Exit(0)
	}

	if os.Geteuid() != 0 {
		fmt.Fprintln(os.Stderr, "错误: 必须使用 root 权限运行 hongaibox。")
		fmt.Fprintln(os.Stderr, "请使用: sudo hongaibox")
		os.Exit(1)
	}

	m := app.NewAppModel()
	p := tea.NewProgram(m, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "错误: %v\n", err)
		os.Exit(1)
	}
}
