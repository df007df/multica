package handler

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgtype"
	db "github.com/multica-ai/multica/server/pkg/db/generated"
	"github.com/multica-ai/multica/server/pkg/protocol"
)

// GiteePullRequestResponse mirrors GitHubPullRequestResponse but omits
// GitHub-specific fields (mergeable_state, checks_*). The frontend
// PullRequestList component already handles nil/missing fields gracefully.
type GiteePullRequestResponse struct {
	ID              string  `json:"id"`
	WorkspaceID     string  `json:"workspace_id"`
	Provider        string  `json:"provider"`
	RepoOwner       string  `json:"repo_owner"`
	RepoName        string  `json:"repo_name"`
	Number          int32   `json:"number"`
	Title           string  `json:"title"`
	State           string  `json:"state"`
	HtmlURL         string  `json:"html_url"`
	Branch          *string `json:"branch"`
	AuthorLogin     *string `json:"author_login"`
	AuthorAvatarURL *string `json:"author_avatar_url"`
	MergedAt        *string `json:"merged_at"`
	ClosedAt        *string `json:"closed_at"`
	PRCreatedAt     string  `json:"pr_created_at"`
	PRUpdatedAt     string  `json:"pr_updated_at"`
	MergeableState  *string `json:"mergeable_state"`
	ChecksPassed    int64   `json:"checks_passed"`
	ChecksFailed    int64   `json:"checks_failed"`
	ChecksPending   int64   `json:"checks_pending"`
	Additions       int32   `json:"additions"`
	Deletions       int32   `json:"deletions"`
	ChangedFiles    int32   `json:"changed_files"`
}

func giteePullRequestToResponse(p db.GiteePullRequest) GiteePullRequestResponse {
	return GiteePullRequestResponse{
		ID:              uuidToString(p.ID),
		WorkspaceID:     uuidToString(p.WorkspaceID),
		Provider:        "gitee",
		RepoOwner:       p.RepoOwner,
		RepoName:        p.RepoName,
		Number:          p.PrNumber,
		Title:           p.Title,
		State:           p.State,
		HtmlURL:         p.HtmlUrl,
		Branch:          textToPtr(p.Branch),
		AuthorLogin:     textToPtr(p.AuthorLogin),
		AuthorAvatarURL: textToPtr(p.AuthorAvatarUrl),
		MergedAt:        timestampToPtr(p.MergedAt),
		ClosedAt:        timestampToPtr(p.ClosedAt),
		PRCreatedAt:     timestampToString(p.PrCreatedAt),
		PRUpdatedAt:     timestampToString(p.PrUpdatedAt),
		Additions:       p.Additions,
		Deletions:       p.Deletions,
		ChangedFiles:    p.ChangedFiles,
	}
}

// giteePullRequestToGitHubResponse converts a Gitee PR row into the unified
// GitHubPullRequestResponse shape so ListPullRequestsForIssue can return a
// single merged array with a provider discriminator.
func giteePullRequestToGitHubResponse(p db.GiteePullRequest) GitHubPullRequestResponse {
	return GitHubPullRequestResponse{
		ID:              uuidToString(p.ID),
		WorkspaceID:     uuidToString(p.WorkspaceID),
		Provider:        "gitee",
		RepoOwner:       p.RepoOwner,
		RepoName:        p.RepoName,
		Number:          p.PrNumber,
		Title:           p.Title,
		State:           p.State,
		HtmlURL:         p.HtmlUrl,
		Branch:          textToPtr(p.Branch),
		AuthorLogin:     textToPtr(p.AuthorLogin),
		AuthorAvatarURL: textToPtr(p.AuthorAvatarUrl),
		MergedAt:        timestampToPtr(p.MergedAt),
		ClosedAt:        timestampToPtr(p.ClosedAt),
		PRCreatedAt:     timestampToString(p.PrCreatedAt),
		PRUpdatedAt:     timestampToString(p.PrUpdatedAt),
		Additions:       p.Additions,
		Deletions:       p.Deletions,
		ChangedFiles:    p.ChangedFiles,
	}
}

func giteeWebhookSecret() string {
	return strings.TrimSpace(os.Getenv("GITEE_WEBHOOK_SECRET"))
}

// ── HandleGiteeWebhook (POST /api/webhooks/gitee) ───────────────────────────

