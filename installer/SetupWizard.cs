using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;

internal sealed class MusicoSetupForm : Form
{
    private readonly TextBox installPath;
    private readonly TextBox mediaPath;
    private readonly ProgressBar progress;
    private readonly Label status;
    private Button installButton;

    public MusicoSetupForm()
    {
        Text = "Musico Setup";
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        Width = 620;
        Height = 400;
        BackColor = Color.FromArgb(15, 17, 24);
        ForeColor = Color.FromArgb(241, 240, 242);

        var title = new Label
        {
            Text = "Install Musico",
            Font = new Font("Segoe UI", 20, FontStyle.Bold),
            ForeColor = ForeColor,
            Location = new Point(28, 24),
            AutoSize = true,
        };
        Controls.Add(title);

        Controls.Add(CreateLabel("Install location", 28, 82));
        installPath = CreatePathBox(InstallerEngine.DefaultInstallDirectory(), 28, 108);
        Controls.Add(installPath);
        Controls.Add(CreateBrowseButton(520, 106, installPath));

        Controls.Add(CreateLabel("Media storage location", 28, 154));
        mediaPath = CreatePathBox(InstallerEngine.DefaultMediaDirectory(), 28, 180);
        Controls.Add(mediaPath);
        Controls.Add(CreateBrowseButton(520, 178, mediaPath));

        progress = new ProgressBar
        {
            Location = new Point(28, 232),
            Size = new Size(556, 14),
            Style = ProgressBarStyle.Marquee,
            MarqueeAnimationSpeed = 0,
        };
        Controls.Add(progress);

        status = new Label
        {
            Location = new Point(28, 252),
            Size = new Size(556, 40),
            ForeColor = Color.FromArgb(176, 174, 182),
            Text = "",
        };
        Controls.Add(status);

        var cancel = new Button
        {
            Text = "Cancel",
            Location = new Point(365, 310),
            Size = new Size(100, 36),
        };
        cancel.Click += (s, e) => Close();
        Controls.Add(cancel);

        installButton = new Button
        {
            Text = "Install Musico",
            Location = new Point(473, 310),
            Size = new Size(111, 36),
        };
        installButton.Click += InstallClicked;
        Controls.Add(installButton);
    }

    private Label CreateLabel(string text, int x, int y)
    {
        return new Label
        {
            Text = text,
            Location = new Point(x, y),
            AutoSize = true,
            ForeColor = Color.FromArgb(212, 210, 216),
            Font = new Font("Segoe UI", 9, FontStyle.Bold),
        };
    }

    private TextBox CreatePathBox(string text, int x, int y)
    {
        return new TextBox
        {
            Text = text,
            Location = new Point(x, y),
            Size = new Size(484, 28),
            BackColor = Color.FromArgb(27, 28, 35),
            ForeColor = Color.FromArgb(241, 240, 242),
            BorderStyle = BorderStyle.FixedSingle,
        };
    }

    private Button CreateBrowseButton(int x, int y, TextBox target)
    {
        var button = new Button
        {
            Text = "Browse...",
            Location = new Point(x, y),
            Size = new Size(64, 30),
        };
        button.Click += (s, e) =>
        {
            using (var dialog = new FolderBrowserDialog())
            {
                dialog.Description = "Choose Musico folder";
                dialog.ShowNewFolderButton = true;
                dialog.SelectedPath = target.Text;
                if (dialog.ShowDialog() == DialogResult.OK)
                {
                    target.Text = dialog.SelectedPath;
                }
            }
        };
        return button;
    }

    private void Report(string message)
    {
        if (IsDisposed || !IsHandleCreated) return;
        try
        {
            BeginInvoke(
                new Action(() =>
                {
                    if (!IsDisposed) status.Text = message;
                })
            );
        }
        catch (InvalidOperationException)
        {
            // The window closed while the install was finishing.
        }
    }

