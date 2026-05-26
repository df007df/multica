package handler

import (
	"encoding/json"
	"strings"
)

// giteeWebhookRepo is the repository object embedded in Gitee pull_request
// webhooks (base.repo / head.repo) and optionally at the payload root.
type giteeWebhookRepo struct {
	Name              string `json:"name"`
	Path              string `json:"path"`
	Namespace         string `json:"namespace"`
	PathWithNamespace string `json:"path_with_namespace"`
	Owner             struct {
		Login string `json:"login"`
	} `json:"owner"`
}

func (r giteeWebhookRepo) ownerAndName() (owner, name string) {
	if r.Owner.Login != "" && r.Name != "" {
		return r.Owner.Login, r.Name
	}
	if r.PathWithNamespace != "" {
		if o, n, ok := strings.Cut(r.PathWithNamespace, "/"); ok && o != "" && n != "" {
			return o, n
		}
	}
	if r.Namespace != "" && r.Path != "" {
		return r.Namespace, r.Path
	}
	if r.Namespace != "" && r.Name != "" {
		return r.Namespace, r.Name
	}
	return "", ""
}

type giteeWebhookPRPayload struct {
	HookName    string `json:"hook_name"`
	Action      string `json:"action"`
	PullRequest struct {
		ID           int64  `json:"id"`
		Number       int32  `json:"number"`
		Title        string `json:"title"`
		Body         string `json:"body"`
		State        string `json:"state"`
		HTMLURL      string `json:"html_url"`
		Merged       bool   `json:"merged"`
		MergedAt     string `json:"merged_at"`
		ClosedAt     string `json:"closed_at"`
		CreatedAt    string `json:"created_at"`
		UpdatedAt    string `json:"updated_at"`
		Additions    int32  `json:"additions"`
		Deletions    int32  `json:"deletions"`
		ChangedFiles int32  `json:"changed_files"`
		Head         struct {
			Ref  string           `json:"ref"`
			Repo giteeWebhookRepo `json:"repo"`
		} `json:"head"`
		Base struct {
			Ref  string           `json:"ref"`
			Repo giteeWebhookRepo `json:"repo"`
		} `json:"base"`
		User struct {
			Login     string `json:"login"`
			AvatarURL string `json:"avatar_url"`
		} `json:"user"`
	} `json:"pull_request"`
	Repository giteeWebhookRepo `json:"repository"`
}

// resolveGiteeRepoFromPRPayload returns the target-repo owner/name for a PR
// webhook. Gitee.com public-cloud payloads usually put the repo on
// pull_request.base.repo; older/alternate shapes may use a top-level
// repository object.
func resolveGiteeRepoFromPRPayload(p giteeWebhookPRPayload) (owner, name string) {
	if owner, name = p.Repository.ownerAndName(); owner != "" && name != "" {
		return owner, name
	}
	if owner, name = p.PullRequest.Base.Repo.ownerAndName(); owner != "" && name != "" {
		return owner, name
	}
	return p.PullRequest.Head.Repo.ownerAndName()
}

// isGiteePullRequestWebhook reports whether the request should be handled as a
// PR mirror + auto-link event. Gitee.com sends X-Gitee-Event: "Merge Request
// Hook" with hook_name "merge_request_hooks"; other deployments use shorter
// names.
func isGiteePullRequestWebhook(eventHeader, hookName string) bool {
	switch normalizeGiteeWebhookEventName(eventHeader) {
	case "pull request", "pull request hook", "pull request hooks",
		"merge request", "merge request hook", "merge request hooks":
		return true
	}
	switch strings.ToLower(strings.TrimSpace(hookName)) {
	case "pull_request_hooks", "merge_request_hooks":
		return true
	default:
		return false
	}
}

func normalizeGiteeWebhookEventName(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = strings.ReplaceAll(s, "_", " ")
	s = strings.ReplaceAll(s, "-", " ")
	return strings.Join(strings.Fields(s), " ")
}

// giteeHookNameFromBody reads hook_name without fully unmarshaling the PR payload.
func giteeHookNameFromBody(body []byte) string {
	var probe struct {
		HookName string `json:"hook_name"`
	}
	if err := json.Unmarshal(body, &probe); err != nil {
		return ""
	}
	return probe.HookName
}
