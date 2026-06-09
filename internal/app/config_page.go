package app

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/huh"
	"github.com/hongge/hongaibox/internal/wizard"
)

// ─── Global Config ───────────────────────────────────────────────

func (m *AppModel) initGlobalConfigForm() {
	var mode wizard.AccessMode

	m.globalConfigForm = huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[wizard.AccessMode]().
				Key("access_mode").
				Title("访问方式").
				Description("所有服务的统一访问模式").
				Options(
					huh.NewOption[wizard.AccessMode]("域名（推荐，自动申请 Let's Encrypt 证书）", wizard.AccessDomain),
					huh.NewOption[wizard.AccessMode]("IP 地址（自签名证书，无需域名）", wizard.AccessIP),
					huh.NewOption[wizard.AccessMode]("仅 HTTP（无 SSL，仅限内网/开发）", wizard.AccessHTTP),
				).
				Value(&mode),
		),
		huh.NewGroup(
			huh.NewInput().
				Key("domain").
				Title("域名").
				Description("例如: api.example.com").
				Placeholder("api.example.com").
				Validate(validateDomain),
		).WithHideFunc(func() bool {
			return mode != wizard.AccessDomain
		}),
	).
		WithShowHelp(true).
		WithWidth(m.width - 4).
		WithHeight(m.height - 4)
}

func (m AppModel) updateGlobalConfig(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.globalConfigForm == nil {
		return m, nil
	}

	newModel, cmd := m.globalConfigForm.Update(msg)
	m.globalConfigForm = newModel.(*huh.Form)

	switch m.globalConfigForm.State {
	case huh.StateCompleted:
		rawMode := m.globalConfigForm.Get("access_mode")
		if rawMode != nil {
			if mode, ok := rawMode.(wizard.AccessMode); ok {
				m.config.AccessMode = mode
			}
		}

		rawDomain := m.globalConfigForm.Get("domain")
		if rawDomain != nil {
			if domain, ok := rawDomain.(string); ok {
				m.config.Domain = strings.TrimSpace(domain)
			}
		}

		// Auto-detect IP for ip/http modes
		if m.config.AccessMode != wizard.AccessDomain {
			return m, func() tea.Msg {
				ip := detectServerIP()
				return globalConfigDoneMsg{Mode: m.config.AccessMode, Domain: ip}
			}
		}

		return m, func() tea.Msg {
			return globalConfigDoneMsg{Mode: m.config.AccessMode, Domain: m.config.Domain}
		}
	case huh.StateAborted:
		return m, func() tea.Msg { return prevPageMsg{} }
	}

	return m, cmd
}

func (m AppModel) viewGlobalConfig() string {
	if m.globalConfigForm == nil {
		return "Loading..."
	}
	b := strings.Builder{}
	b.WriteString(m.header())
	b.WriteString("\n\n")
	b.WriteString(m.globalConfigForm.View())
	b.WriteString("\n")
	b.WriteString(m.footer())
	return b.String()
}

// validateDomain performs conservative ASCII domain validation.
func validateDomain(s string) error {
	raw := s
	s = strings.TrimSpace(s)
	if s == "" {
		return fmt.Errorf("域名不能为空")
	}
	if len(s) > 253 {
		return fmt.Errorf("域名过长 (最多 253 字符)")
	}
	if raw != s || strings.ContainsAny(s, " \t\r\n") {
		return fmt.Errorf("域名不能包含空白字符")
	}
	if !strings.Contains(s, ".") {
		return fmt.Errorf("请输入有效的域名 (需包含 '.')")
	}
	if strings.HasPrefix(s, ".") || strings.HasSuffix(s, ".") {
		return fmt.Errorf("域名不能以点号开头或结尾")
	}

	for _, label := range strings.Split(s, ".") {
		if label == "" {
			return fmt.Errorf("域名标签不能为空")
		}
		if len(label) > 63 {
			return fmt.Errorf("域名单段长度不能超过 63 字符")
		}
		if label[0] == '-' || label[len(label)-1] == '-' {
			return fmt.Errorf("域名单段不能以连字符开头或结尾")
		}
		for i := 0; i < len(label); i++ {
			ch := label[i]
			if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-') {
				return fmt.Errorf("域名只能包含字母、数字、点号和连字符")
			}
		}
	}
	return nil
}

// detectServerIP attempts to detect the public IP via public echo services.
func detectServerIP() string {
	services := []string{
		"https://api.ipify.org",
		"https://ifconfig.me/ip",
		"https://icanhazip.com",
	}
	client := &http.Client{Timeout: 3 * time.Second}

	for _, url := range services {
		resp, err := client.Get(url)
		if err != nil {
			continue
		}
		body, readErr := io.ReadAll(io.LimitReader(resp.Body, 64))
		closeErr := resp.Body.Close()
		if readErr != nil || closeErr != nil || resp.StatusCode < 200 || resp.StatusCode >= 300 {
			continue
		}
		ip := strings.TrimSpace(string(body))
		if net.ParseIP(ip) != nil {
			return ip
		}
	}
	return ""
}

