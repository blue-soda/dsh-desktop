' Launch the DeepSeek Harness desktop development build without a console window.
'
' The shortcut used to point straight at dsh-desktop.cmd, which opened a console and made
' Electron a child of it: closing that console killed the application. This wrapper runs the
' same launcher with a hidden window, so nothing on screen can be closed by accident.
'
' Quit the application from the tray menu (Quit DeepSeek Harness) or its own Quit command.
' For a visible console while rebuilding or troubleshooting, run dsh-desktop-full.cmd instead.
Set shell = CreateObject("WScript.Shell")
launcher = shell.ExpandEnvironmentStrings("%USERPROFILE%") & "\bin\dsh-desktop.cmd"
shell.Run """" & launcher & """", 0, False