    private async void InstallClicked(object sender, EventArgs e)
    {
        var installDirectory = installPath.Text.Trim();
        var mediaDirectory = mediaPath.Text.Trim();
        if (installDirectory.Length == 0 || mediaDirectory.Length == 0)
        {
            status.Text = "Choose both an install folder and a media folder.";
            return;
        }
        if (InstallerEngine.IsDriveRootOrProtectedFolder(installDirectory))
        {
            status.Text =
                "Choose a user folder such as Downloads\\Musico App. "
                + "Drive roots and Windows system folders are not allowed.";
            return;
        }
        if (InstallerEngine.IsDriveRootOrProtectedFolder(mediaDirectory))
        {
            status.Text =
                "Choose a user folder such as Documents\\Musico or Downloads\\Musico. "
                + "Drive roots and Windows system folders are not allowed.";
            return;
        }

        installButton.Enabled = false;
        progress.MarqueeAnimationSpeed = 30;
        progress.Value = 0;
        status.Text = "Preparing folders...";

        var result = await Task.Run(
            () => InstallerEngine.Install(
                installDirectory,
                mediaDirectory,
                Report,
                launch: true,
                closeRunningApp: true
            )
        );

        installButton.Enabled = true;
        progress.MarqueeAnimationSpeed = 0;
        if (result.Ok)
        {
            progress.Value = 100;
            status.Text = result.Message;
            Close();
        }
        else
        {
            status.Text = "Installation failed: " + result.Message;
        }
    }
}

internal sealed class InstallResult
{
    public bool Ok;
    public string Message = "";
    public string InstallDirectory = "";
    public string MediaDirectory = "";
}

internal static class InstallerEngine
{
    private const string BundleUrl =
        "https://github.com/Noone-prachan/Musico/releases/latest/download/Musico-Windows-x64.zip";
    private const string ChecksumUrl =
        "https://github.com/Noone-prachan/Musico/releases/latest/download/Musico-Windows-x64.zip.sha256";
    private static readonly string LogPath = Path.Combine(
        Path.GetTempPath(),
        "musico-setup.log"
    );

