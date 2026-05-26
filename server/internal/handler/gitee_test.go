package handler

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	db "github.com/multica-ai/multica/server/pkg/db/generated"
)

func TestIsGiteePullRequestWebhook(t *testing.T) {
	cases := []struct {
		event    string
		hookName string
		want     bool
	}{
		{event: "Merge Request Hook", want: true},
		{event: "merge_request_hooks", want: true},
		{event: "pull_request", want: true},
		{event: "merge_request", want: true},
		{hookName: "merge_request_hooks", want: true},
		{hookName: "pull_request_hooks", want: true},
		{event: "push", hookName: "push_hooks", want: false},
		{event: "Issue Hook", want: false},
	}
	for _, tc := range cases {
		if got := isGiteePullRequestWebhook(tc.event, tc.hookName); got != tc.want {
			t.Errorf("isGiteePullRequestWebhook(%q, %q) = %v, want %v", tc.event, tc.hookName, got, tc.want)
		}
	}
}

func TestResolveGiteeRepoFromPRPayload(t *testing.T) {
	t.Run("top_level_repository", func(t *testing.T) {
		var p giteeWebhookPRPayload
		p.Repository.Owner.Login = "acme"
		p.Repository.Name = "widget"
		owner, name := resolveGiteeRepoFromPRPayload(p)
		if owner != "acme" || name != "widget" {
			t.Fatalf("got %q/%q, want acme/widget", owner, name)
		}
	})

	t.Run("base_repo_path_with_namespace", func(t *testing.T) {
		var p giteeWebhookPRPayload
		p.PullRequest.Base.Repo.PathWithNamespace = "oschina/gitee"
		owner, name := resolveGiteeRepoFromPRPayload(p)
		if owner != "oschina" || name != "gitee" {
			t.Fatalf("got %q/%q, want oschina/gitee", owner, name)
		}
	})

	t.Run("base_repo_namespace_and_path", func(t *testing.T) {
		var p giteeWebhookPRPayload
		p.PullRequest.Base.Repo.Namespace = "myorg"
		p.PullRequest.Base.Repo.Path = "svc"
		owner, name := resolveGiteeRepoFromPRPayload(p)
		if owner != "myorg" || name != "svc" {
			t.Fatalf("got %q/%q, want myorg/svc", owner, name)
		}
	})

	t.Run("prefers_top_level_over_base", func(t *testing.T) {
		var p giteeWebhookPRPayload
		p.Repository.Owner.Login = "top"
		p.Repository.Name = "level"
		p.PullRequest.Base.Repo.PathWithNamespace = "base/repo"
		owner, name := resolveGiteeRepoFromPRPayload(p)
		if owner != "top" || name != "level" {
			t.Fatalf("got %q/%q, want top/level", owner, name)
		}
	})
}

func TestWorkspaceHasGiteeRepo(t *testing.T) {
	repos := []byte(`[{"url":"https://gitee.com/acme/widget.git"}]`)
	if !workspaceHasGiteeRepo(repos, "acme", "widget") {
		t.Fatal("expected match for https gitee URL")
	}
	if workspaceHasGiteeRepo(repos, "other", "widget") {
		t.Fatal("expected no match for wrong owner")
	}
}

