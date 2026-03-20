## Edge Studio 
Edge Studio is a .NET application written in C# using the Avalonia framework and SukiUI theme and controls.  It is a desktop application that allows you to create a local Ditto Database based on a database registered in the Ditto Portal and use the Ditto SDK to query information in the Ditto Edge Server, local Edge Server, or P2P with other devices sharing the same DatabaseId.  

Edge Studio can run on Windows, Linux, and macOS with the same codebase.

## Requirements

### Ditto Portal Account:
- You need a Ditto Portal account.  You can sign up for a free account at [Ditto Portal](https://portal.ditto.live/create-account?_gl=1*gkhgpr*_gcl_au*MTE4OTI1ODI0OS4xNzQ3MzEzNTc4*_ga*MTM3NDExNTUyOS4xNzMzMTQ4MTc5*_ga_D8PMW3CCL2*czE3NTAzNTA2MjYkbzE2MyRnMCR0MTc1MDM1MDYyNyRqNTkkbDAkaDA.).

### MacOS 
- A Mac with MacOS 15 and Xcode 16.0 or later installed  
- .NET SDK 10.0 or later installed.

### Linux 
- Debian 9+
- Ubuntu 16.04+
- Fedora 30+
- .NET SDK 10.0 or later installed.
- Avalonia works reliably on most Linux distributions as long as they support the .NET SDK and have either X11 or framebuffer capabilities. 
- WSL 2 distros are supported as well, but libice6, libsm6 and libfontconfig1 dependencies must be installed individually.

### Windows 11
- .NET SDK 10.0 or later installed.

## Getting Started from Source

### Setup Local Database information in .NET Environment Variables

To setup Edge Studio to run, you'll need to tell the it about which DatbaseId to use for the local Ditto Store.  Copy the .env.sample file from the root folder to .env and fill in the values based on your DatabaseId from the Ditto Portal.

### Material Icons
https://pictogrammers.com/library/mdi/