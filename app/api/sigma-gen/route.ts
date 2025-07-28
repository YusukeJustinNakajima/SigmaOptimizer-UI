// app/api/sigma-gen/route.ts
import { NextRequest, NextResponse } from "next/server";
import { runPs } from "@/lib/runPs";

export async function POST(req: NextRequest) {
  const { finalLogPath } = await req.json();
  const { stdout, stderr, code } = await runPs("powershell/generateSigmaRules.ps1", [
    "-FinalLogPath", finalLogPath,
  ]);

  if (code !== 0) {
    return NextResponse.json({ success: false, stderr, detail: stdout }, { status: 500 });
  }

  const jsonLine = stdout.trim().split(/\r?\n/).pop() as string;
  return NextResponse.json(JSON.parse(jsonLine));
}
