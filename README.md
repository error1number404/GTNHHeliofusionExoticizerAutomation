# GTNHHeliofusionExoticizerAutomation

A collection of OpenComputers automation programs for managing Heliofusion Exoticizer production in GregTech: New Horizons (GTNH).

## Projects

- **QuarkGluonPlasma**: Automation for transferring items from Heliofusion Exoticizer output to Plasma module dedicated AE network
- **Magmatter**: Automation for managing fluid transfers between main AE network and Heliofusion Exoticizer subnets

## Installation

Each project includes an automated installer script. To install a program:

1. **Navigate to the project directory** on your OpenComputers computer
2. **Download the installer**:
   ```lua
   wget https://raw.githubusercontent.com/error1number404/GTNHHeliofusionExoticizerAutomation/master/[ProjectName]/installer.lua && installer
   ```
   Replace `[ProjectName]` with either `QuarkGluonPlasma` or `Magmatter`

3. **Run the installer**:
   ```lua
   installer
   ```

The installer will:
- Create necessary directories (`src`, `lib`, `lib/gui-widgets`, `lib/logger-handler`)
- Download all required files from the GitHub repository
- Preserve your existing `config.lua` if it exists (otherwise downloads a default one)
- Reboot the computer after installation completes

### Example Installation Commands

**For QuarkGluonPlasma:**
```lua
wget https://raw.githubusercontent.com/error1number404/GTNHHeliofusionExoticizerAutomation/master/QuarkGluonPlasma/installer.lua && installer
```

**For Magmatter:**
```lua
wget https://raw.githubusercontent.com/error1number404/GTNHHeliofusionExoticizerAutomation/master/Magmatter/installer.lua && installer
```

## Configuration

After installation, edit `config.lua` in the project directory to configure:
- ME Interface addresses
- Redstone IO component address and side
- Other hardware-specific settings

See individual project READMEs for detailed configuration instructions:
- [QuarkGluonPlasma README](QuarkGluonPlasma/README.md)
- [Magmatter README](Magmatter/README.md)

## Usage

Once installed and configured, run the program:
```lua
main
```

Each program monitors for redstone signals and automatically manages item/fluid transfers when production is needed.

## Requirements

- OpenComputers mod
- Computer with appropriate tier components
- ME Interfaces connected to your AE networks
- Redstone IO component
- Internet Card (for installation and auto-updates)

See individual project READMEs for specific hardware requirements.