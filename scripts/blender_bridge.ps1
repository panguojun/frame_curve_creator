param(
    [Parameter(Mandatory = $true)][string]$ImportScript,
    [Parameter(Mandatory = $true)][string]$Receipt,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class BlenderBridgeInput {
    [StructLayout(LayoutKind.Sequential)]
    public struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct Key { public ushort VirtualKey; public ushort ScanCode; public uint Flags; public uint Time; public IntPtr ExtraInfo; }
    [StructLayout(LayoutKind.Explicit, Size = 40)]
    public struct Input {
        [FieldOffset(0)] public int Type;
        [FieldOffset(8)] public Key Keyboard;
    }
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect bounds);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);

    private static void Send(ushort virtualKey, ushort scanCode, uint flags) {
        Input input = new Input();
        input.Type = 1;
        input.Keyboard.VirtualKey = virtualKey;
        input.Keyboard.ScanCode = scanCode;
        input.Keyboard.Flags = flags;
        if (SendInput(1, new Input[] { input }, Marshal.SizeOf(typeof(Input))) != 1)
            throw new Win32Exception(Marshal.GetLastWin32Error());
    }
    public static void Shortcut(ushort modifier, ushort key) {
        Send(modifier, 0, 0);
        Send(key, 0, 0);
        Send(key, 0, 2);
        Send(modifier, 0, 2);
    }
    public static void TypeText(string value) {
        foreach (char letter in value) {
            Send(0, letter, 4);
            Send(0, letter, 6);
        }
    }
    public static void Enter() { Send(13, 0, 0); Send(13, 0, 2); }
}
'@

try {
    $windows = @(Get-Process -Name blender -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero })
    if ($windows.Count -eq 0) { exit 2 }

    $foreground = [BlenderBridgeInput]::GetForegroundWindow()
    $foregroundPid = [uint32]0
    [void][BlenderBridgeInput]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
    $target = $windows | Where-Object { $_.Id -eq $foregroundPid } | Select-Object -First 1
    if ($null -eq $target) { $target = $windows | Sort-Object StartTime -Descending | Select-Object -First 1 }
    $window = $target.MainWindowHandle
    $literal = ConvertTo-Json -Compress -InputObject $ImportScript
    $command = 'exec(compile(open(' + $literal + ',encoding="utf-8").read(),' + $literal + ',"exec"))'
    if ($DryRun) {
        Write-Output ("Blender PID {0}; command: {1}" -f $target.Id, $command)
        exit 0
    }

    $cursor = New-Object BlenderBridgeInput+Point
    [void][BlenderBridgeInput]::GetCursorPos([ref]$cursor)
    try {
        [void][BlenderBridgeInput]::ShowWindow($window, 9)
        [void][BlenderBridgeInput]::SetForegroundWindow($window)
        Start-Sleep -Milliseconds 300
        if ([BlenderBridgeInput]::GetForegroundWindow() -ne $window) {
            throw 'Could not focus the open Blender window'
        }
        $bounds = New-Object BlenderBridgeInput+Rect
        if (-not [BlenderBridgeInput]::GetWindowRect($window, [ref]$bounds)) {
            throw 'Could not locate the Blender window'
        }
        [void][BlenderBridgeInput]::SetCursorPos([int]($bounds.Left + ($bounds.Right - $bounds.Left) * 0.35), [int]($bounds.Top + ($bounds.Bottom - $bounds.Top) * 0.5))
        Start-Sleep -Milliseconds 150
        [BlenderBridgeInput]::Shortcut(16, 115) # Shift+F4 opens Blender's Python console.
        Start-Sleep -Milliseconds 350
        if ([BlenderBridgeInput]::GetForegroundWindow() -ne $window) {
            throw 'Blender lost focus before the import command'
        }
        [BlenderBridgeInput]::TypeText($command)
        [BlenderBridgeInput]::Enter()
        $completed = $false
        for ($attempt = 0; $attempt -lt 120; $attempt++) {
            if (Test-Path -LiteralPath $Receipt) { $completed = $true; break }
            Start-Sleep -Milliseconds 100
        }
        if ([BlenderBridgeInput]::GetForegroundWindow() -eq $window) {
            [BlenderBridgeInput]::Shortcut(16, 116) # Shift+F5 returns to the 3D viewport.
        }
        if (-not $completed) { throw 'Blender did not confirm the import within 12 seconds' }
        Write-Output (Get-Content -LiteralPath $Receipt -Raw)
    }
    finally {
        [void][BlenderBridgeInput]::SetCursorPos($cursor.X, $cursor.Y)
    }
    exit 0
}
catch {
    Write-Output $_.Exception.Message
    exit 1
}
