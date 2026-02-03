# Edge Debug Helper
Edge Debug Helper is a set of tools and an application that allows you to create a local Ditto Database based on a database registered in the Ditto Portal and use the Ditto SDK to query information in the Ditto Edge Server, local Edge Server, or P2P with other devices sharing the same DatabaseId.

## ⚠️ DISCLAIMER

**THIS SOFTWARE IS PROVIDED "AS-IS" WITHOUT WARRANTY OF ANY KIND.**

This tool is **NOT** officially supported by Ditto or the author. It is provided as a community resource for development and debugging purposes only.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

By using this software, you acknowledge and agree that:
- There is no official support from Ditto or the author
- The software may contain bugs or incomplete features
- You use this software at your own risk
- No warranty of any kind is provided
- The authors are not liable for any damages resulting from use of this software

For official Ditto support and documentation, please visit [Ditto Documentation](https://docs.ditto.live/).

## Swift UI App
Edge Debug Helper is a SwiftUI application that allows you to create a local Ditto Database based on a database registered in the Ditto Portal and use the Ditto SDK to query information in the Ditto Edge Server, local Edge Server, or P2P with other devices sharing the same DatabaseId.

## Rust 
The rust folder contains Edge Bot (codename Grimlock), which is a tool that allows you to register local workflow tasks such as:
- import data from a JSON file at a set interval
- update data from a JSON file at a set interval
- export data to a JSON file based on an observer firing 

## Requirements

### Ditto Portal Account:
- You need a Ditto Portal account.  You can sign up for a free account at [Ditto Portal](https://portal.ditto.live/create-account?_gl=1*gkhgpr*_gcl_au*MTE4OTI1ODI0OS4xNzQ3MzEzNTc4*_ga*MTM3NDExNTUyOS4xNzMzMTQ4MTc5*_ga_D8PMW3CCL2*czE3NTAzNTA2MjYkbzE2MyRnMCR0MTc1MDM1MDYyNyRqNTkkbDAkaDA.).

### SwiftUI:
- A Mac with MacOS 15 and Xcode 16.0 or later installed  
- An iPad with OS 18.0 or later installed.

Note: The SwiftUI app is only officially supports MacOS and iPadOS.  While it will build and run on iOS, it has not been tested on iOS and there are known issues with the SwiftUI app on iOS.

## Rust:
- Rust 1.84.0 or later installed.
- Cargo installed.


## Getting Started from Source

The SwiftUI Edge Debug Helper app requires a dedicated DatabaseId to that it uses to save:
- Registered Apps
- Subscriptions
- Query History
- Query Favorites
- Observers

These are saved into a local Ditto Store that is created when the app is first run.  This store will not sync to the cloud or to other devices.  This is by design.

### Setup Local Database information in SwiftUI

To setup Edge Debug Helper to run, you'll need to tell the it about which AppId to use for the local Ditto Store.  Copy the dittoConfig.plist file from the root folder into the SwiftUI/Edge Debug Helper/ folder and fill in the values based on your DatabaseId from the Ditto Portal.

- Rust:
TODO

