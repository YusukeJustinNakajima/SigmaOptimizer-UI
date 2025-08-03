# SigmaOptimizer-UI <br> ~ Automated Sigma Rule Generation and Optimization ~  

## 🎯 Overview  
**SigmaOptimizer-UI** is a user-friendly interface built on top of [SigmaOptimizer](https://github.com/YusukeJustinNakajima/SigmaOptimizer), designed to make end-to-end Sigma rule generation and optimization more accessible and intuitive.
By combining log analysis, rule evaluation, and iterative refinement powered by LLM, it streamlines the entire workflow—enabling seamless creation, testing, and tuning of Sigma rules without the need to directly interact with PowerShell scripts.

✅ **Automated Sigma rule generation based on real-world logs**  
✅ **Integration with [MITRE Caldera](https://github.com/mitre/caldera) (β version)**  
✅ **Rule validation with syntax checks (Invoke-SigmaRuleTests)**  
✅ **Detection rate measurement using [Hayabusa](https://github.com/Yamato-Security/hayabusa)**  
✅ **FP check of created rules using [evtx-baseline](https://github.com/NextronSystems/evtx-baseline)**  
✅ **Command obfuscation support ([Invoke-ArgFuscator](https://github.com/wietze/Invoke-ArgFuscator)) for robust detection**  

## Quick Demo
https://github.com/user-attachments/assets/7424b073-8841-4fc2-af27-ed7d5b020df9

## 🚀 Getting Started  
### 🔧 Prerequisites   
- **Windows environment** 
- **Node.js**
- **Run `powershell/AutoSetup.ps1` to automate the entire setup process. This script handles all the necessary preparations seamlessly.**
    - Setting OpenAI API Key
        - The script prompts you to enter your OpenAI API key, which is required for LLM-based rule generation.
    - Generating unrelatedLogs.txt
        - The script generates a file named `powershell/config/unrelatedLogs.txt` to store logs that are not related to the Sigma rule generation process.
    - Installing Required PowerShell Modules
        - `Pester 5.x.x` (for running tests)  
        - `powershell-yaml` (for parsing YAML files)  
        - `Invoke-ArgFuscator` (for command obfuscation) 
    - Downloading and Setting Up Hayabusa
        - The script automatically downloads the latest Hayabusa release from GitHub.
    - Extracting the Archive
        - The script ensures the benign_evtx_logs/win10-client.tgz file is extracted
        - The default setting only checks false positives (FP) using the normal logs obtained in a **Windows 10 client environment.**
        - If needed, add your own logs according to your environment(or use [evtx-baseline](https://github.com/NextronSystems/evtx-baseline))
- **Recommended to configure the following two log sources to create better sigma rules:**
    - Microsoft-Windows-Sysmon/Operational -> Sysmon installation
    - Security EventID:4688 -> https://learn.microsoft.com/ja-jp/windows-server/identity/ad-ds/manage/component-updates/command-line-process-auditing

### Installation Steps
1. Repository Clone
```
git clone https://github.com/YusukeJustinNakajima/SigmaOptimizer-UI.git
cd SigmaOptimizer-UI
```

2. Install Package
```
npm install
```

3. Install required PowerShell modules and binaries
```
cd powershell
AutoSetup.ps1
```

4. Copy the `.env.example` file located in the `powershell` directory to create a `.env` file, and modify the model used as needed.
```
# AI Provider Settings
AI_PROVIDER=OpenAI  # Options: OpenAI, Claude
AI_MODEL=GPT-4.1  # Leave empty for default model

# API Keys
OPENAI_APIKEY=your-openai-key-here
CLAUDE_APIKEY=your-claude-key-here
```

### Development Server
1. Start in development mode
```
npm run dev
```

2. Access to http://localhost:3000

## 🤝 Contributing  
I would love to hear your feedback and contributions! 🚀  
If you try **SigmaOptimizer-UI** and have suggestions for improvements, **please submit a pull request or create an issue** on GitHub. Your contributions will help make this tool even better!  

💡 **Ways to contribute:**  
- Report **bugs** or **feature requests** via GitHub Issues 🐛  
- Submit **pull requests** to enhance the rule generation logic 🔧  
- Improve **documentation** or add **new functionalities** 📝  

Your input is greatly appreciated! 🙌