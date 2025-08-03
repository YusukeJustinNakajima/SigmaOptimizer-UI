// app/api/llm-optimize/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs/promises';
import * as path from 'path';

const execAsync = promisify(exec);

interface OptimizeRequest {
  rule: string;
  prompt: string;
  rulePath: string;
}

interface OptimizeResponse {
  Success: boolean;
  OptimizedRule: string;
  Message?: string;
  Error?: string;
}

export async function POST(request: NextRequest) {
  try {
    // Parse request body
    const body: OptimizeRequest = await request.json();
    const { rule, prompt, rulePath } = body;

    // Validate inputs
    if (!rule || !prompt || !rulePath) {
      return NextResponse.json(
        { 
          Success: false, 
          Error: 'Missing required parameters: rule, prompt, or rulePath' 
        },
        { status: 400 }
      );
    }

    // Validate prompt length
    if (prompt.length > 1000) {
      return NextResponse.json(
        { 
          Success: false, 
          Error: 'Optimization prompt too long (max 1000 characters)' 
        },
        { status: 400 }
      );
    }

    // Create a temporary file to store the current rule
    const tempRulePath = path.join(process.cwd(), 'temp', `temp_rule_${Date.now()}.yml`);
    
    // Ensure temp directory exists
    await fs.mkdir(path.dirname(tempRulePath), { recursive: true });
    
    // Write current rule to temp file
    await fs.writeFile(tempRulePath, rule, 'utf-8');

    // Prepare PowerShell command
    const scriptPath = path.join(process.cwd(), 'powershell', 'llm-optimize.ps1');
    
    // Escape special characters in the prompt and rule for PowerShell
    const escapedPrompt = prompt.replace(/"/g, '`"').replace(/'/g, "''");
    const escapedRule = rule.replace(/"/g, '`"').replace(/'/g, "''");
    
    // Build PowerShell command
    const psCommand = `powershell.exe -ExecutionPolicy Bypass -File "${scriptPath}" -RulePath "${rulePath}" -OptimizationPrompt "${escapedPrompt}" -CurrentRule "${escapedRule}"`;

    console.log('Executing PowerShell command for LLM optimization...');
    
    // Execute PowerShell script
    const { stdout, stderr } = await execAsync(psCommand, {
      maxBuffer: 1024 * 1024 * 10, // 10MB buffer for large rules
      timeout: 180000, // 180 second timeout for API calls
      windowsHide: true
    });

    if (stderr) {
      console.error('PowerShell stderr:', stderr);
    }

    // Parse PowerShell output
    let result: OptimizeResponse;
    try {
      // Log raw output for debugging
      console.log('PowerShell stdout:', stdout);
      
      // Find JSON in output (might be mixed with other output)
      const jsonMatch = stdout.match(/\{[\s\S]*\}(?!.*\{)/);
      if (!jsonMatch) {
        throw new Error('No JSON found in PowerShell output');
      }
      
      result = JSON.parse(jsonMatch[0]);
    } catch (parseError) {
      console.error('Failed to parse PowerShell output:', stdout);
      console.error('Parse error:', parseError);
      throw new Error('Invalid response from optimization script');
    }

    // Clean up temporary file
    try {
      await fs.unlink(tempRulePath);
    } catch (cleanupError) {
      console.warn('Failed to clean up temp file:', cleanupError);
    }

    // Check if optimization was successful
    if (!result.Success || !result.OptimizedRule) {
      return NextResponse.json(
        {
          Success: false,
          Error: result.Error || 'Optimization failed',
          Message: result.Message || 'Failed to optimize rule'
        },
        { status: 500 }
      );
    }

    // Save the optimized rule to the original path (optional - can be removed if not needed)
    try {
      await fs.writeFile(rulePath, result.OptimizedRule, 'utf-8');
      console.log(`Optimized rule saved to: ${rulePath}`);
    } catch (saveError) {
      console.warn('Failed to save optimized rule to file:', saveError);
      // Don't fail the request if we can't save - the UI has the optimized rule
    }

    // Return successful response
    return NextResponse.json({
      Success: true,
      OptimizedRule: result.OptimizedRule,
      Message: 'Rule optimized successfully'
    });

  } catch (error) {
    console.error('LLM optimization error:', error);
    
    return NextResponse.json(
      {
        Success: false,
        Error: error instanceof Error ? error.message : 'Unknown error occurred',
        Message: 'Failed to optimize rule'
      },
      { status: 500 }
    );
  }
}

// Optional: Add GET method to check endpoint status
export async function GET() {
  return NextResponse.json({
    status: 'LLM Optimization API is running',
    endpoints: {
      POST: '/api/llm-optimize',
      body: {
        rule: 'Current Sigma rule in YAML format',
        prompt: 'Optimization instructions',
        rulePath: 'Path to the rule file'
      }
    }
  });
}