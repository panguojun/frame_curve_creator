Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeUi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
"@
[NativeUi]::SetProcessDPIAware() | Out-Null
function Save-Client([IntPtr]$handle, [string]$path) {
  $r = New-Object NativeUi+RECT
  [NativeUi]::GetClientRect($handle, [ref]$r) | Out-Null
  $p = New-Object NativeUi+POINT
  [NativeUi]::ClientToScreen($handle, [ref]$p) | Out-Null
  $bmp = New-Object System.Drawing.Bitmap($r.Right, $r.Bottom)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($p.X, $p.Y, 0, 0, $bmp.Size)
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Output "client $($r.Right)x$($r.Bottom) at $($p.X),$($p.Y) -> $path"
}
$process = Start-Process -FilePath (Join-Path (Get-Location) 'Frame3DCurveBoard.exe') -ArgumentList '--log-file', (Join-Path (Get-Location) 'build/ui_click.log') -PassThru
try {
  Start-Sleep -Seconds 3
  $process.Refresh()
  $handle = $process.MainWindowHandle
  Write-Output "pid=$($process.Id) handle=$handle"
  if ($handle -eq [IntPtr]::Zero) { throw 'No visible application window' }
  [NativeUi]::SetWindowPos($handle,[IntPtr]::Zero,320,80,0,0,0x0001) | Out-Null
  Start-Sleep -Milliseconds 200
  Save-Client $handle (Join-Path (Get-Location) 'build/ui_before.png')
  $r = New-Object NativeUi+RECT
  [NativeUi]::GetClientRect($handle, [ref]$r) | Out-Null
  $p = New-Object NativeUi+POINT
  [NativeUi]::ClientToScreen($handle, [ref]$p) | Out-Null
  $shell = New-Object -ComObject WScript.Shell
  Write-Output "app_activate=$($shell.AppActivate($process.Id))"
  Start-Sleep -Milliseconds 300
  Write-Output "foreground_set=$([NativeUi]::SetForegroundWindow($handle)) now=$([NativeUi]::GetForegroundWindow())"
  Write-Output "set_cursor=$([NativeUi]::SetCursorPos($p.X + 52, $p.Y + 319))"
  $cursor = New-Object NativeUi+POINT
  [NativeUi]::GetCursorPos([ref]$cursor) | Out-Null
  Write-Output "cursor=$($cursor.X),$($cursor.Y) target=$($p.X + 52),$($p.Y + 319)"
  [NativeUi]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Milliseconds 80
  [NativeUi]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
  Start-Sleep -Seconds 2
  Save-Client $handle (Join-Path (Get-Location) 'build/ui_after.png')
  $before = [System.Drawing.Bitmap]::FromFile((Join-Path (Get-Location) 'build/ui_before.png'))
  $after = [System.Drawing.Bitmap]::FromFile((Join-Path (Get-Location) 'build/ui_after.png'))
  $changed = 0
  for ($x = 620; $x -le 900; $x += 4) {
    for ($y = 500; $y -le 700; $y += 4) {
      $old = $before.GetPixel($x,$y)
      $now = $after.GetPixel($x,$y)
      if (([Math]::Abs([int]$old.R-[int]$now.R)+[Math]::Abs([int]$old.G-[int]$now.G)+[Math]::Abs([int]$old.B-[int]$now.B)) -gt 70) { $changed++ }
    }
  }
  $before.Dispose(); $after.Dispose()
  Write-Output "perspective_changed_samples=$changed"
  if ($changed -lt 100) { throw 'Surface click did not visibly change the perspective view' }
} finally {
  if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
}






