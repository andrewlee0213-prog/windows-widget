' 挂件看门狗: 每60秒检查GLM挂件进程, 不在则自动拉起 (隐藏运行)
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
Do While True
    Set procs = GetObject("winmgmts:\\.\root\cimv2").ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='powershell.exe' AND CommandLine LIKE '%glm-widget.ps1%'")
    If procs.Count = 0 Then
        sh.Run "wscript.exe """ & dir & "\launch.vbs""", 0, False
    End If
    WScript.Sleep 60000
Loop
