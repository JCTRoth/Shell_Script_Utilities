# SkillOpt CLI Usage Guide

This guide explains how to use the SkillOpt CLI tools (`skillopt-eval`, `skillopt-sleep`, `skillopt-train`) in your codebase, including installation instructions for **Linux** and **macOS**.

---

## **Table of Contents**

1. [Prerequisites](#prerequisites)
2. [Installation](#installation)
  - [Linux (Fedora/Ubuntu)](#linux-fedoraubuntu)
  - [macOS](#macos)
  - [Windows](#windows)
3. [CLI Tools Overview](#cli-tools-overview)
4. [Setup](#setup)
5. [How to Use Each Command](#how-to-use-each-command)
6. [Example Workflow](#example-workflow)
7. [Configuration Files](#configuration-files)
8. [Directory Structure](#directory-structure)
9. [Tips](#tips)
10. [Troubleshooting](#troubleshooting)
11. [Next Steps](#next-steps)

---

## **Prerequisites**

- Python 3.10+
- SkillOpt installed (`pip install skillopt`)
- Access to LLM backends (e.g., Azure OpenAI, OpenAI, Anthropic, or local models)

---

## **Installation**

### **Linux (Fedora/Ubuntu)**

Use the following script to install SkillOpt on Linux. This script:

1. Save the script as `install_skillopt_linux.sh`.
2. Run it as root:
  ```bash
   sudo ./install_skillopt_linux.sh
  ```

---

### **macOS**

Use the following script to install SkillOpt on macOS. This script:

1. Save the script as `install_skillopt_macos.sh`.
2. Run it:
  ```bash
   ./install_skillopt_macos.sh
  ```

---

### **Windows**

Open PowerShell as Administrator and run:

 Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
 .\install_skillopt_windows.ps1


---

## **CLI Tools Overview**


| Command          | Purpose                                                        | When to Use                                             |
| ---------------- | -------------------------------------------------------------- | ------------------------------------------------------- |
| `skillopt-eval`  | Evaluate trained skills on benchmarks                          | After training, to test skill performance               |
| `skillopt-sleep` | Offline self-evolution (harvest → mine → replay → consolidate) | Nightly or periodic runs to improve skills autonomously |
| `skillopt-train` | Train skills on custom datasets                                | During development or to adapt skills to new tasks      |


---

## **Setup**

### 1. **Install SkillOpt**

Follow the installation steps for your OS above.

### 2. **Configure Environment Variables**

Set the required credentials for your LLM backend. For example:

#### **Azure OpenAI**

```bash
export AZURE_OPENAI_ENDPOINT="https://your-endpoint.openai.azure.com/"
export AZURE_OPENAI_API_KEY="your-api-key"
export AZURE_OPENAI_AUTH_MODE="openai_compatible"
```

#### **OpenAI**

```bash
export OPENAI_API_KEY="your-api-key"
```

---

## **How to Use Each Command**

### **1. `skillopt-eval`**

Evaluate trained skills on benchmarks to measure performance.

**Usage:**

```bash
skillopt-eval --config <path_to_config.yaml> --backend <backend_name>
```

**Example:**

```bash
skillopt-eval --config configs/searchqa/default.yaml --backend azure_openai
```

**When to Use:**

- After training a skill, to validate its performance on a benchmark.
- To compare different versions of a skill.

---

### **2. `skillopt-sleep`**

Run offline self-evolution to improve skills autonomously. This command:

- Harvests agent session transcripts
- Mines recurring tasks
- Replays and consolidates them into long-term skills

**Usage:**

```bash
skillopt-sleep run --backend <backend_name> --model <model_name>
```

**Example:**

```bash
skillopt-sleep run --backend azure_openai --model gpt-4
```

**When to Use:**

- **Nightly or periodic runs** to update skills based on real-world usage.
- To adapt skills to new patterns in agent behavior.

---

### **3. `skillopt-train`**

Train skills on custom datasets or benchmarks.

**Usage:**

```bash
python scripts/train.py --config <path_to_config.yaml>
```

**Example:**

```bash
python scripts/train.py --config configs/searchqa/default.yaml
```

**When to Use:**

- During **development** to create new skills.
- To fine-tune skills for specific tasks or domains.

---

## **Example Workflow**

### **1. Train a Skill**

```bash
python scripts/train.py --config configs/searchqa/default.yaml
```

### **2. Evaluate the Skill**

```bash
skillopt-eval --config configs/searchqa/default.yaml --backend azure_openai
```

### **3. Run Nightly Self-Evolution**

```bash
skillopt-sleep run --backend azure_openai --model gpt-4
```

---

## **Configuration Files**

SkillOpt uses YAML files to define benchmarks, models, and training parameters. Example structure:

```yaml
# configs/searchqa/default.yaml
backend: azure_openai
model: gpt-4
benchmark:
  name: SearchQA
  data_dir: data/searchqa
  splits: [train, val, test]
```

---

## **Directory Structure**

```
SkillOpt/
├── configs/          # Configuration files for benchmarks
│   └── searchqa/
│       └── default.yaml
├── data/             # Benchmark datasets
│   └── searchqa/
│       ├── train/
│       ├── val/
│       └── test/
├── scripts/          # Training and evaluation scripts
│   ├── train.py
│   └── materialize_searchqa.py
└── skillopt/         # Core SkillOpt library
```

---

## **Tips**

- Use `--help` with any command for detailed options:
  ```bash
  skillopt-eval --help
  skillopt-sleep run --help
  ```
- For **development**, install SkillOpt in editable mode:
  ```bash
  git clone https://github.com/microsoft/SkillOpt.git
  cd SkillOpt
  pip install -e .
  ```
- To install **optional dependencies** (e.g., for SearchQA or WebUI):
  ```bash
  pip install -e ".[searchqa,webui]"
  ```

---

## **Troubleshooting**

- **Permission Issues**: Ensure environment variables are set correctly and you have API access.
- **Missing Dependencies**: Install required extras (e.g., `pip install -e ".[searchqa]"`).
- **Model Errors**: Verify your backend and model names in the config file.

---

## **Next Steps**

1. Explore the [official SkillOpt documentation](https://microsoft.github.io/SkillOpt/docs/guideline.html).
2. Check out the [GitHub repository](https://github.com/microsoft/SkillOpt) for updates and examples.
3. Experiment with custom benchmarks and models!
