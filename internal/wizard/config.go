package wizard

// AccessMode defines how services are exposed.
type AccessMode string

const (
	AccessDomain AccessMode = "domain"
	AccessIP     AccessMode = "ip"
	AccessHTTP   AccessMode = "http"
)

// DBType for New-API.
type DBType string

const (
	DBPostgresql DBType = "postgresql"
	DBMySQL      DBType = "mysql"
)

// ServiceConfig holds per-service settings.
type ServiceConfig struct {
	Enabled       bool
	AccessMode    AccessMode
	Domain        string
	AdminPassword string // cliproxyapi
	DBType        DBType // newapi
	DestSNI       string // science
	RealityPort   string // science
}

// Config is the global user configuration collected by the wizard.
type Config struct {
	// Global settings
	AccessMode AccessMode
	Domain     string // primary domain or IP

	// Per-service overrides
	Services map[ServiceID]*ServiceConfig
}

// NewConfig creates an empty Config with initialized map.
func NewConfig() *Config {
	return &Config{
		Services: make(map[ServiceID]*ServiceConfig),
	}
}

// GetOrCreate returns the config for a service, creating it if absent.
func (c *Config) GetOrCreate(id ServiceID) *ServiceConfig {
	if c.Services[id] == nil {
		c.Services[id] = &ServiceConfig{}
	}
	return c.Services[id]
}

// SelectedIDs returns the list of service IDs the user has enabled.
func (c *Config) SelectedIDs() []ServiceID {
	var ids []ServiceID
	for _, svc := range AllServices {
		if svc.Mandatory {
			ids = append(ids, svc.ID)
			continue
		}
		if sc := c.Services[svc.ID]; sc != nil && sc.Enabled {
			ids = append(ids, svc.ID)
		}
	}
	return ids
}

// IsServiceEnabled reports whether a service is enabled.
func (c *Config) IsServiceEnabled(id ServiceID) bool {
	svc, ok := ServiceByID(id)
	if !ok {
		return false
	}
	if svc.Mandatory {
		return true
	}
	if sc := c.Services[id]; sc != nil {
		return sc.Enabled
	}
	return false
}
