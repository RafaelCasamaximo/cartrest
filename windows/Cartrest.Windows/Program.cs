using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;

namespace Cartrest.Windows;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        bool smoke = args is ["--smoke-test", _];
        string? output = smoke ? Path.GetFullPath(args[1]) : null;
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        if (smoke)
            RenderOptions.ProcessRenderMode = System.Windows.Interop.RenderMode.SoftwareOnly;

        try
        {
            if (output is not null)
                Directory.CreateDirectory(output);
            var window = new MainWindow(output is null ? null : Path.Combine(output, "profiles"));
            if (output is not null)
            {
                window.Loaded += (_, _) => window.Dispatcher.InvokeAsync(() =>
                {
                    try
                    {
                        window.VerifyInstalledApp(output);
                        app.Shutdown(0);
                    }
                    catch (Exception error)
                    {
                        File.WriteAllText(Path.Combine(output, "failure.txt"), error.ToString());
                        app.Shutdown(1);
                    }
                }, DispatcherPriority.ApplicationIdle);
            }
            return app.Run(window);
        }
        catch (Exception error)
        {
            if (output is not null)
                File.WriteAllText(Path.Combine(output, "failure.txt"), error.ToString());
            else
                MessageBox.Show($"Cartrest could not open. {error.Message}", "Cartrest", MessageBoxButton.OK, MessageBoxImage.Error);
            return 1;
        }
    }
}
