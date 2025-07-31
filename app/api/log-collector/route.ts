import { NextRequest, NextResponse } from "next/server";
import { runPs } from "@/lib/runPs";

export async function POST(req: NextRequest) {
  const { mode, command, logSources = ["sysmon"] } = await req.json();
  
  // ログソースの配列をカンマ区切りの文字列に変換
  const logSourcesString = logSources.join(",");
  
  const { stdout, stderr, code } = await runPs("powershell/logCollector.ps1", [
    "-Mode", mode,
    "-Command", command,
    "-LogSources", logSourcesString
  ]);

  if (code !== 0) {
    return NextResponse.json({ success: false, stderr, detail: stdout }, { status: 500 });
  }

  const lines = stdout.trim().split(/\r?\n/).filter(Boolean);
  if (lines.length === 0) {
    return NextResponse.json(
      { success: false, error: "No JSON output", raw: stdout, stderr },
      { status: 500 }
    );
  }

  const jsonLine = lines.pop()!;
  try {
    return NextResponse.json(JSON.parse(jsonLine));
  } catch (err) {
    return NextResponse.json(
      { success: false, error: "Invalid JSON", jsonLine, raw: stdout },
      { status: 500 }
    );
  }
}