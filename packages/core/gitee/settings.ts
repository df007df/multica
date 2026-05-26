import type { Workspace } from "../types";

export interface GiteeSettings {
  /** Master switch. When false, every UI affordance and side-effect is gated off. */
  enabled: boolean;
  /** Issue-detail PR sidebar visibility. Implies `enabled`. */
  prSidebar: boolean;
  /** Auto-link issues ↔ PRs from webhook payloads. Implies `enabled`. */
  autoLinkPRs: boolean;
}

/**
 * Pure derivation from a workspace's settings JSONB. Defaults every flag to
 * true so workspaces predating Gitee support keep the "all on" behavior
 * once Gitee is configured server-side.
 */
export function deriveGiteeSettings(
  workspace: Pick<Workspace, "settings"> | null | undefined,
): GiteeSettings {
  const s = (workspace?.settings ?? {}) as Record<string, unknown>;
  const enabled = s.gitee_enabled !== false;
  return {
    enabled,
    prSidebar: enabled && s.gitee_pr_sidebar_enabled !== false,
    autoLinkPRs: enabled && s.gitee_auto_link_prs_enabled !== false,
  };
}
