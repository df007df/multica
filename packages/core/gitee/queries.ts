import { queryOptions } from "@tanstack/react-query";
import { api } from "../api";

export const giteeKeys = {
  all: (wsId: string) => ["gitee", wsId] as const,
  connections: (wsId: string) => [...giteeKeys.all(wsId), "connections"] as const,
};

export const giteeConnectionsOptions = (wsId: string) =>
  queryOptions({
    queryKey: giteeKeys.connections(wsId),
    queryFn: () => api.listGiteeConnections(wsId),
    enabled: !!wsId,
  });
