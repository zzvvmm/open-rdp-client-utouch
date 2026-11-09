# PC library and connection workflows

Linux desktop and Ubuntu Touch offer the same PC library features. Linux uses a
navigation rail; Ubuntu Touch uses bottom navigation and a Library options sheet.
The layout takes inspiration from [Windows App's connection center](https://learn.microsoft.com/en-us/windows-app/get-started-connect-devices-desktops-apps?pivots=remote-pc).

## Find and organize PCs

- **All** shows saved PCs. **Favorites** shows starred PCs. **Recent** shows PCs
  that have connected successfully, newest first. Existing timestamps are retained.
- Search matches a PC's friendly name, address, or group. Search and group filters
  work together with Favorites and Recent.
- Choose Grid or List and sort by name, address, or last connection. These choices
  persist independently in each platform's existing settings. Recent always sorts
  newest first. Ubuntu Touch uses compact rows when the viewport is short.
- Assign a group in the PC editor, choosing an existing name or entering a new one.
  Select a group in the library to rename or remove it. Renaming to an existing
  name combines the groups. Removing a group moves its PCs to **Saved PCs**;
  it does not delete them. Empty groups are not stored separately.
- A PC's menu offers Connect, Edit, Duplicate, Clear thumbnail, and Delete.
  Thumbnails describe a previous session; they do not indicate whether a PC is
  currently online. Connected/Connecting badges describe the app's active session.

## Add a PC or connect temporarily

**Add PC** opens General, Display, and Devices settings. Choose **Save** to keep
it in the library, or **Save & Connect** to save and then connect. The editor stays
open with its input intact if address validation or storage fails.

**Quick Connect** accepts a hostname, IPv4 address, or IPv6 address. An optional
port can be included, such as `work-pc:3390` or `[fd00::1234]:3390`. Choose an
existing saved account or **Ask every time**. Temporary connections use the
connection defaults from Settings.

Quick Connect does not add a PC to the library, Recent, or thumbnail cache.
Choose **Save PC** from the session to keep it, including its successful-connection
time. A temporary target remains in memory for retry and is lost when the app
closes or a later temporary connection replaces it. Typed passwords are cleared
after submission or cancellation; saving a PC never saves the entered password.
Passwords are stored only through an explicit account-save action.

Saved accounts are credentials for remote PCs. They are separate from Microsoft
work/school account sign-in and cloud workspace subscriptions.

## Connection feedback

The connection view shows progress through resolving, connecting, TLS,
certificate verification, and authentication. Cancel stops the attempt. A failure
keeps its details visible and offers **Retry** and **Back to PCs**. Retry reads the
current saved credentials or asks for them again.

Only one session is active. Connecting to another PC requires confirmation before
replacing the session. Returning to an already active PC resumes its session view.
Certificate-change warnings still require an explicit trust decision.

Desktop reserves **Ctrl+Alt+Enter** for fullscreen. Escape continues to reach the
remote PC. Fixed-resolution profiles keep their configured size; Dynamic follows
the actual session viewport.

## Bridge additions

The existing C ABI and JSON actions remain available. New JSON actions are
`quick_connect` (`hostInput`, optional `accountId`, viewport dimensions),
`save_temporary_pc` (optional `friendlyName`, `groupName`), `rename_group`
(`groupName`, `newName`), and `remove_group` (`groupName`). Credentials supplied
in response to a prompt continue through `connect_pc` using the returned ID.

Requests may include a string `requestId`. The matching `action_result` event
contains `requestId`, `action`, `ok`, `message`, and optional `entityId`. Error
results contain no request payload or credentials. Requests without a correlation
ID continue to receive `toast_error` on failure. Successful saves emit their state
snapshot before the action result.

Session snapshots add `activeProfile`, `isTemporary`, and `stageDetail`.
`activeProfile` uses the library profile representation and also covers unsaved
connections. Settings add `libraryLayout` (`grid` or `list`) and `librarySort`
(`name`, `address`, or `recent`), with grid/name defaults for existing data.
