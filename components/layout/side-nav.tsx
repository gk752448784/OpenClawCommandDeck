"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const groups = [
  {
    title: "Observe",
    description: "观察",
    links: [
      { href: "/workbench", label: "工作台" },
      { href: "/alerts", label: "告警" }
    ]
  },
  {
    title: "Act",
    description: "处置",
    links: [
      { href: "/control", label: "控制" },
      { href: "/sessions", label: "会话" }
    ]
  },
  {
    title: "Operate",
    description: "运行",
    links: [
      { href: "/channels", label: "渠道" },
      { href: "/cron", label: "任务" },
      { href: "/agents", label: "代理" }
    ]
  },
  {
    title: "Configure",
    description: "配置",
    links: [
      { href: "/models", label: "模型" },
      { href: "/settings", label: "设置" },
      { href: "/diagnostics", label: "诊断" }
    ]
  }
];

function isActiveLink(pathname: string, href: string) {
  return pathname === href || pathname.startsWith(`${href}/`);
}

export function SideNav() {
  const pathname = usePathname();

  return (
    <aside className="side-nav">
      <div className="side-nav-intro">
        <div className="side-nav-brand">
          <span className="brand-kicker">OpenClaw</span>
          <strong>Command Deck</strong>
          <p>本地 AI 编排与运维</p>
        </div>
        <p className="side-nav-note">以姿态、告警和高频操作为中心的本地控制台。</p>
      </div>
      <div className="side-nav-status">
        <span className="side-nav-status-dot" />
        <span>Local instance connected</span>
      </div>
      <nav className="side-nav-groups">
        {groups.map((group) => (
          <div key={group.title} className="side-nav-group">
            <p className="side-nav-group-title">
              <span>{group.title}</span>
              <small>{group.description}</small>
            </p>
            <div className="side-nav-group-links">
              {group.links.map((link) => {
                const active = isActiveLink(pathname, link.href);

                return (
                  <Link
                    key={link.href}
                    href={link.href}
                    aria-current={active ? "page" : undefined}
                    className={`side-nav-link${active ? " side-nav-link-active" : ""}`}
                  >
                    {link.label}
                  </Link>
                );
              })}
            </div>
          </div>
        ))}
      </nav>
    </aside>
  );
}
