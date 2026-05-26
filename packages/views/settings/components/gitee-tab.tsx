"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Link2, PanelRight } from "lucide-react";
import { Card, CardContent } from "@multica/ui/components/ui/card";
import { Label } from "@multica/ui/components/ui/label";
import { Switch } from "@multica/ui/components/ui/switch";
import { Button } from "@multica/ui/components/ui/button";
import { useAuthStore } from "@multica/core/auth";
import { useWorkspaceId } from "@multica/core/hooks";
import { useCurrentWorkspace } from "@multica/core/paths";
import { memberListOptions, workspaceKeys } from "@multica/core/workspace/queries";
import { deriveGiteeSettings, buildGiteeWebhookUrl } from "@multica/core/gitee";
import { api } from "@multica/core/api";
import type { Workspace } from "@multica/core/types";
import { useNavigation } from "../../navigation";
import { useT } from "../../i18n";
import { GiteeMark } from "./gitee-mark";

type SettingsKey =
  | "gitee_enabled"
  | "gitee_pr_sidebar_enabled"
  | "gitee_auto_link_prs_enabled";

export function GiteeTab() {
  const { t } = useT("settings");
  const workspace = useCurrentWorkspace();
  const wsId = useWorkspaceId();
  const qc = useQueryClient();
  const navigation = useNavigation();
  const user = useAuthStore((s) => s.user);

  const { data: members = [] } = useQuery(memberListOptions(wsId));
  const currentMember = members.find((m) => m.user_id === user?.id) ?? null;
  const canManage = currentMember?.role === "owner" || currentMember?.role === "admin";

  const { data: appConfig } = useQuery({
    queryKey: ["app-config"],
    queryFn: () => api.getConfig(),
    staleTime: 60_000,
  });
  const configured = appConfig?.gitee_enabled === true;

  const flags = deriveGiteeSettings(workspace);
  const [savingKey, setSavingKey] = useState<SettingsKey | null>(null);

  const repositoriesHref = `${navigation.pathname}?tab=repositories`;
  const webhookUrl = buildGiteeWebhookUrl(api.getBaseUrl(), typeof window !== "undefined" ? window.location.origin : undefined);

  async function persistSetting(key: SettingsKey, next: boolean) {
    if (!workspace || savingKey) return;
    setSavingKey(key);
    try {
      const merged = {
        ...((workspace.settings as Record<string, unknown>) ?? {}),
        [key]: next,
      };
      const updated = await api.updateWorkspace(workspace.id, { settings: merged });
      qc.setQueryData(workspaceKeys.list(), (old: Workspace[] | undefined) =>
        old?.map((ws) => (ws.id === updated.id ? updated : ws)),
      );
    } catch (e) {
      toast.error(e instanceof Error ? e.message : t(($) => $.gitee.toast_failed));
    } finally {
      setSavingKey(null);
    }
  }

  if (!workspace) return null;

  return (
    <div className="space-y-8">
      <section className="space-y-1">
        <p className="text-sm text-muted-foreground">
          {t(($) => $.gitee.page_description)}
        </p>
      </section>

      <section className="space-y-3">
        <Card>
          <CardContent>
            <div className="flex items-start justify-between gap-4">
              <div className="flex items-start gap-3">
                <div className="rounded-md border bg-muted/50 p-2 text-muted-foreground">
                  <GiteeMark className="h-4 w-4" />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="gitee-master" className="text-sm font-medium">
                    {t(($) => $.gitee.section_master)}
                  </Label>
                  <p className="text-sm text-muted-foreground">
                    {flags.enabled
                      ? t(($) => $.gitee.master_description_on)
                      : t(($) => $.gitee.master_description_off)}
                  </p>
                </div>
              </div>
              <Switch
                id="gitee-master"
                checked={flags.enabled}
                onCheckedChange={(v) => persistSetting("gitee_enabled", v)}
                disabled={!canManage || savingKey === "gitee_enabled"}
              />
            </div>
          </CardContent>
        </Card>
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold">{t(($) => $.gitee.section_webhook)}</h2>
        <Card>
          <CardContent className="space-y-4">
            <div className="flex items-start gap-3">
              <GiteeMark className="h-6 w-6 mt-0.5 shrink-0" />
              <div className="space-y-3">
                <div className="space-y-1">
                  <p className="text-sm font-medium">{t(($) => $.gitee.webhook_title)}</p>
                  <p className="text-xs text-muted-foreground">
                    {t(($) => $.gitee.webhook_description)}
                  </p>
                </div>
                <div className="space-y-1">
                  <p className="text-xs font-medium text-muted-foreground">
                    {t(($) => $.gitee.webhook_url_label)}
                  </p>
                  <code className="block rounded bg-muted px-2 py-1.5 text-xs break-all">
                    {webhookUrl}
                  </code>
                </div>
                {canManage && !configured && (
                  <p className="text-xs text-muted-foreground">
                    {t(($) => $.gitee.not_configured)}{" "}
                    <code className="rounded bg-muted px-1 py-0.5 text-[10px]">GITEE_WEBHOOK_SECRET</code>.
                  </p>
                )}
                {canManage && configured && (
                  <p className="text-xs text-muted-foreground">
                    {t(($) => $.gitee.webhook_secret_hint)}
                  </p>
                )}
              </div>
            </div>
          </CardContent>
        </Card>
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold">{t(($) => $.gitee.section_repositories)}</h2>
        <Card>
          <CardContent>
            <div className="flex items-start justify-between gap-4">
              <div className="space-y-1">
                <p className="text-sm font-medium">{t(($) => $.gitee.repositories_shortcut_label)}</p>
                <p className="text-xs text-muted-foreground">
                  {t(($) => $.gitee.repositories_shortcut_description)}
                </p>
              </div>
              {canManage && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => navigation.push(repositoriesHref)}
                >
                  {t(($) => $.gitee.repositories_shortcut_link)}
                </Button>
              )}
            </div>
          </CardContent>
        </Card>
      </section>

      <section className="space-y-3">
        <h2 className="text-sm font-semibold">{t(($) => $.gitee.section_features)}</h2>
        <Card>
          <CardContent className="space-y-4">
            <FeatureRow
              id="gitee-pr-sidebar"
              icon={<PanelRight className="h-4 w-4" />}
              label={t(($) => $.gitee.feature_pr_sidebar_label)}
              description={
                <p className="text-sm text-muted-foreground">
                  {t(($) => $.gitee.feature_pr_sidebar_description)}
                </p>
              }
              checked={flags.prSidebar}
              disabled={!canManage || !flags.enabled || savingKey === "gitee_pr_sidebar_enabled"}
              onCheckedChange={(v) => persistSetting("gitee_pr_sidebar_enabled", v)}
            />

            <FeatureRow
              id="gitee-auto-link"
              icon={<Link2 className="h-4 w-4" />}
              label={t(($) => $.gitee.feature_auto_link_label)}
              description={
                <p className="text-sm text-muted-foreground">
                  {t(($) => $.gitee.feature_auto_link_description)}
                </p>
              }
              checked={flags.autoLinkPRs}
              disabled={!canManage || !flags.enabled || savingKey === "gitee_auto_link_prs_enabled"}
              onCheckedChange={(v) => persistSetting("gitee_auto_link_prs_enabled", v)}
            />
          </CardContent>
        </Card>
      </section>
    </div>
  );
}

function FeatureRow({
  id,
  icon,
  label,
  description,
  checked,
  disabled,
  onCheckedChange,
}: {
  id: string;
  icon: React.ReactNode;
  label: string;
  description: React.ReactNode;
  checked: boolean;
  disabled: boolean;
  onCheckedChange: (v: boolean) => void;
}) {
  return (
    <div className="flex items-start justify-between gap-4">
      <div className="flex items-start gap-3">
        <div className="rounded-md border bg-muted/50 p-2 text-muted-foreground">{icon}</div>
        <div className="space-y-1">
          <Label htmlFor={id} className="text-sm font-medium">
            {label}
          </Label>
          {description}
        </div>
      </div>
      <Switch
        id={id}
        checked={checked}
        disabled={disabled}
        onCheckedChange={onCheckedChange}
      />
    </div>
  );
}
