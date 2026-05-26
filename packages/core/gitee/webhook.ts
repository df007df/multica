export function buildGiteeWebhookUrl(apiBaseUrl: string, currentOrigin?: string): string {
  const base = stripTrailingSlash(apiBaseUrl) || stripTrailingSlash(currentOrigin ?? "");
  return base ? `${base}/api/webhooks/gitee` : "/api/webhooks/gitee";
}

function stripTrailingSlash(url: string): string {
  return url.replace(/\/+$/, "");
}
