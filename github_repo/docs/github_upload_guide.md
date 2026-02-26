# Step-by-Step: How to Upload to GitHub

Follow these exact steps to publish your Ibex UVM testbench as a professional portfolio project.

---

## Step 1 — Install Git (if needed)

**Windows:**  
Download from https://git-scm.com/download/win and install.

**Mac:**  
```bash
xcode-select --install
```

**Linux (Ubuntu/Debian):**  
```bash
sudo apt-get install git
```

Verify:
```bash
git --version
# Should show: git version 2.x.x
```

---

## Step 2 — Configure Git with your identity

```bash
git config --global user.name  "Your Full Name"
git config --global user.email "you@example.com"
```

---

## Step 3 — Create the GitHub repository

1. Go to **https://github.com/new**
2. Fill in:
   - **Repository name:** `ibex-uvm-tb`
   - **Description:** `UVM 1.2 testbench for the lowRISC Ibex RV32IMC processor — RVFI-based ISA golden model scoreboard, 9 test classes, full architectural state verification`
   - **Visibility:** Public ✅ (required to show on your profile)
   - **DO NOT** check "Initialize this repository with a README" (we have our own)
3. Click **Create repository**
4. Copy the URL shown — it will look like:  
   `https://github.com/YOUR_USERNAME/ibex-uvm-tb.git`

---

## Step 4 — Set up the local repo

Unzip the files you downloaded, then:

```bash
# Go into the folder containing all the files
cd ibex-uvm-tb    # or wherever you extracted them

# Initialize git
git init

# Add the Ibex RTL as a submodule (this links to the real lowRISC RTL)
git submodule add https://github.com/lowRISC/ibex.git rtl

# Stage everything
git add .

# First commit
git commit -m "feat: initial UVM testbench for Ibex RV32IMC core

- Full UVM 1.2 architecture: transaction, sequences, driver, monitor,
  agent, scoreboard, env, 9 test classes
- RVFI-based ISA golden model scoreboard (predict-and-check)
- Verifies: all RV32IM instructions, PC updates, load/store byte enables,
  data hazards/forwarding, CSRs, interrupts
- OBI memory model with configurable grant/rvalid delays
- Functional coverage: opcode × rd cross, branch taken/not-taken, LSU width
- Makefile targets for VCS, Xcelium, Questa + regression runner
- Verification plan: 40 test plan items with priority ratings"
```

---

## Step 5 — Push to GitHub

```bash
# Connect local repo to GitHub (paste your URL from Step 3)
git remote add origin https://github.com/YOUR_USERNAME/ibex-uvm-tb.git

# Rename default branch to 'main' (GitHub standard)
git branch -M main

# Push
git push -u origin main
```

If GitHub asks for credentials:
- **Username:** your GitHub username
- **Password:** use a **Personal Access Token** (not your password)  
  → GitHub → Settings → Developer Settings → Personal Access Tokens → Tokens (classic) → Generate new token → check `repo` scope

---

## Step 6 — Add topics to your repo (makes it discoverable)

1. Go to your repo page on GitHub
2. Click the ⚙️ gear icon next to "About" (top right of the repo page)
3. Add these **Topics:**
   ```
   uvm  risc-v  ibex  systemverilog  verification  cpu  dv  rvfi  fpga  lowrisc
   ```
4. Add **Website:** `https://ibex-core.readthedocs.io/` (links to Ibex docs)
5. Click **Save changes**

---

## Step 7 — Pin the repo on your GitHub profile

1. Go to your GitHub profile: `https://github.com/YOUR_USERNAME`
2. Click **Customize your pins**
3. Select `ibex-uvm-tb`
4. Click **Save pins**

This puts your project front and center on your profile page.

---

## Step 8 — Verify everything looks right

Visit `https://github.com/YOUR_USERNAME/ibex-uvm-tb` and check:

- ✅ README renders with the architecture diagram
- ✅ All 10 `.sv` files visible in their subdirectories
- ✅ `docs/verification_plan.md` present
- ✅ **Actions** tab shows the lint CI workflow ran (green ✓ or yellow ○)
- ✅ Topics appear under the description
- ✅ File count in each directory is correct

---

## Step 9 — Update your LinkedIn / resume

**LinkedIn headline addition:**
> Hands-on UVM CPU DV: implemented full UVM 1.2 testbench for lowRISC Ibex RV32IMC core — RVFI-based ISA golden model scoreboard, architectural state verification, hazard/forwarding sequences

**Resume bullet points:**
```
• Designed UVM 1.2 testbench for lowRISC Ibex RV32IMC RISC-V processor core
  - RVFI-based ISA golden model scoreboard: checks rd_wdata, next PC, and memory
    address/data on every retired instruction without pipeline signal probing
  - 8 directed sequences targeting: ALU, load/store, control flow, data hazards,
    CSR access, interrupts, and 1000-instruction random regressions
  - OBI memory model with configurable grant/rvalid delays for timing corner coverage
  - Functional coverage: opcode×rd cross, branch taken/not-taken, LSU access width
  - Verified: all 47 RV32I + 8 M-extension instructions, 9 CSRs, interrupt entry/exit
```

**GitHub profile README** (add to your profile's README.md):
```markdown
### Featured Projects
| Project | Description | Stack |
|---------|-------------|-------|
| [ibex-uvm-tb](https://github.com/YOUR_USERNAME/ibex-uvm-tb) | UVM testbench for Ibex RISC-V core | SystemVerilog · UVM 1.2 · RVFI |
```

---

## Step 10 — Keep the repo active (optional but recommended)

Future improvements to commit over time:
```bash
# Example: add a new test, then commit it
git add test/ibex_tests.sv
git commit -m "feat(test): add multiply corner case sequence for DIV-by-zero"
git push
```

Good commit message format for this kind of repo:
- `feat(scoreboard): add CSRRC atomicity check`
- `fix(driver): handle back-to-back OBI grants correctly`  
- `test: add JALR negative-offset directed test`
- `docs: expand verification plan with coverage goals`

---

## Troubleshooting

**`git push` asks for password repeatedly:**  
Set up SSH keys: https://docs.github.com/en/authentication/connecting-to-github-with-ssh

**Submodule shows as empty folder:**  
```bash
git submodule update --init --recursive
```

**GitHub Actions lint fails:**  
That's OK — Verilator can't fully lint UVM code without the UVM package. The CI workflow is designed to check file structure and key patterns, not full compilation.

**Want to make the repo private later:**  
GitHub → Settings → scroll to "Danger Zone" → Change visibility
