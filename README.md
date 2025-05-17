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
https://github.com/user-attachments/assets/ec7e025b-b3cd-4a86-bdd6-5198ffc4db2e

## 🚀 Usage  
### 🔧 Prerequisites   
- **Windows environment** 
- **Node.js**
- **Run `powershell/AutoSetup.ps1` to automate the entire setup process. This script handles all the necessary preparations seamlessly. Before executing the script, update the `OPENAI_APIKEY` section in `AutoSetup.ps1` with your own API key.**
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
