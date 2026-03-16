using System;
using System.Linq;
using Avalonia.Controls;
using Avalonia.Controls.Templates;
using EdgeStudio.ViewModels;

namespace EdgeStudio;

public class ViewLocator : IDataTemplate
{
    public Control? Build(object? param)
    {
        if (param is null)
            return null;

        var viewName = param.GetType().Name.Replace("ViewModel", "View", StringComparison.Ordinal);
        var type = AppDomain.CurrentDomain.GetAssemblies()
            .SelectMany(a => { try { return a.GetTypes(); } catch { return Array.Empty<Type>(); } })
            .FirstOrDefault(t => t.Name == viewName && typeof(Control).IsAssignableFrom(t));

        if (type != null)
            return (Control)Activator.CreateInstance(type)!;

        return new TextBlock { Text = "Not Found: " + viewName };
    }

    public bool Match(object? data)
    {
        return data is ViewModelBase;
    }
}
