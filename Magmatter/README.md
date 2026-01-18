# Magmatter Controller

Automation program for managing fluid transfers between main AE network and Heliofusion Exoticizer subnets.

## Features

- Monitors Heliofusion Exoticizer output in dedicated subnet when redstone signal is provided
- Takes required fluids from main AE network
- Puts required liquids in input subnet responsible for inputting liquids to Heliofusion Exoticizer

## Setup

### Hardware Requirements

- Computer with OpenComputers
- ME Interfaces (3x):
  - Output ME Interface (in dedicated subnet connected to Heliofusion Exoticizer output)
  - Main ME Interface (connected to main AE network)
  - Input ME Interface (in subnet responsible for inputting liquids to Heliofusion Exoticizer)
- Redstone IO

### Configuration

Edit `config.lua` and set the following addresses:

- `outputMeInterfaceAddress`: ME Interface in dedicated subnet connected to Heliofusion Exoticizer output
- `mainMeInterfaceAddress`: ME Interface connected to main AE network
- `inputMeInterfaceAddress`: ME Interface in subnet responsible for inputting liquids
- `redstoneIoAddress`: Redstone IO component address
- `redstoneIoSide`: Side of redstone IO connected to controller

### Usage

1. Configure all component addresses in `config.lua`
2. Run `main.lua`
3. The program will monitor for redstone signals and automatically manage fluid transfers when detected

## How It Works

1. **Idle State**: Waits for redstone signal indicating production is needed
2. **Process Outputs State**: 
   - Gets items from Heliofusion Exoticizer output in dedicated subnet
   - Determines required fluids based on outputs
   - Transfers required fluids from main AE network
   - Exports required liquids to input subnet

## Notes

- The program only checks for outputs when redstone signal is provided
- All operations happen in dedicated subnets as specified
- Fluids are transferred from main network to input subnet for Heliofusion Exoticizer