// TestGiteeWebhook_MergedPR_AdvancesLinkedIssueToDone mirrors the GitHub
// merge-sync test using a gitee.com-style payload (merge_request_hooks,
// repo on pull_request.base.repo).
func TestGiteeWebhook_MergedPR_AdvancesLinkedIssueToDone(t *testing.T) {
	if testHandler == nil {
		t.Skip("handler test fixture not initialized (no DB?)")
	}
	ctx := context.Background()
	secret := "gitee-merge-sync-test-secret"
	t.Setenv("GITEE_WEBHOOK_SECRET", secret)

	w := httptest.NewRecorder()
	req := newRequest("POST", "/api/issues?workspace_id="+testWorkspaceID, map[string]any{
		"title":  "Gitee PR auto-merge test",
		"status": "in_progress",
	})
	testHandler.CreateIssue(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("CreateIssue: %d %s", w.Code, w.Body.String())
	}
	var created IssueResponse
	json.NewDecoder(w.Body).Decode(&created)

	reposJSON, _ := json.Marshal([]RepoData{{URL: "https://gitee.com/acme/widget.git"}})
	if _, err := testPool.Exec(ctx, `UPDATE workspace SET repos = $1 WHERE id = $2`, reposJSON, testWorkspaceID); err != nil {
		t.Fatalf("update workspace repos: %v", err)
	}

	t.Cleanup(func() {
		testPool.Exec(ctx, `DELETE FROM issue_gitee_pull_request WHERE issue_id = $1`, created.ID)
		testPool.Exec(ctx, `DELETE FROM gitee_pull_request WHERE workspace_id = $1`, testWorkspaceID)
		testPool.Exec(ctx, `DELETE FROM activity_log WHERE issue_id = $1`, created.ID)
		testPool.Exec(ctx, `DELETE FROM issue WHERE id = $1`, created.ID)
		testPool.Exec(ctx, `UPDATE workspace SET repos = $1 WHERE id = $2`, []byte("[]"), testWorkspaceID)
	})

	body := map[string]any{
		"hook_name": "merge_request_hooks",
		"action":    "merge",
		"pull_request": map[string]any{
			"number":        42,
			"html_url":      "https://gitee.com/acme/widget/pulls/42",
			"title":         "Fix login " + created.Identifier,
			"body":          "",
			"state":         "closed",
			"merged":        true,
			"merged_at":     "2026-04-29T00:00:00Z",
			"closed_at":     "2026-04-29T00:00:00Z",
			"created_at":    "2026-04-28T00:00:00Z",
			"updated_at":    "2026-04-29T00:00:00Z",
			"additions":     3,
			"deletions":     1,
			"changed_files": 2,
			"head": map[string]any{
				"ref": "fix/login-" + created.Identifier,
			},
			"base": map[string]any{
				"ref": "master",
				"repo": map[string]any{
					"name":                "widget",
					"path":                "widget",
					"namespace":           "acme",
					"path_with_namespace": "acme/widget",
					"owner":               map[string]any{"login": "acme"},
				},
			},
			"user": map[string]any{"login": "dev1", "avatar_url": ""},
		},
	}
	raw, _ := json.Marshal(body)

	w = httptest.NewRecorder()
	req2 := httptest.NewRequest("POST", "/api/webhooks/gitee", bytes.NewReader(raw))
	req2.Header.Set("X-Gitee-Event", "Merge Request Hook")
	req2.Header.Set("X-Gitee-Token", secret)
	testHandler.HandleGiteeWebhook(w, req2)
	if w.Code != http.StatusAccepted {
		t.Fatalf("webhook: expected 202, got %d (%s)", w.Code, w.Body.String())
	}

	pr, err := testHandler.Queries.GetGiteePullRequest(ctx, db.GetGiteePullRequestParams{
		WorkspaceID: parseUUID(testWorkspaceID),
		RepoOwner:   "acme",
		RepoName:    "widget",
		PrNumber:    42,
	})
	if err != nil {
		t.Fatalf("GetGiteePullRequest: %v", err)
	}
	if pr.State != "merged" {
		t.Errorf("expected pr state merged, got %q", pr.State)
	}

	linked, err := testHandler.Queries.ListGiteePullRequestsByIssue(ctx, parseUUID(created.ID))
	if err != nil {
		t.Fatalf("ListGiteePullRequestsByIssue: %v", err)
	}
	if len(linked) != 1 {
		t.Fatalf("expected 1 linked PR, got %d", len(linked))
	}

	updated, err := testHandler.Queries.GetIssue(ctx, parseUUID(created.ID))
	if err != nil {
		t.Fatalf("GetIssue: %v", err)
	}
	if updated.Status != "done" {
		t.Errorf("expected issue status 'done', got %q", updated.Status)
	}
}
