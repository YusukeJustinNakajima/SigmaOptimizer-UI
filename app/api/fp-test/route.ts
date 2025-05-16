import { NextRequest, NextResponse } from "next/server";
import { runPs } from "@/lib/runPs";

export async function POST(req: NextRequest) {
  const { rulePath } = await req.json();
  const { stdout, stderr, code } = await runPs("powershell/fpTest.ps1", [
    "-RulePath", rulePath
  ]);

  if (code !== 0) {
    return NextResponse.json({ success: false, stderr }, { status: 500 });
  }

  //return NextResponse.json(JSON.parse(stdout));

  // for debug
  //console.log("STDOUT>>>\n" + stdout + "\n<<<");
  //console.log("STDERR>>>\n" + stderr + "\n<<<");

  const jsonLine = stdout
    .trim()
    .split(/\r?\n/)
    .reverse()
    .find(l => l.trim().startsWith("{") && l.trim().endsWith("}"));

  if (!jsonLine) {
    return NextResponse.json(
      { success: false, error: "No JSON found", raw: stdout },
      { status: 500 },
    );
  }

  return NextResponse.json(JSON.parse(jsonLine));
}
