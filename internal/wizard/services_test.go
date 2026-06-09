package wizard

import (
	"reflect"
	"testing"
)

func TestServiceByID(t *testing.T) {
	tests := []struct {
		id      ServiceID
		wantOK  bool
		wantSvc Service
	}{
		{ServiceNginx, true, Service{ID: ServiceNginx, Mandatory: true}},
		{ServiceDocker, true, Service{ID: ServiceDocker, Mandatory: false}},
		{"nonexistent", false, Service{}},
	}

	for _, tt := range tests {
		svc, ok := ServiceByID(tt.id)
		if ok != tt.wantOK {
			t.Errorf("ServiceByID(%q) ok = %v, want %v", tt.id, ok, tt.wantOK)
		}
		if ok && svc.ID != tt.wantSvc.ID {
			t.Errorf("ServiceByID(%q).ID = %q, want %q", tt.id, svc.ID, tt.wantSvc.ID)
		}
		if ok && svc.Mandatory != tt.wantSvc.Mandatory {
			t.Errorf("ServiceByID(%q).Mandatory = %v, want %v", tt.id, svc.Mandatory, tt.wantSvc.Mandatory)
		}
	}
}

func TestResolveDeps(t *testing.T) {
	tests := []struct {
		name     string
		selected []ServiceID
		want     []ServiceID
	}{
		{
			name:     "just nginx",
			selected: []ServiceID{ServiceNginx},
			want:     []ServiceID{ServiceNginx},
		},
		{
			name:     "nginx + docker",
			selected: []ServiceID{ServiceNginx, ServiceDocker},
			want:     []ServiceID{ServiceNginx, ServiceDocker},
		},
		{
			name:     "newapi depends on nginx+docker",
			selected: []ServiceID{ServiceNewAPI},
			want:     []ServiceID{ServiceNginx, ServiceDocker, ServiceNewAPI},
		},
		{
			name:     "cliproxyapi depends on nginx",
			selected: []ServiceID{ServiceCliproxyAPI},
			want:     []ServiceID{ServiceNginx, ServiceCliproxyAPI},
		},
		{
			name:     "pi has no deps",
			selected: []ServiceID{ServicePi},
			want:     []ServiceID{ServicePi},
		},
		{
			name:     "science has no deps",
			selected: []ServiceID{ServiceScience},
			want:     []ServiceID{ServiceScience},
		},
		{
			name:     "all together",
			selected: []ServiceID{ServiceNewAPI, ServiceCliproxyAPI, ServicePi, ServiceScience},
			want:     []ServiceID{ServiceNginx, ServiceDocker, ServiceNewAPI, ServiceCliproxyAPI, ServicePi, ServiceScience},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ResolveDeps(tt.selected)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("ResolveDeps(%v) = %v, want %v", tt.selected, got, tt.want)
			}
		})
	}
}

func TestConfigSelectedIDs(t *testing.T) {
	cfg := NewConfig()

	// Initially only mandatory services
	ids := cfg.SelectedIDs()
	if len(ids) != 1 {
		t.Fatalf("initial SelectedIDs len = %d, want 1 (nginx mandatory)", len(ids))
	}
	if ids[0] != ServiceNginx {
		t.Errorf("first mandatory = %s, want nginx", ids[0])
	}

	// Enable docker
	cfg.GetOrCreate(ServiceDocker).Enabled = true
	ids = cfg.SelectedIDs()
	if len(ids) != 2 {
		t.Errorf("after docker SelectedIDs len = %d, want 2", len(ids))
	}

	// Enable newapi
	cfg.GetOrCreate(ServiceNewAPI).Enabled = true
	ids = cfg.SelectedIDs()
	if len(ids) != 3 {
		t.Errorf("after newapi SelectedIDs len = %d, want 3", len(ids))
	}
}

func TestConfigGetOrCreate(t *testing.T) {
	cfg := NewConfig()

	// GetOrCreate returns existing
	sc1 := cfg.GetOrCreate(ServiceNginx)
	sc1.Domain = "example.com"

	sc2 := cfg.GetOrCreate(ServiceNginx)
	if sc2.Domain != "example.com" {
		t.Error("GetOrCreate should return the same pointer")
	}

	// GetOrCreate creates new for unseen service
	sc3 := cfg.GetOrCreate(ServiceCliproxyAPI)
	if sc3 == nil {
		t.Fatal("GetOrCreate should never return nil")
	}
}

func TestConfigIsServiceEnabled(t *testing.T) {
	cfg := NewConfig()

	// Mandatory services always enabled
	if !cfg.IsServiceEnabled(ServiceNginx) {
		t.Error("nginx should be enabled (mandatory)")
	}

	// Non-mandatory not enabled by default
	if cfg.IsServiceEnabled(ServiceDocker) {
		t.Error("docker should not be enabled by default")
	}

	// Enable docker
	cfg.GetOrCreate(ServiceDocker).Enabled = true
	if !cfg.IsServiceEnabled(ServiceDocker) {
		t.Error("docker should be enabled after setting")
	}

	// Unknown service
	if cfg.IsServiceEnabled("foobar") {
		t.Error("unknown service should not be enabled")
	}
}

func TestAllServicesCount(t *testing.T) {
	// All services should be listed
	if len(AllServices) < 6 {
		t.Errorf("AllServices should have at least 6 entries, got %d", len(AllServices))
	}

	// Exactly one mandatory
	mandatory := 0
	for _, s := range AllServices {
		if s.Mandatory {
			mandatory++
		}
	}
	if mandatory != 1 {
		t.Errorf("expected exactly 1 mandatory service, got %d", mandatory)
	}

	// Every service should have a non-empty ScriptPath
	for _, s := range AllServices {
		if s.ScriptPath == "" {
			t.Errorf("service %s has empty ScriptPath", s.ID)
		}
	}
}