    public static string DefaultInstallDirectory()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Programs",
            "Musico"
        );
    }

    public static string DefaultMediaDirectory()
    {
        return Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Downloads",
            "Musico"
        );
    }

    public static void Log(string message)
    {
        var line =
            DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "  " + message + "\r\n";
        try
        {
            File.AppendAllText(LogPath, line);
        }
        catch
        {
            try
            {
                var beside = Path.Combine(
                    Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),
                    "musico-setup.log"
                );
                File.AppendAllText(beside, line);
            }
            catch
            {
                // Logging must never break the install.
            }
        }
    }

    public static InstallResult Install(
        string installDirectory,
        string mediaDirectory,
        Action<string> report,
        bool launch,
        bool closeRunningApp
    )
    {
        var result = new InstallResult();
        try
        {
            Log("Install started.");
            installDirectory = Normalize(installDirectory);
            result.InstallDirectory = installDirectory;

            SafeReport(report, "Preparing install folder...");
            EnsureWritableDirectory(installDirectory, "install");
            Log("Install folder is writable: " + installDirectory);

            SafeReport(report, "Choosing a media folder...");
            var media = ResolveMediaDirectory(mediaDirectory, installDirectory, report);
            result.MediaDirectory = media;
            Log("Media folder: " + media);

            SafeReport(report, "Downloading Musico from GitHub...");
            var bundlePath = DownloadVerifiedBundle();
            try
            {
                if (closeRunningApp) CloseRunningMusico(installDirectory, report);

                SafeReport(report, "Installing Musico files...");
                ExtractBundle(installDirectory, bundlePath);
            }
            finally
            {
                DeleteTemporaryFile(bundlePath);
            }
            Log("Bundle extracted.");

            SafeReport(report, "Saving setup details...");
            WriteSetupFile(installDirectory, media);

            result.Ok = true;
            result.Message = "Installation complete. Media is stored in " + media;
            Log("Install completed: " + result.Message);

            if (launch) Launch(installDirectory);
            return result;
        }
        catch (Exception error)
        {
            result.Ok = false;
            result.Message = error.Message;
            Log("Install failed: " + error);
            return result;
        }
    }

    private static void SafeReport(Action<string> report, string message)
    {
        if (report == null) return;
        try
        {
            report(message);
        }
        catch (Exception error)
        {
            Log("Status update failed: " + error.Message);
        }
    }

    private static string Normalize(string path)
    {
        return Path.GetFullPath(path.Trim())
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static bool SamePath(string left, string right)
    {
        return string.Equals(
            Normalize(left),
            Normalize(right),
            StringComparison.OrdinalIgnoreCase
        );
    }

    private static void EnsureWritableDirectory(string path, string label)
    {
        try
        {
            Directory.CreateDirectory(path);
            VerifyWritableDirectory(path);
        }
        catch (Exception error)
        {
            throw new IOException(
                "The "
                    + label
                    + " folder \""
                    + path
                    + "\" cannot be written to. Choose another folder with Browse... and try again. ("
                    + error.Message
                    + ")",
                error
            );
        }
    }

    private static void VerifyWritableDirectory(string path)
    {
        var probeDirectory = Path.Combine(
            path,
            ".musico-write-test-" + Guid.NewGuid().ToString("N")
        );
        try
        {
            Directory.CreateDirectory(probeDirectory);
            File.WriteAllText(Path.Combine(probeDirectory, "write-test"), "ok");
        }
        finally
        {
            if (Directory.Exists(probeDirectory))
            {
                Directory.Delete(probeDirectory, true);
            }
        }
    }

    private static string ResolveMediaDirectory(
        string requested,
        string installDirectory,
        Action<string> report
    )
    {
        var candidates = new List<string> { requested };
        candidates.Add(Path.Combine(installDirectory, "Media"));
        candidates.Add(
            Path.Combine(
                Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData
                ),
                "Musico",
                "Media"
            )
        );
        candidates.Add(Path.Combine(Path.GetTempPath(), "Musico Media"));

        foreach (var candidate in candidates)
        {
            if (string.IsNullOrWhiteSpace(candidate)) continue;
            try
            {
                Directory.CreateDirectory(candidate);
                VerifyWritableDirectory(candidate);
                var resolved = Normalize(candidate);
                if (!SamePath(resolved, requested))
                {
                    SafeReport(report, "Using " + resolved + " for media.");
                }
                return resolved;
            }
            catch (Exception error)
            {
                Log(
                    "Media folder rejected: "
                        + candidate
                        + " -> "
                        + error.Message
                );
            }
        }

        throw new IOException(
            "No writable folder was found for Musico media. "
                + "Choose a folder you own, such as Documents\\Musico."
        );
    }

    private static void CloseRunningMusico(
        string installDirectory,
        Action<string> report
    )
    {
        var targetExecutable = Path.Combine(installDirectory, "Musico.exe");
        foreach (var process in Process.GetProcessesByName("Musico"))
        {
            using (process)
            {
                string executablePath;
                try
                {
                    executablePath = process.MainModule.FileName;
                }
                catch (Exception error)
                {
                    throw new IOException(
                        "Could not identify a running Musico process before updating. "
                            + error.Message,
                        error
                    );
                }

                if (!SamePath(executablePath, targetExecutable)) continue;

                SafeReport(report, "Closing the running Musico...");
                if (process.MainWindowHandle != IntPtr.Zero)
                {
                    process.CloseMainWindow();
                }
                if (!process.WaitForExit(5000))
                {
                    throw new IOException(
                        "Close Musico before installing the update, then try again."
                    );
                }
                Log("Closed running Musico (pid " + process.Id + ").");
            }
        }
    }

    private static string DownloadVerifiedBundle()
    {
        var bundlePath = Path.Combine(
            Path.GetTempPath(),
            "musico-bundle-" + Guid.NewGuid().ToString("N") + ".zip"
        );
        var embeddedBundle = Assembly
            .GetExecutingAssembly()
            .GetManifestResourceStream("MusicoBundle.zip");
        if (embeddedBundle != null)
        {
            try
            {
                using (embeddedBundle)
                using (var output = File.Create(bundlePath))
                {
                    embeddedBundle.CopyTo(output);
                }
                return bundlePath;
            }
            catch
            {
                DeleteTemporaryFile(bundlePath);
                throw;
            }
        }

        var checksumPath = Path.Combine(
            Path.GetTempPath(),
            "musico-bundle-" + Guid.NewGuid().ToString("N") + ".sha256"
        );
        try
        {
            ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072;
            using (var client = new WebClient())
            {
                client.Headers[HttpRequestHeader.UserAgent] = "Musico-Setup/1.0";
                client.DownloadFile(ChecksumUrl, checksumPath);
                client.DownloadFile(BundleUrl, bundlePath);
            }

            var expectedHash = File.ReadAllText(checksumPath)
                .Trim()
                .Split(new[] { ' ', '\t', '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
                .FirstOrDefault();
            if (
                expectedHash == null
                || expectedHash.Length != 64
                || expectedHash.Any(character => !Uri.IsHexDigit(character))
            )
            {
                throw new InvalidDataException(
                    "The GitHub release checksum is missing or invalid."
                );
            }

            string actualHash;
            using (var sha256 = SHA256.Create())
            using (var stream = File.OpenRead(bundlePath))
            {
                actualHash = BitConverter.ToString(sha256.ComputeHash(stream))
                    .Replace("-", "");
            }
            if (!expectedHash.Equals(actualHash, StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException(
                    "The downloaded Musico package failed its SHA-256 integrity check."
                );
            }

            return bundlePath;
        }
        catch (WebException error)
        {
            DeleteTemporaryFile(bundlePath);
            throw new IOException(
                "Musico could not be downloaded. Publish a GitHub Release in "
                    + "Noone-prachan/Musico containing both "
                    + "Musico-Windows-x64.zip and Musico-Windows-x64.zip.sha256, "
                    + "then try again. Check your internet connection. ("
                    + error.Message
                    + ")",
                error
            );
        }
        catch
        {
            DeleteTemporaryFile(bundlePath);
            throw;
        }
        finally
        {
            DeleteTemporaryFile(checksumPath);
        }
    }

    private static void DeleteTemporaryFile(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception error)
        {
            Log("Could not remove temporary file " + path + ": " + error.Message);
        }
    }

    private static void ExtractBundle(string installDirectory, string bundlePath)
    {
        using (var file = File.OpenRead(bundlePath))
        using (var archive = new ZipArchive(file, ZipArchiveMode.Read))
        {
            var root = Path.GetFullPath(installDirectory)
                + Path.DirectorySeparatorChar;
            foreach (var entry in archive.Entries)
            {
                var relativePath = entry.FullName.Replace(
                    '/',
                    Path.DirectorySeparatorChar
                );
                var expectedPrefix = "Musico" + Path.DirectorySeparatorChar;
                if (
                    relativePath.Equals(
                        "Musico",
                        StringComparison.OrdinalIgnoreCase
                    )
                    || relativePath.Equals(
                        expectedPrefix,
                        StringComparison.OrdinalIgnoreCase
                    )
                )
                {
                    Directory.CreateDirectory(installDirectory);
                    continue;
                }
                if (
                    !relativePath.StartsWith(
                        expectedPrefix,
                        StringComparison.OrdinalIgnoreCase
                    )
                )
                {
                    throw new InvalidDataException(
                        "The Musico ZIP must contain a single top-level Musico folder."
                    );
                }

                relativePath = relativePath.Substring(expectedPrefix.Length);
                var destination = Path.GetFullPath(
                    Path.Combine(installDirectory, relativePath)
                );
                if (
                    !destination.StartsWith(
                        root,
                        StringComparison.OrdinalIgnoreCase
                    )
                )
                {
                    throw new InvalidDataException(
                        "The Musico ZIP contains an unsafe file path."
                    );
                }
                if (entry.Name.Length == 0)
                {
                    Directory.CreateDirectory(destination);
                    continue;
                }
                var parent = Path.GetDirectoryName(destination);
                if (!string.IsNullOrEmpty(parent))
                {
                    Directory.CreateDirectory(parent);
                }
                ExtractEntry(entry, destination);
            }
        }
    }

    private static void ExtractEntry(ZipArchiveEntry entry, string destination)
    {
        try
        {
            entry.ExtractToFile(destination, true);
        }
        catch (UnauthorizedAccessException)
        {
            if (!File.Exists(destination)) throw;
            // A previous run may have left the file read-only.
            File.SetAttributes(destination, FileAttributes.Normal);
            entry.ExtractToFile(destination, true);
        }
        catch (Exception error)
        {
            throw new IOException(
                "Could not write \""
                    + destination
                    + "\". Close Musico if it is running, then try again. ("
                    + error.Message
                    + ")",
                error
            );
        }
    }

    private static void WriteSetupFile(string installDirectory, string mediaDirectory)
    {
        var json = new StringBuilder();
        json.Append('{');
        json.Append("\"mediaRoot\":\"");
        json.Append(EscapeJson(mediaDirectory));
        json.Append("\",\"setupCompleted\":true}");
        File.WriteAllText(
            Path.Combine(installDirectory, "musico_setup.json"),
            json.ToString(),
            new UTF8Encoding(false)
        );
    }

    private static string EscapeJson(string value)
    {
        return value.Replace("\\", "\\\\").Replace("\"", "\\\"");
    }

    private static void Launch(string installDirectory)
    {
        var executable = Path.Combine(installDirectory, "Musico.exe");
        if (!File.Exists(executable)) return;
        try
        {
            Process.Start(
                new ProcessStartInfo(executable)
                {
                    WorkingDirectory = installDirectory,
                    UseShellExecute = true,
                }
            );
        }
        catch (Exception error)
        {
            Log("Musico was installed but could not be started: " + error.Message);
        }
    }

    public static bool IsDriveRootOrProtectedFolder(string path)
    {
        try
        {
            var full = Normalize(path);
            var root = Path.GetPathRoot(full);
            if (
                root != null
                && full.Equals(
                    root.TrimEnd(
                        Path.DirectorySeparatorChar,
                        Path.AltDirectorySeparatorChar
                    ),
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                return true;
            }

            var lower = full.ToLowerInvariant();
            var windows = Environment
                .GetFolderPath(Environment.SpecialFolder.Windows)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar
                )
                .ToLowerInvariant();
            var programFiles = Environment
                .GetFolderPath(Environment.SpecialFolder.ProgramFiles)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar
                )
                .ToLowerInvariant();
            var temp = Path
                .GetTempPath()
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar
                )
                .ToLowerInvariant();

            return lower == windows
                || lower.StartsWith(windows + "\\")
                || lower == programFiles
                || lower.StartsWith(programFiles + "\\")
                || lower == temp
                || lower.StartsWith(temp + "\\");
        }
        catch
        {
            return true;
        }
    }
}

