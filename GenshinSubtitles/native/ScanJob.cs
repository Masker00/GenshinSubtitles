using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

// One bounded process per scan. The job owns all descendants, including Python.
// stdin gates execution until the process has joined the job, closing the spawn race.
public sealed class SubtitleScanJob : IDisposable {
    private Process process;
    private IntPtr job;
    private readonly Task<string> stdout, stderr;
    public string Stamp { get; private set; }
    public int Generation { get; private set; }
    public int ProcessId { get; private set; }
    public DateTime DeadlineUtc { get; private set; }

    [StructLayout(LayoutKind.Sequential)] private struct IoCounters {
        public ulong ReadOperations, WriteOperations, OtherOperations;
        public ulong ReadBytes, WriteBytes, OtherBytes;
    }
    [StructLayout(LayoutKind.Sequential)] private struct BasicLimit {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinimumWorkingSet, MaximumWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] private struct ExtendedLimit {
        public BasicLimit Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", SetLastError=true)] private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimit info, uint length);
    [DllImport("kernel32.dll", SetLastError=true)] private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);

    private SubtitleScanJob(Process child, IntPtr handle, Task<string> output, Task<string> error, string stamp, int generation, int timeout) {
        process = child; job = handle; stdout = output; stderr = error;
        Stamp = stamp; Generation = generation; ProcessId = child.Id;
        DeadlineUtc = DateTime.UtcNow.AddSeconds(timeout);
    }
    public static SubtitleScanJob Start(string shell, string script, string request, string stamp, int generation, int timeout) {
        string command = "$null=[Console]::In.ReadLine(); & '" + script.Replace("'", "''") + "' -WorkerRequest '" + request.Replace("'", "''") + "'";
        string encoded = Convert.ToBase64String(Encoding.Unicode.GetBytes(command));
        var info = new ProcessStartInfo(shell, "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand " + encoded);
        info.UseShellExecute = false; info.CreateNoWindow = true;
        info.RedirectStandardInput = true; info.RedirectStandardOutput = true; info.RedirectStandardError = true;
        info.StandardOutputEncoding = Encoding.UTF8; info.StandardErrorEncoding = Encoding.UTF8;
        var child = new Process(); child.StartInfo = info;
        IntPtr handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot create scan cleanup job.");
        try {
            var limits = new ExtendedLimit(); limits.Basic.Flags = 0x2000; // KILL_ON_JOB_CLOSE
            if (!SetInformationJobObject(handle, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimit))))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot configure scan cleanup job.");
            if (!child.Start()) throw new InvalidOperationException("Cannot start scan worker.");
            if (!AssignProcessToJobObject(handle, child.Handle))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Cannot attach scan worker to cleanup job.");
            var output = child.StandardOutput.ReadToEndAsync(); var error = child.StandardError.ReadToEndAsync();
            child.StandardInput.WriteLine("ready"); child.StandardInput.Close();
            return new SubtitleScanJob(child, handle, output, error, stamp, generation, timeout);
        } catch {
            CloseHandle(handle);
            try { if (!child.HasExited) child.Kill(); } catch { }
            child.Dispose(); throw;
        }
    }
    public bool Completed { get { return process != null && process.HasExited && stdout.IsCompleted && stderr.IsCompleted; } }
    public bool TimedOut { get { return DateTime.UtcNow >= DeadlineUtc; } }
    public string Output { get { if (!Completed) throw new InvalidOperationException("Worker is busy."); return stdout.Result; } }
    public string Error { get { if (!Completed) throw new InvalidOperationException("Worker is busy."); return stderr.Result; } }
    public int ExitCode { get { return process.ExitCode; } }
    public void Dispose() {
        if (job != IntPtr.Zero) { CloseHandle(job); job = IntPtr.Zero; }
        if (process == null) return;
        try { if (!process.HasExited) process.Kill(); process.WaitForExit(300); } catch { }
        process.Dispose(); process = null;
    }
}
