import {
  buildGatewayRestartCommand,
  buildSwitchModelCommand,
  buildToggleChannelCommand,
  buildTogglePluginCommand,
  type CliCommand
} from "@/lib/control/commands";
import type { IssueSignals } from "@/lib/server/load-dashboard-data";
import type { Issue } from "@/lib/types/issues";

function pluginIdForScope(signals: IssueSignals, scope: string) {
  return signals.channels.find((channel) => channel.channelId === scope)?.pluginId ?? scope;
}

function preferredCandidateModel(signals: IssueSignals) {
  return signals.models.candidateModelKeys.find(
    (candidate) => candidate !== signals.models.primaryModelKey
  ) ?? null;
}

export function resolveRepairCommand(issue: Issue, signals: IssueSignals): CliCommand | null {
  switch (issue.rootCause.type) {
    case "channel_disabled":
      return buildToggleChannelCommand(issue.rootCause.evidence.impactScope, true);
    case "plugin_disabled":
      return buildTogglePluginCommand(pluginIdForScope(signals, issue.rootCause.evidence.impactScope), true);
    case "channel_plugin_mismatch":
      return buildTogglePluginCommand(pluginIdForScope(signals, issue.rootCause.evidence.impactScope), true);
    case "primary_model_missing":
    case "primary_model_unavailable": {
      const candidate = preferredCandidateModel(signals);
      return candidate ? buildSwitchModelCommand(candidate) : null;
    }
    case "gateway_unreachable":
    case "gateway_restart_required":
      return buildGatewayRestartCommand();
    default:
      return null;
  }
}
