# QuarkGluonPlasma Controller

Automation program for transferring items from Heliofusion Exoticizer output to Plasma module dedicated AE network.

## Features

- Monitors Heliofusion Exoticizer output when redstone signal is provided
- Transfers dusts + 8 dusts for each dust to Plasma module dedicated AE
- Transfers liquid + 999L for each L to Plasma module dedicated AE
- Takes additional items from main AE network

## Setup

### Hardware Requirements

- Computer with OpenComputers
- ME Interfaces (3x):
  - Output ME Interface (connected to Heliofusion Exoticizer output)
  - Plasma ME Interface (connected to Plasma module dedicated AE)
  - Main ME Interface (connected to main AE network)
- Redstone IO

### Configuration

Edit `config.lua` and set the following addresses:

- `outputMeInterfaceAddress`: ME Interface connected to Heliofusion Exoticizer output
- `plasmaMeInterfaceAddress`: ME Interface connected to Plasma module dedicated AE
- `mainMeInterfaceAddress`: ME Interface connected to main AE network
- `redstoneIoAddress`: Redstone IO component address
- `redstoneIoSide`: Side of redstone IO connected to controller

### Usage

1. Configure all component addresses in `config.lua`
2. Run `main.lua`
3. The program will monitor for redstone signals and automatically transfer items when detected

## How It Works

1. **Idle State**: Waits for redstone signal indicating production is needed
2. **Transfer Items State**: 
   - Gets items from Heliofusion Exoticizer output
   - Transfers dusts (original + 8x) to Plasma module
   - Transfers liquids (original + 999L) to Plasma module
   - Requests additional items from main AE network

## Notes

- The program only checks for outputs when redstone signal is provided
- Transfer amounts are calculated as: dusts = count + (8 * count), liquids = count + 999L
- Additional items are requested from main AE network

