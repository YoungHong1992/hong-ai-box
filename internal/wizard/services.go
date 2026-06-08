package wizard

// ServiceID uniquely identifies a deployable service.
type ServiceID string

const (
	ServiceNginx       ServiceID = "nginx"
	ServiceDocker      ServiceID = "docker"
	ServiceCliproxyAPI ServiceID = "cliproxyapi"
	ServiceNewAPI      ServiceID = "newapi"
	ServicePi          ServiceID = "pi"
	ServiceScience     ServiceID = "science"
)

// Service describes a deployable component.
type Service struct {
	ID          ServiceID
	Name        string
	Description string
	Mandatory   bool
	Recommended bool
	ResourceHint string
	DependsOn   []ServiceID
	ScriptPath  string
}

// AllServices is the canonical list of services.
var AllServices = []Service{
	{
		ID:           ServiceNginx,
		Name:         "Nginx (HTTP/3)",
		Description:  "Nginx 官方主线仓库安装，支持 HTTP/3 (QUIC)、TCP BBR 优化",
		Mandatory:    true,
		Recommended:  true,
		ResourceHint: "512MB 内存 / 500MB 磁盘",
		ScriptPath:   "scripts/nginx/install_nginx.sh",
	},
	{
		ID:           ServiceDocker,
		Name:         "Docker 容器环境",
		Description:  "Docker Engine + Docker Compose 插件",
		Mandatory:    false,
		Recommended:  true,
		ResourceHint: "无额外需求",
		ScriptPath:   "scripts/docker/install_docker.sh",
	},
	{
		ID:           ServiceCliproxyAPI,
		Name:         "CliproxyAPI",
		Description:  "轻量 AI API 转发代理 (~50MB)，支持 OpenAI / Claude / Gemini",
		Mandatory:    false,
		Recommended:  false,
		ResourceHint: "256MB 内存",
		DependsOn:    []ServiceID{ServiceNginx},
		ScriptPath:   "scripts/cliproxyapi/install_cliproxyapi_v2.sh",
	},
	{
		ID:           ServiceNewAPI,
		Name:         "New-API",
		Description:  "AI 模型网关与资产管理系统，支持多模型聚合、计费、用户管理",
		Mandatory:    false,
		Recommended:  false,
		ResourceHint: "推荐 ≥ 1GB 内存",
		DependsOn:    []ServiceID{ServiceNginx, ServiceDocker},
		ScriptPath:   "scripts/new-api/install_newapi_docker.sh",
	},
	{
		ID:           ServicePi,
		Name:         "Pi 编程助手",
		Description:  "极简终端 AI 编程助手，支持 Anthropic / OpenAI / Gemini / DeepSeek",
		Mandatory:    false,
		Recommended:  false,
		ResourceHint: "500MB 磁盘",
		ScriptPath:   "scripts/pi-coding-agent/install_pi.sh",
	},
	{
		ID:           ServiceScience,
		Name:         "Science (网络工具)",
		Description:  "VLESS + XTLS-Vision + Reality，无需域名和 SSL",
		Mandatory:    false,
		Recommended:  false,
		ResourceHint: "极低",
		ScriptPath:   "scripts/science/setup.sh",
	},
}

// ServiceByID returns a service by its ID.
func ServiceByID(id ServiceID) (Service, bool) {
	for _, s := range AllServices {
		if s.ID == id {
			return s, true
		}
	}
	return Service{}, false
}

// ResolveDeps returns the given services plus all transitive dependencies,
// ordered such that dependencies appear before dependents.
func ResolveDeps(selected []ServiceID) []ServiceID {
	seen := make(map[ServiceID]bool)
	order := make([]ServiceID, 0)

	var visit func(id ServiceID)
	visit = func(id ServiceID) {
		if seen[id] {
			return
		}
		seen[id] = true
		svc, ok := ServiceByID(id)
		if !ok {
			return
		}
		for _, dep := range svc.DependsOn {
			visit(dep)
		}
		order = append(order, id)
	}

	for _, id := range selected {
		visit(id)
	}
	return order
}
