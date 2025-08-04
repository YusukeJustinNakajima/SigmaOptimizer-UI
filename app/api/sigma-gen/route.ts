// app/api/sigma-gen/route.ts
import { NextRequest, NextResponse } from "next/server";
import { runPs } from "@/lib/runPs";

export async function POST(req: NextRequest) {

  const provider = process.env.AI_PROVIDER || "OpenAI";
  const model = process.env.AI_MODEL || "";
  
  console.log('=== Sigma Generation Configuration ===');
  console.log('Environment variables:');
  console.log('  AI_PROVIDER:', process.env.AI_PROVIDER);
  console.log('  AI_MODEL:', process.env.AI_MODEL);
  console.log('Using Provider:', provider);
  console.log('Using Model:', model || 'default');
  console.log('======================================');
  
  const args = ["-Provider", provider];
  if (model) {
    args.push("-Model", model);
  }
  
  console.log('Executing PowerShell script with args:', args.join(' '));
  
  const { stdout, stderr, code } = await runPs("powershell/generateSigmaRules.ps1", args);

  if (code !== 0) {
    console.error('PowerShell script failed with exit code:', code);
    console.error('stderr:', stderr);
    console.error('stdout:', stdout);
    
    return NextResponse.json({ 
      success: false, 
      stderr, 
      detail: stdout,
      provider: provider,
      model: model || "default",
      message: `Failed to generate Sigma rule using ${provider} (${model || 'default'})`
    }, { status: 500 });
  }

  try {
    const jsonLine = stdout.trim().split(/\r?\n/).pop() as string;
    const result = JSON.parse(jsonLine);
    
    result.provider = provider;
    result.model = model || "default";
    
    console.log(`✅ Sigma rule generated successfully using ${provider} (${model || 'default'})`);
    console.log(`Rule path: ${result.RulePath}`);
    
    return NextResponse.json(result);
  } catch (parseError) {
    console.error('Failed to parse PowerShell output:', parseError);
    console.error('Raw output:', stdout);
    
    return NextResponse.json({
      success: false,
      error: 'Failed to parse PowerShell output',
      detail: stdout,
      provider: provider,
      model: model || "default"
    }, { status: 500 });
  }
}

// GET method to check endpoint status and current configuration
export async function GET() {
  const provider = process.env.AI_PROVIDER || 'OpenAI';
  const model = process.env.AI_MODEL || 'default';
  
  let displayModel = model;
  if (model === 'default' || !model) {
    switch (provider) {
      case 'OpenAI':
        displayModel = 'gpt-4.1 (default)';
        break;
      case 'Claude':
        displayModel = 'claude-sonnet-4-20250514 (default)';
        break;
      default:
        displayModel = 'default';
    }
  }
  
  return NextResponse.json({
    status: 'Sigma Generation API is running',
    configuration: {
      provider: provider,
      model: displayModel,
      hasOpenAIKey: !!process.env.OPENAI_APIKEY,
      hasClaudeKey: !!process.env.CLAUDE_APIKEY,
      environment: {
        AI_PROVIDER: process.env.AI_PROVIDER || 'Not set (using default: OpenAI)',
        AI_MODEL: process.env.AI_MODEL || 'Not set (using provider default)'
      }
    },
    endpoints: {
      POST: '/api/sigma-gen',
      description: 'Generate Sigma rules using configured AI provider',
      requiredEnvVars: [
        'AI_PROVIDER (optional, defaults to OpenAI)',
        'AI_MODEL (optional, uses provider default)',
        'OPENAI_APIKEY or CLAUDE_APIKEY (depending on provider)'
      ]
    }
  });
}