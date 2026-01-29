# Magmatter Controller

Automation program for managing the magmatter module puzzle in GTNH. Automatically detects puzzle outputs, pulls required liquids from ready liquid interfaces, and returns them to complete the puzzle.

## Features

- Monitors two puzzle output interfaces for module outputs (tachyon rich temporal fluid, spatially enlarged fluid, and dust)
- Automatically pulls all items and liquids from puzzle outputs to main network
- Pulls required liquids from three ready liquid interfaces:
  - Interface 1: 6 plasmas
  - Interface 2: 6 plasmas
  - Interface 3: 2 plasmas + tachyon rich temporal fluid + spatially enlarged fluid
- Calculates required plasma amount (difference between spatially enlarged and tachyon rich fluid amounts)
- Returns all required liquids to puzzle output interfaces to complete the recipe

## Setup

### Hardware Requirements

- Computer with OpenComputers
- ME Interfaces (5x):
  - Puzzle Output 1 ME Interface (connected to first puzzle output subnet)
  - Puzzle Output 2 ME Interface (connected to second puzzle output subnet)
  - Ready Liquid 1 ME Interface (6 plasmas, with adapter behind)
  - Ready Liquid 2 ME Interface (6 plasmas, with adapter behind)
  - Ready Liquid 3 ME Interface (2 plasmas + tachyon + spatially enlarged, with adapter behind)
- Transposers (5x):
  - Puzzle Output 1 Transposer (above puzzle output 1 interface, connects to main net above)
  - Puzzle Output 2 Transposer (above puzzle output 2 interface, connects to main net above)
  - Ready Liquid 1 Transposer (above ready liquid 1 interface, transfers to puzzle output)
  - Ready Liquid 2 Transposer (above ready liquid 2 interface, transfers to puzzle output)
  - Ready Liquid 3 Transposer (above ready liquid 3 interface, transfers to puzzle output)
- Adapters behind each interface with stocked materials/fluids

### Configuration

Edit `config.lua` and set the following addresses:

**Puzzle Output Interfaces:**
- `puzzleOutput1MeInterfaceAddress`: First puzzle output ME interface address
- `puzzleOutput2MeInterfaceAddress`: Second puzzle output ME interface address

**Ready Liquid Interfaces:**
- `readyLiquid1MeInterfaceAddress`: First ready liquid ME interface (6 plasmas)
- `readyLiquid2MeInterfaceAddress`: Second ready liquid ME interface (6 plasmas)
- `readyLiquid3MeInterfaceAddress`: Third ready liquid ME interface (2 plasmas + tachyon + spatially enlarged)

**Transposers:**
- `puzzleOutput1TransposerAddress`: Transposer above first puzzle output interface
- `puzzleOutput2TransposerAddress`: Transposer above second puzzle output interface
- `readyLiquid1TransposerAddress`: Transposer above first ready liquid interface
- `readyLiquid2TransposerAddress`: Transposer above second ready liquid interface
- `readyLiquid3TransposerAddress`: Transposer above third ready liquid interface

**Transposer Sides:**
- `puzzleOutput1TransposerOutputSide`: Side of puzzle output 1 transposer connected to puzzle output interface
- `puzzleOutput1TransposerMainSide`: Side of puzzle output 1 transposer connected to main interface
- `puzzleOutput2TransposerOutputSide`: Side of puzzle output 2 transposer connected to puzzle output interface
- `puzzleOutput2TransposerMainSide`: Side of puzzle output 2 transposer connected to main interface
- `readyLiquid1TransposerReadySide`: Side of ready liquid 1 transposer connected to ready liquid interface
- `readyLiquid1TransposerOutputSide`: Side of ready liquid 1 transposer connected to puzzle output
- `readyLiquid2TransposerReadySide`: Side of ready liquid 2 transposer connected to ready liquid interface
- `readyLiquid2TransposerOutputSide`: Side of ready liquid 2 transposer connected to puzzle output
- `readyLiquid3TransposerReadySide`: Side of ready liquid 3 transposer connected to ready liquid interface
- `readyLiquid3TransposerOutputSide`: Side of ready liquid 3 transposer connected to puzzle output

### Usage

1. Configure all component addresses in `config.lua`
2. Ensure all interfaces have adapters behind them with stocked materials/fluids
3. Run `main.lua`
4. The program will continuously monitor puzzle output interfaces and automatically process outputs

## How It Works

### Puzzle Output Detection

The controller monitors both puzzle output interfaces every second for:
- **Tachyon Rich Temporal Fluid**: 1-50L
- **Spatially Enlarged Fluid**: 51-100L
- **Dust Material**: 1 dust of a high tier material

### Processing Flow

1. **Idle State**: Continuously checks puzzle output interfaces every second for new outputs

2. **Pull To Main State**: 
   - Pulls all items and liquids from both puzzle output interfaces
   - Transfers them to main network via transposers above puzzle output interfaces
   - This clears the puzzle output interfaces for the return step

3. **Pull Required Liquids State**:
   - Pulls tachyon rich temporal fluid from Ready Liquid Interface 3
   - Pulls spatially enlarged fluid from Ready Liquid Interface 3
   - Calculates required plasma amount: `spatially_enlarged_amount - tachyon_rich_amount` (in ingots)
   - Searches all three ready liquid interfaces for the required plasma type
   - Pulls plasma from whichever interface(s) have it until required amount is met

4. **Return To Puzzle State**:
   - Verifies all required liquids are present in puzzle output interfaces
   - Once all fluids are returned in correct amounts, the recipe processes and outputs magmatter

## Puzzle Mechanics

The magmatter module outputs:
- 1-50L of tachyon rich temporal fluid
- 51-100L of spatially enlarged fluid
- 1 dust of a high tier material

To complete the puzzle, you must return:
- The same amount of tachyon rich temporal fluid
- The same amount of spatially enlarged fluid
- Plasma of the dust's material (in ingots) equal to the difference between spatially enlarged and tachyon rich fluid amounts

Example: If module outputs 20L tachyon rich and 80L spatially enlarged, you need to return:
- 20L tachyon rich temporal fluid
- 80L spatially enlarged fluid
- 60 ingots of plasma (80 - 20 = 60)

## Notes

- The program checks for outputs every second automatically (no redstone triggering needed)
- All ready liquids must be pre-stocked in the ready liquid interfaces via adapters
- The controller searches all three ready liquid interfaces for plasma, so plasma can be distributed across interfaces
- Module has 64 base parallel processing capability
- Once all required fluids are returned, the recipe automatically processes and outputs magmatter
