import { spawn } from "child_process";
import path from "path";

export async function runPs(scriptRelPath: string, args: string[] = []) {
  return new Promise<{ stdout: string; stderr: string; code: number }>((res, rej) => {
    const script = path.join(process.cwd(), scriptRelPath); 
    const ps = spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, ...args]);
    let stdout = "";
    let stderr = "";
    ps.stdout.on("data", (d) => (stdout += d.toString()));
    ps.stderr.on("data", (d) => (stderr += d.toString()));
    ps.on("error", rej);
    ps.on("close", (code) => res({ stdout, stderr, code: code ?? 1 }));
  });
}
