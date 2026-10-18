# ============================================================
# Browser tabs: find and select a tab by its title (focus tab ...)
# ============================================================

# Windows only sees a browser window's active tab, through the window title.
# UI Automation can see every tab in the tab strip, so "focus tab" uses it.
$BrowserSource = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows.Automation;

public class BrowserTab
{
    public AutomationElement Element;
    public IntPtr WindowHandle;
    public string Name;
    public string WindowTitle;
    public bool IsSelected;
}

public static class TabFinder
{
    // Deep enough for Edge/Chrome tab strips, shallow enough to stay quick
    const int MaxDepth = 25;

    // Every tab in the top-level windows of the given processes
    public static List<BrowserTab> FindTabs(string[] processNames)
    {
        HashSet<int> processIds = new HashSet<int>();

        foreach (string name in processNames)
        {
            foreach (Process process in Process.GetProcessesByName(name))
            {
                processIds.Add(process.Id);
            }
        }

        List<BrowserTab> tabs = new List<BrowserTab>();

        if (processIds.Count == 0)
        {
            return tabs;
        }

        TreeWalker walker = TreeWalker.ControlViewWalker;
        AutomationElement window = walker.GetFirstChild(AutomationElement.RootElement);

        while (window != null)
        {
            try
            {
                if (processIds.Contains(window.Current.ProcessId))
                {
                    Collect(window, window, walker, 0, tabs);
                }
            }
            catch (ElementNotAvailableException)
            {
                // The window closed while we were looking
            }

            window = walker.GetNextSibling(window);
        }

        return tabs;
    }

    static void Collect(AutomationElement window, AutomationElement parent, TreeWalker walker, int depth, List<BrowserTab> tabs)
    {
        if (depth > MaxDepth)
        {
            return;
        }

        AutomationElement child = walker.GetFirstChild(parent);

        while (child != null)
        {
            ControlType type = child.Current.ControlType;

            if (type == ControlType.TabItem)
            {
                BrowserTab tab = new BrowserTab();
                tab.Element = child;
                tab.WindowHandle = new IntPtr(window.Current.NativeWindowHandle);
                tab.Name = child.Current.Name;
                tab.WindowTitle = window.Current.Name;
                tab.IsSelected = IsSelected(child);
                tabs.Add(tab);
            }
            else if (type != ControlType.Document)
            {
                // Web page content is skipped: it can be huge and holds no browser tabs
                Collect(window, child, walker, depth + 1, tabs);
            }

            child = walker.GetNextSibling(child);
        }
    }

    public static bool IsSelected(AutomationElement element)
    {
        object pattern;

        if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern))
        {
            return ((SelectionItemPattern)pattern).Current.IsSelected;
        }

        return false;
    }

    // Selects the tab without input. Returns how ("select" or "invoke"), or null if the tab supports neither.
    public static string Select(AutomationElement element)
    {
        object pattern;

        if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out pattern))
        {
            ((SelectionItemPattern)pattern).Select();
            return "select";
        }

        if (element.TryGetCurrentPattern(InvokePattern.Pattern, out pattern))
        {
            ((InvokePattern)pattern).Invoke();
            return "invoke";
        }

        return null;
    }

    // Centre of the tab on screen as { x, y }, or null if it isn't on screen
    public static int[] GetCenter(AutomationElement element)
    {
        System.Windows.Rect rect = element.Current.BoundingRectangle;

        if (rect.IsEmpty || rect.Width <= 0 || rect.Height <= 0)
        {
            return null;
        }

        return new int[] { (int)(rect.X + rect.Width / 2), (int)(rect.Y + rect.Height / 2) };
    }
}
"@

# Compile on first use only, so runs without "focus tab" don't load UI Automation
function Initialize-TabFinder {

    if ("TabFinder" -as [type]) {
        return
    }

    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, WindowsBase
    Add-Type -TypeDefinition $BrowserSource -ReferencedAssemblies UIAutomationClient, UIAutomationTypes, WindowsBase
}

# All tabs in the given browsers. Emits BrowserTab objects one by one.
function Get-BrowserTabs {
    param(
        [string[]]$Browsers
    )

    Initialize-TabFinder

    return [TabFinder]::FindTabs($Browsers)
}

# The tab whose title contains Text (case-insensitive), or $null.
# An already selected match wins, so no switching is needed.
function Find-BrowserTab {
    param(
        [string]$Text,
        [string[]]$Browsers
    )

    $matched = @(Get-BrowserTabs $Browsers | Where-Object { $_.Name -and $_.Name.IndexOf($Text, [StringComparison]::OrdinalIgnoreCase) -ge 0 })

    if ($matched.Count -eq 0) {
        return $null
    }

    $selected = @($matched | Where-Object { $_.IsSelected })

    if ($selected.Count -gt 0) {
        return $selected[0]
    }

    return $matched[0]
}

# The selected tab in the same window as Tab, or $null
function Get-SelectedTabInWindow {
    param(
        [object]$Tab,
        [string[]]$Browsers
    )

    $selected = @(Get-BrowserTabs $Browsers | Where-Object { $_.WindowHandle -eq $Tab.WindowHandle -and $_.IsSelected })

    if ($selected.Count -gt 0) {
        return $selected[0]
    }

    return $null
}