func (h *Handler) HandleGiteeWebhook(w http.ResponseWriter, r *http.Request) {
	secret := giteeWebhookSecret()
	if secret == "" {
		writeError(w, http.StatusServiceUnavailable, "gitee webhooks not configured")
		return
	}

	body, err := io.ReadAll(io.LimitReader(r.Body, 10<<20))
	if err != nil {
		slog.Warn("gitee: read webhook body failed", "err", err)
		w.WriteHeader(http.StatusBadRequest)
		return
	}

	// Verify webhook password via X-Gitee-Token header
	token := r.Header.Get("X-Gitee-Token")
	if token != secret {
		slog.Warn("gitee: webhook token mismatch")
		w.WriteHeader(http.StatusUnauthorized)
		return
	}

	event := r.Header.Get("X-Gitee-Event")
	switch event {
	case "ping":
		writeJSON(w, http.StatusOK, map[string]string{"ok": "pong"})
		return
	case "pull_request":
		h.handleGiteePullRequestEvent(r.Context(), body)
	case "merge_request":
		// Gitee enterprise may use this alias
		h.handleGiteePullRequestEvent(r.Context(), body)
	default:
		slog.Debug("gitee: unhandled webhook event", "event", event)
	}

	w.WriteHeader(http.StatusAccepted)
}

// ── Webhook payload types ────────────────────────────────────────────────────

type giteeWebhookPRPayload struct {
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
			Ref string `json:"ref"`
		} `json:"head"`
		Base struct {
			Ref string `json:"ref"`
		} `json:"base"`
		User struct {
			Login     string `json:"login"`
			AvatarURL string `json:"avatar_url"`
		} `json:"user"`
	} `json:"pull_request"`
	Repository struct {
		Name  string `json:"name"`
		Owner struct {
			Login string `json:"login"`
		} `json:"owner"`
	} `json:"repository"`
}

func (h *Handler) handleGiteePullRequestEvent(ctx context.Context, body []byte) {
	var p giteeWebhookPRPayload
	if err := json.Unmarshal(body, &p); err != nil {
		slog.Warn("gitee: bad pull_request payload", "err", err)
		return
	}

	repoOwner := p.Repository.Owner.Login
	repoName := p.Repository.Name
	if repoOwner == "" || repoName == "" {
		return
	}

	wsUUID, ok := h.findWorkspaceForGiteeRepo(ctx, repoOwner, repoName)
	if !ok {
		return
	}

	state := deriveGiteePRState(p.PullRequest.State, p.PullRequest.Merged)
	pr, err := h.Queries.UpsertGiteePullRequest(ctx, db.UpsertGiteePullRequestParams{
		WorkspaceID:     wsUUID,
		RepoOwner:       repoOwner,
		RepoName:        repoName,
		PrNumber:        p.PullRequest.Number,
		Title:           p.PullRequest.Title,
		State:           state,
		HtmlUrl:         p.PullRequest.HTMLURL,
		Branch:          ptrToText(strPtrOrNil(p.PullRequest.Head.Ref)),
		AuthorLogin:     ptrToText(strPtrOrNil(p.PullRequest.User.Login)),
		AuthorAvatarUrl: ptrToText(strPtrOrNil(p.PullRequest.User.AvatarURL)),
		MergedAt:        parseGHTime(p.PullRequest.MergedAt),
		ClosedAt:        parseGHTime(p.PullRequest.ClosedAt),
		PrCreatedAt:     parseGHTimeRequired(p.PullRequest.CreatedAt),
		PrUpdatedAt:     parseGHTimeRequired(p.PullRequest.UpdatedAt),
		Additions:       p.PullRequest.Additions,
		Deletions:       p.PullRequest.Deletions,
		ChangedFiles:    p.PullRequest.ChangedFiles,
	})
	if err != nil {
		slog.Warn("gitee: upsert pr failed", "err", err)
		return
	}

	workspaceID := uuidToString(wsUUID)
	resp := giteePullRequestToResponse(pr)

	// Auto-link to issues
	linkedIssueIDs := make([]string, 0)
	if h.workspaceGiteeAutoLinkPRsEnabled(ctx, wsUUID) {
		idents := extractIdentifiers(p.PullRequest.Title, p.PullRequest.Body, p.PullRequest.Head.Ref)
		prefix := h.getIssuePrefix(ctx, wsUUID)
		for _, id := range idents {
			issue, issueOk := h.lookupIssueByIdentifier(ctx, wsUUID, prefix, id)
			if !issueOk {
				continue
			}
			if err := h.Queries.LinkIssueToGiteePullRequest(ctx, db.LinkIssueToGiteePullRequestParams{
				IssueID:       issue.ID,
				PullRequestID: pr.ID,
				LinkedByType:  strToText("system"),
				LinkedByID:    pgtype.UUID{},
			}); err != nil {
				slog.Warn("gitee: link failed", "err", err)
				continue
			}
			linkedIssueIDs = append(linkedIssueIDs, uuidToString(issue.ID))

			if (state == "merged" || state == "closed") && issue.Status != "done" && issue.Status != "cancelled" {
				counts, err := h.Queries.GetSiblingGiteePullRequestStateCountsForIssue(ctx, db.GetSiblingGiteePullRequestStateCountsForIssueParams{
					IssueID: issue.ID,
					ID:      pr.ID,
				})
				if err != nil {
					slog.Warn("gitee: count sibling pr states failed", "err", err, "issue_id", uuidToString(issue.ID))
					continue
				}
				anyMerged := state == "merged" || counts.MergedCount > 0
				allClosed := counts.OpenCount == 0
				if allClosed && anyMerged {
					h.advanceIssueToDone(ctx, issue, workspaceID)
				}
			}
		}
	}

	// Broadcast PR updated event
	h.publish(protocol.EventPullRequestUpdated, workspaceID, "system", "", map[string]any{
		"pull_request":     resp,
		"linked_issue_ids": linkedIssueIDs,
		"provider":         "gitee",
	})

	// Also broadcast per-linked-issue
	for _, issueID := range linkedIssueIDs {
		h.publish(protocol.EventPullRequestLinked, workspaceID, "system", "", map[string]any{
			"pull_request": resp,
			"issue_id":     issueID,
			"provider":     "gitee",
		})
	}
}

