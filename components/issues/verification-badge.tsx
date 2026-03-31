import type { VerificationStatus } from "@/lib/types/issues";

function labelForStatus(status: VerificationStatus) {
  switch (status) {
    case "resolved":
      return "已恢复";
    case "partially_resolved":
      return "部分恢复";
    default:
      return "待验证";
  }
}

function classNameForStatus(status: VerificationStatus) {
  switch (status) {
    case "resolved":
      return "status-healthy";
    case "partially_resolved":
      return "status-warning";
    default:
      return "status-critical";
  }
}

export function VerificationBadge({ status }: { status: VerificationStatus }) {
  return (
    <span className={`status-badge ${classNameForStatus(status)}`}>
      <span className="status-dot" />
      {labelForStatus(status)}
    </span>
  );
}
