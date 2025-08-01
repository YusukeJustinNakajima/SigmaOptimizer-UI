import { NextRequest, NextResponse } from "next/server";
import { runPs } from "@/lib/runPs";

export async function POST(req: NextRequest) {
  const { rulePath } = await req.json();
  const { stdout, stderr, code } = await runPs("powershell/syntaxTest.ps1", [
    "-RuleFilePath", rulePath,
  ]);

  if (code !== 0 && !stdout.trim()) {
    return NextResponse.json({ 
      Success: false, 
      Message: "Syntax validation failed",
      Details: stderr || "Unknown error occurred"
    }, { status: 200 });
  }

  try {
    const jsonLine = stdout.trim().split(/\r?\n/).pop() as string;
    const result = JSON.parse(jsonLine);
    return NextResponse.json(result);
  } catch (e) {
    return NextResponse.json({ 
      Success: false, 
      Message: "Failed to parse test results",
      Details: stdout + "\n" + stderr
    }, { status: 200 });
  }
}