func deriveGiteePRState(state string, merged bool) string {
	if merged {
		return "merged"
	}
	switch state {
	case "closed":
		return "closed"
	case "open":
		return "open"
	default:
		return "open"
	}
}

// workspaceGiteeAutoLinkPRsEnabled checks workspace settings for
// gitee_enabled and gitee_auto_link_prs_enabled. Defaults to true.
func (h *Handler) workspaceGiteeAutoLinkPRsEnabled(ctx context.Context, workspaceID pgtype.UUID) bool {
	ws, err := h.Queries.GetWorkspace(ctx, workspaceID)
	if err != nil || len(ws.Settings) == 0 {
		return true
	}
	var s struct {
		GiteeEnabled            *bool `json:"gitee_enabled"`
		GiteeAutoLinkPRsEnabled *bool `json:"gitee_auto_link_prs_enabled"`
	}
	if err := json.Unmarshal(ws.Settings, &s); err != nil {
		return true
	}
	if s.GiteeEnabled != nil && !*s.GiteeEnabled {
		return false
	}
	if s.GiteeAutoLinkPRsEnabled == nil {
		return true
	}
	return *s.GiteeAutoLinkPRsEnabled
}

// findWorkspaceForGiteeRepo locates the workspace whose configured repository
// URLs match the given Gitee owner/name.
func (h *Handler) findWorkspaceForGiteeRepo(ctx context.Context, repoOwner, repoName string) (pgtype.UUID, bool) {
	rows, err := h.Queries.ListWorkspacesWithRepos(ctx)
	if err != nil {
		return pgtype.UUID{}, false
	}
	for _, row := range rows {
		if workspaceHasGiteeRepo(row.Repos, repoOwner, repoName) {
			return row.ID, true
		}
	}
	return pgtype.UUID{}, false
}

// workspaceHasGiteeRepo checks the workspace repos JSON for a Gitee repo URL
// matching the given owner/name. Gitee repo URLs look like:
//
//	https://gitee.com/owner/repo.git
//	https://gitee.com/owner/repo
//	git@gitee.com:owner/repo.git
func workspaceHasGiteeRepo(repos []byte, owner, name string) bool {
	if len(repos) == 0 {
		return false
	}
	var repoList []RepoData
	if err := json.Unmarshal(repos, &repoList); err != nil {
		return false
	}
	for _, r := range repoList {
		if strings.Contains(r.URL, "gitee.com/"+owner+"/"+name) ||
			strings.Contains(r.URL, "gitee.com:"+owner+"/"+name) {
			return true
		}
	}
	return false
}