// ─── Service-specific Config ─────────────────────────────────────

func (m *AppModel) initServiceConfigForm() {
	if m.configIdx >= len(m.configQueue) {
		return
	}
	switch m.configQueue[m.configIdx] {
	case wizard.ServiceCliproxyAPI:
		m.initCliproxyAPIForm()
	case wizard.ServiceNewAPI:
		m.initNewAPIForm()
	case wizard.ServiceScience:
		m.initScienceForm()
	}
}

func (m *AppModel) initCliproxyAPIForm() {
	sc := m.config.GetOrCreate(wizard.ServiceCliproxyAPI)
	m.serviceConfigForm = huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Key("admin_password").
				Title("CliproxyAPI 管理面板密码").
				Description("留空将自动生成随机密码").
				Placeholder("自动生成").
				EchoMode(huh.EchoModePassword).
				Value(&sc.AdminPassword),
		),
	).
		WithShowHelp(true).
		WithWidth(m.width - 4).
		WithHeight(m.height - 4)
}

func (m *AppModel) initNewAPIForm() {
	sc := m.config.GetOrCreate(wizard.ServiceNewAPI)
	var db wizard.DBType = wizard.DBPostgresql
	if sc.DBType != "" {
		db = sc.DBType
	}
	m.serviceConfigForm = huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[wizard.DBType]().
				Key("db_type").
				Title("数据库类型").
				Description("New-API 使用的数据库").
				Options(
					huh.NewOption[wizard.DBType]("PostgreSQL（推荐）", wizard.DBPostgresql),
					huh.NewOption[wizard.DBType]("MySQL", wizard.DBMySQL),
				).
				Value(&db),
		),
	).
		WithShowHelp(true).
		WithWidth(m.width - 4).
		WithHeight(m.height - 4)
}

func (m *AppModel) initScienceForm() {
	sc := m.config.GetOrCreate(wizard.ServiceScience)
	if sc.DestSNI == "" {
		sc.DestSNI = "www.microsoft.com"
	}
	if sc.RealityPort == "" {
		sc.RealityPort = "8443"
	}
	m.serviceConfigForm = huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Key("dest_sni").
				Title("目标 SNI").
				Description("Reality 伪装目标站点").
				Placeholder("www.microsoft.com").
				Value(&sc.DestSNI),
			huh.NewInput().
				Key("reality_port").
				Title("监听端口").
				Description("Science 服务监听端口").
				Placeholder("8443").
				Validate(func(s string) error {
					if s == "" {
						return fmt.Errorf("端口不能为空")
					}
					if _, err := net.LookupPort("tcp", s); err != nil {
						return fmt.Errorf("无效端口")
					}
					return nil
				}).
				Value(&sc.RealityPort),
		),
	).
		WithShowHelp(true).
		WithWidth(m.width - 4).
		WithHeight(m.height - 4)
}

func (m AppModel) updateServiceConfig(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.serviceConfigForm == nil {
		return m, nil
	}

	newModel, cmd := m.serviceConfigForm.Update(msg)
	m.serviceConfigForm = newModel.(*huh.Form)

	switch m.serviceConfigForm.State {
	case huh.StateCompleted:
		// Persist db_type for newapi
		if m.configQueue[m.configIdx] == wizard.ServiceNewAPI {
			raw := m.serviceConfigForm.Get("db_type")
			if raw != nil {
				if db, ok := raw.(wizard.DBType); ok {
					m.config.GetOrCreate(wizard.ServiceNewAPI).DBType = db
				}
			}
		}
		return m, func() tea.Msg { return serviceConfigDoneMsg{} }
	case huh.StateAborted:
		return m, func() tea.Msg { return prevPageMsg{} }
	}

	return m, cmd
}

func (m AppModel) viewServiceConfig() string {
	if m.serviceConfigForm == nil {
		return "Loading..."
	}
	b := strings.Builder{}
	b.WriteString(m.header())
	b.WriteString("\n\n")

	svcID := m.configQueue[m.configIdx]
	svc, _ := wizard.ServiceByID(svcID)
	b.WriteString(Subtitle.Render(fmt.Sprintf("配置: %s", svc.Name)))
	b.WriteString("\n\n")

	b.WriteString(m.serviceConfigForm.View())
	b.WriteString("\n")
	b.WriteString(m.footer())
	return b.String()
}
