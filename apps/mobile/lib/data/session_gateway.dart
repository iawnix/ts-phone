import '../models/workspace.dart';

abstract interface class SessionManagementGateway {
  Future<SessionSummary> createSession();
  Future<void> removeSession(String sessionId);
}

abstract interface class WorkspaceManagementGateway {
  Future<WorkspaceSummary> createWorkspace(String workspaceId);
}

abstract interface class WorkspaceSessionGateway {
  Future<SessionSummary> createWorkspaceSession(String workspaceId);
  Future<void> removeWorkspaceSession(String workspaceId, String sessionId);
}

abstract interface class SessionResumeGateway {
  Future<SessionSummary> resumeWorkspaceSession(
    String workspaceId,
    String sessionId,
  );
}

extension WorkspaceSessionManagement on SessionManagementGateway {
  Future<SessionSummary> createWorkspaceSession(String workspaceId) {
    final gateway = this;
    return gateway is WorkspaceSessionGateway
        ? gateway.createWorkspaceSession(workspaceId)
        : gateway.createSession();
  }

  Future<void> removeWorkspaceSession(String workspaceId, String sessionId) {
    final gateway = this;
    return gateway is WorkspaceSessionGateway
        ? gateway.removeWorkspaceSession(workspaceId, sessionId)
        : gateway.removeSession(sessionId);
  }
}
