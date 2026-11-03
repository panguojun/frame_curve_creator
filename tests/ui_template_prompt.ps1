Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class TemplateUi {
 [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
}
"@
[TemplateUi]::SetProcessDPIAware() | Out-Null
$proc = Start-Process -FilePath (Join-Path (Get-Location) 'Frame3DCurveBoard.exe') -ArgumentList '--log-file', (Join-Path (Get-Location) 'build/template_ui.log') -PassThru
try {
 Start-Sleep -Seconds 3
 $proc.Refresh()
 $handle = $proc.MainWindowHandle
 if ($handle -eq [IntPtr]::Zero) { throw 'No visible main window' }
 [TemplateUi]::SetWindowPos($handle,[IntPtr]::Zero,320,80,0,0,0x0001) | Out-Null
 [TemplateUi]::SetForegroundWindow($handle) | Out-Null
 Start-Sleep -Milliseconds 300
 [TemplateUi]::SetCursorPos(381,387) | Out-Null
 [TemplateUi]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 100
 [TemplateUi]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Seconds 1
 $shell = New-Object -ComObject WScript.Shell
 $shell.SendKeys('{ENTER}')
 Start-Sleep -Seconds 1
 $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
 $bmp = New-Object System.Drawing.Bitmap($bounds.Width,$bounds.Height)
 $g = [System.Drawing.Graphics]::FromImage($bmp)
 $g.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bmp.Size)
 $path = Join-Path (Get-Location) 'build/template_prompt.png'
 $bmp.Save($path,[System.Drawing.Imaging.ImageFormat]::Png)
 $g.Dispose(); $bmp.Dispose()
 [TemplateUi]::SetCursorPos(1112,545) | Out-Null
 [TemplateUi]::mouse_event(0x0002,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Milliseconds 100
 [TemplateUi]::mouse_event(0x0004,0,0,0,[UIntPtr]::Zero)
 Start-Sleep -Seconds 1
 $after = New-Object System.Drawing.Bitmap($bounds.Width,$bounds.Height)
 $afterGraphics = [System.Drawing.Graphics]::FromImage($after)
 $afterGraphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$after.Size)
 $afterPath = Join-Path (Get-Location) 'build/template_replaced.png'
 $after.Save($afterPath,[System.Drawing.Imaging.ImageFormat]::Png)
 $afterGraphics.Dispose(); $after.Dispose()
 Write-Output "pid=$($proc.Id) prompt_capture=$path replaced_capture=$afterPath"
} finally { if (!$proc.HasExited) { Stop-Process -Id $proc.Id -Force } }