internal static class EntryPoint
{
    [STAThread]
    private static void Main(string[] args)
    {
        if (HasFlag(args, "--silent"))
        {
            var installDirectory =
                GetOption(args, "--install") ?? InstallerEngine.DefaultInstallDirectory();
            var mediaDirectory =
                GetOption(args, "--media") ?? InstallerEngine.DefaultMediaDirectory();
            var result = InstallerEngine.Install(
                installDirectory,
                mediaDirectory,
                InstallerEngine.Log,
                launch: !HasFlag(args, "--no-launch"),
                closeRunningApp: true
            );
            InstallerEngine.Log(
                "Silent install finished with exit code " + (result.Ok ? 0 : 1)
            );
            Console.WriteLine(result.Ok ? "OK: " : "FAILED: ");
            Console.WriteLine(result.Message);
            if (!result.Ok)
            {
                Console.WriteLine("InstallDir: " + result.InstallDirectory);
                Console.WriteLine("MediaDir: " + result.MediaDirectory);
            }
            Environment.ExitCode = result.Ok ? 0 : 1;
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new MusicoSetupForm());
    }

    private static bool HasFlag(string[] args, string flag)
    {
        return args.Any(
            argument =>
                argument.Equals(flag, StringComparison.OrdinalIgnoreCase)
        );
    }

    private static string GetOption(string[] args, string option)
    {
        for (var index = 0; index < args.Length; index++)
        {
            var argument = args[index];
            if (
                argument.StartsWith(
                    option + "=",
                    StringComparison.OrdinalIgnoreCase
                )
            )
            {
                return argument.Substring(option.Length + 1);
            }
            if (argument.Equals(option, StringComparison.OrdinalIgnoreCase))
            {
                if (index + 1 < args.Length)
                {
                    return args[index + 1];
                }
            }
        }
        return null;
    }
}
