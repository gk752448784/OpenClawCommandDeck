import path from "node:path";
import { copyFile, mkdir, readdir, readFile, stat, writeFile } from "node:fs/promises";

import { OPENCLAW_ROOT } from "@/lib/config";

const BACKUP_ROOT = path.join(OPENCLAW_ROOT, "commanddeck-backups");
const SNAPSHOT_ID_RE = /^\d{8}T\d{6}Z$/;
const BACKUP_FILE_PATHS = ["openclaw.json", "cron/jobs.json", "workspace/HEARTBEAT.md"] as const;

type BackupMetadata = {
  id: string;
  createdAt: string;
  files: string[];
};

export type ServiceBackupItem = {
  id: string;
  createdAt: string;
  fileCount: number;
};

function nextSnapshotId() {
  return new Date().toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

function backupPathFor(id: string) {
  return path.join(BACKUP_ROOT, id);
}

async function fileExists(filePath: string) {
  try {
    const info = await stat(filePath);
    return info.isFile();
  } catch {
    return false;
  }
}

export async function listServiceBackups(): Promise<ServiceBackupItem[]> {
  try {
    const entries = await readdir(BACKUP_ROOT, { withFileTypes: true });
    const backups: ServiceBackupItem[] = [];
    for (const entry of entries) {
      if (!entry.isDirectory() || !SNAPSHOT_ID_RE.test(entry.name)) {
        continue;
      }
      const metadataPath = path.join(BACKUP_ROOT, entry.name, "metadata.json");
      try {
        const metadata = JSON.parse(await readFile(metadataPath, "utf8")) as BackupMetadata;
        backups.push({
          id: metadata.id,
          createdAt: metadata.createdAt,
          fileCount: metadata.files.length
        });
      } catch {
        backups.push({
          id: entry.name,
          createdAt: new Date().toISOString(),
          fileCount: 0
        });
      }
    }

    return backups.sort((left, right) => right.id.localeCompare(left.id));
  } catch {
    return [];
  }
}

export async function createServiceBackup() {
  const id = nextSnapshotId();
  const snapshotPath = backupPathFor(id);
  await mkdir(snapshotPath, { recursive: true });

  const backedUpFiles: string[] = [];
  for (const relativePath of BACKUP_FILE_PATHS) {
    const source = path.join(OPENCLAW_ROOT, relativePath);
    if (!(await fileExists(source))) {
      continue;
    }
    const destination = path.join(snapshotPath, relativePath);
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(source, destination);
    backedUpFiles.push(relativePath);
  }

  const metadata: BackupMetadata = {
    id,
    createdAt: new Date().toISOString(),
    files: backedUpFiles
  };
  await writeFile(
    path.join(snapshotPath, "metadata.json"),
    `${JSON.stringify(metadata, null, 2)}\n`,
    "utf8"
  );

  return {
    id,
    createdAt: metadata.createdAt,
    files: backedUpFiles
  };
}

export async function restoreServiceBackup(backupId: string) {
  if (!SNAPSHOT_ID_RE.test(backupId)) {
    throw new Error("备份 ID 非法");
  }

  const snapshotPath = backupPathFor(backupId);
  const metadata = JSON.parse(
    await readFile(path.join(snapshotPath, "metadata.json"), "utf8")
  ) as BackupMetadata;

  for (const relativePath of metadata.files) {
    const source = path.join(snapshotPath, relativePath);
    const destination = path.join(OPENCLAW_ROOT, relativePath);
    await mkdir(path.dirname(destination), { recursive: true });
    await copyFile(source, destination);
  }

  return {
    id: metadata.id,
    restoredFiles: metadata.files
  };
}
