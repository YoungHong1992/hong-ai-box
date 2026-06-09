package app

import "testing"

func TestValidateDomain(t *testing.T) {
	valid := []string{
		"example.com",
		"api.example.com",
		"a-b.example.co",
		"xn--fiqs8s.example",
	}
	for _, domain := range valid {
		t.Run("valid_"+domain, func(t *testing.T) {
			if err := validateDomain(domain); err != nil {
				t.Fatalf("validateDomain(%q) returned error: %v", domain, err)
			}
		})
	}

	invalid := []string{
		"",
		"localhost",
		"example",
		" example.com",
		"example.com ",
		"exa mple.com",
		".example.com",
		"example.com.",
		"example..com",
		"-example.com",
		"example-.com",
		"abc_foo.com",
	}
	for _, domain := range invalid {
		t.Run("invalid_"+domain, func(t *testing.T) {
			if err := validateDomain(domain); err == nil {
				t.Fatalf("validateDomain(%q) returned nil, want error", domain)
			}
		})
	}
}
