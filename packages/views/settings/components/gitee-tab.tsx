"use client";

import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { Link2, PanelRight } from "lucide-react";
import { Card, CardContent } from "@multica/ui/components/ui/card";
import { Label } from "@multica/ui/components/ui/label";
import { Switch } from "@multica/ui/components/ui/switch";
import { Button } from "@multica/ui/components/ui/button";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@multica/ui/components/ui/alert-dialog";
import { useAuthStore } from "@multica/core/auth";
import { useWorkspaceId } from "@multica/core/hooks";
import { useCurrentWorkspace } from "@multica/core/paths";
import { memberListOptions, workspaceKeys } from "@multica/core/workspace/queries";
import { deriveGiteeSettings, buildGiteeWebhookUrl, giteeConnectionsOptions } from "@multica/core/gitee";
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
  const oauthConfigured = appConfig?.gitee_oauth_configured === true;

  const { data: connectionData } = useQuery(giteeConnectionsOptions(wsId));
  const connections = connectionData?.connections ?? [];

  const flags = deriveGiteeSettings(workspace);
  const [savingKey, setSavingKey] = useState<SettingsKey | null>(null);
  const [connecting, setConnecting] = useState(false);
  const [disconnectingId, setDisconnectingId] = useState<string | null>(null);
  const [disconnectTarget, setDisconnectTarget] = useState<string | null>(null);

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

  async function handleConnect() {
    if (!wsId || connecting) return;
    setConnecting(true);
    try {
      const resp = await api.getGiteeConnectURL(wsId);
      if (!resp.configured) {
        toast.error(t(($) => $.gitee.toast_not_configured));
        return;
      }
      if (resp.url) {
        window.open(resp.url, "_blank", "noopener");
      }
    } catch {
      toast.error(t(($) => $.gitee.toast_open_failed));
    } finally {
      setConnecting(false);
    }
  }

  async function handleDisconnect() {
    if (!wsId || !disconnectTarget || disconnectingId) return;
    setDisconnectingId(disconnectTarget);
    try {
      await api.deleteGiteeConnection(wsId, disconnectTarget);
      qc.invalidateQueries({ queryKey: giteeConnectionsOptions(wsId).queryKey });
      toast.success(t(($) => $.gitee.toast_disconnected));
    } catch {
      toast.error(t(($) => $.gitee.toast_disconnect_failed));
    } finally {
      setDisconnectingId(null);
      setDisconnectTarget(null);
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
        <h2 className="text-sm font-semibold">{t(($) => $.gitee.section_connection)}</h2>
        <Card>
          <CardContent className="space-y-4">
            <div className="flex items-start gap-3">
              <GiteeMark className="h-6 w-6 mt-0.5 shrink-0" />
              <div className="space-y-3 flex-1">
                <div className="space-y-1">
                  <p className="text-sm font-medium">{t(($) => $.gitee.connection_title)}</p>
                  <p className="text-xs text-muted-foreground">
                    {t(($) => $.gitee.connection_description)}
                  </p>
                </div>

                {connections.length > 0 ? (
                  <div className="space-y-2">
                    {connections.map((c) => (
                      <div key={c.id} className="flex items-center justify-between rounded-md border bg-muted/30 px-3 py-2">
                        <div className="flex items-center gap-2">
                          {c.gitee_avatar_url && (
                            <img
                              src={c.gitee_avatar_url}
                              alt=""
                              className="h-5 w-5 rounded-full"
                            />
                          )}
                          <span className="text-sm">
                            {t(($) => $.gitee.connected_to, { login: c.gitee_login })}
                          </span>
                        </div>
                        {canManage && (
                          <Button
                            variant="ghost"
                            size="sm"
                            disabled={disconnectingId === c.id}
                            onClick={() => setDisconnectTarget(c.id)}
                          >
                            {disconnectingId === c.id
                              ? t(($) => $.gitee.disconnecting)
                              : t(($) => $.gitee.disconnect)}
                          </Button>
                        )}
                      </div>
                    ))}
                  </div>
                ) : canManage ? (
                  <div>
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={!oauthConfigured || connecting}
                      onClick={handleConnect}
                      title={!oauthConfigured ? t(($) => $.gitee.connect_disabled_tooltip) : undefined}
                    >
                      {connecting ? t(($) => $.gitee.connect_opening) : t(($) => $.gitee.connect_gitee)}
                    </Button>
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground">
                    {t(($) => $.gitee.contact_admin_to_connect)}
                  </p>
                )}

                {canManage && !oauthConfigured && (
                  <p className="text-xs text-muted-foreground">
                    {t(($) => $.gitee.not_configured)}{" "}
                    <code className="rounded bg-muted px-1 py-0.5 text-[10px]">GITEE_CLIENT_ID</code>{" "}
                    {t(($) => $.gitee.not_configured_and)}{" "}
                    <code className="rounded bg-muted px-1 py-0.5 text-[10px]">GITEE_CLIENT_SECRET</code>.
                  </p>
                )}

                {!canManage && (
                  <p className="text-xs text-muted-foreground">{t(($) => $.gitee.read_only_hint)}</p>
                )}
              </div>
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

      <AlertDialog open={!!disconnectTarget} onOpenChange={(open) => !open && setDisconnectTarget(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t(($) => $.gitee.disconnect_confirm_title)}</AlertDialogTitle>
            <AlertDialogDescription>
              {t(($) => $.gitee.disconnect_confirm_description)}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t(($) => $.gitee.disconnect_confirm_cancel)}</AlertDialogCancel>
            <AlertDialogAction onClick={handleDisconnect}>
              {t(($) => $.gitee.disconnect_confirm_action)}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
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
