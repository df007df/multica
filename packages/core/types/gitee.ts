export interface GiteeConnection {
  id: string;
  workspace_id: string;
  gitee_user_id: string;
  gitee_login: string;
  gitee_avatar_url: string | null;
  created_at: string;
}

export interface ListGiteeConnectionsResponse {
  connections: GiteeConnection[];
  configured: boolean;
  can_manage?: boolean;
}

export interface GiteeConnectResponse {
  url?: string;
  configured: boolean;
}
