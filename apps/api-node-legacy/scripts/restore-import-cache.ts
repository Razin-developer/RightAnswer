import { copyFile, mkdir, readdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

async function listVersionDirs(rootDir: string) {
  const subjectDirs = await readdir(rootDir, { withFileTypes: true });
  const versionDirs: Array<{ subjectCode: string; medium: string; versionLabel: string; rawPdfPath: string }> = [];

  for (const subjectDir of subjectDirs) {
    if (!subjectDir.isDirectory()) continue;
    const subjectPath = path.join(rootDir, subjectDir.name);
    const mediumDirs = await readdir(subjectPath, { withFileTypes: true });

    for (const mediumDir of mediumDirs) {
      if (!mediumDir.isDirectory()) continue;
      const mediumPath = path.join(subjectPath, mediumDir.name);
      const candidateVersions = await readdir(mediumPath, { withFileTypes: true });

      for (const versionDir of candidateVersions) {
        if (!versionDir.isDirectory()) continue;
        const rawPdfPath = path.join(mediumPath, versionDir.name, "source.pdf");
        if (!existsSync(rawPdfPath)) continue;

        versionDirs.push({
          subjectCode: subjectDir.name,
          medium: mediumDir.name,
          versionLabel: versionDir.name,
          rawPdfPath,
        });
      }
    }
  }

  return versionDirs;
}

function derivePartDir(versionLabel: string) {
  const match = versionLabel.match(/-(part-\d+|full)$/i);
  return match?.[1]?.toLowerCase() ?? "full";
}

async function main() {
  const root = process.cwd();
  const rawRoot = path.join(root, "storage", "textbooks", "raw", "sslc");
  const importRoot = path.join(root, "storage", "imports", "textbooks");

  const versionDirs = await listVersionDirs(rawRoot);
  let restored = 0;

  for (const version of versionDirs) {
    const partDir = derivePartDir(version.versionLabel);
    const targetDir = path.join(importRoot, version.subjectCode, version.medium, partDir);
    const targetPath = path.join(targetDir, "source.pdf");

    if (existsSync(targetPath)) {
      continue;
    }

    await mkdir(targetDir, { recursive: true });
    await copyFile(version.rawPdfPath, targetPath);
    restored += 1;
    console.log(`[restored] ${targetPath}`);
  }

  console.log(JSON.stringify({ discovered: versionDirs.length, restored }, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
