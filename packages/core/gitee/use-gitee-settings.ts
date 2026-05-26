"use client";

import { useMemo } from "react";
import { useCurrentWorkspace } from "../paths";
import { deriveGiteeSettings, type GiteeSettings } from "./settings";

/**
 * Reads the Gitee feature flags off the current workspace's settings JSONB.
 * Components downstream should consult this hook rather than poking at
 * `workspace.settings` directly, so the per-flag fallback semantics
 * (see deriveGiteeSettings) stay consistent.
 */
export function useGiteeSettings(): GiteeSettings {
  const workspace = useCurrentWorkspace();
  return useMemo(() => deriveGiteeSettings(workspace), [workspace]);
}
