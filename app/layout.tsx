import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "OpenClaw 工作台",
  description: "替代 OpenClaw 原生面板的中文工作台与控制台"
};

export default function RootLayout({
  children
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>
        <div className="app-root">{children}</div>
      </body>
    </html>
  );
}
