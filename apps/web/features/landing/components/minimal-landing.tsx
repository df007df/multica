"use client";

import { useConfigStore } from "@multica/core/config";
import { Button } from "@multica/ui/components/ui/button";
import Image from "next/image";

export function MinimalLanding() {
  const dingtalkClientId = useConfigStore((state) => state.dingtalkClientId);

  const handleDingTalkLogin = () => {
    if (!dingtalkClientId) return;
    const params = new URLSearchParams({
      redirect_uri: `${window.location.origin}/auth/callback`,
      response_type: "code",
      client_id: dingtalkClientId,
      scope: "openid",
      prompt: "consent",
    });
    params.set("state", "provider:dingtalk");
    window.location.href = `https://login.dingtalk.com/oauth2/auth?${params}`;
  };

  return (
    <div className="flex min-h-svh items-center justify-center">
      <div className="flex flex-col items-center gap-6">
        <Image
          src="/mofaAI.png"
          alt="魔法笔记"
          width={80}
          height={80}
          className="rounded-2xl"
          priority
        />
        <div className="flex flex-col items-center gap-1">
          <h1 className="text-2xl font-semibold tracking-tight">魔法笔记</h1>
          <p className="text-sm text-muted-foreground">钉钉扫码登录</p>
        </div>
        {dingtalkClientId ? (
          <Button
            onClick={handleDingTalkLogin}
            size="lg"
            className="gap-2"
          >
            <svg className="h-4 w-4" viewBox="0 0 24 24" fill="none">
              <path
                d="M12 2C6.477 2 2 6.477 2 12s4.477 10 10 10 10-4.477 10-10S17.523 2 12 2z"
                fill="#0089FF"
              />
              <path
                d="M16.5 9.5h-3.75l-1.5 5h3.75l1.5-5zM8.25 9.5H12l-1.5 5H6.75l1.5-5z"
                fill="#fff"
              />
            </svg>
            钉钉扫码登录
          </Button>
        ) : (
          <p className="text-sm text-muted-foreground">钉钉登录未配置</p>
        )}
      </div>
    </div>
  );
}
