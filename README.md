# Edge Studio

Edge Studio is an application that allows you to connect to Edge Studio and use the Ditto SDK to query information in the Ditto Edge Server, local Edge Server, or P2P with other devices sharing the same AppId.

## Requirements
### Ditto Portal Account:
- You need a Ditto Portal account.  You can sign up for a free account at [Ditto Portal](https://portal.ditto.live/create-account?_gl=1*gkhgpr*_gcl_au*MTE4OTI1ODI0OS4xNzQ3MzEzNTc4*_ga*MTM3NDExNTUyOS4xNzMzMTQ4MTc5*_ga_D8PMW3CCL2*czE3NTAzNTA2MjYkbzE2MyRnMCR0MTc1MDM1MDYyNyRqNTkkbDAkaDA.).

### SwiftUI:
- A Mac with MacOS 15 and Xcode 16.0 or later installed  
- An iPad with OS 18.0 or later installed.

Note: The SwiftUI app is only officially supports MacOS and iPadOS.  While it will build and run on iOS, it has not been tested on iOS.

### Rust:
TODO

## Getting Started from Source

Edge Studio requires a dedicated AppId to that it uses to save:

- Registered Apps
- Subscriptions
- Query History
- Query Favorites
- Observers

These are saved into a local Ditto Store that is created when the app is first run.  This store will not sync to the cloud or to other devices.  This is by design.

### Setup Local Database information in SwiftUI

To setup Edge Studio to run, you'll need to tell the it about which AppId to use for the local Ditto Store.  Copy the dittoConfig.plist file from the root folder into the SwiftUI/Ditto Edge Studio/ folder and fill in the values based on your AppId from the Ditto Portal.

- Rust:
TODO

