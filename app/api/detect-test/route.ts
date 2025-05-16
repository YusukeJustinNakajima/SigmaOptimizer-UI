import { NextRequest, NextResponse } from "next/server";
import { runPs } from "@/lib/runPs";

export async function POST(req: NextRequest) {
  try {
    const { rulePath, startTime, endTime } = await req.json();
    const { stdout, stderr, code } = await runPs("powershell/detectTest.ps1", [
      "-RulePath", rulePath,
      "-StartTime", startTime,
      "-EndTime", endTime,
    ]);

    if (code !== 0) {
      return NextResponse.json({ success: false, stderr }, { status: 500 });
    }
    

    //const jsonLine = stdout.trim().split(/\r?\n/).pop() as string;
    // return NextResponse.json(JSON.parse(jsonLine));

    // for debug
    console.log("STDOUT>>>\n" + stdout + "\n<<<");
    console.log("STDERR>>>\n" + stderr + "\n<<<");

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
  } catch (e) {
    console.error("[detect-test route error]", e);
    return NextResponse.json({ success: false, error: String(e) }, { status: 500 });
  }
}
