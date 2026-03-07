# Logging

Capture and view log messages from the Ditto SDK in real time.

## Overview

The Logging view intercepts messages written by the Ditto SDK and displays them here for debugging.

## Log Levels

| Level   | Description                          |
|---------|--------------------------------------|
| Verbose | All messages including internal ones |
| Debug   | Debug messages                       |
| Info    | General information messages         |
| Warning | Non-fatal issues and warnings        |
| Error   | Errors and failures                  |

## Filtering

- **Search box** — Filter by message content
- **Component** — Filter by Sync, Store, Query, Transport, etc.
- **SDK Level** — Change the minimum Ditto log level in the sidebar

## Tips

- Set SDK Level to **verbose** to see all messages
- Use the Component filter to focus on a specific subsystem
- Click **Clear** to reset the log buffer
