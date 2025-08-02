"use client"

import type React from "react"

import { useState, useRef } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { RadioGroup, RadioGroupItem } from "@/components/ui/radio-group"
import { Textarea } from "@/components/ui/textarea"
import {
  CheckCircle2,
  Code,
  Terminal,
  TestTube,
  XCircle,
  Github,
  Loader2,
  Copy,
  Download,
  Check,
  Save,
  FileText,
  Shield,
  Settings,
  Database,
  PowerIcon
} from "lucide-react"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { motion } from "framer-motion"
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip"
import { toast, Toaster } from "sonner"

export default function SigmaRuleCreator() {
  const [currentStep, setCurrentStep] = useState(1)
  const [mode, setMode] = useState<"cmd" | "powershell" | "mitre">("cmd")
  const [command, setCommand] = useState("")
  const [sigmaRule, setSigmaRule] = useState("")
  const [syntaxTestResult, setSyntaxTestResult] = useState<"pending" | "success" | "failed">("pending")
  const [detectionTestResult, setDetectionTestResult] = useState<"pending" | "success" | "failed">("pending")
  const [falsePositiveTestResult, setFalsePositiveTestResult] = useState<"pending" | "success" | "failed">("pending")
  const [logSources, setLogSources] = useState<string[]>(["sysmon"]);
  const [isGenerating, setIsGenerating] = useState(false)
  const [isTesting, setIsTesting] = useState(false)
  const [isCopied, setIsCopied] = useState(false)
  const [isSaved, setIsSaved] = useState(false)
  const [rulePath, setRulePath] = useState("")
  const [finalLog, setFinalLog] = useState("")  // final_log.txt
  const [isSaving, setIsSaving] = useState(false)
  const [startTime, setStartTime] = useState("")
  const [endTime, setEndTime] = useState("")
  const [fpLogOption, setFpLogOption] = useState<"default" | "custom">("default");
  const [customLogName, setCustomLogName] = useState("");
  const [syntaxErrorMessage, setSyntaxErrorMessage] = useState("");

  const textareaRef = useRef<HTMLTextAreaElement>(null)

  const handleModeChange = (value: "cmd" | "powershell" | "mitre") => {
    setMode(value)
  }

  const handleCommandChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setCommand(e.target.value)
  }

  const handleGenerateLogs = async () => {
    setIsGenerating(true);
    try {
      const { FinalLogPath, StartTime, EndTime } = await collectLogs(); 
      const txt = await fetch(FinalLogPath).then(r => r.text());
      
      setFinalLog(txt);
      setStartTime(StartTime);
      setEndTime(EndTime);  
      nextStep();
    } catch (err) {
      console.error("[collectLogs error]", err); 
      alert("collectLogs failed");
    } finally {
      setIsGenerating(false);
    }
  };

  const handleGenerateSigmaRules = async () => {
    setIsGenerating(true);
    try {
      await generateSigmaRule();  // Wait for success
      nextStep();
    } catch {
    } finally {
      setIsGenerating(false);
    }
  };

  const collectLogs = async (): Promise<{ FinalLogPath: string, StartTime: string, EndTime: string }> => {
    const res = await fetch("/api/log-collector", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ mode, command, logSources }),
    });

    if (!res.ok) throw new Error("log-collector API error");
    return res.json();
  };

  const generateSigmaRule = async () => {
    setIsGenerating(true);
    try {

      const res = await fetch("/api/sigma-gen", {
        method: "POST",
        body: JSON.stringify({}),
      });

      if (!res.ok) throw new Error("sigma-gen API error");

      const { RuleText, RulePath } = await res.json();

      setSigmaRule(RuleText);
      setRulePath(RulePath);
      setCurrentStep(2);           
    } catch (err) {
      console.error(err);
      toast.error("Failed to generate sigma rule");
    } finally {
      setIsGenerating(false);
    }
  };

  const runSyntaxTest = async () => {
    setIsTesting(true);
    setSyntaxTestResult("pending");
    setSyntaxErrorMessage("");
    
    const res = await fetch("/api/syntax-test", {
      method: "POST",
      body: JSON.stringify({ rulePath }),
    });

    const data = await res.json();
    const testPassed = data.Success ? "success" : "failed";
    setSyntaxTestResult(testPassed);
    
    // Save Error Message
    if (!data.Success) {
      const errorMessage = data.Details || data.Message || "Syntax validation failed";
      setSyntaxErrorMessage(errorMessage);
    }
    
    setIsTesting(false);
    
    // If the syntax test is successful, it will automatically proceed to the next step.
    if (testPassed === "success") {
      setTimeout(() => {
        nextStep();
      }, 1500);
    }
  };

  const runDetectionTest = async () => {
    setIsTesting(true);
    setDetectionTestResult("pending");
    const res = await fetch("/api/detect-test", {
      method: "POST",
      body: JSON.stringify({ rulePath, startTime, endTime }),
    });
    
    const data = await res.json();
    const testPassed = data.Success ? "success" : "failed";
    setDetectionTestResult(testPassed);
    setIsTesting(false);

    // If the syntax test is successful, it will automatically proceed to the next step.
    if (testPassed === "success") {
      setTimeout(() => {
        nextStep();
      }, 1500); 
    }
  };

  const runFalsePositiveTest = async () => {
    setIsTesting(true);
    setFalsePositiveTestResult("pending");
    const res = await fetch("/api/fp-test", {
      method: "POST",
      body: JSON.stringify({ rulePath }),
    });

    const data = await res.json();
    setFalsePositiveTestResult(data.Success ? "success" : "failed");
    setIsTesting(false);
  };

  const nextStep = () => {
    if (currentStep < 5) {
      setCurrentStep(currentStep + 1)
    }
  }

  const prevStep = () => {
    if (currentStep > 1) {
      setCurrentStep(currentStep - 1)
    }
  }

  const copyToClipboard = () => {
    if (textareaRef.current) {
      navigator.clipboard.writeText(textareaRef.current.value)
      setIsCopied(true)

      toast.success("Copied to clipboard", {
        description: "Sigma rule has been copied to your clipboard",
        duration: 2000,
      })

      setTimeout(() => {
        setIsCopied(false)
      }, 2000)
    }
  }

  const saveRule = () => {
    setIsSaved(true)

    // Simulate saving the rule
    setTimeout(() => {
      toast.success("Rule saved successfully", {
        description: `Sigma rule has been saved to ${rulePath}`,
        action: {
          label: "View",
          onClick: () => console.log("View rule at", rulePath),
        },
      })
      setIsSaved(false)
    }, 1500)
  }

  const downloadRule = () => {
    const element = document.createElement("a")
    const file = new Blob([sigmaRule], { type: "text/plain" })
    element.href = URL.createObjectURL(file)
    element.download = rulePath.split("/").pop() || "sigma_rule.yml"
    document.body.appendChild(element)
    element.click()
    document.body.removeChild(element)

    toast.success("Rule downloaded", {
      description: "Sigma rule has been downloaded to your device",
    })
  }

  const downloadFile = (filePath: string, fileName?: string) => {
    const anchor = document.createElement("a");
    anchor.href = filePath;                                 // public 配下の静的ファイル
    anchor.download = fileName ?? filePath.split("/").pop() ?? "file.csv";
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
  };

  // Animation variants for transitions
  const pageVariants = {
    initial: { opacity: 0, y: 20 },
    animate: { opacity: 1, y: 0 },
    exit: { opacity: 0, y: -20 },
  }

  return (
    <div className="container mx-auto py-6 max-w-7xl relative">
      {/* Sonner Toaster component */}
      <Toaster position="top-right" richColors />

      {/* GitHub link in top right */}
      <div className="absolute top-0 right-0 p-4">
        <a
          href="https://github.com/YusukeJustinNakajima/SigmaOptimizer-UI"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center text-blue-600 hover:text-blue-800 transition-colors"
        >
          <Github className="mr-2 h-7 w-7" />
          GitHub
        </a>
      </div>

      {/* Title in top left */}
      <div className="flex items-center mb-8">
        <div>
          <h1 className="text-2xl font-bold">SigmaOptimizer</h1>
          <p className="text-sm text-black-800">Automated Sigma Rule Generation and Optimization</p>
        </div>
      </div>

      {/* Progress Indicator */}
      <div className="mb-6">
        <div className="flex justify-between">
          {["Command Input", "Sigma Rule Generation", "Syntax Test", "Detection Test", "False Positive Test"].map(
            (step, index) => (
              <div key={index} className="flex flex-col items-center">
                <div
                  className={`w-10 h-10 rounded-full flex items-center justify-center ${
                    currentStep > index + 1
                      ? "bg-green-100 text-green-600 border-2 border-green-600"
                      : currentStep === index + 1
                        ? "bg-blue-100 text-blue-600 border-2 border-blue-600"
                        : "bg-gray-100 text-gray-400 border-2 border-gray-300"
                  }`}
                >
                  {index + 1}
                </div>
                <span
                  className={`text-xs mt-2 ${currentStep === index + 1 ? "font-bold text-blue-600" : "text-gray-500"}`}
                >
                  {step}
                </span>
              </div>
            ),
          )}
        </div>
        <div className="relative mt-2">
          <div className="absolute top-0 h-1 bg-gray-200 w-full"></div>
          <div
            className="absolute top-0 h-1 bg-blue-600 transition-all duration-300"
            style={{ width: `${((currentStep - 1) / 4) * 100}%` }}
          ></div>
        </div>
      </div>

      {/* Step 1: Command Input */}
      {currentStep === 1 && (
        <motion.div
          initial="initial"
          animate="animate"
          exit="exit"
          variants={pageVariants}
          transition={{ duration: 0.3 }}
        >
          <Card className="relative">
            <CardHeader className="pb-4">
              <CardTitle>Command Input</CardTitle>
              <CardDescription>Select mode and enter command to generate Event Logs</CardDescription>
            </CardHeader>

            <CardContent>
              <div className="grid grid-cols-2 gap-6">
                <div>
                  <div className="mb-4">
                    <Label className="text-base">Select Mode</Label>
                    <RadioGroup
                      value={mode}
                      onValueChange={(v: "cmd" | "powershell" | "mitre") => handleModeChange(v)}
                      className="grid grid-cols-3 gap-2 mt-2"
                    >
                      {/* CMD */}
                      <div className="flex items-center space-x-2 border rounded-md p-2 hover:bg-gray-50 cursor-pointer">
                        <RadioGroupItem value="cmd" id="cmd" />
                        <Label htmlFor="cmd" className="flex items-center cursor-pointer">
                          <Terminal className="mr-1 h-4 w-4" />
                          CMD
                        </Label>
                      </div>
                      {/* PowerShell */}
                      <div className="flex items-center space-x-2 border rounded-md p-2 hover:bg-gray-50 cursor-pointer">
                        <RadioGroupItem value="powershell" id="powershell" />
                        <Label htmlFor="powershell" className="flex items-center cursor-pointer">
                          <Code className="mr-1 h-4 w-4" />
                          PowerShell
                        </Label>
                      </div>
                      {/* Caldera */}
                      <div className="flex items-center space-x-2 border rounded-md p-2 hover:bg-gray-50 cursor-pointer">
                        <RadioGroupItem value="mitre" id="mitre" />
                        <Label htmlFor="mitre" className="flex items-center cursor-pointer">
                          <TestTube className="mr-1 h-4 w-4" />
                          Caldera
                        </Label>
                      </div>
                    </RadioGroup>
                  </div>
                  <div className="mt-4">
                  {/*// ログソース選択部分を以下のように置き換え*/}
                  <div className="mt-4">
                  <Label className="text-base mb-3 block">Select Log Sources</Label>
                  <div className="space-y-3">
                    {/* Sysmon */}
                    <div className="flex items-center space-x-3 p-3 border rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
                        onClick={() => {
                          if (logSources.includes("sysmon")) {
                            setLogSources(logSources.filter(src => src !== "sysmon"));
                          } else {
                            setLogSources([...logSources, "sysmon"]);
                          }
                        }}>
                      <input
                        type="checkbox"
                        id="sysmon"
                        checked={logSources.includes("sysmon")}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setLogSources([...logSources, "sysmon"]);
                          } else {
                            setLogSources(logSources.filter(src => src !== "sysmon"));
                          }
                        }}
                        className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
                        onClick={(e) => e.stopPropagation()}
                      />
                      <Database className="h-4 w-4 text-blue-600" />
                      <div className="flex-1">
                        <Label htmlFor="sysmon" className="text-sm font-medium cursor-pointer select-none">
                          Sysmon
                        </Label>
                        <p className="text-xs text-gray-500 mt-0.5 select-none">System Monitor event logs (Default)</p>
                      </div>
                    </div>

                    {/* Application */}
                    <div className="flex items-center space-x-3 p-3 border rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
                        onClick={() => {
                          if (logSources.includes("application")) {
                            setLogSources(logSources.filter(src => src !== "application"));
                          } else {
                            setLogSources([...logSources, "application"]);
                          }
                        }}>
                      <input
                        type="checkbox"
                        id="application"
                        checked={logSources.includes("application")}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setLogSources([...logSources, "application"]);
                          } else {
                            setLogSources(logSources.filter(src => src !== "application"));
                          }
                        }}
                        className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
                        onClick={(e) => e.stopPropagation()}
                      />
                      <FileText className="h-4 w-4 text-green-600" />
                      <div className="flex-1">
                        <Label htmlFor="application" className="text-sm font-medium cursor-pointer select-none">
                          Application
                        </Label>
                        <p className="text-xs text-gray-500 mt-0.5 select-none">Application event logs</p>
                      </div>
                    </div>

                    {/* Security */}
                    <div className="flex items-center space-x-3 p-3 border rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
                        onClick={() => {
                          if (logSources.includes("security")) {
                            setLogSources(logSources.filter(src => src !== "security"));
                          } else {
                            setLogSources([...logSources, "security"]);
                          }
                        }}>
                      <input
                        type="checkbox"
                        id="security"
                        checked={logSources.includes("security")}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setLogSources([...logSources, "security"]);
                          } else {
                            setLogSources(logSources.filter(src => src !== "security"));
                          }
                        }}
                        className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
                        onClick={(e) => e.stopPropagation()}
                      />
                      <Shield className="h-4 w-4 text-red-600" />
                      <div className="flex-1">
                        <Label htmlFor="security" className="text-sm font-medium cursor-pointer select-none">
                          Security
                        </Label>
                        <p className="text-xs text-gray-500 mt-0.5 select-none">Security audit logs</p>
                      </div>
                    </div>

                    {/* System */}
                    <div className="flex items-center space-x-3 p-3 border rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
                        onClick={() => {
                          if (logSources.includes("system")) {
                            setLogSources(logSources.filter(src => src !== "system"));
                          } else {
                            setLogSources([...logSources, "system"]);
                          }
                        }}>
                      <input
                        type="checkbox"
                        id="system"
                        checked={logSources.includes("system")}
                        onChange={(e) => {
                          if (e.target.checked) {
                            setLogSources([...logSources, "system"]);
                          } else {
                            setLogSources(logSources.filter(src => src !== "system"));
                          }
                        }}
                        className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
                        onClick={(e) => e.stopPropagation()}
                      />
                      <Settings className="h-4 w-4 text-purple-600" />
                      <div className="flex-1">
                        <Label htmlFor="system" className="text-sm font-medium cursor-pointer select-none">
                          System
                        </Label>
                        <p className="text-xs text-gray-500 mt-0.5 select-none">Windows system event logs</p>
                      </div>
                    </div>

                    {/* PowerShell logs - only show when PowerShell mode is selected */}
                    {mode === "powershell" && (
                      <>
                        <div className="flex items-center space-x-3 p-3 border rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
                            onClick={() => {
                              if (logSources.includes("powershell")) {
                                setLogSources(logSources.filter(src => src !== "powershell"));
                              } else {
                                setLogSources([...logSources, "powershell"]);
                              }
                            }}>
                          <input
                            type="checkbox"
                            id="powershell"
                            checked={logSources.includes("powershell")}
                            onChange={(e) => {
                              if (e.target.checked) {
                                setLogSources([...logSources, "powershell"]);
                              } else {
                                setLogSources(logSources.filter(src => src !== "powershell"));
                              }
                            }}
                            className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
                            onClick={(e) => e.stopPropagation()}
                          />
                          <Terminal className="h-4 w-4 text-indigo-600" />
                          <div className="flex-1">
                            <Label htmlFor="powershell" className="text-sm font-medium cursor-pointer select-none">
                              Windows PowerShell
                            </Label>
                            <p className="text-xs text-gray-500 mt-0.5 select-none">Classic PowerShell logs</p>
                          </div>
                        </div>

                        <div className="flex items-center space-x-3 p-3 border rounded-lg hover:bg-gray-50 transition-colors cursor-pointer"
                            onClick={() => {
                              if (logSources.includes("powershell-operational")) {
                                setLogSources(logSources.filter(src => src !== "powershell-operational"));
                              } else {
                                setLogSources([...logSources, "powershell-operational"]);
                              }
                            }}>
                          <input
                            type="checkbox"
                            id="powershell-operational"
                            checked={logSources.includes("powershell-operational")}
                            onChange={(e) => {
                              if (e.target.checked) {
                                setLogSources([...logSources, "powershell-operational"]);
                              } else {
                                setLogSources(logSources.filter(src => src !== "powershell-operational"));
                              }
                            }}
                            className="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 focus:ring-2"
                            onClick={(e) => e.stopPropagation()}
                          />
                          <Code className="h-4 w-4 text-indigo-600" />
                          <div className="flex-1">
                            <Label htmlFor="powershell-operational" className="text-sm font-medium cursor-pointer select-none">
                              PowerShell/Operational
                            </Label>
                            <p className="text-xs text-gray-500 mt-0.5 select-none">Enhanced PowerShell logging</p>
                          </div>
                        </div>
                      </>
                    )}
                  </div>
                  
                  {/* 選択されたログソースの数を表示 */}
                  <p className="text-xs text-gray-600 mt-3">
                    {logSources.length} log source{logSources.length !== 1 ? 's' : ''} selected
                  </p>
                </div>
                  </div>
                </div>

                <div>
                  {mode !== "mitre" ? (
                    <div className="space-y-2">
                      <Label htmlFor="command">Enter {mode === "cmd" ? "Command Line" : "PowerShell"} Command</Label>
                      <div className="bg-gray-900 text-gray-100 p-4 rounded-md font-mono h-[200px] overflow-auto">
                        <div className="flex">
                          <span className="text-green-400 mr-2">{mode === "cmd" ? "C:\\>" : "PS C:\\>"}</span>
                          <Textarea
                            id="command"
                            placeholder={`Enter ${mode === "cmd" ? "CMD" : "PowerShell"} command here...`}
                            value={command}
                            onChange={handleCommandChange}
                            className="min-h-[160px] bg-transparent border-none focus:ring-0 focus-visible:ring-0 resize-none flex-1 p-0"
                            spellCheck={false}
                          />
                        </div>
                      </div>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      <Label htmlFor="command">Enter Mitre Caldera Agent Command</Label>
                      <div className="bg-gray-900 text-gray-100 p-4 rounded-md font-mono h-[200px] overflow-auto">
                        <div className="flex">
                          <span className="text-blue-400 mr-2">caldera$</span>
                          <Textarea
                            id="command"
                            placeholder="Enter command to create caldera agent here..."
                            value={command}
                            onChange={handleCommandChange}
                            className="min-h-[160px] bg-transparent border-none focus:ring-0 focus-visible:ring-0 resize-none flex-1 p-0"
                            spellCheck={false}
                          />
                        </div>
                      </div>
                    </div>
                  )}
                </div>
              </div>
            </CardContent>

            <CardFooter className="flex justify-end">
              {/* After wrapping the generated handler and completing nextStep() */}
              <Button 
                onClick={handleGenerateLogs}
                disabled={isGenerating || !command}
              >
                {isGenerating ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Generating...
                  </>
                ) : (
                  "Generate Logs"
                )}
              </Button>
            </CardFooter>
          </Card>
        </motion.div>
      )}


      {/* Step 2 : Sigma Rule Generation */}
      {currentStep === 2 && (
        <motion.div
          initial="initial"
          animate="animate"
          exit="exit"
          variants={pageVariants}
          transition={{ duration: 0.3 }}
        >
          <Card className="relative">
            <CardHeader className="pb-4">
              <div className="flex justify-between items-center">
                <div>
                  <CardTitle>Sigma Rule Generation</CardTitle>
                  <CardDescription>Generate Sigma Rule Based On Event Logs</CardDescription>
                </div>
                <div className="text-sm text-gray-500">
                  <span className="font-semibold">Mode:</span> {mode.toUpperCase()} |
                  <span className="font-semibold ml-2">Log Source:</span> {logSources}
                </div>
              </div>
            </CardHeader>

            <CardContent>
              <div className="mb-2 flex justify-between items-center">
                <div className="text-sm text-gray-600">
                  <span className="font-medium">Parsed logs generated by command execution (input to LLM)</span>
                </div>

                {/* copy / download button */}
                <div className="flex space-x-2">
                  <TooltipProvider>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button variant="outline" size="sm" onClick={copyToClipboard}>
                          {isCopied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                          <span className="ml-2">{isCopied ? "Copied" : "Copy"}</span>
                        </Button>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Copy rule to clipboard</p>
                      </TooltipContent>
                    </Tooltip>
                  </TooltipProvider>

                  <TooltipProvider>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button variant="outline" size="sm" onClick={downloadRule}>
                          <Download className="h-4 w-4" />
                          <span className="ml-2">Download</span>
                        </Button>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Download rule as YAML</p>
                      </TooltipContent>
                    </Tooltip>
                  </TooltipProvider>
                </div>
              </div>

              <div className="border rounded-md p-1 bg-gray-50">
                <Textarea
                  ref={textareaRef}
                  defaultValue={finalLog}
                  //onChange={(e) => setSigmaRule(e.target.value)}
                  className="font-mono min-h-[500px] w-full border-none focus:ring-0 focus-visible:ring-0"
                  spellCheck={false}
                />
              </div>
            </CardContent>
            <CardFooter className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                Back
              </Button>
              <Button
                onClick={handleGenerateSigmaRules}
                disabled={isGenerating}
              >
                {isGenerating ? (
                  <>
                    <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                    Generating...
                  </>
                ) : (
                  "Generate Sigma Rule"
                )}
              </Button>
            </CardFooter>
          </Card>
        </motion.div>
      )}


      {/* Step 3: Syntax Test */}
      {currentStep === 3 && (
        <motion.div
          initial="initial"
          animate="animate"
          exit="exit"
          variants={pageVariants}
          transition={{ duration: 0.3 }}
        >
          <Card>
            <CardHeader className="pb-4">
              <div className="flex justify-between items-center">
                <div>
                  <CardTitle>Syntax Test</CardTitle>
                  <CardDescription>Validate the syntax of your Sigma rule</CardDescription>
                </div>
                <div className="text-sm text-gray-500">
                  <span className="font-semibold">Mode:</span> {mode.toUpperCase()} |
                  <span className="font-semibold ml-2">Log Source:</span> {logSources}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="mb-2 flex justify-between items-center">
                <div className="text-sm text-gray-600">
                  <span className="font-medium">Rule Path:</span> {rulePath}
                </div>
                <Button variant="outline" size="sm" onClick={copyToClipboard}>
                  {isCopied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  <span className="ml-2">{isCopied ? "Copied" : "Copy"}</span>
                </Button>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="col-span-2">
                  <div className="border rounded-md p-1 bg-gray-50">
                    <Textarea
                      ref={textareaRef}
                      value={sigmaRule}
                      onChange={(e) => setSigmaRule(e.target.value)} 
                      className="font-mono min-h-[450px] w-full border-none focus:ring-0 focus-visible:ring-0"
                      spellCheck={false}
                    />
                  </div>

                  {/* Save Button */}
                  <div className="mt-2 flex justify-end">
                    <Button
                      variant="secondary"
                      size="sm"
                      disabled={isSaving}
                      onClick={async () => {
                        setIsSaving(true);
                        try {
                          /* save using /api/save-rule */
                          await fetch("/api/save-rule", {
                            method: "POST",
                            body: JSON.stringify({ path: rulePath, content: sigmaRule }),
                          });
                          toast.success("Rule saved!");

                          /* Re-run Syntax Test immediately after saving */
                          await runSyntaxTest();
                        } catch (err) {
                          toast.error("Save failed");
                        } finally {
                          setIsSaving(false);
                        }
                      }}
                    >
                      {isSaving ? (
                        <>
                          <Loader2 className="mr-1 h-4 w-4 animate-spin" /> Saving…
                        </>
                      ) : (
                        "Modify & Save Rule"
                      )}
                    </Button>
                  </div>
                </div>
                <div className="space-y-4">
                  <div className="border rounded-md p-4 bg-gray-50 h-[450px] flex flex-col">
                    <h3 className="font-medium mb-2">Syntax Validation</h3>
                    <p className="text-sm text-gray-600 mb-4">
                      The syntax test will validate your Sigma rule against the official Sigma specification.
                    </p>

                    <div className="flex-grow flex flex-col items-center justify-center">
                      {syntaxTestResult === "pending" ? (
                        isTesting ? (
                          <div className="text-center">
                            <Loader2 className="h-10 w-10 animate-spin mx-auto mb-4 text-blue-600" />
                            <p className="text-gray-600">Testing syntax...</p>
                          </div>
                        ) : (
                          <div className="text-center">
                            <p className="text-gray-600">Click the button below to validate your Sigma rule syntax</p>
                          </div>
                        )
                      ) : syntaxTestResult === "success" ? (
                        <motion.div
                          initial={{ scale: 0.8, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ duration: 0.3 }}
                          className="text-center"
                        >
                          <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                            <CheckCircle2 className="h-8 w-8 text-green-600" />
                          </div>
                          <h3 className="text-lg font-medium text-green-800 mb-2">Syntax Test Passed</h3>
                          <p className="text-green-700">Your Sigma rule is valid and follows the correct syntax.</p>
                        </motion.div>
                      ) : (
                        <motion.div
                          initial={{ scale: 0.8, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ duration: 0.3 }}
                          className="text-center"
                        >
                          <div className="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
                            <XCircle className="h-8 w-8 text-red-600" />
                          </div>
                          <h3 className="text-lg font-medium text-red-800 mb-2">Syntax Test Failed</h3>
                          <p className="text-red-700 mb-3">Please check your rule for syntax errors.</p>
                          
                          {/* エラーメッセージ表示 */}
                          {syntaxErrorMessage && (
                            <div className="mt-4 text-left">
                              <div className="bg-red-50 border border-red-200 rounded-md p-3 max-h-32 overflow-y-auto">
                                <p className="text-sm text-red-800 font-mono whitespace-pre-wrap">
                                  {syntaxErrorMessage}
                                </p>
                              </div>
                              
                              {/* エラーログダウンロードボタン */}
                              <Button
                                variant="outline"
                                size="sm"
                                className="mt-2"
                                onClick={() => {
                                  const blob = new Blob([syntaxErrorMessage], { type: 'text/plain' });
                                  const url = URL.createObjectURL(blob);
                                  const a = document.createElement('a');
                                  a.href = url;
                                  a.download = 'syntax_error_log.txt';
                                  document.body.appendChild(a);
                                  a.click();
                                  document.body.removeChild(a);
                                  URL.revokeObjectURL(url);
                                  
                                  toast.success("Error log downloaded");
                                }}
                              >
                                <Download className="h-4 w-4 mr-2" />
                                Download Error Log
                              </Button>
                            </div>
                          )}
                        </motion.div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
            <CardFooter className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                Back
              </Button>
              <div className="flex gap-2">
                {syntaxTestResult === "pending" && !isTesting && (
                  <Button onClick={runSyntaxTest}>
                    Run Syntax Test
                  </Button>
                )}
                {syntaxTestResult === "failed" && (
                  <Button onClick={nextStep} disabled>
                    Continue to Detection Test
                  </Button>
                )}
              </div>
            </CardFooter>
          </Card>
        </motion.div>
      )}

      {/* Step 4: Detection Test */}
      {currentStep === 4 && (
        <motion.div
          initial="initial"
          animate="animate"
          exit="exit"
          variants={pageVariants}
          transition={{ duration: 0.3 }}
        >
          <Card>
            <CardHeader className="pb-4">
              <div className="flex justify-between items-center">
                <div>
                  <CardTitle>Detection Test with Hayabusa</CardTitle>
                  <CardDescription>Test if your rule detects the intended behavior</CardDescription>
                </div>
                <div className="text-sm text-gray-500">
                  <span className="font-semibold">Mode:</span> {mode.toUpperCase()} |
                  <span className="font-semibold ml-2">Log Source:</span> {logSources}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="mb-2 flex justify-between items-center">
                <div className="text-sm text-gray-600">
                  <span className="font-medium">Rule Path:</span> {rulePath}
                </div>
                <Button variant="outline" size="sm" onClick={copyToClipboard}>
                  {isCopied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  <span className="ml-2">{isCopied ? "Copied" : "Copy"}</span>
                </Button>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="col-span-2">
                  <div className="border rounded-md p-1 bg-gray-50">
                    <Textarea
                      ref={textareaRef}
                      value={sigmaRule}
                      onChange={(e) => setSigmaRule(e.target.value)}
                      className="font-mono min-h-[450px] w-full border-none focus:ring-0 focus-visible:ring-0"
                      spellCheck={false}
                    />
                  </div>

                  {/* Save Button を左側カードの右下に配置 */}
                  <div className="mt-2 flex justify-end">
                    <Button
                      variant="secondary"
                      size="sm"
                      disabled={isSaving}
                      onClick={async () => {
                        setIsSaving(true);
                        try {
                          await fetch("/api/save-rule", {
                            method: "POST",
                            body: JSON.stringify({ path: rulePath, content: sigmaRule }),
                          });
                          toast.success("Rule saved!");
                          await runDetectionTest();
                        } catch (err) {
                          toast.error("Save failed");
                        } finally {
                          setIsSaving(false);
                        }
                      }}
                    >
                      {isSaving ? (
                        <>
                          <Loader2 className="mr-1 h-4 w-4 animate-spin" /> Saving…
                        </>
                      ) : (
                        "Modify & Save Rule"
                      )}
                    </Button>
                  </div>
                </div>
                
                <div className="space-y-4">
                  <div className="border rounded-md p-4 bg-gray-50 h-[450px] flex flex-col">
                    <h3 className="font-medium mb-2">Detection Testing</h3>
                    <p className="text-sm text-gray-600 mb-4">
                      The detection test will run your Sigma rule against sample logs to verify it detects the intended
                      behavior.
                    </p>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => downloadFile("/detection_result.csv", "detection_result.csv")}
                    >
                      <Download className="h-4 w-4" />
                      <span className="ml-2">Download CSV</span>
                    </Button>

                    <div className="flex-grow flex flex-col items-center justify-center">
                      {detectionTestResult === "pending" ? (
                        isTesting ? (
                          <div className="text-center">
                            <Loader2 className="h-10 w-10 animate-spin mx-auto mb-4 text-blue-600" />
                            <p className="text-gray-700">Running detection test...</p>
                            <p className="text-xs text-gray-600 mt-2">Testing against malicious activity logs</p>
                          </div>
                        ) : (
                          <div className="text-center">
                            <p className="text-gray-600">Click the button below to test detection capability</p>
                          </div>
                        )
                      ) : detectionTestResult === "success" ? (
                        <motion.div
                          initial={{ scale: 0.8, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ duration: 0.3 }}
                          className="text-center"
                        >
                          <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                            <CheckCircle2 className="h-8 w-8 text-green-500" />
                          </div>
                          <h3 className="text-lg font-medium text-green-800 mb-2">Detection Test Passed</h3>
                          <p className="text-green-700">Your rule successfully detected the malicious activity.</p>
                        </motion.div>
                      ) : (
                        <motion.div
                          initial={{ scale: 0.8, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ duration: 0.3 }}
                          className="text-center"
                        >
                          <div className="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
                            <XCircle className="h-8 w-8 text-red-500" />
                          </div>
                          <h3 className="text-lg font-medium text-red-800 mb-2">Detection Test Failed</h3>
                          <p className="text-red-700">Your rule did not detect the malicious activity.</p>
                        </motion.div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
            <CardFooter className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                Back
              </Button>
              <div className="flex gap-2">
                {detectionTestResult === "pending" && !isTesting && (
                  <Button onClick={runDetectionTest}>
                    Run Detection Test
                  </Button>
                )}
                {detectionTestResult === "failed" && (
                  <Button onClick={nextStep} disabled>
                    Continue to False Positive Test
                  </Button>
                )}
              </div>
            </CardFooter>
          </Card>
        </motion.div>
      )}

      {/* Step 5: False Positive Test */}
      {currentStep === 5 && (
        <motion.div
          initial="initial"
          animate="animate"
          exit="exit"
          variants={pageVariants}
          transition={{ duration: 0.3 }}
        >
          <Card>
            <CardHeader className="pb-4">
              <div className="flex justify-between items-center">
                <div>
                  <CardTitle>False Positive Test</CardTitle>
                  <CardDescription>Test if your rule avoids false positives</CardDescription>
                </div>
                <div className="text-sm text-gray-500">
                  <span className="font-semibold">Mode:</span> {mode.toUpperCase()} |
                  <span className="font-semibold ml-2">Log Source:</span> {logSources}
                </div>
              </div>
            </CardHeader>
            <CardContent>
              <div className="mb-2 flex justify-between items-center">
                <div className="text-sm text-gray-600">
                  <span className="font-medium">Rule Path:</span> {rulePath}
                </div>
                <Button variant="outline" size="sm" onClick={copyToClipboard}>
                  {isCopied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                  <span className="ml-2">{isCopied ? "Copied" : "Copy"}</span>
                </Button>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div className="col-span-2">
                  <div className="border rounded-md p-1 bg-gray-50">
                    <Textarea
                      ref={textareaRef}
                      value={sigmaRule}
                      onChange={(e) => setSigmaRule(e.target.value)}
                      className="font-mono min-h-[450px] w-full border-none focus:ring-0 focus-visible:ring-0"
                      spellCheck={false}
                    />
                  </div>

                  {/* Save Button */}
                  <div className="mt-2 flex justify-end">
                    <Button
                      variant="secondary"
                      size="sm"
                      disabled={isSaving}
                      onClick={async () => {
                        setIsSaving(true);
                        try {
                          /* save using /api/save-rule */
                          await fetch("/api/save-rule", {
                            method: "POST",
                            body: JSON.stringify({ path: rulePath, content: sigmaRule }),
                          });
                          toast.success("Rule saved!");

                          /* Re-run False Positive Test immediately after saving */
                          await runFalsePositiveTest();
                        } catch (err) {
                          toast.error("Save failed");
                        } finally {
                          setIsSaving(false);
                        }
                      }}
                    >
                      {isSaving ? (
                        <>
                          <Loader2 className="mr-1 h-4 w-4 animate-spin" /> Saving…
                        </>
                      ) : (
                        "Modify & Save Rule"
                      )}
                    </Button>
                  </div>
                </div>
                <div className="space-y-4">
                  <div className="border rounded-md p-4 bg-gray-50 h-[450px] flex flex-col">
                    <h3 className="font-medium mb-2">False Positive Testing</h3>
                    <p className="text-sm text-gray-600 mb-4">
                      This test will run your Sigma rule against benign activity logs to ensure it doesn't generate
                      false positives.
                    </p>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => downloadFile("/fp_check_result.csv", "fp_check_result.csv")}
                    >
                      <Download className="h-4 w-4" />
                      <span className="ml-2">Download CSV</span>
                    </Button>

                    <div className="mb-4">
                      <Label className="text-sm font-medium mb-2 block">Log Source</Label>
                      <RadioGroup
                        value={fpLogOption}
                        onValueChange={(v: "default" | "custom") => setFpLogOption(v)}
                        className="space-y-2"
                      >
                        <div className="flex items-center space-x-2">
                          <RadioGroupItem value="default" id="default-logs" />
                          <Label htmlFor="default-logs">
                            Default (Windows 10 client environment evtx-baseline)
                          </Label>
                        </div>

                        <div className="flex items-center space-x-2">
                          <RadioGroupItem value="custom" id="custom-logs" />
                          <Label htmlFor="custom-logs">
                            Custom logs from <code>benign_evtx_logs</code> directory
                          </Label>
                        </div>
                      </RadioGroup>
                      {fpLogOption === "custom" && (
                        <div className="mb-4">
                          <Label htmlFor="log-name" className="text-sm font-medium mb-2 block">
                            Custom Log Name
                          </Label>
                          <Input
                            id="log-name"
                            placeholder="Enter log file name from benign_evtx_logs directory"
                            value={customLogName}
                            onChange={(e) => setCustomLogName(e.target.value)}
                          />
                        </div>
                      )}
                    </div>

                    <div className="flex-grow flex flex-col items-center justify-center">
                      {falsePositiveTestResult === "pending" ? (
                        isTesting ? (
                          <div className="text-center">
                            <Loader2 className="h-10 w-10 animate-spin mx-auto mb-4 text-blue-600" />
                            <p className="text-gray-700">Running false positive test...</p>
                            <p className="text-xs text-gray-600 mt-2">Testing against benign activity logs</p>
                          </div>
                        ) : (
                          <Button onClick={runFalsePositiveTest} className="w-full">
                            Run False Positive Test
                          </Button>
                        )
                      ) : falsePositiveTestResult === "success" ? (
                        <motion.div
                          initial={{ scale: 0.8, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ duration: 0.3 }}
                          className="text-center"
                        >
                          <div className="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
                            <CheckCircle2 className="h-7 w-7 text-green-500" />
                          </div>
                          <h3 className="text-lg font-medium text-green-800 mb-2">False Positive Test Passed</h3>
                          <p className="text-green-700">Your rule doesn't trigger on benign activity.</p>
                        </motion.div>
                      ) : (
                        <motion.div
                          initial={{ scale: 0.8, opacity: 0 }}
                          animate={{ scale: 1, opacity: 1 }}
                          transition={{ duration: 0.3 }}
                          className="text-center"
                        >
                          <div className="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
                            <XCircle className="h-8 w-8 text-red-500" />
                          </div>
                          <h3 className="text-lg font-medium text-red-800 mb-2">False Positive Test Failed</h3>
                          <p className="text-red-700">Your rule triggered on benign activity.</p>
                        </motion.div>
                      )}
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
            <CardFooter className="flex justify-between">
              <Button variant="outline" onClick={prevStep}>
                Back
              </Button>
              <div className="space-x-2">
                {falsePositiveTestResult !== "pending" && (
                  <Button
                    variant="secondary"
                    onClick={() => {
                      setIsTesting(true)
                      // Logic to regenerate rule based on test results
                      setTimeout(() => {
                        setSigmaRule((prevRule) => {
                          // This would typically call an API to optimize the rule
                          return `${prevRule}\n# Optimized based on false positive test results`
                        })
                        setIsTesting(false)
                        setCurrentStep(2) // Go back to rule generation step

                        toast("Rule optimized", {
                          description: "Sigma rule has been optimized based on test results",
                        })
                      }, 1500)
                    }}
                    disabled={isTesting}
                  >
                    {isTesting ? (
                      <>
                        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                        Optimizing...
                      </>
                    ) : (
                      "Regenerate Rule"
                    )}
                  </Button>
                )}
                <Button
                  variant="default"
                  disabled={falsePositiveTestResult !== "success" || isTesting || isSaved}
                  onClick={saveRule}
                >
                  {isSaved ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Saving...
                    </>
                  ) : (
                    <>
                      <Save className="mr-2 h-4 w-4" />
                      Finalize Sigma Rule
                    </>
                  )}
                </Button>
              </div>
            </CardFooter>
          </Card>
        </motion.div>
      )}
    </div>
  )
}
