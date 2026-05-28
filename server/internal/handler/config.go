package handler

import (
	"net/http"
	"os"

	"github.com/multica-ai/multica/server/internal/analytics"
)

type AppConfig struct {
	CdnDomain string `json:"cdn_domain"`
	// Public auth config consumed by the web app at runtime so self-hosted
	// deployments do not need to rebuild the frontend image when operators
	// toggle signup or wire Google OAuth.
	AllowSignup       bool   `json:"allow_signup"`
	GoogleClientID    string `json:"google_client_id,omitempty"`
	DingTalkClientID  string `json:"dingtalk_client_id,omitempty"`
	// WorkspaceCreationDisabled mirrors the server-side
	// DISABLE_WORKSPACE_CREATION env var so the UI can hide every
	// "Create workspace" affordance on self-hosted instances. Omitted
	// from the JSON when false to keep responses identical to the
	// previous shape for the common managed-cloud case (#3433).
	WorkspaceCreationDisabled bool `json:"workspace_creation_disabled,omitempty"`

	// GitHub App enabled (true when both GITHUB_APP_SLUG and GITHUB_WEBHOOK_SECRET are set).
	GitHubEnabled bool `json:"github_enabled"`

	// Gitee webhook integration enabled (true when GITEE_WEBHOOK_SECRET is set).
	GiteeEnabled bool `json:"gitee_enabled"`

	// Gitee OAuth configured (true when GITEE_CLIENT_ID and GITEE_CLIENT_SECRET are set).
	GiteeOAuthConfigured bool `json:"gitee_oauth_configured"`

	// PostHog public config for the frontend. The key is the same Project
	// API Key the backend uses; returning it here (instead of baking it
	// into the frontend bundle via NEXT_PUBLIC_*) means self-hosted
	// instances — whose server returns an empty key — automatically
	// disable frontend event shipping too.
	PosthogKey           string `json:"posthog_key"`
	PosthogHost          string `json:"posthog_host"`
	AnalyticsEnvironment string `json:"analytics_environment"`
}

// GetConfig is mounted on the public (unauthenticated) route group because
// the web app calls it before login to decide whether to render the Google
// sign-in button and signup UI. Only add fields here that are safe to expose
// to anonymous callers — never user- or tenant-scoped data.
func (h *Handler) GetConfig(w http.ResponseWriter, r *http.Request) {
	config := AppConfig{
		AllowSignup:               os.Getenv("ALLOW_SIGNUP") != "false",
		GoogleClientID:            os.Getenv("GOOGLE_CLIENT_ID"),
		DingTalkClientID:          os.Getenv("DINGTALK_CLIENT_ID"),
		WorkspaceCreationDisabled: os.Getenv("DISABLE_WORKSPACE_CREATION") == "true",
		GitHubEnabled:             os.Getenv("GITHUB_APP_SLUG") != "" && os.Getenv("GITHUB_WEBHOOK_SECRET") != "",
		GiteeEnabled:              os.Getenv("GITEE_WEBHOOK_SECRET") != "",
		GiteeOAuthConfigured:      os.Getenv("GITEE_CLIENT_ID") != "" && os.Getenv("GITEE_CLIENT_SECRET") != "",
	}
	if h.Storage != nil {
		config.CdnDomain = h.Storage.CdnDomain()
	}

	// Re-read from env on every request so operators can rotate keys via
	// secret refresh without a server restart.
	if v := os.Getenv("ANALYTICS_DISABLED"); v != "true" && v != "1" {
		config.PosthogKey = os.Getenv("POSTHOG_API_KEY")
		config.PosthogHost = os.Getenv("POSTHOG_HOST")
		config.AnalyticsEnvironment = analytics.EnvironmentFromEnv()
		if config.PosthogHost == "" && config.PosthogKey != "" {
			config.PosthogHost = "https://us.i.posthog.com"
		}
	}

	writeJSON(w, http.StatusOK, config)
}
