export type GatewayStatusInput = {
  gateway?: {
    reachable?: boolean;
    error?: string | null;
  };
};

export type GatewaySignal = {
  reachable: "reachable" | "unreachable" | "unknown";
  error: string | null;
};

export function collectGatewaySignal(status: GatewayStatusInput): GatewaySignal {
  const error = status.gateway?.error?.trim();
  const reachable = status.gateway?.reachable;

  return {
    reachable:
      reachable === true ? "reachable" : reachable === false ? "unreachable" : "unknown",
    error: error ? error : null
  };
}
